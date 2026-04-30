---@diagnostic disable: need-check-nil
--- Integration tests for the full LootRolls → ButtonsMixin → GroupLootFrameOverride flow.
---
--- These tests exercise real code paths end-to-end, wiring together:
---   LootRolls.lua  ←→  LootRollsButtonsMixin.lua  ←→  GroupLootFrameOverride.lua
---
--- All WoW APIs (C_LootHistory, RollOnLoot, GroupLootFrame) are stubbed.
--- Row rendering is simulated via a minimal mock row that delegates to the mixin.

local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootRollsButtonsMixin.lua"

-- ─── Shared fixtures ─────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:12345|r"

local function makePendingDrop(overrides)
	local base = {
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
	if overrides then
		for k, v in pairs(overrides) do
			base[k] = v
		end
	end
	return base
end

local function makeResolvedDrop(winnerOverrides, selfRollInfo)
	local winner = {
		playerName = "Warrior",
		playerClass = "WARRIOR",
		roll = 94,
		state = 0,
		isSelf = false,
		isWinner = true,
	}
	if winnerOverrides then
		for k, v in pairs(winnerOverrides) do
			winner[k] = v
		end
	end
	local rollInfos = {}
	if selfRollInfo then
		table.insert(rollInfos, selfRollInfo)
	end
	return {
		itemHyperlink = ITEM_LINK,
		winner = winner,
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = rollInfos,
		playerRollState = selfRollInfo and selfRollInfo.state or nil,
	}
end

--- Build a minimal mock button frame.
local function makeMockBtn()
	local btn = {
		rollKey = nil,
		isRollEnabled = false,
		_shown = false,
		_alpha = 1,
		_scripts = {},
		_textures = {},
		tex = {
			SetDesaturated = function() end,
			SetAtlas = function() end,
			SetAllPoints = function() end,
		},
		disabledOverlay = {
			_shown = false,
			Show = function(self)
				self._shown = true
			end,
			Hide = function(self)
				self._shown = false
			end,
		},
		highlight = {
			SetAllPoints = function() end,
			SetColorTexture = function() end,
		},
		SetSize = function() end,
		SetID = function() end,
		SetNormalAtlas = function() end,
		SetPushedAtlas = function() end,
		SetHighlightAtlas = function() end,
		ClearAllPoints = function() end,
		SetPoint = function() end,
		SetAlpha = function(self, a)
			self._alpha = a
		end,
		Enable = function(self)
			self._enabled = true
		end,
		Disable = function(self)
			self._enabled = false
		end,
		Show = function(self)
			self._shown = true
		end,
		Hide = function(self)
			self._shown = false
		end,
		EnableMouse = function() end,
		SetScript = function(self, evt, fn)
			self._scripts[evt] = fn
		end,
		SetFrameLevel = function() end,
		GetFrameLevel = function()
			return 5
		end,
		RegisterForClicks = function() end,
		GetNormalTexture = function()
			return { SetDesaturation = function() end }
		end,
	}
	btn.CreateTexture = function(self, _name, _layer)
		local t = {
			_shown = false,
			SetAllPoints = function() end,
			SetColorTexture = function() end,
			SetAtlas = function() end,
			SetDesaturated = function() end,
			Hide = function(self2)
				self2._shown = false
			end,
			Show = function(self2)
				self2._shown = true
			end,
		}
		table.insert(self._textures, t)
		return t
	end
	return btn
end
local function buildMockRow(ns, withButtons)
	assert(loadfile(MIXIN_FILE))("TestAddon", ns)

	local row = {
		frameType = "MAIN",
		type = nil,
		rollID = nil,
		ClickableButton = {
			_scripts = {},
			GetFrameLevel = function()
				return 5
			end,
			SetScript = function(self, evt, fn)
				self._scripts[evt] = fn
			end,
		},
		IsMouseOver = function()
			return false
		end,
		-- SetClickThrough stub — required by UpdateLootRollButtons (S04 dismiss gating).
		_isClickThrough = false,
		SetClickThrough = function(self, enabled)
			self._isClickThrough = enabled
		end,
	}

	for k, v in pairs(RLF_LootRollsButtonsMixin) do
		row[k] = v
	end

	-- Stub frame-level methods.
	row.LogDebug = function() end
	row.LogWarn = function() end

	-- TextAlignment enum needed by LayoutButtons.
	ns.TextAlignment = { LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER" }

	ns.DbAccessor.Sizing = function(_, _ft)
		return { padding = 2, iconSize = 20 }
	end
	ns.DbAccessor.Styling = function(_, _ft)
		return { textAlignment = ns.TextAlignment.LEFT }
	end

	if withButtons then
		row.NeedButton = makeMockBtn()
		row.PassButton = makeMockBtn()
		row.GreedButton = makeMockBtn()
		row.TransmogButton = makeMockBtn()
	end

	return row
end

-- ─── Main integration suite ──────────────────────────────────────────────────

describe("LootRolls integration", function()
	local _ = match._
	---@type RLF_LootRolls
	local LootRolls, ns, sendMessageSpy

	before_each(function()
		sendMessageSpy = spy.new(function() end)

		ns = {
			LootElementBase = nil,
			ItemQualEnum = { Uncommon = 2, Epic = 4 },
			DefaultIcons = { LOOTROLLS = 132319 },
			FeatureModule = { LootRolls = "LootRolls" },
			LogDebug = spy.new(function() end),
			LogInfo = spy.new(function() end),
			LogWarn = spy.new(function() end),
			LogError = spy.new(function() end),
			IsRetail = function()
				return true
			end,
			SendMessage = sendMessageSpy,
			TooltipBuilders = nil,
			db = {
				global = {
					animations = { exit = { fadeOutDelay = 3 } },
					misc = { hideAllIcons = false },
				},
			},
			WoWAPI = { LootRolls = {} },
			DbAccessor = {
				IsFeatureNeededByAnyFrame = function()
					return true
				end,
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
				["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
				["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s, rolled %d",
			},
			RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
		}

		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)

		ns.FeatureBase = {
			new = function(_, name)
				return {
					moduleName = name,
					Enable = function() end,
					Disable = function() end,
					IsEnabled = function()
						return true
					end,
					RegisterEvent = function() end,
					UnregisterAllEvents = function() end,
				}
			end,
		}

		LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
		assert.is_not_nil(LootRolls)

		-- Wire LootRolls into ns so the mixin can call Submit*.
		ns.LootRolls = LootRolls

		-- Default adapter stubs.
		LootRolls._lootRollsAdapter = {
			HasLootHistory = function()
				return true
			end,
			GetSortedInfoForDrop = function()
				return nil
			end,
			GetInfoForEncounter = function()
				return nil
			end,
			GetRaidClassColor = function()
				return nil
			end,
			GetItemInfoIcon = function()
				return 12345
			end,
			GetItemInfoQuality = function()
				return 4
			end,
			GetRollButtonValidity = function(_rollID)
				return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
			end,
			GetRetailRollItemLink = function(_rollID)
				return ITEM_LINK
			end,
		}

		LootRolls._dropStates = {}
		LootRolls._buttonValidityCache = {}
		LootRolls._stagedRollValidity = {}

		-- ScanUnmatchedPendingActions (called from LOOT_HISTORY_UPDATE_DROP) needs
		-- GetTime() via CurrentTimestamp().  Provide a deterministic stub so any
		-- test that fires LOOT_HISTORY_UPDATE_DROP does not crash on nil GetTime.
		_G.GetTime = function()
			return 1000
		end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- ── Scenario 1: Pending roll — buttons visible and correctly enabled ───────

	describe("Scenario 1: pending roll, button layout, validity state", function()
		it("BuildPayload for pending drop includes rollState=pending, buttonValidity, no playerSelection", function()
			local drop = makePendingDrop()
			-- Warm the validity cache.
			LootRolls._dropStates["1_1"] = { state = "pending" }
			LootRolls._buttonValidityCache["1_1"] =
				{ canNeed = true, canGreed = true, canTransmog = false, canPass = true }

			local payload = LootRolls:BuildPayload(1, 1, drop, "pending")

			assert.are.equal("pending", payload.rollState)
			assert.are.equal(1, payload.encounterID)
			assert.are.equal(1, payload.lootListID)
			assert.is_not_nil(payload.buttonValidity)
			assert.is_true(payload.buttonValidity.canNeed)
			assert.is_true(payload.buttonValidity.canGreed)
			assert.is_false(payload.buttonValidity.canTransmog)
			assert.is_true(payload.buttonValidity.canPass)
			assert.is_nil(payload.playerSelection)
		end)

		it("LOOT_HISTORY_UPDATE_DROP for pending drop caches validity and dispatches payload", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end

			-- On Retail, START_LOOT_ROLL fires first and stages validity by item link.
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 99, 60)
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 5, 2)

			-- Validity was cached.
			assert.is_not_nil(LootRolls._buttonValidityCache["5_2"])
			assert.is_true(LootRolls._buttonValidityCache["5_2"].canNeed)
			assert.is_false(LootRolls._buttonValidityCache["5_2"].canTransmog)
			-- Payload was sent.
			assert.spy(sendMessageSpy).was.called(1)
		end)

		it(
			"row UpdateLootRollButtons shows all four buttons for pending state with enableLootRollActions=true",
			function()
				local row = buildMockRow(ns, true)
				ns.DbAccessor.AnyFeatureConfig = function(_, key)
					if key == "lootRolls" then
						return { enableLootRollActions = true }
					end
				end

				local payload = {
					rollState = "pending",
					lootListID = 2,
					buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
				}

				row:UpdateLootRollButtons(payload)

				-- Named buttons should be shown.
				assert.is_true(row.NeedButton._shown)
				assert.is_true(row.GreedButton._shown)
				assert.is_true(row.PassButton._shown)
			end
		)

		it("NEED and GREED buttons are enabled when canNeed=true, canGreed=true", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true }
				end
			end

			local payload = {
				rollState = "pending",
				lootListID = 2,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			}
			row:UpdateLootRollButtons(payload)

			assert.is_true(row.NeedButton._enabled)
			assert.is_true(row.GreedButton._enabled)
			assert.is_true(row.PassButton._enabled)
		end)

		it("GREED button is disabled when canGreed=false", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true }
				end
			end

			-- canGreed=false, canTransmog=false → GreedButton disabled
			row:UpdateLootRollButtons({
				rollState = "pending",
				lootListID = 2,
				buttonValidity = { canNeed = true, canGreed = false, canTransmog = false, canPass = true },
			})

			assert.is_false(row.GreedButton._enabled)
			assert.is_true(row.NeedButton._enabled)
		end)

		it("pending secondary text is 'Waiting for rolls' when no leader yet", function()
			local drop = makePendingDrop()
			local payload = LootRolls:BuildPayload(1, 1, drop, "pending")
			assert.are.equal("Waiting for rolls", payload.secondaryText)
		end)
	end)

	-- ── Scenario 2: Click Need button → SubmitLootRoll called → payload updated ─

	describe("Scenario 2: click Need → payload reflects selection", function()
		it("BuildPayload after SubmitNeed includes playerSelection=NEED", function()
			LootRolls._dropStates["1_1"] = { state = "pending", playerSelection = "NEED" }
			LootRolls._buttonValidityCache["1_1"] =
				{ canNeed = true, canGreed = true, canTransmog = false, canPass = true }

			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.are.equal("NEED", payload.playerSelection)
		end)
	end)

	-- ── Scenario 3: Roll resolves → buttons hidden → secondary text with winner ─

	describe("Scenario 3: roll resolves → secondary text shows winner + player selection", function()
		it("resolved payload has rollState=resolved", function()
			local selfRoll = { playerName = "Me", roll = 67, state = 0, isSelf = true, isWinner = false }
			local drop = makeResolvedDrop(nil, selfRoll)
			local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
			assert.are.equal("resolved", payload.rollState)
		end)

		it("resolved secondary text includes winner and self roll (no selection)", function()
			-- Self rolled but didn't use action buttons.
			local selfRoll = { playerName = "Me", roll = 67, state = 0, isSelf = true, isWinner = false }
			local drop = makeResolvedDrop(nil, selfRoll)

			-- No playerSelection recorded.
			LootRolls._dropStates["1_1"] = { state = "resolved" }

			local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
			-- Should use WinnerWithSelfFmt (no selection label).
			assert.is_not_nil(string.find(payload.secondaryText, "You: rolled 67"))
		end)

		it("resolved secondary text includes winner and selection label when player used action buttons", function()
			local selfRoll = { playerName = "Me", roll = 67, state = 0, isSelf = true, isWinner = false }
			local drop = makeResolvedDrop(nil, selfRoll)

			-- Player had previously selected NEED via the buttons.
			LootRolls._dropStates["1_1"] = { state = "resolved", playerSelection = "NEED" }

			local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
			-- Should use WinnerWithSelfAndSelectionFmt.
			assert.is_not_nil(string.find(payload.secondaryText, "You: Need"))
			assert.is_not_nil(string.find(payload.secondaryText, "67")) -- self roll number
		end)

		it("resolved secondary text format: 'Won by Warrior ♦ 94  |  You: Need, rolled 67'", function()
			local selfRoll = { playerName = "Me", roll = 67, state = 0, isSelf = true, isWinner = false }
			local drop = makeResolvedDrop({ playerName = "Warrior", playerClass = "WARRIOR", roll = 94 }, selfRoll)

			LootRolls._dropStates["1_1"] = { state = "resolved", playerSelection = "NEED" }

			local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
			-- The format: "%s  |  %s, rolled %d" → winnerText | selectionLabel, rolled selfRoll
			-- winnerText: "Won by Warrior ♦ 94" (state=0 icon varies, check presence of roll)
			assert.is_not_nil(string.find(payload.secondaryText, "Warrior"))
			assert.is_not_nil(string.find(payload.secondaryText, "94"))
			assert.is_not_nil(string.find(payload.secondaryText, "You: Need"))
			assert.is_not_nil(string.find(payload.secondaryText, "67"))
		end)

		it("UpdateLootRollButtons sets row.rollID from payload.rollID (Retail)", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true }
				end
			end
			row:UpdateLootRollButtons({
				rollState = "pending",
				rollID = 42,
				lootListID = 3,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			})
			assert.are.equal(42, row.rollID)
		end)

		it("UpdateLootRollButtons falls back to lootListID when payload.rollID absent (Classic)", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true }
				end
			end
			row:UpdateLootRollButtons({
				rollState = "pending",
				lootListID = 7,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			})
			assert.are.equal(7, row.rollID)
		end)

		it("UpdateLootRollButtons hides buttons when rollState=resolved", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true }
				end
			end
			-- First show them as pending.
			row:UpdateLootRollButtons({
				rollState = "pending",
				lootListID = 1,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			})
			assert.is_true(row.NeedButton._shown)

			-- Now resolve.
			row:UpdateLootRollButtons({
				rollState = "resolved",
				lootListID = 1,
				buttonValidity = nil,
			})
			assert.is_false(row.NeedButton._shown)
			assert.is_false(row.GreedButton._shown)
		end)
	end)

	-- ── Scenario 4: Config mode toggles ──────────────────────────────────────

	describe("Scenario 4: config modes", function()
		it("enableLootRollActions=false → UpdateLootRollButtons hides buttons", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = false }
				end
			end

			row:UpdateLootRollButtons({
				rollState = "pending",
				lootListID = 1,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			})

			assert.is_false(row.NeedButton._shown)
			assert.is_false(row.PassButton._shown)
		end)

		it("enableLootRollActions=true → buttons visible for pending roll", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true, disableLootRollFrame = false }
				end
			end

			row:UpdateLootRollButtons({
				rollState = "pending",
				lootListID = 1,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			})

			assert.is_true(row.NeedButton._shown)
		end)

		it("GroupLootFrameOverride suppresses Show when disableLootRollFrame=true", function()
			local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
			local overrideNs = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
			overrideNs.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { disableLootRollFrame = true }
				end
			end

			local override =
				assert(loadfile("RPGLootFeed/BlizzOverrides/GroupLootFrameOverride.lua"))("TestAddon", overrideNs)

			local testFrame = _G["GroupLootFrame1"] or {}
			testFrame.Hide = function() end
			local originalCalled = false
			override.hooks = {
				[testFrame] = {
					Show = function()
						originalCalled = true
					end,
				},
			}
			override:InterceptGroupLootFrame(testFrame)
			assert.is_false(originalCalled)
		end)

		it("GroupLootFrameOverride passes through Show when disableLootRollFrame=false", function()
			local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
			local overrideNs = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
			overrideNs.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { disableLootRollFrame = false }
				end
			end

			local override =
				assert(loadfile("RPGLootFeed/BlizzOverrides/GroupLootFrameOverride.lua"))("TestAddon", overrideNs)

			local testFrame = _G["GroupLootFrame1"] or {}
			testFrame.Hide = function() end
			local originalCalled = false
			override.hooks = {
				[testFrame] = {
					Show = function()
						originalCalled = true
					end,
				},
			}
			override:InterceptGroupLootFrame(testFrame)
			assert.is_true(originalCalled)
		end)
	end)

	-- ── Regression: payload structure backward compatibility ──────────────────

	describe("Regression: payload structure backward compatibility", function()
		it("payload.key follows 'LR_<encounterID>_<lootListID>' format", function()
			local payload = LootRolls:BuildPayload(7, 3, makePendingDrop(), "pending")
			assert.are.equal("LR_7_3", payload.key)
		end)

		it("payload.type is FeatureModule.LootRolls", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.are.equal("LootRolls", payload.type)
		end)

		it("payload.quantity is 0 (not nil) for LootRolls rows", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.are.equal(0, payload.quantity)
		end)

		it("payload.isLink is true", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_true(payload.isLink)
		end)

		it("payload.IsEnabled returns true when module is enabled", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_true(payload.IsEnabled())
		end)

		it("payload.textFn returns item hyperlink when no truncated link", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.are.equal(ITEM_LINK, payload.textFn(nil, nil))
		end)

		it("payload.textFn returns truncated link when provided", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.are.equal("short", payload.textFn(nil, "short"))
		end)

		it("payload includes icon when enableIcon=true and hideAllIcons=false", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_not_nil(payload.icon)
		end)

		it("payload omits icon when enableIcon=false", function()
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableIcon = false, enableLootRollActions = true }
				end
			end
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_nil(payload.icon)
		end)

		it("allPassed drop yields secondaryText='All Passed'", function()
			local drop = {
				itemHyperlink = ITEM_LINK,
				winner = nil,
				allPassed = true,
				isTied = false,
				currentLeader = nil,
				rollInfos = {},
			}
			local payload = LootRolls:BuildPayload(1, 1, drop, "allPassed")
			assert.are.equal("All Passed", payload.secondaryText)
		end)

		it("LOOT_HISTORY_UPDATE_DROP dispatches payload via SendMessage", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
			assert.spy(sendMessageSpy).was.called(1)
		end)

		it("payload has no buttonValidity when no validity cached", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_nil(payload.buttonValidity)
		end)

		it("payload has no playerSelection before any Submit*", function()
			LootRolls._dropStates["1_1"] = { state = "pending" }
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_nil(payload.playerSelection)
		end)
	end)

	-- ── Full end-to-end flow ──────────────────────────────────────────────────

	describe("Full E2E flow: pending → resolved", function()
		it("complete raid roll scenario — event dispatch and resolution", function()
			-- Step 1: Roll starts — START_LOOT_ROLL fires first on Retail, staging validity.
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 77, 60)

			-- LOOT_HISTORY_UPDATE_DROP arrives with encounterID/lootListID.
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 10, 3)

			-- Validity cached, payload dispatched.
			assert.is_not_nil(LootRolls._buttonValidityCache["10_3"])
			assert.spy(sendMessageSpy).was.called(1)

			-- Step 2: Roll resolves — LOOT_HISTORY_UPDATE_DROP for resolved drop.
			local selfRoll = { playerName = "Me", roll = 67, state = 0, isSelf = true, isWinner = false }
			local resolvedDrop = makeResolvedDrop(nil, selfRoll)
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return resolvedDrop
			end

			sendMessageSpy:clear()
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 10, 3)

			assert.spy(sendMessageSpy).was.called(1)

			-- Step 3: Verify the resolved payload secondary text.
			local payload = LootRolls:BuildPayload(10, 3, resolvedDrop, "resolved")
			assert.is_not_nil(string.find(payload.secondaryText, "67"))
		end)
	end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- Classic Integration Tests
-- ═══════════════════════════════════════════════════════════════════════════════
-- These tests exercise the Classic-specific code paths introduced in S02:
--   LootRolls.START_LOOT_ROLL → BuildClassicPayload → button rendering
--   LootRolls.LOOT_ROLLS_COMPLETE → allPassed resolution → buttons hidden
--   Alt+Click escape hatch with Classic GroupLootFrame1–4
--   All three config modes on Classic
-- ═══════════════════════════════════════════════════════════════════════════════

describe("LootRolls Classic integration", function()
	local _ = match._
	---@type RLF_LootRolls
	local LootRolls, ns, sendMessageSpy

	local CLASSIC_ITEM_LINK = "|cff0070dditem:99999|r"
	local CLASSIC_TEXTURE = 132310

	--- Build a minimal Classic item info table (what GetClassicRollItemInfo returns).
	local function makeClassicItemInfo(overrides)
		local base = {
			itemLink = CLASSIC_ITEM_LINK,
			texture = CLASSIC_TEXTURE,
			quality = 3, -- Rare
			canNeed = true,
			canGreed = true,
			canDisenchant = false,
		}
		if overrides then
			for k, v in pairs(overrides) do
				base[k] = v
			end
		end
		return base
	end

	before_each(function()
		sendMessageSpy = spy.new(function() end)

		ns = {
			LootElementBase = nil,
			ItemQualEnum = { Uncommon = 2, Epic = 4 },
			DefaultIcons = { LOOTROLLS = 132319 },
			FeatureModule = { LootRolls = "LootRolls" },
			LogDebug = spy.new(function() end),
			LogInfo = spy.new(function() end),
			LogWarn = spy.new(function() end),
			LogError = spy.new(function() end),
			-- Classic client — IsRetail() returns false.
			IsRetail = function()
				return false
			end,
			SendMessage = sendMessageSpy,
			TooltipBuilders = nil,
			db = {
				global = {
					animations = { exit = { fadeOutDelay = 3 } },
					misc = { hideAllIcons = false },
				},
			},
			WoWAPI = { LootRolls = {} },
			DbAccessor = {
				IsFeatureNeededByAnyFrame = function()
					return true
				end,
				AnyFeatureConfig = function(_, featureKey)
					if featureKey == "lootRolls" then
						return {
							enableIcon = true,
							enableLootRollActions = true,
							disableLootRollFrame = true,
						}
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
				["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
				["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s, rolled %d",
			},
			RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
		}

		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)

		ns.FeatureBase = {
			new = function(_, name)
				return {
					moduleName = name,
					Enable = function() end,
					Disable = function() end,
					IsEnabled = function()
						return true
					end,
					RegisterEvent = function() end,
					UnregisterAllEvents = function() end,
				}
			end,
		}

		LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
		assert.is_not_nil(LootRolls)
		ns.LootRolls = LootRolls

		-- Classic adapter stubs.
		LootRolls._lootRollsAdapter = {
			HasLootHistory = function()
				return false
			end,
			HasStartLootRollEvent = function()
				return true
			end,
			GetClassicRollItemInfo = function(_rollID)
				return makeClassicItemInfo()
			end,
			GetItemInfoIcon = function()
				return CLASSIC_TEXTURE
			end,
			GetItemInfoQuality = function()
				return 3
			end,
			-- Retail stubs — not used on Classic path but prevent nil errors.
			GetSortedInfoForDrop = function()
				return nil
			end,
			GetInfoForEncounter = function()
				return nil
			end,
			GetRaidClassColor = function()
				return nil
			end,
			GetRollButtonValidity = function()
				return nil
			end,
		}

		LootRolls._dropStates = {}
		LootRolls._buttonValidityCache = {}

		-- GetTime is used by BuildClassicDropInfo to record startTime.
		_G.GetTime = function()
			return 1000
		end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- ── Classic Scenario 1: START_LOOT_ROLL → payload dispatched ─────────────

	describe("Classic Scenario 1: START_LOOT_ROLL fires → payload dispatched with correct shape", function()
		it("Classic START_LOOT_ROLL dispatches a payload via SendMessage", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 42, 60)
			assert.spy(sendMessageSpy).was.called(1)
		end)

		it("Classic drop state entry is created with _isClassic=true and state=pending", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 42, 60)
			local entry = LootRolls._dropStates["42_42"]
			assert.is_not_nil(entry)
			assert.are.equal("pending", entry.state)
			assert.is_true(entry._isClassic)
			assert.are.equal(42, entry._rollID)
		end)

		it("Classic payload key follows 'LR_<rollID>_<rollID>' format", function()
			local payload = LootRolls:BuildClassicPayload(7, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				winner = nil,
				allPassed = false,
				isTied = false,
				currentLeader = nil,
				rollInfos = {},
			}, "pending", makeClassicItemInfo())
			assert.are.equal("LR_7_7", payload.key)
		end)

		it("Classic payload type is FeatureModule.LootRolls", function()
			local payload = LootRolls:BuildClassicPayload(1, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
			}, "pending", makeClassicItemInfo())
			assert.are.equal("LootRolls", payload.type)
		end)

		it("Classic payload encounterID and lootListID both equal rollID", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 55, 60)
			-- Check the drop state key uses rollID_rollID.
			assert.is_not_nil(LootRolls._dropStates["55_55"])
			-- BuildClassicPayload sets both IDs to rollID.
			local payload = LootRolls:BuildClassicPayload(55, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
			}, "pending", makeClassicItemInfo())
			assert.are.equal(55, payload.encounterID)
			assert.are.equal(55, payload.lootListID)
		end)

		it("Classic pending payload rollState=pending", function()
			local payload = LootRolls:BuildClassicPayload(1, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
			}, "pending", makeClassicItemInfo())
			assert.are.equal("pending", payload.rollState)
		end)

		it("Classic pending secondaryText is 'Waiting for rolls'", function()
			local payload = LootRolls:BuildClassicPayload(1, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
				startTime = 1000,
				duration = 60,
			}, "pending", makeClassicItemInfo())
			assert.are.equal("Waiting for rolls", payload.secondaryText)
		end)

		it("Classic payload icon comes from itemInfo.texture when available", function()
			local payload = LootRolls:BuildClassicPayload(1, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
			}, "pending", makeClassicItemInfo({ texture = CLASSIC_TEXTURE }))
			assert.are.equal(CLASSIC_TEXTURE, payload.icon)
		end)

		it("Classic payload textFn returns item hyperlink", function()
			local payload = LootRolls:BuildClassicPayload(1, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
			}, "pending", makeClassicItemInfo())
			assert.are.equal(CLASSIC_ITEM_LINK, payload.textFn(nil, nil))
		end)

		it("Classic payload textFn returns truncated link when provided", function()
			local payload = LootRolls:BuildClassicPayload(1, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
			}, "pending", makeClassicItemInfo())
			assert.are.equal("short", payload.textFn(nil, "short"))
		end)

		it("Classic payload isLink=true and quantity=0", function()
			local payload = LootRolls:BuildClassicPayload(1, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
			}, "pending", makeClassicItemInfo())
			assert.is_true(payload.isLink)
			assert.are.equal(0, payload.quantity)
		end)
	end)

	-- ── Classic Scenario 2: button validity from GetClassicRollItemInfo ────────

	describe("Classic Scenario 2: button validity from GetClassicRollItemInfo", function()
		it("Classic validity cache: canNeed=true, canGreed=true, canTransmog always false", function()
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function()
				return makeClassicItemInfo({ canNeed = true, canGreed = true, canDisenchant = true })
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 10, 60)

			local cached = LootRolls._buttonValidityCache["10_10"]
			assert.is_not_nil(cached)
			assert.is_true(cached.canNeed)
			assert.is_true(cached.canGreed)
			assert.is_false(cached.canTransmog) -- always false on Classic
			assert.is_true(cached.canDisenchant)
			assert.is_true(cached.canPass) -- always true
		end)

		it("Classic payload carries buttonValidity from cache after START_LOOT_ROLL", function()
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function()
				return makeClassicItemInfo({ canNeed = true, canGreed = false, canDisenchant = true })
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 11, 60)

			-- Rebuild payload to inspect buttonValidity.
			local dropInfo = LootRolls._dropStates["11_11"]._dropInfo
			local payload = LootRolls:BuildClassicPayload(11, dropInfo, "pending", nil)

			assert.is_not_nil(payload.buttonValidity)
			assert.is_true(payload.buttonValidity.canNeed)
			assert.is_false(payload.buttonValidity.canGreed)
			assert.is_false(payload.buttonValidity.canTransmog)
			assert.is_true(payload.buttonValidity.canDisenchant)
			assert.is_true(payload.buttonValidity.canPass)
		end)

		it("Classic row buttons: NEED enabled, GREED enabled (canGreed=true)", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true, disableLootRollFrame = true }
				end
			end

			row:UpdateLootRollButtons({
				rollState = "pending",
				lootListID = 10,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			})

			assert.is_true(row.NeedButton._enabled)
			assert.is_true(row.GreedButton._enabled)
			assert.is_true(row.PassButton._enabled)
		end)

		it("Classic row: all three buttons shown when pending with enableLootRollActions=true", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true, disableLootRollFrame = true }
				end
			end

			row:UpdateLootRollButtons({
				rollState = "pending",
				lootListID = 10,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			})

			assert.is_true(row.NeedButton._shown)
			assert.is_true(row.GreedButton._shown)
			assert.is_true(row.PassButton._shown)
		end)

		it("Classic row: GREED button disabled when canGreed=false, canDisenchant=false", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true }
				end
			end

			-- Classic: canDisenchant=false → DISENCHANT slot is disabled
			row:UpdateLootRollButtons({
				rollState = "pending",
				lootListID = 10,
				buttonValidity = {
					canNeed = true,
					canGreed = false,
					canDisenchant = false,
					canTransmog = false,
					canPass = true,
				},
			})

			assert.is_false(row.GreedButton._enabled)
			assert.is_true(row.NeedButton._enabled)
		end)
	end)

	-- ── Classic Scenario 3: LOOT_ROLLS_COMPLETE → buttons hidden ──────────────

	describe("Classic Scenario 3: LOOT_ROLLS_COMPLETE fires → allPassed state, buttons hidden", function()
		it("LOOT_ROLLS_COMPLETE moves pending Classic drop to allPassed", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 20, 60)
			assert.are.equal("pending", LootRolls._dropStates["20_20"].state)

			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 99)

			assert.are.equal("allPassed", LootRolls._dropStates["20_20"].state)
		end)

		it("LOOT_ROLLS_COMPLETE clears button validity cache", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 21, 60)
			assert.is_not_nil(LootRolls._buttonValidityCache["21_21"])

			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 99)

			assert.is_nil(LootRolls._buttonValidityCache["21_21"])
		end)

		it("LOOT_ROLLS_COMPLETE dispatches allPassed payload via SendMessage", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 22, 60)
			sendMessageSpy:clear()

			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 99)

			assert.spy(sendMessageSpy).was.called(1)
		end)

		it("Classic allPassed payload secondary text is 'All Passed'", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 23, 60)
			local entry = LootRolls._dropStates["23_23"]
			local dropInfo = entry._dropInfo
			dropInfo.allPassed = true

			local payload = LootRolls:BuildClassicPayload(23, dropInfo, "allPassed", nil)
			assert.are.equal("All Passed", payload.secondaryText)
		end)

		it("Classic row buttons hidden after allPassed (no buttonValidity)", function()
			local row = buildMockRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true, disableLootRollFrame = true }
				end
			end

			-- First show them as pending.
			row:UpdateLootRollButtons({
				rollState = "pending",
				lootListID = 20,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			})
			assert.is_true(row.NeedButton._shown)

			-- Now allPassed — payload has no buttonValidity, rollState != pending.
			row:UpdateLootRollButtons({
				rollState = "allPassed",
				lootListID = 20,
				buttonValidity = nil,
			})
			assert.is_false(row.NeedButton._shown)
			assert.is_false(row.GreedButton._shown)
			assert.is_false(row.PassButton._shown)
		end)

		it("LOOT_ROLLS_COMPLETE does not affect Retail (non-Classic) drop states", function()
			-- Inject a Retail-style pending entry (no _isClassic flag).
			LootRolls._dropStates["5_2"] = { state = "pending", _isClassic = false }

			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 99)

			-- Retail entry untouched.
			assert.are.equal("pending", LootRolls._dropStates["5_2"].state)
		end)
	end)

	-- ── Classic Scenario 4: roll submission routing ────────────────────────────

	-- ── Classic Scenario 5: player selection in payload ────────────────────────

	describe("Classic Scenario 5: playerSelection label included in Classic payload after submit", function()
		it("BuildClassicPayload includes playerSelection when recorded in drop state", function()
			LootRolls._dropStates["40_40"] = {
				state = "pending",
				_isClassic = true,
				_rollID = 40,
				playerSelection = "GREED",
			}
			local payload = LootRolls:BuildClassicPayload(40, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
			}, "pending", makeClassicItemInfo())
			assert.are.equal("GREED", payload.playerSelection)
		end)

		it("BuildClassicPayload has no playerSelection before any Submit*", function()
			LootRolls._dropStates["41_41"] = { state = "pending", _isClassic = true, _rollID = 41 }
			local payload = LootRolls:BuildClassicPayload(41, {
				itemHyperlink = CLASSIC_ITEM_LINK,
				rollInfos = {},
			}, "pending", makeClassicItemInfo())
			assert.is_nil(payload.playerSelection)
		end)
	end)

	-- ── Classic Scenario 6: Full Classic E2E flow ─────────────────────────────

	describe("Classic Scenario 6: Full Classic E2E — START_LOOT_ROLL → LOOT_ROLLS_COMPLETE", function()
		it("complete Classic raid roll scenario — event dispatch and resolution", function()
			-- Step 1: Roll starts — START_LOOT_ROLL.
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function()
				return makeClassicItemInfo({ canNeed = true, canGreed = true, canDisenchant = false })
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 60, 60)

			local entry = LootRolls._dropStates["60_60"]
			assert.is_not_nil(entry)
			assert.are.equal("pending", entry.state)
			assert.is_true(entry._isClassic)
			assert.is_not_nil(LootRolls._buttonValidityCache["60_60"])
			assert.spy(sendMessageSpy).was.called(1)

			-- Step 2: LOOT_ROLLS_COMPLETE fires.
			sendMessageSpy:clear()
			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 99)

			assert.are.equal("allPassed", LootRolls._dropStates["60_60"].state)
			assert.is_nil(LootRolls._buttonValidityCache["60_60"])
			assert.spy(sendMessageSpy).was.called(1) -- re-dispatch with allPassed

			-- Step 3: Verify allPassed payload secondary text.
			local dropInfo = LootRolls._dropStates["60_60"]._dropInfo
			local payload = LootRolls:BuildClassicPayload(60, dropInfo, "allPassed", nil)
			assert.are.equal("All Passed", payload.secondaryText)
			assert.are.equal("allPassed", payload.rollState)
		end)
	end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- LootRolls unmatched pending action debug scan tests
-- ═══════════════════════════════════════════════════════════════════════════════
-- These tests exercise ScanUnmatchedPendingActions() and verify the integration
-- with LOOT_HISTORY_UPDATE_DROP which triggers the scan on every incoming drop.
-- ═══════════════════════════════════════════════════════════════════════════════

describe("LootRolls unmatched pending actions scan", function()
	local _ = match._
	---@type RLF_LootRolls
	local LootRolls, ns, logDebugSpy

	local ITEM_LINK_A = "|cff0070dditem:11111|r"
	local ITEM_LINK_B = "|cff0070dditem:22222|r"

	before_each(function()
		logDebugSpy = spy.new(function() end)

		ns = {
			LootElementBase = nil,
			ItemQualEnum = { Uncommon = 2, Epic = 4 },
			DefaultIcons = { LOOTROLLS = 132319 },
			FeatureModule = { LootRolls = "LootRolls" },
			LogDebug = logDebugSpy,
			LogInfo = spy.new(function() end),
			LogWarn = spy.new(function() end),
			LogError = spy.new(function() end),
			IsRetail = function()
				return true
			end,
			SendMessage = spy.new(function() end),
			TooltipBuilders = nil,
			db = {
				global = {
					animations = { exit = { fadeOutDelay = 3 } },
					misc = { hideAllIcons = false },
				},
			},
			WoWAPI = { LootRolls = {} },
			DbAccessor = {
				IsFeatureNeededByAnyFrame = function()
					return true
				end,
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
				["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
				["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s, rolled %d",
			},
			RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
		}

		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)

		ns.FeatureBase = {
			new = function(_, name)
				return {
					moduleName = name,
					Enable = function() end,
					Disable = function() end,
					IsEnabled = function()
						return true
					end,
					RegisterEvent = function() end,
					UnregisterAllEvents = function() end,
				}
			end,
		}

		LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
		assert.is_not_nil(LootRolls)

		LootRolls._lootRollsAdapter = {
			HasLootHistory = function()
				return true
			end,
			GetSortedInfoForDrop = function()
				return nil
			end,
			GetInfoForEncounter = function()
				return nil
			end,
			GetRaidClassColor = function()
				return nil
			end,
			GetItemInfoIcon = function()
				return 12345
			end,
			GetItemInfoQuality = function()
				return 4
			end,
			GetRollButtonValidity = function()
				return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
			end,
			GetRetailRollItemLink = function()
				return ITEM_LINK_A
			end,
		}

		LootRolls._dropStates = {}
		LootRolls._buttonValidityCache = {}
		LootRolls._stagedRollValidity = {}
		-- MatchActionToResult (called in LOOT_HISTORY_UPDATE_DROP since S03/T01)
		-- uses CurrentTimestamp() → GetTime(). Provide a deterministic stub so
		-- tests that fire the handler do not crash on a nil global.
		_G.GetTime = function() return 2000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- ── ScanUnmatchedPendingActions unit-level tests ──────────────────────────

	describe("ScanUnmatchedPendingActions: direct function tests", function()
		it("emits summary log when queue is empty", function()
			-- Empty queue → 0 pending, 0 stale.
			LootRolls._pendingActions = {}
			LootRolls.CurrentTimestamp = function()
				return 2000
			end

			LootRolls:ScanUnmatchedPendingActions()

			-- Summary line logged somewhere.
			assert.spy(logDebugSpy).was.called_with(
				match._,
				"ScanUnmatchedPendingActions: summary",
				match.is_string(),
				match.is_string(),
				"0 pending actions;",
				"0 unmatched (>10s old);",
				"0 within window"
			)
		end)

		it("does NOT log stale warning for an action exactly 10s old (boundary: must be >10s)", function()
			LootRolls._pendingActions[1] = {
				itemLink = ITEM_LINK_A,
				rollType = "NEED",
				rollValue = 55,
				timestamp = 990,
			}
			-- age = 1000 - 990 = 10s exactly → NOT stale (>10s, not >=)
			LootRolls.CurrentTimestamp = function()
				return 1000
			end

			LootRolls:ScanUnmatchedPendingActions()

			-- Summary: 1 pending, 0 stale.
			assert.spy(logDebugSpy).was.called_with(
				match._,
				"ScanUnmatchedPendingActions: summary",
				match.is_string(),
				match.is_string(),
				"1 pending actions;",
				"0 unmatched (>10s old);",
				"1 within window"
			)
		end)

		it("logs a stale warning for an action 11s old (>10s threshold)", function()
			LootRolls._pendingActions[42] = {
				itemLink = ITEM_LINK_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 989,
			}
			-- age = 1000 - 989 = 11s → stale
			LootRolls.CurrentTimestamp = function()
				return 1000
			end

			LootRolls:ScanUnmatchedPendingActions()

			-- Summary: 1 pending, 1 stale.
			assert.spy(logDebugSpy).was.called_with(
				match._,
				"ScanUnmatchedPendingActions: summary",
				match.is_string(),
				match.is_string(),
				"1 pending actions;",
				"1 unmatched (>10s old);",
				"0 within window"
			)
			-- Individual stale entry log includes rollID, itemLink, rollType.
			assert.spy(logDebugSpy).was.called_with(
				match._,
				"ScanUnmatchedPendingActions: STALE entry",
				match.is_string(),
				match.is_string(),
				"rollID=42",
				"itemLink=" .. ITEM_LINK_A,
				"rollType=GREED",
				"rollValue=nil",
				match.is_string(), -- age string
				match.is_string() -- cause string
			)
		end)

		it("counts fresh and stale entries independently", function()
			-- Fresh entry: 5s old.
			LootRolls._pendingActions[1] = {
				itemLink = ITEM_LINK_A,
				rollType = "NEED",
				rollValue = 77,
				timestamp = 995,
			}
			-- Stale entry A: 15s old.
			LootRolls._pendingActions[2] = {
				itemLink = ITEM_LINK_B,
				rollType = "PASS",
				rollValue = nil,
				timestamp = 985,
			}
			-- Stale entry B: 11s old.
			LootRolls._pendingActions[3] = {
				itemLink = ITEM_LINK_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 989,
			}
			LootRolls.CurrentTimestamp = function()
				return 1000
			end

			LootRolls:ScanUnmatchedPendingActions()

			-- 3 total, 2 stale, 1 within window.
			assert.spy(logDebugSpy).was.called_with(
				match._,
				"ScanUnmatchedPendingActions: summary",
				match.is_string(),
				match.is_string(),
				"3 pending actions;",
				"2 unmatched (>10s old);",
				"1 within window"
			)
		end)

		it("does NOT remove stale entries (they remain for potential late matching)", function()
			LootRolls._pendingActions[99] = {
				itemLink = ITEM_LINK_A,
				rollType = "NEED",
				rollValue = 44,
				timestamp = 980,
			}
			-- age = 20s → stale
			LootRolls.CurrentTimestamp = function()
				return 1000
			end

			LootRolls:ScanUnmatchedPendingActions()

			-- Entry must still be present after scan (not removed).
			assert.is_not_nil(LootRolls._pendingActions[99])
		end)

		it("stale log line includes rollValue when present (NEED rolls)", function()
			LootRolls._pendingActions[7] = {
				itemLink = ITEM_LINK_B,
				rollType = "NEED",
				rollValue = 83,
				timestamp = 980,
			}
			LootRolls.CurrentTimestamp = function()
				return 1000
			end

			LootRolls:ScanUnmatchedPendingActions()

			-- The per-entry log must include rollValue=83.
			assert.spy(logDebugSpy).was.called_with(
				match._,
				"ScanUnmatchedPendingActions: STALE entry",
				match.is_string(),
				match.is_string(),
				"rollID=7",
				"itemLink=" .. ITEM_LINK_B,
				"rollType=NEED",
				"rollValue=83",
				match.is_string(),
				match.is_string()
			)
		end)
	end)

	-- ── LOOT_HISTORY_UPDATE_DROP triggers scan ────────────────────────────────

	describe("LOOT_HISTORY_UPDATE_DROP triggers ScanUnmatchedPendingActions", function()
		it("scan is called when LOOT_HISTORY_UPDATE_DROP fires with a valid drop", function()
			local scanCalled = false
			LootRolls.ScanUnmatchedPendingActions = function(self)
				scanCalled = true
			end

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return {
					itemHyperlink = ITEM_LINK_A,
					winner = nil,
					allPassed = false,
					isTied = false,
					currentLeader = nil,
					rollInfos = {},
				}
			end

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 5, 2)

			assert.is_true(scanCalled)
		end)

		it("scan is NOT called when GetSortedInfoForDrop returns nil", function()
			local scanCalled = false
			LootRolls.ScanUnmatchedPendingActions = function(self)
				scanCalled = true
			end

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return nil
			end

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 5, 2)

			assert.is_false(scanCalled)
		end)

		it("scan is NOT called for a drop already in terminal state", function()
			-- Pre-set the drop as resolved (terminal).
			LootRolls._dropStates["5_2"] = { state = "resolved" }

			local scanCalled = false
			LootRolls.ScanUnmatchedPendingActions = function(self)
				scanCalled = true
			end

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return {
					itemHyperlink = ITEM_LINK_A,
					winner = { playerName = "Warrior" },
					allPassed = false,
					rollInfos = {},
				}
			end

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 5, 2)

			assert.is_false(scanCalled)
		end)
	end)
end)

