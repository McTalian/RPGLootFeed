---@diagnostic disable: need-check-nil
--- T05 Integration tests: button click -> pending queue -> state transition
---
--- Full Retail + Classic flows for OnRollButtonClick:
---   START_LOOT_ROLL -> EnqueueAction (rollType=nil)
---   -> player fires RollOnLoot -> OnRollButtonClick updates slot + drop state
---   -> _pendingActions[rollID].rollType set
---   -> _dropStates[dropKey].actionPhase = "waiting"
---   -> row re-dispatched (buttons disabled)
---
--- Also covers error cases: no pending slot, unrecognised numericType, toggle off.

local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

local ITEM_LINK = "|cff0070dditem:12345|r"
local ROLL_ID = 77

-- ── helpers ──────────────────────────────────────────────────────────────────

local function pendingDrop()
	return {
		itemHyperlink = ITEM_LINK,
		winner = nil,
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		playerRollState = nil,
		startTime = nil,
		duration = nil,
	}
end

local function makeNs(sendSpy, isRetailFn)
	return {
		LootElementBase = nil,
		ItemQualEnum = { Uncommon = 2, Epic = 4 },
		DefaultIcons = { LOOTROLLS = 132319 },
		FeatureModule = { LootRolls = "LootRolls" },
		LogDebug = spy.new(function() end),
		LogInfo = spy.new(function() end),
		LogWarn = spy.new(function() end),
		LogError = spy.new(function() end),
		IsRetail = isRetailFn or function() return true end,
		SendMessage = sendSpy,
		TooltipBuilders = nil,
		db = { global = { animations = { exit = { fadeOutDelay = 3 } }, misc = { hideAllIcons = false } } },
		WoWAPI = { LootRolls = {} },
		DbAccessor = {
			IsFeatureNeededByAnyFrame = function() return true end,
			AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return { enableIcon = true, enableLootRollActions = true }
				end
				return nil
			end,
		},
		L = {
			["All Passed"] = "All Passed",
			["LootRolls_WaitingForRolls"] = "Waiting for rolls",
			["LootRolls_TiedFmt"] = "Tied at %d",
			["LootRolls_CurrentLeaderFmt"] = "Leading: %s rolled %d",
			["LootRolls_WonByFmt"] = "Won by %s %s %d",
			["LootRolls_WonByNoRollFmt"] = "Won by %s",
			["LootRolls_YouSelected_NEED"] = "You: Need",
			["LootRolls_YouSelected_GREED"] = "You: Greed",
			["LootRolls_YouSelected_TRANSMOG"] = "You: Transmog",
			["LootRolls_YouSelected_PASS"] = "You: Pass",
			["LootRolls_WaitingForResults"] = "Waiting for results",
			["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
			["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s, rolled %d",
		},
		RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
	}
end

local function loadLootRolls(ns, adapterOverrides)
	assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
	ns.FeatureBase = {
		new = function(_, name)
			return {
				moduleName = name,
				Enable = function() end,
				Disable = function() end,
				IsEnabled = function() return true end,
				RegisterEvent = function() end,
				UnregisterAllEvents = function() end,
			}
		end,
	}
	local lr = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
	assert.is_not_nil(lr)
	ns.LootRolls = lr
	local adapter = {
		HasLootHistory = function() return true end,
		HasStartLootRollEvent = function() return true end,
		GetSortedInfoForDrop = function() return nil end,
		GetInfoForEncounter = function() return nil end,
		GetRaidClassColor = function() return nil end,
		GetItemInfoIcon = function() return 12345 end,
		GetItemInfoQuality = function() return 4 end,
		GetRollButtonValidity = function()
			return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
		end,
		GetRetailRollItemLink = function() return ITEM_LINK end,
		GetClassicRollItemInfo = function()
			return { itemLink = ITEM_LINK, texture = 132310, quality = 3, canNeed = true, canGreed = true, canDisenchant = false }
		end,
	}
	if adapterOverrides then
		for k, v in pairs(adapterOverrides) do adapter[k] = v end
	end
	lr._lootRollsAdapter = adapter
	lr._dropStates = {}
	lr._buttonValidityCache = {}
	lr._stagedRollValidity = {}
	lr._pendingActions = {}
	return lr
end

local function fireRetailSequence(lr, encID, llID, rollID)
	lr:START_LOOT_ROLL("START_LOOT_ROLL", rollID or ROLL_ID, 60)
	lr._lootRollsAdapter.GetSortedInfoForDrop = function() return pendingDrop() end
	lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", encID, llID)
end

-- =============================================================================
-- Retail button-submit integration
-- =============================================================================

describe("button-submit integration: Retail button click -> pending queue -> state", function()
	local _ = match._
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("START_LOOT_ROLL pre-enqueues pending slot with rollType=nil and correct itemLink", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		local slot = lr._pendingActions[ROLL_ID]
		assert.is_not_nil(slot, "pending slot must be created by START_LOOT_ROLL")
		assert.are.equal(ITEM_LINK, slot.itemLink)
		assert.is_nil(slot.rollType)
	end)

	it("Retail Need: OnRollButtonClick(1) sets rollType='NEED' on pending slot", function()
		fireRetailSequence(lr, 10, 3)
		lr:OnRollButtonClick(ROLL_ID, 1)
		assert.are.equal("NEED", lr._pendingActions[ROLL_ID].rollType)
	end)

	it("Retail Need: actionPhase transitions to 'waiting'", function()
		fireRetailSequence(lr, 10, 3)
		lr:OnRollButtonClick(ROLL_ID, 1)
		assert.are.equal("waiting", lr._dropStates["10_3"].actionPhase)
	end)

	it("Retail Need: playerSelection='NEED' recorded on drop state", function()
		fireRetailSequence(lr, 10, 3)
		lr:OnRollButtonClick(ROLL_ID, 1)
		assert.are.equal("NEED", lr._dropStates["10_3"].playerSelection)
	end)

	it("Retail Need: SendMessage called once (row re-dispatched)", function()
		fireRetailSequence(lr, 10, 3)
		sendSpy:clear()
		lr:OnRollButtonClick(ROLL_ID, 1)
		assert.spy(sendSpy).was.called(1)
	end)

	it("Retail Need: BuildPayload suppresses buttonValidity when waiting", function()
		fireRetailSequence(lr, 10, 3)
		lr:OnRollButtonClick(ROLL_ID, 1)
		local payload = lr:BuildPayload(10, 3, pendingDrop(), "pending")
		assert.is_nil(payload.buttonValidity, "buttonValidity suppressed when actionPhase=waiting")
	end)

	it("Retail Greed: OnRollButtonClick(2) sets rollType='GREED' and actionPhase='waiting'", function()
		fireRetailSequence(lr, 10, 3)
		lr:OnRollButtonClick(ROLL_ID, 2)
		assert.are.equal("GREED", lr._pendingActions[ROLL_ID].rollType)
		assert.are.equal("waiting", lr._dropStates["10_3"].actionPhase)
		assert.are.equal("GREED", lr._dropStates["10_3"].playerSelection)
	end)

	it("Retail Greed: SendMessage called once", function()
		fireRetailSequence(lr, 10, 3)
		sendSpy:clear()
		lr:OnRollButtonClick(ROLL_ID, 2)
		assert.spy(sendSpy).was.called(1)
	end)

	it("Retail Pass: OnRollButtonClick(0) sets rollType='PASS' and actionPhase='waiting'", function()
		fireRetailSequence(lr, 10, 3)
		lr:OnRollButtonClick(ROLL_ID, 0)
		assert.are.equal("PASS", lr._pendingActions[ROLL_ID].rollType)
		assert.are.equal("waiting", lr._dropStates["10_3"].actionPhase)
		assert.are.equal("PASS", lr._dropStates["10_3"].playerSelection)
	end)

	it("Retail Pass: SendMessage called once", function()
		fireRetailSequence(lr, 10, 3)
		sendSpy:clear()
		lr:OnRollButtonClick(ROLL_ID, 0)
		assert.spy(sendSpy).was.called(1)
	end)
end)

-- =============================================================================
-- Classic button-submit integration
-- =============================================================================

describe("button-submit integration: Classic button click -> pending queue -> state", function()
	local _ = match._
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy, function() return false end)
		ns.DbAccessor.AnyFeatureConfig = function(_, k)
			if k == "lootRolls" then return { enableIcon = true, enableLootRollActions = true, disableLootRollFrame = true } end
			return nil
		end
		lr = loadLootRolls(ns, { HasLootHistory = function() return false end })
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("Classic START_LOOT_ROLL pre-enqueues pending slot with rollType=nil", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		local slot = lr._pendingActions[ROLL_ID]
		assert.is_not_nil(slot)
		assert.is_nil(slot.rollType)
	end)

	it("Classic Need: rollType='NEED' and actionPhase='waiting'", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		lr:OnRollButtonClick(ROLL_ID, 1)
		assert.are.equal("NEED", lr._pendingActions[ROLL_ID].rollType)
		local entry = lr._dropStates[ROLL_ID .. "_" .. ROLL_ID]
		assert.are.equal("waiting", entry.actionPhase)
		assert.are.equal("NEED", entry.playerSelection)
	end)

	it("Classic Greed: actionPhase='waiting' with playerSelection='GREED'", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		lr:OnRollButtonClick(ROLL_ID, 2)
		local entry = lr._dropStates[ROLL_ID .. "_" .. ROLL_ID]
		assert.are.equal("waiting", entry.actionPhase)
		assert.are.equal("GREED", entry.playerSelection)
	end)

	it("Classic Pass: actionPhase='waiting' with playerSelection='PASS'", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		lr:OnRollButtonClick(ROLL_ID, 0)
		local entry = lr._dropStates[ROLL_ID .. "_" .. ROLL_ID]
		assert.are.equal("waiting", entry.actionPhase)
		assert.are.equal("PASS", entry.playerSelection)
	end)

	it("Classic Need: SendMessage called once (row re-dispatched)", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		sendSpy:clear()
		lr:OnRollButtonClick(ROLL_ID, 1)
		assert.spy(sendSpy).was.called(1)
	end)

	it("Classic Need: BuildClassicPayload suppresses buttonValidity when waiting", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		lr:OnRollButtonClick(ROLL_ID, 1)
		local entry = lr._dropStates[ROLL_ID .. "_" .. ROLL_ID]
		local payload = lr:BuildClassicPayload(ROLL_ID, entry._dropInfo, "pending", nil)
		assert.is_nil(payload.buttonValidity, "buttonValidity suppressed when waiting")
	end)
end)

-- =============================================================================
-- Error cases: toggle off / no pending slot / bad numericType
-- =============================================================================

describe("button-submit integration: error cases", function()
	local _ = match._
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("OnRollButtonClick does not crash when no pending slot exists (toggle was off)", function()
		assert.has_no_errors(function()
			lr:OnRollButtonClick(999, 1)
		end)
	end)

	it("OnRollButtonClick creates a fallback pending entry when no prior slot", function()
		lr:OnRollButtonClick(888, 1)
		-- fallback entry created with rollType set and nil itemLink
		local fallback = lr._pendingActions[888]
		assert.is_not_nil(fallback, "fallback entry must be created")
		assert.are.equal("NEED", fallback.rollType)
	end)

	it("unrecognised numericType: pending slot rollType stays nil", function()
		lr._pendingActions[42] = { itemLink = ITEM_LINK, rollType = nil, rollValue = nil, timestamp = 999 }
		lr:OnRollButtonClick(42, 99) -- bogus type -> early return, no update
		assert.is_nil(lr._pendingActions[42].rollType)
	end)

	it("buttons hidden via UpdateLootRollButtons when enableLootRollActions=false", function()
		local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootRollsButtonsMixin.lua"
		local ns2 = makeNs(sendSpy)
		ns2.DbAccessor.AnyFeatureConfig = function(_, k)
			if k == "lootRolls" then return { enableLootRollActions = false } end
		end
		ns2.TextAlignment = { LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER" }
		ns2.DbAccessor.Sizing = function() return { padding = 2, iconSize = 20 } end
		ns2.DbAccessor.Styling = function() return { textAlignment = "LEFT" } end
		assert(loadfile(MIXIN_FILE))("TestAddon", ns2)

		local function makeBtn()
			return {
				_shown = false, _enabled = false,
				Show = function(self) self._shown = true end,
				Hide = function(self) self._shown = false end,
				Enable = function(self) self._enabled = true end,
				Disable = function(self) self._enabled = false end,
				SetAlpha = function() end, SetSize = function() end, SetID = function() end,
				SetNormalAtlas = function() end, SetPushedAtlas = function() end,
				SetHighlightAtlas = function() end, ClearAllPoints = function() end,
				SetPoint = function() end, EnableMouse = function() end,
				SetScript = function(self, e, f) self._scripts = self._scripts or {}; self._scripts[e] = f end,
				SetFrameLevel = function() end, GetFrameLevel = function() return 5 end,
				RegisterForClicks = function() end,
				GetNormalTexture = function() return { SetDesaturation = function() end } end,
				CreateTexture = function()
					return { SetAllPoints=function()end, SetColorTexture=function()end, SetAtlas=function()end,
						SetDesaturated=function()end, Hide=function()end, Show=function()end, _shown=false }
				end,
				disabledOverlay = { _shown=false, Show=function(self)self._shown=true end, Hide=function(self)self._shown=false end },
				highlight = { SetAllPoints=function()end, SetColorTexture=function()end },
				tex = { SetDesaturated=function()end, SetAtlas=function()end, SetAllPoints=function()end },
			}
		end

		local row = {
			frameType = "MAIN", type = nil, rollID = nil,
			NeedButton = makeBtn(), GreedButton = makeBtn(), PassButton = makeBtn(), TransmogButton = makeBtn(),
			ClickableButton = {
				_scripts = {}, GetFrameLevel=function()return 5 end,
				SetScript=function(self,e,f) self._scripts[e]=f end,
			},
			IsMouseOver = function() return false end,
			LogDebug = function() end, LogWarn = function() end,
			_isClickThrough = false,
			SetClickThrough = function(self, enabled) self._isClickThrough = enabled end,
		}
		for k, v in pairs(RLF_LootRollsButtonsMixin) do row[k] = v end

		row:UpdateLootRollButtons({
			rollState = "pending", lootListID = 1,
			buttonValidity = { canNeed=true, canGreed=true, canTransmog=false, canPass=true },
		})

		assert.is_false(row.NeedButton._shown, "NeedButton hidden when feature off")
		assert.is_false(row.GreedButton._shown, "GreedButton hidden when feature off")
		assert.is_false(row.PassButton._shown, "PassButton hidden when feature off")
	end)
end)
