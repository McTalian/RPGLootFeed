---@diagnostic disable: need-check-nil
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local stub = busted.stub

describe("LootRolls module", function()
	local _ = match._
	---@type RLF_LootRolls
	local LootRolls, ns, sendMessageSpy

	-- ── Shared dropInfo fixtures ────────────────────────────────────────────────

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

	local function makeResolvedDrop(winner, selfRoll)
		return {
			itemHyperlink = ITEM_LINK,
			winner = winner or {
				playerName = "Arthas",
				playerClass = "DEATHKNIGHT",
				roll = 87,
				state = 0,
				isSelf = false,
				isWinner = true,
			},
			allPassed = false,
			isTied = false,
			currentLeader = nil,
			rollInfos = selfRoll and { selfRoll } or {},
			playerRollState = selfRoll and selfRoll.state or nil,
		}
	end

	local function makeAllPassedDrop()
		return {
			itemHyperlink = ITEM_LINK,
			winner = nil,
			allPassed = true,
			isTied = false,
			currentLeader = nil,
			rollInfos = {},
		}
	end

	-- ── Test setup ─────────────────────────────────────────────────────────────

	before_each(function()
		sendMessageSpy = spy.new(function() end)

		ns = {
			LootElementBase = nil, -- populated after loadfile below
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
			TooltipBuilders = nil, -- tests that need it set it explicitly
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
						return { enableIcon = true }
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
				["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
			},
		}

		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
		assert.is_not_nil(ns.LootElementBase)

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

		-- Default adapter: HasLootHistory=true, GetSortedInfoForDrop returns nil
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
		}

		-- Reset drop state between tests
		LootRolls._dropStates = {}
	end)

	-- ── OnInitialize ──────────────────────────────────────────────────────────

	describe("OnInitialize", function()
		it("enables module when lootRolls needed by any frame", function()
			local enableSpy = spy.on(LootRolls, "Enable")
			LootRolls:OnInitialize()
			assert.spy(enableSpy).was.called(1)
		end)

		it("disables module when lootRolls not needed", function()
			ns.DbAccessor.IsFeatureNeededByAnyFrame = function()
				return false
			end
			local disableSpy = spy.on(LootRolls, "Disable")
			LootRolls:OnInitialize()
			assert.spy(disableSpy).was.called(1)
		end)
	end)

	-- ── OnEnable / OnDisable ──────────────────────────────────────────────────

	describe("OnEnable", function()
		it("registers LOOT_HISTORY_UPDATE_DROP on Retail with C_LootHistory available", function()
			local regSpy = spy.on(LootRolls, "RegisterEvent")
			LootRolls:OnEnable()
			assert.spy(regSpy).was.called_with(LootRolls, "LOOT_HISTORY_UPDATE_DROP")
		end)

		it("does not register event on non-Retail", function()
			ns.IsRetail = function()
				return false
			end
			local regSpy = spy.on(LootRolls, "RegisterEvent")
			LootRolls:OnEnable()
			assert.spy(regSpy).was.not_called()
		end)

		it("does not register event when C_LootHistory unavailable", function()
			LootRolls._lootRollsAdapter.HasLootHistory = function()
				return false
			end
			local regSpy = spy.on(LootRolls, "RegisterEvent")
			LootRolls:OnEnable()
			assert.spy(regSpy).was.not_called()
		end)
	end)

	describe("OnDisable", function()
		it("unregisters all events", function()
			local unregSpy = spy.on(LootRolls, "UnregisterAllEvents")
			LootRolls:OnDisable()
			assert.spy(unregSpy).was.called(1)
		end)

		it("resets _dropStates", function()
			LootRolls._dropStates["1_1"] = { state = "pending" }
			LootRolls:OnDisable()
			assert.are.same({}, LootRolls._dropStates)
		end)
	end)

	-- ── BuildPayload ──────────────────────────────────────────────────────────

	describe("BuildPayload", function()
		it("returns nil when module is disabled", function()
			LootRolls.IsEnabled = function()
				return false
			end
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_nil(payload)
		end)

		it("returns nil when enableLootRollResults is false", function()
			local origFn = ns.DbAccessor.AnyFeatureConfig
			ns.DbAccessor.AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return { enableLootRollResults = false }
				end
				return origFn(_, featureKey)
			end
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_nil(payload)
			ns.DbAccessor.AnyFeatureConfig = origFn
		end)

		it("returns payload when enableLootRollResults is true (explicit)", function()
			local origFn = ns.DbAccessor.AnyFeatureConfig
			ns.DbAccessor.AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return { enableLootRollResults = true, enableIcon = true }
				end
				return origFn(_, featureKey)
			end
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_not_nil(payload)
			ns.DbAccessor.AnyFeatureConfig = origFn
		end)

		it("sets key from encounterID and lootListID", function()
			local payload = LootRolls:BuildPayload(42, 7, makePendingDrop(), "pending")
			assert.are.equal("LR_42_7", payload.key)
		end)

		it("sets type to LootRolls FeatureModule", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.are.equal("LootRolls", payload.type)
		end)

		it("sets quantity to 0", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.are.equal(0, payload.quantity)
		end)

		it("sets isLink to true", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_true(payload.isLink)
		end)

		it("includes icon when enableIcon is true and hideAllIcons is false", function()
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_not_nil(payload.icon)
		end)

		it("omits icon when hideAllIcons is true", function()
			ns.db.global.misc.hideAllIcons = true
			local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
			assert.is_nil(payload.icon)
		end)

		describe("allPassed state", function()
			it("sets secondaryText to All Passed", function()
				local payload = LootRolls:BuildPayload(1, 1, makeAllPassedDrop(), "allPassed")
				assert.are.equal("All Passed", payload.secondaryText)
			end)
		end)

		describe("resolved state", function()
			it("includes winner name and roll in secondaryText", function()
				local drop = makeResolvedDrop()
				local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
				assert.is_not_nil(payload.secondaryText)
				assert.is_truthy(payload.secondaryText:find("Arthas"))
				assert.is_truthy(payload.secondaryText:find("87"))
			end)

			it("appends player roll when self rolled and did not win", function()
				local selfRoll = { roll = 55, state = 0, isSelf = true, isWinner = false }
				local drop = makeResolvedDrop(nil, selfRoll)
				local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
				assert.is_truthy(payload.secondaryText:find("55"))
			end)

			it("does not append player roll when self is the winner", function()
				local winner = {
					playerName = "Me",
					playerClass = "WARRIOR",
					roll = 99,
					state = 0,
					isSelf = true,
					isWinner = true,
				}
				local selfRoll = { roll = 99, state = 0, isSelf = true, isWinner = true }
				local drop = makeResolvedDrop(winner, selfRoll)
				local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
				-- secondaryText should not contain the "You: rolled" suffix format
				assert.is_falsy(payload.secondaryText:find("|  You:"))
			end)
		end)

		describe("pending state", function()
			it("sets secondaryText to waiting message when no leader", function()
				local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
				assert.are.equal("Waiting for rolls", payload.secondaryText)
			end)

			it("sets secondaryText to current leader when leader present", function()
				local drop = makePendingDrop({
					currentLeader = { playerName = "Thrall", playerClass = "SHAMAN", roll = 72 },
				})
				local payload = LootRolls:BuildPayload(1, 1, drop, "pending")
				assert.is_truthy(payload.secondaryText:find("Thrall"))
				assert.is_truthy(payload.secondaryText:find("72"))
			end)

			it("sets secondaryText to tied message when isTied", function()
				local drop = makePendingDrop({
					isTied = true,
					currentLeader = { playerName = "A", playerClass = "WARRIOR", roll = 50 },
				})
				local payload = LootRolls:BuildPayload(1, 1, drop, "pending")
				assert.is_truthy(payload.secondaryText:find("50"))
				assert.is_truthy(payload.secondaryText:find("Tied") or payload.secondaryText:find("Tied"))
			end)

			it("sets showForSeconds from startTime+duration when available", function()
				_G.GetTime = function()
					return 100
				end
				local drop = makePendingDrop({ startTime = 95, duration = 30 })
				local payload = LootRolls:BuildPayload(1, 1, drop, "pending")
				-- remaining = (95+30) - 100 = 25, plus PENDING_EXIT_BUFFER (1.0) = 26
				assert.are.equal(26.0, payload.showForSeconds)
				_G.GetTime = nil
			end)

			it("does not set showForSeconds when startTime absent", function()
				local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
				assert.is_nil(payload.showForSeconds)
			end)
		end)
	end)

	-- ── LOOT_HISTORY_UPDATE_DROP ──────────────────────────────────────────────

	describe("LOOT_HISTORY_UPDATE_DROP", function()
		before_each(function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
		end)

		it("skips dispatch when enableLootRollResults is false (first gate)", function()
			local origFn = ns.DbAccessor.AnyFeatureConfig
			ns.DbAccessor.AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return { enableLootRollResults = false }
				end
				return origFn(_, featureKey)
			end
			local dispatchSpy = spy.on(LootRolls, "DispatchPayload")
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
			assert.spy(dispatchSpy).was.not_called()
			ns.DbAccessor.AnyFeatureConfig = origFn
		end)

		it("dispatches payload when enableLootRollResults is true (first gate passes)", function()
			local origFn = ns.DbAccessor.AnyFeatureConfig
			ns.DbAccessor.AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return { enableLootRollResults = true }
				end
				return origFn(_, featureKey)
			end
			local dispatchSpy = spy.on(LootRolls, "DispatchPayload")
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
			assert.spy(dispatchSpy).was.called(1)
			ns.DbAccessor.AnyFeatureConfig = origFn
		end)

		it("dispatches payload for a new drop", function()
			local dispatchSpy = spy.on(LootRolls, "DispatchPayload")
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
			assert.spy(dispatchSpy).was.called(1)
		end)

		it("records drop state on first event", function()
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 5, 3)
			assert.is_not_nil(LootRolls._dropStates["5_3"])
			assert.are.equal("pending", LootRolls._dropStates["5_3"].state)
		end)

		it("skips dispatch when drop already in resolved terminal state", function()
			LootRolls._dropStates["1_1"] = { state = "resolved" }
			local dispatchSpy = spy.on(LootRolls, "DispatchPayload")
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
			assert.spy(dispatchSpy).was.not_called()
		end)

		it("skips dispatch when drop already in allPassed terminal state", function()
			LootRolls._dropStates["1_1"] = { state = "allPassed" }
			local dispatchSpy = spy.on(LootRolls, "DispatchPayload")
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
			assert.spy(dispatchSpy).was.not_called()
		end)

		it("updates state when pending drop becomes resolved", function()
			LootRolls._dropStates["1_1"] = { state = "pending" }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
			assert.are.equal("resolved", LootRolls._dropStates["1_1"].state)
		end)

		it("warns and skips dispatch when GetSortedInfoForDrop returns nil", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return nil
			end
			local dispatchSpy = spy.on(LootRolls, "DispatchPayload")
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
			assert.spy(dispatchSpy).was.not_called()
		end)
	end)

	-- ── DispatchPayload ───────────────────────────────────────────────────────

	describe("DispatchPayload", function()
		it("sends message via LootElementBase:Show when payload is valid", function()
			LootRolls:DispatchPayload(1, 1, makePendingDrop(), "pending")
			assert.spy(sendMessageSpy).was.called(1)
		end)

		it("does not send message when module is disabled", function()
			LootRolls.IsEnabled = function()
				return false
			end
			LootRolls:DispatchPayload(1, 1, makePendingDrop(), "pending")
			assert.spy(sendMessageSpy).was.not_called()
		end)
	end)

	-- ── Classic: OnEnable event registration ─────────────────────────────────

	describe("Classic OnEnable", function()
		before_each(function()
			ns.IsRetail = function()
				return false
			end
			LootRolls._lootRollsAdapter.HasStartLootRollEvent = function()
				return true
			end
		end)

		it("registers START_LOOT_ROLL on Classic when HasStartLootRollEvent is true", function()
			local registered = {}
			LootRolls.RegisterEvent = function(self, event)
				table.insert(registered, event)
			end
			LootRolls:OnEnable()
			local found = false
			for _, e in ipairs(registered) do
				if e == "START_LOOT_ROLL" then
					found = true
				end
			end
			assert.is_true(found)
		end)

		it("registers LOOT_ROLLS_COMPLETE on Classic when HasStartLootRollEvent is true", function()
			local registered = {}
			LootRolls.RegisterEvent = function(self, event)
				table.insert(registered, event)
			end
			LootRolls:OnEnable()
			local found = false
			for _, e in ipairs(registered) do
				if e == "LOOT_ROLLS_COMPLETE" then
					found = true
				end
			end
			assert.is_true(found)
		end)

		it("does not register LOOT_HISTORY_UPDATE_DROP on Classic", function()
			local registered = {}
			LootRolls.RegisterEvent = function(self, event)
				table.insert(registered, event)
			end
			LootRolls:OnEnable()
			for _, e in ipairs(registered) do
				assert.is_not_equal("LOOT_HISTORY_UPDATE_DROP", e)
			end
		end)

		it("does not register any event when HasStartLootRollEvent returns false", function()
			LootRolls._lootRollsAdapter.HasStartLootRollEvent = function()
				return false
			end
			local regSpy = spy.on(LootRolls, "RegisterEvent")
			LootRolls:OnEnable()
			assert.spy(regSpy).was.not_called()
		end)
	end)

	-- ── Classic: START_LOOT_ROLL handler ──────────────────────────────────────

	describe("Classic START_LOOT_ROLL", function()
		local CLASSIC_ITEM_LINK = "|cff0070dditem:99999|r"
		local function makeClassicItemInfo(overrides)
			local base = {
				texture = "Interface\\Icons\\INV_Sword_01",
				name = "Sword of the Gods",
				count = 1,
				quality = 4,
				canNeed = true,
				canGreed = true,
				canDisenchant = false,
				itemLink = CLASSIC_ITEM_LINK,
			}
			if overrides then
				for k, v in pairs(overrides) do
					base[k] = v
				end
			end
			return base
		end

		before_each(function()
			ns.IsRetail = function()
				return false
			end
			_G.GetTime = function()
				return 1000
			end
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function(_rollID)
				return makeClassicItemInfo()
			end
			LootRolls._lootRollsAdapter.HasStartLootRollEvent = function()
				return true
			end
		end)

		it("dispatches Classic payload on START_LOOT_ROLL", function()
			local dispatchSpy = spy.on(LootRolls, "DispatchClassicPayload")
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 42, 60)
			assert.spy(dispatchSpy).was.called(1)
		end)

		it("records pending drop state with _isClassic flag", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 42, 60)
			local entry = LootRolls._dropStates["42_42"]
			assert.is_not_nil(entry)
			assert.are.equal("pending", entry.state)
			assert.is_true(entry._isClassic)
		end)

		it("caches button validity on first START_LOOT_ROLL", function()
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function()
				return makeClassicItemInfo({ canNeed = true, canGreed = true, canDisenchant = true })
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 7, 60)
			local cached = LootRolls._buttonValidityCache["7_7"]
			assert.is_not_nil(cached)
			assert.is_true(cached.canNeed)
			assert.is_true(cached.canGreed)
			assert.is_true(cached.canDisenchant)
			assert.is_false(cached.canTransmog)
			assert.is_true(cached.canPass)
			assert.is_true(cached.isCached)
		end)

		it("does not re-cache validity when called again for same rollID", function()
			local callCount = 0
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function()
				callCount = callCount + 1
				return makeClassicItemInfo()
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 5, 60)
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 5, 60)
			assert.are.equal(2, callCount)
			assert.is_not_nil(LootRolls._buttonValidityCache["5_5"])
		end)

		it("skips dispatch when GetClassicRollItemInfo returns nil", function()
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function()
				return nil
			end
			local dispatchSpy = spy.on(LootRolls, "DispatchClassicPayload")
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 3, 60)
			assert.spy(dispatchSpy).was.not_called()
		end)

		it("skips dispatch when itemLink is nil", function()
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function()
				-- Return itemInfo without itemLink to simulate API returning no link.
				return {
					texture = "tex",
					name = "Sword",
					count = 1,
					quality = 4,
					canNeed = true,
					canGreed = true,
					canDisenchant = false,
				}
			end
			local dispatchSpy = spy.on(LootRolls, "DispatchClassicPayload")
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 3, 60)
			assert.spy(dispatchSpy).was.not_called()
		end)

		it("skips dispatch when drop is already terminal", function()
			LootRolls._dropStates["10_10"] = { state = "resolved", _isClassic = true, _rollID = 10 }
			local dispatchSpy = spy.on(LootRolls, "DispatchClassicPayload")
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 10, 60)
			assert.spy(dispatchSpy).was.not_called()
		end)

		it("stores _dropInfo on state entry after START_LOOT_ROLL", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 20, 60)
			local entry = LootRolls._dropStates["20_20"]
			assert.is_not_nil(entry._dropInfo)
		end)
	end)

	-- ── Classic: BuildClassicPayload ──────────────────────────────────────────

	describe("Classic BuildClassicPayload", function()
		local CLASSIC_ITEM_LINK = "|cff0070dditem:99999|r"
		local function makeClassicDropInfo(overrides)
			local base = {
				itemHyperlink = CLASSIC_ITEM_LINK,
				winner = nil,
				allPassed = false,
				isTied = false,
				currentLeader = nil,
				rollInfos = {},
				startTime = 1000,
				duration = 60,
			}
			if overrides then
				for k, v in pairs(overrides) do
					base[k] = v
				end
			end
			return base
		end

		local function makeClassicItemInfo()
			return {
				texture = "Interface\\Icons\\INV_Sword_01",
				name = "Sword",
				count = 1,
				quality = 4,
				canNeed = true,
				canGreed = true,
				canDisenchant = false,
				itemLink = CLASSIC_ITEM_LINK,
			}
		end

		before_each(function()
			_G.GetTime = function()
				return 1000
			end
		end)

		it("returns nil when module is disabled", function()
			LootRolls.IsEnabled = function()
				return false
			end
			local payload = LootRolls:BuildClassicPayload(42, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.is_nil(payload)
		end)

		it("sets key from rollID", function()
			local payload = LootRolls:BuildClassicPayload(42, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.are.equal("LR_42_42", payload.key)
		end)

		it("sets type to LootRolls", function()
			local payload = LootRolls:BuildClassicPayload(7, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.are.equal("LootRolls", payload.type)
		end)

		it("sets quantity to 0", function()
			local payload = LootRolls:BuildClassicPayload(1, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.are.equal(0, payload.quantity)
		end)

		it("sets isLink to true", function()
			local payload = LootRolls:BuildClassicPayload(1, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.is_true(payload.isLink)
		end)

		it("uses itemInfo texture for icon when available", function()
			local payload = LootRolls:BuildClassicPayload(1, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.are.equal("Interface\\Icons\\INV_Sword_01", payload.icon)
		end)

		it("omits icon when hideAllIcons is true", function()
			ns.db.global.misc.hideAllIcons = true
			local payload = LootRolls:BuildClassicPayload(1, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.is_nil(payload.icon)
		end)

		it("sets quality from itemInfo", function()
			local payload = LootRolls:BuildClassicPayload(1, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.are.equal(4, payload.quality)
		end)

		it("sets secondaryText to waiting message when pending", function()
			local payload = LootRolls:BuildClassicPayload(1, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.are.equal("Waiting for rolls", payload.secondaryText)
		end)

		it("sets secondaryText to All Passed when allPassed", function()
			local drop = makeClassicDropInfo({ allPassed = true })
			local payload = LootRolls:BuildClassicPayload(1, drop, "allPassed", nil)
			assert.are.equal("All Passed", payload.secondaryText)
		end)

		it("sets showForSeconds from dropInfo timing when pending", function()
			_G.GetTime = function()
				return 1000
			end
			local drop = makeClassicDropInfo({ startTime = 1000, duration = 60 })
			local payload = LootRolls:BuildClassicPayload(1, drop, "pending", makeClassicItemInfo())
			assert.are.equal(61.0, payload.showForSeconds)
		end)

		it("sets encounterID and lootListID to rollID", function()
			local payload = LootRolls:BuildClassicPayload(55, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.are.equal(55, payload.encounterID)
			assert.are.equal(55, payload.lootListID)
		end)

		it("includes buttonValidity from cache", function()
			LootRolls._buttonValidityCache["8_8"] = {
				canNeed = true,
				canGreed = false,
				canTransmog = false,
				canDisenchant = true,
				canPass = true,
				isCached = true,
			}
			local payload = LootRolls:BuildClassicPayload(8, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.is_not_nil(payload.buttonValidity)
			assert.is_true(payload.buttonValidity.canNeed)
			assert.is_false(payload.buttonValidity.canGreed)
			assert.is_false(payload.buttonValidity.canTransmog)
			assert.is_true(payload.buttonValidity.canDisenchant)
		end)

		it("includes playerSelection from drop state", function()
			LootRolls._dropStates["9_9"] = { state = "pending", playerSelection = "GREED", _isClassic = true }
			local payload = LootRolls:BuildClassicPayload(9, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.are.equal("GREED", payload.playerSelection)
		end)
	end)

	-- ── Classic: LOOT_ROLLS_COMPLETE handler ──────────────────────────────────

	describe("Classic LOOT_ROLLS_COMPLETE", function()
		before_each(function()
			ns.IsRetail = function()
				return false
			end
			_G.GetTime = function()
				return 1000
			end
		end)

		it("marks pending Classic drops as allPassed", function()
			LootRolls._dropStates["15_15"] = {
				state = "pending",
				_isClassic = true,
				_rollID = 15,
				_dropInfo = { itemHyperlink = "|cff0070dditem:15|r", allPassed = false, rollInfos = {} },
			}
			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 999)
			assert.are.equal("allPassed", LootRolls._dropStates["15_15"].state)
		end)

		it("clears button validity cache for completed Classic drops", function()
			LootRolls._dropStates["16_16"] = {
				state = "pending",
				_isClassic = true,
				_rollID = 16,
				_dropInfo = { itemHyperlink = "|cff0070dditem:16|r", allPassed = false, rollInfos = {} },
			}
			LootRolls._buttonValidityCache["16_16"] = { canNeed = true, isCached = true }
			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 999)
			assert.is_nil(LootRolls._buttonValidityCache["16_16"])
		end)

		it("does not touch already-terminal drops", function()
			LootRolls._dropStates["17_17"] = {
				state = "resolved",
				_isClassic = true,
				_rollID = 17,
				_dropInfo = { itemHyperlink = "|cff0070dditem:17|r", allPassed = false, rollInfos = {} },
			}
			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 999)
			assert.are.equal("resolved", LootRolls._dropStates["17_17"].state)
		end)

		it("does not affect non-classic pending entries", function()
			LootRolls._dropStates["18_18"] = { state = "pending", _isClassic = nil }
			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 999)
			assert.are.equal("pending", LootRolls._dropStates["18_18"].state)
		end)

		it("dispatches allPassed payload for completed Classic drops", function()
			LootRolls._dropStates["19_19"] = {
				state = "pending",
				_isClassic = true,
				_rollID = 19,
				_dropInfo = { itemHyperlink = "|cff0070dditem:19|r", allPassed = false, rollInfos = {} },
			}
			local dispatchSpy = spy.on(LootRolls, "DispatchClassicPayload")
			LootRolls:LOOT_ROLLS_COMPLETE("LOOT_ROLLS_COMPLETE", 999)
			assert.spy(dispatchSpy).was.called(1)
		end)
	end)

	-- ── Classic: SubmitClassicRoll ─────────────────────────────────────────────

	describe("Classic SubmitClassicRoll", function()
		before_each(function()
			ns.IsRetail = function()
				return false
			end
			LootRolls._lootRollsAdapter.ClassicRollOnLoot = function(_rollID, _rollType)
				return true
			end
			LootRolls._dropStates["30_30"] = {
				state = "pending",
				_isClassic = true,
				_rollID = 30,
				_dropInfo = { itemHyperlink = "|cff0070dditem:30|r", allPassed = false, rollInfos = {} },
			}
		end)

		it("calls ClassicRollOnLoot with NEED type (1)", function()
			local capturedType
			LootRolls._lootRollsAdapter.ClassicRollOnLoot = function(_rollID, rollType)
				capturedType = rollType
				return true
			end
			LootRolls:SubmitClassicRoll(30, "NEED")
			assert.are.equal(1, capturedType)
		end)

		it("calls ClassicRollOnLoot with GREED type (2)", function()
			local capturedType
			LootRolls._lootRollsAdapter.ClassicRollOnLoot = function(_rollID, rollType)
				capturedType = rollType
				return true
			end
			LootRolls:SubmitClassicRoll(30, "GREED")
			assert.are.equal(2, capturedType)
		end)

		it("calls ClassicRollOnLoot with DISENCHANT type (3)", function()
			local capturedType
			LootRolls._lootRollsAdapter.ClassicRollOnLoot = function(_rollID, rollType)
				capturedType = rollType
				return true
			end
			LootRolls:SubmitClassicRoll(30, "DISENCHANT")
			assert.are.equal(3, capturedType)
		end)

		it("calls ClassicRollOnLoot with PASS type (0)", function()
			local capturedType
			LootRolls._lootRollsAdapter.ClassicRollOnLoot = function(_rollID, rollType)
				capturedType = rollType
				return true
			end
			LootRolls:SubmitClassicRoll(30, "PASS")
			assert.are.equal(0, capturedType)
		end)

		it("records playerSelection in drop state", function()
			LootRolls:SubmitClassicRoll(30, "NEED")
			assert.are.equal("NEED", LootRolls._dropStates["30_30"].playerSelection)
		end)

		it("does not record selection when ClassicRollOnLoot fails", function()
			LootRolls._lootRollsAdapter.ClassicRollOnLoot = function(_rollID, _rollType)
				return false, "API unavailable"
			end
			LootRolls:SubmitClassicRoll(30, "GREED")
			assert.is_nil(LootRolls._dropStates["30_30"].playerSelection)
		end)

		it("logs warning for unrecognised rollTypeName (TRANSMOG not valid on Classic)", function()
			local warnCalled = false
			ns.LogWarn = function(...)
				warnCalled = true
			end
			LootRolls:SubmitClassicRoll(30, "TRANSMOG")
			assert.is_true(warnCalled)
		end)
	end)

	-- ── Action row lifecycle: hide on outcome events ──────────────────────────────

	describe("Action row lifecycle (hide on outcome)", function()
		local LIFECYCLE_ITEM_LINK = "|cff0070dditem:11111|r"
		local function makeActionRowEntry(overrides)
			local base = {
				state = "pending",
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
				itemLink = LIFECYCLE_ITEM_LINK,
				startTime = 1000,
				rollTime = 60,
			}
			if overrides then
				for k, v in pairs(overrides) do
					base[k] = v
				end
			end
			return base
		end

		before_each(function()
			LootRolls._actionRowStates = {}
		end)

		-- START_LOOT_ROLL shows the action row

		describe("START_LOOT_ROLL shows action row", function()
			before_each(function()
				ns.IsRetail = function()
					return true
				end
				_G.GetTime = function()
					return 500
				end
				LootRolls._lootRollsAdapter.GetRollButtonValidity = function(_rollID)
					return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
				end
				LootRolls._lootRollsAdapter.GetRollItemLink = function(_rollID)
					return LIFECYCLE_ITEM_LINK
				end
				LootRolls._rollValidityStaging = {}
			end)

			it("populates _actionRowStates on START_LOOT_ROLL", function()
				LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 300, 60)
				assert.is_not_nil(LootRolls._actionRowStates[300])
				assert.are.equal("pending", LootRolls._actionRowStates[300].state)
			end)
		end)

		-- MAIN_SPEC_NEED_ROLL hides action row

		describe("MAIN_SPEC_NEED_ROLL", function()
			it("hides action row when rollID matches", function()
				LootRolls._actionRowStates[500] = makeActionRowEntry()
				local dispatchSpy = spy.on(LootRolls, "DispatchActionRowPayload")
				LootRolls:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", 500)
				assert.spy(dispatchSpy).was.called(1)
				assert.is_nil(LootRolls._actionRowStates[500])
			end)

			it("dispatches resolved state on MAIN_SPEC_NEED_ROLL", function()
				LootRolls._actionRowStates[501] = makeActionRowEntry()
				local capturedState
				LootRolls.DispatchActionRowPayload = function(self, rollID, rollTime, itemLink, bv, state)
					capturedState = state
				end
				LootRolls:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", 501)
				assert.are.equal("resolved", capturedState)
				LootRolls.DispatchActionRowPayload = nil
			end)

			it("does nothing when no action row entry exists for rollID", function()
				local ok, err = pcall(function()
					LootRolls:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", 999)
				end)
				assert.is_true(ok, err)
				assert.is_nil(LootRolls._actionRowStates[999])
			end)

			it("clears _actionRowStates entry after hiding (no orphan)", function()
				LootRolls._actionRowStates[502] = makeActionRowEntry()
				LootRolls:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", 502)
				assert.is_nil(LootRolls._actionRowStates[502])
			end)
		end)

		-- CANCEL_LOOT_ROLL hides action row

		describe("CANCEL_LOOT_ROLL", function()
			it("hides action row for matching rollID", function()
				LootRolls._actionRowStates[600] = makeActionRowEntry()
				local dispatchSpy = spy.on(LootRolls, "DispatchActionRowPayload")
				LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 600)
				assert.spy(dispatchSpy).was.called(1)
				assert.is_nil(LootRolls._actionRowStates[600])
			end)

			it("does NOT hide action row for different rollID", function()
				LootRolls._actionRowStates[601] = makeActionRowEntry()
				local dispatchSpy = spy.on(LootRolls, "DispatchActionRowPayload")
				LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 999)
				assert.spy(dispatchSpy).was.not_called()
				assert.is_not_nil(LootRolls._actionRowStates[601])
			end)

			it("dispatches resolved state on CANCEL_LOOT_ROLL", function()
				LootRolls._actionRowStates[602] = makeActionRowEntry()
				local capturedState
				LootRolls.DispatchActionRowPayload = function(self, rollID, rollTime, itemLink, bv, state)
					capturedState = state
				end
				LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 602)
				assert.are.equal("resolved", capturedState)
				LootRolls.DispatchActionRowPayload = nil
			end)

			it("does nothing when no entry exists for rollID", function()
				local ok, err = pcall(function()
					LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 9999)
				end)
				assert.is_true(ok, err)
			end)

			it("clears _actionRowStates entry after hiding (no orphan)", function()
				LootRolls._actionRowStates[603] = makeActionRowEntry()
				LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 603)
				assert.is_nil(LootRolls._actionRowStates[603])
			end)
		end)

		-- CANCEL_ALL_LOOT_ROLLS hides every pending action row

		describe("CANCEL_ALL_LOOT_ROLLS", function()
			it("hides all pending action rows", function()
				LootRolls._actionRowStates[700] = makeActionRowEntry()
				LootRolls._actionRowStates[701] = makeActionRowEntry()
				LootRolls._actionRowStates[702] = makeActionRowEntry()
				local dispatchSpy = spy.on(LootRolls, "DispatchActionRowPayload")
				LootRolls:CANCEL_ALL_LOOT_ROLLS("CANCEL_ALL_LOOT_ROLLS")
				assert.spy(dispatchSpy).was.called(3)
				assert.is_nil(LootRolls._actionRowStates[700])
				assert.is_nil(LootRolls._actionRowStates[701])
				assert.is_nil(LootRolls._actionRowStates[702])
			end)

			it("does nothing when there are no pending action rows", function()
				local ok, err = pcall(function()
					LootRolls:CANCEL_ALL_LOOT_ROLLS("CANCEL_ALL_LOOT_ROLLS")
				end)
				assert.is_true(ok, err)
			end)

			it("leaves _actionRowStates empty after cancelling all", function()
				LootRolls._actionRowStates[710] = makeActionRowEntry()
				LootRolls._actionRowStates[711] = makeActionRowEntry()
				LootRolls:CANCEL_ALL_LOOT_ROLLS("CANCEL_ALL_LOOT_ROLLS")
				assert.are.same({}, LootRolls._actionRowStates)
			end)
		end)
	end)

	-- ── BuildActionRowPayload ─────────────────────────────────────────────────

	describe("BuildActionRowPayload", function()
		local ACTION_ITEM_LINK = "|cff0070dditem:99999|r"
		local function makeValidity(overrides)
			local base = { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
			if overrides then
				for k, v in pairs(overrides) do
					base[k] = v
				end
			end
			return base
		end

		before_each(function()
			LootRolls._lootRollsAdapter.GetItemInfoIcon = function()
				return 132319
			end
			LootRolls._lootRollsAdapter.GetItemInfoQuality = function()
				return 4
			end
			LootRolls._actionRowStates = {}
		end)

		it("returns nil when module is disabled", function()
			LootRolls.IsEnabled = function()
				return false
			end
			local payload = LootRolls:BuildActionRowPayload(101, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.is_nil(payload)
			LootRolls.IsEnabled = function()
				return true
			end
		end)

		it("sets key with LAR_ prefix and rollID", function()
			local payload = LootRolls:BuildActionRowPayload(202, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.are.equal("LAR_202", payload.key)
		end)

		it("sets type to LootRolls FeatureModule", function()
			local payload = LootRolls:BuildActionRowPayload(203, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.are.equal("LootRolls", payload.type)
		end)

		it("sets quantity to 0", function()
			local payload = LootRolls:BuildActionRowPayload(204, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.are.equal(0, payload.quantity)
		end)

		it("sets isLink to true", function()
			local payload = LootRolls:BuildActionRowPayload(205, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.is_true(payload.isLink)
		end)

		it("sets isActionRow to true", function()
			local payload = LootRolls:BuildActionRowPayload(206, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.is_true(payload.isActionRow)
		end)

		it("includes rollID in payload", function()
			local payload = LootRolls:BuildActionRowPayload(207, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.are.equal(207, payload.rollID)
		end)

		it("includes rollState in payload", function()
			local payload = LootRolls:BuildActionRowPayload(208, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.are.equal("pending", payload.rollState)
		end)

		it("sets showForSeconds = rollTime + PENDING_EXIT_BUFFER when rollTime > 0", function()
			local payload = LootRolls:BuildActionRowPayload(209, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			-- PENDING_EXIT_BUFFER is 1.0
			assert.are.equal(61.0, payload.showForSeconds)
		end)

		it("does not set showForSeconds when rollTime is 0", function()
			local payload = LootRolls:BuildActionRowPayload(210, 0, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.is_nil(payload.showForSeconds)
		end)

		it("does not set showForSeconds when rollTime is nil", function()
			local payload = LootRolls:BuildActionRowPayload(211, nil, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.is_nil(payload.showForSeconds)
		end)

		it("copies buttonValidity into payload", function()
			local validity = makeValidity({ canNeed = false, canGreed = true, canTransmog = true, canPass = false })
			local payload = LootRolls:BuildActionRowPayload(212, 60, ACTION_ITEM_LINK, validity, "pending")
			assert.is_not_nil(payload.buttonValidity)
			assert.is_false(payload.buttonValidity.canNeed)
			assert.is_true(payload.buttonValidity.canGreed)
			assert.is_true(payload.buttonValidity.canTransmog)
		end)

		it("defaults canPass to true when buttonValidity.canPass is nil", function()
			local validity = { canNeed = true, canGreed = true, canTransmog = false }
			local payload = LootRolls:BuildActionRowPayload(213, 60, ACTION_ITEM_LINK, validity, "pending")
			assert.is_true(payload.buttonValidity.canPass)
		end)

		it("includes lootRollsFeature reference in payload", function()
			local payload = LootRolls:BuildActionRowPayload(214, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.are.equal(LootRolls, payload.lootRollsFeature)
		end)

		it("secondaryText is WaitingForRolls on pending state", function()
			local payload = LootRolls:BuildActionRowPayload(215, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.are.equal("Waiting for rolls", payload.secondaryText)
		end)

		it("secondaryText shows playerSelection on submitted state when entry exists", function()
			LootRolls._actionRowStates[216] = {
				state = "submitted",
				playerSelection = "NEED",
				buttonValidity = makeValidity(),
				itemLink = ACTION_ITEM_LINK,
				startTime = 1000,
				rollTime = 60,
			}
			ns.L["LootRolls_YouSelected_NEED"] = "You selected: Need"
			local payload = LootRolls:BuildActionRowPayload(216, 60, ACTION_ITEM_LINK, makeValidity(), "submitted")
			assert.are.equal("You selected: Need", payload.secondaryText)
		end)

		it("includes icon when enableIcon is true", function()
			local payload = LootRolls:BuildActionRowPayload(217, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.are.equal(132319, payload.icon)
		end)

		it("omits icon when hideAllIcons is true", function()
			ns.db.global.misc.hideAllIcons = true
			local payload = LootRolls:BuildActionRowPayload(218, 60, ACTION_ITEM_LINK, makeValidity(), "pending")
			assert.is_nil(payload.icon)
			ns.db.global.misc.hideAllIcons = false
		end)
	end)

	-- ── DispatchActionRowPayload ───────────────────────────────────────────────

	describe("DispatchActionRowPayload", function()
		before_each(function()
			LootRolls._actionRowStates = {}
			LootRolls._lootRollsAdapter.GetItemInfoIcon = function()
				return 132319
			end
			LootRolls._lootRollsAdapter.GetItemInfoQuality = function()
				return 4
			end
		end)

		it("sends a message via LootElementBase:Show when payload is valid", function()
			LootRolls:DispatchActionRowPayload(
				300,
				60,
				"|cff0070dditem:300|r",
				{ canNeed = true, canGreed = true, canTransmog = false, canPass = true },
				"pending"
			)
			assert.spy(sendMessageSpy).was.called_at_least(1)
		end)

		it("does not send a message when module is disabled", function()
			LootRolls.IsEnabled = function()
				return false
			end
			sendMessageSpy:clear()
			LootRolls:DispatchActionRowPayload(
				301,
				60,
				"|cff0070dditem:301|r",
				{ canNeed = true, canPass = true },
				"pending"
			)
			assert.spy(sendMessageSpy).was.not_called()
			LootRolls.IsEnabled = function()
				return true
			end
		end)
	end)

	-- ── SubmitActionRoll ──────────────────────────────────────────────────────

	describe("SubmitActionRoll", function()
		local ACTION_ITEM_LINK = "|cff0070dditem:77777|r"

		before_each(function()
			LootRolls._actionRowStates = {}
			LootRolls._lootRollsAdapter.DecodeRollType = function(rollTypeName)
				local map = { NEED = 1, GREED = 2, TRANSMOG = 3, PASS = 0 }
				local t = map[rollTypeName]
				if t then
					return t, nil
				end
				return nil, "unknown rollType: " .. tostring(rollTypeName)
			end
			LootRolls._lootRollsAdapter.SubmitLootRoll = function(_rollID, _rollType)
				return true, nil
			end
			LootRolls._lootRollsAdapter.GetItemInfoIcon = function()
				return 132319
			end
			LootRolls._lootRollsAdapter.GetItemInfoQuality = function()
				return 4
			end
		end)

		it("calls SubmitLootRoll with rollID and NEED type (1)", function()
			local calledWith = {}
			LootRolls._lootRollsAdapter.SubmitLootRoll = function(rollID, rollType)
				calledWith = { rollID = rollID, rollType = rollType }
				return true, nil
			end
			LootRolls:SubmitActionRoll(400, "NEED")
			assert.are.equal(400, calledWith.rollID)
			assert.are.equal(1, calledWith.rollType)
		end)

		it("calls SubmitLootRoll with rollID and GREED type (2)", function()
			local calledWith = {}
			LootRolls._lootRollsAdapter.SubmitLootRoll = function(rollID, rollType)
				calledWith = { rollID = rollID, rollType = rollType }
				return true, nil
			end
			LootRolls:SubmitActionRoll(401, "GREED")
			assert.are.equal(2, calledWith.rollType)
		end)

		it("calls SubmitLootRoll with rollID and TRANSMOG type (3)", function()
			local calledWith = {}
			LootRolls._lootRollsAdapter.SubmitLootRoll = function(rollID, rollType)
				calledWith = { rollID = rollID, rollType = rollType }
				return true, nil
			end
			LootRolls:SubmitActionRoll(402, "TRANSMOG")
			assert.are.equal(3, calledWith.rollType)
		end)

		it("calls SubmitLootRoll with rollID and PASS type (0)", function()
			local calledWith = {}
			LootRolls._lootRollsAdapter.SubmitLootRoll = function(rollID, rollType)
				calledWith = { rollID = rollID, rollType = rollType }
				return true, nil
			end
			LootRolls:SubmitActionRoll(403, "PASS")
			assert.are.equal(0, calledWith.rollType)
		end)

		it("records playerSelection in _actionRowStates when entry exists", function()
			LootRolls._actionRowStates[404] = {
				state = "pending",
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
				itemLink = ACTION_ITEM_LINK,
				startTime = 1000,
				rollTime = 60,
			}
			LootRolls:SubmitActionRoll(404, "NEED")
			assert.are.equal("NEED", LootRolls._actionRowStates[404].playerSelection)
		end)

		it("re-dispatches as submitted state after successful roll", function()
			LootRolls._actionRowStates[405] = {
				state = "pending",
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
				itemLink = ACTION_ITEM_LINK,
				startTime = 1000,
				rollTime = 60,
			}
			local dispatchSpy = spy.on(LootRolls, "DispatchActionRowPayload")
			LootRolls:SubmitActionRoll(405, "GREED")
			assert.spy(dispatchSpy).was.called_at_least(1)
			-- Verify the state arg was "submitted" (self, rollID, rollTime, itemLink, buttonValidity, state)
			local args = dispatchSpy.calls[1].vals
			assert.are.equal("submitted", args[6])
		end)

		it("returns early and logs warn when rollID is nil", function()
			local warnSpy = ns.LogWarn
			LootRolls:SubmitActionRoll(nil, "NEED")
			assert.spy(warnSpy).was.called_at_least(1)
		end)

		it("returns early when DecodeRollType is not available", function()
			LootRolls._lootRollsAdapter.DecodeRollType = nil
			local ok, err = pcall(function()
				LootRolls:SubmitActionRoll(406, "NEED")
			end)
			assert.is_true(ok, tostring(err))
		end)

		it("returns early when rollTypeName is invalid", function()
			local submitCalled = false
			LootRolls._lootRollsAdapter.SubmitLootRoll = function()
				submitCalled = true
				return true, nil
			end
			LootRolls:SubmitActionRoll(407, "INVALID_ROLL_TYPE")
			assert.is_false(submitCalled)
		end)

		it("returns early when SubmitLootRoll is not available", function()
			LootRolls._lootRollsAdapter.SubmitLootRoll = nil
			local ok, err = pcall(function()
				LootRolls:SubmitActionRoll(408, "NEED")
			end)
			assert.is_true(ok, tostring(err))
		end)

		it("returns early when SubmitLootRoll returns failure", function()
			LootRolls._lootRollsAdapter.SubmitLootRoll = function()
				return false, "API error"
			end
			LootRolls._actionRowStates[409] = {
				state = "pending",
				buttonValidity = { canNeed = true, canPass = true },
				itemLink = ACTION_ITEM_LINK,
				startTime = 1000,
				rollTime = 60,
			}
			-- Should not update playerSelection on failure
			LootRolls:SubmitActionRoll(409, "NEED")
			assert.is_nil(LootRolls._actionRowStates[409].playerSelection)
		end)
	end)

	-- ── Retail START_LOOT_ROLL action row dispatch ─────────────────────────────

	describe("Retail START_LOOT_ROLL action row dispatch", function()
		local RETAIL_ITEM_LINK = "|cff0070dditem:55555|r"

		before_each(function()
			ns.IsRetail = function()
				return true
			end
			_G.GetTime = function()
				return 1000
			end
			LootRolls._actionRowStates = {}
			LootRolls._rollValidityStaging = {}
			LootRolls._lootRollsAdapter.GetRollButtonValidity = function(_rollID)
				return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
			end
			LootRolls._lootRollsAdapter.GetRollItemLink = function(_rollID)
				return RETAIL_ITEM_LINK
			end
			LootRolls._lootRollsAdapter.GetItemInfoIcon = function()
				return 132319
			end
			LootRolls._lootRollsAdapter.GetItemInfoQuality = function()
				return 4
			end
		end)

		it("dispatches action row payload on Retail START_LOOT_ROLL", function()
			local dispatchSpy = spy.on(LootRolls, "DispatchActionRowPayload")
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 800, 60)
			assert.spy(dispatchSpy).was.called(1)
		end)

		it("stages button validity in _rollValidityStaging for result row absorption", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 801, 60)
			assert.is_not_nil(LootRolls._rollValidityStaging[801])
		end)

		it("caches entry with correct rollTime in _actionRowStates", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 802, 45)
			assert.is_not_nil(LootRolls._actionRowStates[802])
			assert.are.equal(45, LootRolls._actionRowStates[802].rollTime)
		end)

		it("does not re-cache when rollID already has an entry", function()
			LootRolls._actionRowStates[803] = {
				state = "pending",
				buttonValidity = { canNeed = false, canGreed = false, canTransmog = false, canPass = true },
				itemLink = RETAIL_ITEM_LINK,
				startTime = 900,
				rollTime = 60,
			}
			local dispatchSpy = spy.on(LootRolls, "DispatchActionRowPayload")
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 803, 60)
			-- DispatchActionRowPayload should NOT be called again for the existing entry
			assert.spy(dispatchSpy).was.not_called()
		end)

		it("skips state population when GetRollButtonValidity returns nil", function()
			LootRolls._lootRollsAdapter.GetRollButtonValidity = function()
				return nil
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 804, 60)
			assert.is_nil(LootRolls._actionRowStates[804])
		end)

		it("skips all action row logic on non-Retail", function()
			ns.IsRetail = function()
				return false
			end
			-- Classic path runs — action row state should NOT be set
			-- (Classic uses _dropStates, not _actionRowStates)
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function()
				return nil
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 805, 60)
			assert.is_nil(LootRolls._actionRowStates[805])
		end)

		it("caches itemLink from GetRollItemLink in action row entry", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 806, 60)
			assert.are.equal(RETAIL_ITEM_LINK, LootRolls._actionRowStates[806].itemLink)
		end)
	end)
end)
