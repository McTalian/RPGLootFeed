---@diagnostic disable: need-check-nil
-- Tests for LootRolls row timer phasing (T03 — action → result → final).
-- Verifies showForSeconds is set correctly for each lifecycle phase:
--   action  (pending, from START_LOOT_ROLL):            rollTime + 1.0
--   result  (pending→result, LOOT_HISTORY_UPDATE_DROP): drop.duration + 1.0 (or remaining)
--   final   (resolved/allPassed):                       exit.fadeOutDelay from config

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

describe("LootRolls timer phasing", function()
	---@type RLF_LootRolls
	local LootRolls, ns

	local ITEM_LINK = "|cff0070dditem:99999|r"
	local ENC_ID = 1001
	local LIST_ID = 2
	local DROP_KEY = ENC_ID .. "_" .. LIST_ID
	local ROLL_ID = 42
	local FADE_OUT_DELAY = 3

	-- Minimal ns fixture.
	local function makeNs()
		local n = {
			LootElementBase = nil,
			ItemQualEnum = { Uncommon = 2, Epic = 4 },
			DefaultIcons = { LOOTROLLS = 132319 },
			FeatureModule = { LootRolls = "LootRolls" },
			LogDebug = function() end,
			LogInfo = function() end,
			LogWarn = function() end,
			LogError = function() end,
			IsRetail = function() return true end,
			SendMessage = function() end,
			TooltipBuilders = nil,
			db = {
				global = {
					animations = { exit = { fadeOutDelay = FADE_OUT_DELAY } },
					misc = { hideAllIcons = false },
				},
			},
			WoWAPI = { LootRolls = {} },
			DbAccessor = {
				IsFeatureNeededByAnyFrame = function() return true end,
				AnyFeatureConfig = function(_, _) return { enableIcon = false } end,
			},
			L = {
				["All Passed"] = "All Passed",
				["LootRolls_WaitingForResults"] = "Waiting for results...",
				["LootRolls_WaitingForRolls"] = "Waiting for rolls",
				["LootRolls_TiedFmt"] = "Tied at %d",
				["LootRolls_CurrentLeaderFmt"] = "Leading: %s rolled %d",
				["LootRolls_WonByFmt"] = "Won by %s %s %d",
				["LootRolls_WonByNoRollFmt"] = "Won by %s",
				["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
				["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  You selected %s and rolled %d",
				["LootRolls_YouSelected_NEED"] = "You: Need",
				["LootRolls_YouSelected_GREED"] = "You: Greed",
				["LootRolls_YouSelected_PASS"] = "You: Pass",
				["LootRolls_YouSelected_TRANSMOG"] = "You: Transmog",
			},
			RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
		}

		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", n)
		assert.is_not_nil(n.LootElementBase)

		n.FeatureBase = {
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
		return n
	end

	local function makePendingDropWithTimer(startTime, duration)
		return {
			itemHyperlink = ITEM_LINK,
			winner = nil,
			allPassed = false,
			isTied = false,
			currentLeader = nil,
			rollInfos = {},
			startTime = startTime,
			duration = duration,
		}
	end

	local function makeResolvedDrop()
		return {
			itemHyperlink = ITEM_LINK,
			winner = {
				playerName = "Arthas", playerClass = "DEATHKNIGHT",
				roll = 87, state = 0, isSelf = false, isWinner = true,
			},
			allPassed = false,
			isTied = false,
			currentLeader = nil,
			rollInfos = {},
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

	local function makeAdapter(dropInfoFn)
		return {
			HasLootHistory = function() return true end,
			GetSortedInfoForDrop = dropInfoFn or function() return makePendingDropWithTimer(0, 60) end,
			GetInfoForEncounter = function() return nil end,
			GetRaidClassColor = function() return nil end,
			GetItemInfoIcon = function() return nil end,
			GetItemInfoQuality = function() return 2 end,
			GetRollButtonValidity = function()
				return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
			end,
			GetRetailRollItemLink = function() return ITEM_LINK end,
		}
	end

	before_each(function()
		_G.GetTime = function() return 0 end
		ns = makeNs()
		LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
		LootRolls._lootRollsAdapter = makeAdapter()
		LootRolls._dropStates = {}
		LootRolls._stagedRollValidity = {}
		LootRolls._buttonValidityCache = {}
		LootRolls._pendingActions = {}
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- ── Action phase: BuildPayload (Retail pending drop with startTime + duration) ──

	describe("action phase timer", function()
		it("BuildPayload sets showForSeconds = remaining (startTime + duration - GetTime + buffer)", function()
			-- GetTime = 0, startTime = 0, duration = 60 → remaining = 60 + 1 = 61
			local dropInfo = makePendingDropWithTimer(0, 60)
			LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "pending" }

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
			assert.is_not_nil(payload)
			assert.is_not_nil(payload.showForSeconds, "showForSeconds should be set for action phase")
			assert.is_near(61.0, payload.showForSeconds, 0.1, "showForSeconds should be duration + buffer")
		end)

		it("BuildPayload uses full duration + buffer when startTime is absent", function()
			-- No startTime → GetRemainingPendingSeconds returns nil → fallback to duration + buffer
			local dropInfo = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
				isTied = false, currentLeader = nil, rollInfos = {}, startTime = nil, duration = 45 }
			LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "pending" }

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
			assert.is_not_nil(payload)
			assert.is_not_nil(payload.showForSeconds)
			assert.is_near(46.0, payload.showForSeconds, 0.1, "should be duration + buffer when startTime absent")
		end)

		it("BuildPayload leaves showForSeconds nil when no duration data at all", function()
			local dropInfo = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
				isTied = false, currentLeader = nil, rollInfos = {}, startTime = nil, duration = nil }
			LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "pending" }

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
			assert.is_not_nil(payload)
			assert.is_nil(payload.showForSeconds, "showForSeconds should be nil when no duration data")
		end)

		it("timer reflects partial consumption when GetTime advances mid-roll", function()
			-- Roll window 60s, 20s have elapsed: remaining = (0+60) - 20 + 1 = 41
			_G.GetTime = function() return 20 end
			local dropInfo = makePendingDropWithTimer(0, 60)
			LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "pending" }

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
			assert.is_not_nil(payload.showForSeconds)
			assert.is_near(41.0, payload.showForSeconds, 0.1, "remaining should account for elapsed time")
		end)
	end)

	-- ── Result phase: LOOT_HISTORY_UPDATE_DROP pending → result ──────────────

	describe("result phase timer", function()
		it("payload showForSeconds set from drop.duration on result arrival", function()
			-- duration=30; startTime absent → falls back to duration + buffer
			local dropInfo = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
				isTied = false, currentLeader = nil, rollInfos = {}, startTime = nil, duration = 30 }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function() return dropInfo end

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local entry = LootRolls._dropStates[DROP_KEY]
			assert.equals("result", entry.phase)
			-- The BuildPayload call inside DispatchPayload will set showForSeconds.
			-- We verify via BuildPayload directly.
			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
			assert.is_not_nil(payload.showForSeconds)
			assert.is_near(31.0, payload.showForSeconds, 0.1)
		end)

		it("payload showForSeconds uses remaining time when startTime is present", function()
			-- startTime=0, duration=60, GetTime=10 → remaining = (0+60-10) + 1 = 51
			local dropInfo = makePendingDropWithTimer(0, 60)
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function() return dropInfo end
			_G.GetTime = function() return 10 end

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
			assert.is_not_nil(payload.showForSeconds)
			assert.is_near(51.0, payload.showForSeconds, 0.1)
		end)

		it("timer never 0: zero duration does not set showForSeconds", function()
			local dropInfo = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
				isTied = false, currentLeader = nil, rollInfos = {}, startTime = nil, duration = 0 }
			LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "result" }

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
			-- duration=0 should not be used (would be 0+buffer, which is too short but not harmful).
			-- The guard is `duration > 0`, so nil is expected when duration is exactly 0.
			assert.is_nil(payload.showForSeconds, "duration=0 should not set showForSeconds")
		end)
	end)

	-- ── Final phase: resolved / allPassed ────────────────────────────────────

	describe("final phase timer (resolved/allPassed)", function()
		it("BuildPayload sets showForSeconds = exit.fadeOutDelay on resolved state", function()
			local dropInfo = makeResolvedDrop()
			LootRolls._dropStates[DROP_KEY] = { state = "resolved", phase = "resolved" }

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "resolved")
			assert.is_not_nil(payload)
			assert.equals(FADE_OUT_DELAY, payload.showForSeconds,
				"resolved phase should use configured fadeOutDelay")
		end)

		it("BuildPayload sets showForSeconds = exit.fadeOutDelay on allPassed state", function()
			local dropInfo = makeAllPassedDrop()
			LootRolls._dropStates[DROP_KEY] = { state = "allPassed", phase = "resolved" }

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "allPassed")
			assert.is_not_nil(payload)
			assert.equals(FADE_OUT_DELAY, payload.showForSeconds,
				"allPassed phase should use configured fadeOutDelay")
		end)

		it("resolved showForSeconds reflects config changes", function()
			ns.db.global.animations.exit.fadeOutDelay = 10
			-- Reload to pick up new ns.
			LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
			LootRolls._lootRollsAdapter = makeAdapter()
			LootRolls._dropStates = {}

			local dropInfo = makeResolvedDrop()
			LootRolls._dropStates[DROP_KEY] = { state = "resolved", phase = "resolved" }

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "resolved")
			assert.equals(10, payload.showForSeconds)
		end)

		it("falls back to 5s when db.global.animations is nil", function()
			-- Simulate early-startup when db is not yet populated.
			-- Keep db nil when calling BuildPayload so GetFadeOutDelay uses the fallback.
			ns.db = nil
			LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
			LootRolls._lootRollsAdapter = makeAdapter()
			LootRolls._dropStates = {}

			local dropInfo = makeResolvedDrop()
			LootRolls._dropStates[DROP_KEY] = { state = "resolved", phase = "resolved" }

			-- G_RLF.db is nil → GetFadeOutDelay() falls back to 5.0.
			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "resolved")
			assert.is_not_nil(payload.showForSeconds)
			assert.equals(5.0, payload.showForSeconds, "fallback should be 5.0 when db is nil")

			-- Restore db for subsequent tests.
			ns.db = { global = { animations = { exit = { fadeOutDelay = FADE_OUT_DELAY } },
				misc = { hideAllIcons = false } } }
		end)

		it("LOOT_HISTORY_UPDATE_DROP dispatch sets resolved showForSeconds to fadeOutDelay", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function() return makeResolvedDrop() end

			-- Capture payloads dispatched through element.Show()
			local lastPayload = nil
			local origFromPayload = ns.LootElementBase.fromPayload
			ns.LootElementBase.fromPayload = function(self, payload)
				lastPayload = payload
				return { Show = function() end }
			end

			LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
			LootRolls._lootRollsAdapter = makeAdapter(function() return makeResolvedDrop() end)
			LootRolls._dropStates = {}
			LootRolls._stagedRollValidity = {}
			LootRolls._buttonValidityCache = {}

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			assert.is_not_nil(lastPayload, "payload should have been dispatched")
			assert.equals(FADE_OUT_DELAY, lastPayload.showForSeconds,
				"dispatched resolved payload should carry fadeOutDelay")

			ns.LootElementBase.fromPayload = origFromPayload
		end)
	end)

	-- ── Phase transition → timer reset sequence ───────────────────────────────

	describe("full phase sequence: pending → result → resolved", function()
		it("showForSeconds increases then becomes fadeOutDelay across the full lifecycle", function()
			-- Phase 1: pending row with 60s roll window
			local pendingDrop = makePendingDropWithTimer(0, 60)
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function() return pendingDrop end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local p1 = LootRolls:BuildPayload(ENC_ID, LIST_ID, pendingDrop, "pending")
			assert.is_not_nil(p1.showForSeconds)
			-- At GetTime=0: remaining = 60+1 = 61
			assert.is_near(61.0, p1.showForSeconds, 0.1)

			-- Phase 2: resolved drop arrives
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function() return makeResolvedDrop() end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local p2 = LootRolls:BuildPayload(ENC_ID, LIST_ID, makeResolvedDrop(), "resolved")
			assert.equals(FADE_OUT_DELAY, p2.showForSeconds)
			assert.is_true(p2.showForSeconds < p1.showForSeconds,
				"final timer should be shorter than full roll window")
		end)

		it("allPassed transition sets final timer to fadeOutDelay", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDropWithTimer(0, 60)
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function() return makeAllPassedDrop() end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local p = LootRolls:BuildPayload(ENC_ID, LIST_ID, makeAllPassedDrop(), "allPassed")
			assert.equals(FADE_OUT_DELAY, p.showForSeconds)
		end)

		it("row expires cleanly if result never arrives (action timer expires)", function()
			-- Simulate: roll window 60s, GetTime advances past the window.
			-- GetRemainingPendingSeconds should return nil (expired), so showForSeconds is nil.
			_G.GetTime = function() return 70 end -- past startTime(0) + duration(60)
			local dropInfo = makePendingDropWithTimer(0, 60)
			LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "pending" }

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
			-- remaining = (0+60) - 70 = -10 < 0 → nil, and duration > 0 fallback not triggered
			-- because startTime IS present (GetRemainingPendingSeconds returned nil due to expiry)
			assert.is_nil(payload.showForSeconds, "expired roll window should yield nil showForSeconds")
		end)
	end)

	-- ── Classic: BuildClassicPayload timer phasing ─────────────────────────────

	describe("Classic timer phasing via BuildClassicPayload", function()
		before_each(function()
			ns.IsRetail = function() return false end
			LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
			LootRolls._lootRollsAdapter = {
				HasStartLootRollEvent = function() return true end,
				GetSortedInfoForDrop = function() return nil end,
				GetInfoForEncounter = function() return nil end,
				GetRaidClassColor = function() return nil end,
				GetItemInfoIcon = function() return nil end,
				GetItemInfoQuality = function() return 2 end,
				GetClassicRollItemInfo = function(rollID)
					return { itemLink = ITEM_LINK, texture = nil, quality = 2,
						canNeed = true, canGreed = true, canDisenchant = false }
				end,
			}
			LootRolls._dropStates = {}
			LootRolls._stagedRollValidity = {}
			LootRolls._buttonValidityCache = {}
			LootRolls._pendingActions = {}
		end)

		it("action phase: START_LOOT_ROLL sets showForSeconds = rollTime + buffer via dispatch", function()
			-- START_LOOT_ROLL triggers DispatchClassicPayload → BuildClassicPayload.
			-- dropInfo built with startTime=GetTime()=0, duration=rollTime=30.
			-- showForSeconds = remaining = 30 + 1 = 31.
			local capturedPayload = nil
			ns.LootElementBase.fromPayload = function(_, payload)
				capturedPayload = payload
				return { Show = function() end }
			end
			LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
			LootRolls._lootRollsAdapter = {
				HasStartLootRollEvent = function() return true end,
				GetSortedInfoForDrop = function() return nil end,
				GetClassicRollItemInfo = function()
					return { itemLink = ITEM_LINK, texture = nil, quality = 2,
						canNeed = true, canGreed = true, canDisenchant = false }
				end,
			}
			LootRolls._dropStates = {}
			LootRolls._stagedRollValidity = {}
			LootRolls._buttonValidityCache = {}
			LootRolls._pendingActions = {}

			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 30)

			assert.is_not_nil(capturedPayload, "START_LOOT_ROLL should dispatch a payload")
			assert.is_not_nil(capturedPayload.showForSeconds)
			assert.is_near(31.0, capturedPayload.showForSeconds, 0.1, "action phase = rollTime + buffer")
		end)

		it("resolved state: BuildClassicPayload sets showForSeconds = fadeOutDelay", function()
			local dropKey = ROLL_ID .. "_" .. ROLL_ID
			LootRolls._dropStates[dropKey] = { state = "allPassed", phase = "resolved", _isClassic = true, _rollID = ROLL_ID }
			local dropInfo = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = true,
				isTied = false, currentLeader = nil, rollInfos = {}, startTime = 0, duration = 30 }
			LootRolls._dropStates[dropKey]._dropInfo = dropInfo

			local payload = LootRolls:BuildClassicPayload(ROLL_ID, dropInfo, "allPassed", nil)
			assert.is_not_nil(payload)
			assert.equals(FADE_OUT_DELAY, payload.showForSeconds,
				"Classic resolved should use fadeOutDelay")
		end)

		it("pending state: BuildClassicPayload uses remaining roll window", function()
			-- startTime=0, duration=45, GetTime=0 → remaining = 46
			local dropKey = ROLL_ID .. "_" .. ROLL_ID
			LootRolls._dropStates[dropKey] = { state = "pending", phase = "pending", _isClassic = true, _rollID = ROLL_ID }
			local dropInfo = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
				isTied = false, currentLeader = nil, rollInfos = {}, startTime = 0, duration = 45 }

			local payload = LootRolls:BuildClassicPayload(ROLL_ID, dropInfo, "pending", nil)
			assert.is_not_nil(payload)
			assert.is_not_nil(payload.showForSeconds)
			assert.is_near(46.0, payload.showForSeconds, 0.1)
		end)
	end)

	-- ── Timer logging ─────────────────────────────────────────────────────────

	describe("timer update logging", function()
		it("LogDebug is called with timer info on resolved dispatch", function()
			local debugCalls = {}
			-- The module calls G_RLF:LogDebug(msg, ...) which invokes ns.LogDebug(ns, msg, ...)
			-- so the first arg is ns (self) and the second arg is the message string.
			ns.LogDebug = function(self, msg, ...)
				debugCalls[#debugCalls + 1] = msg
			end
			LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
			LootRolls._lootRollsAdapter = makeAdapter(function() return makeResolvedDrop() end)
			LootRolls._dropStates = {}
			LootRolls._stagedRollValidity = {}
			LootRolls._buttonValidityCache = {}

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local timerLogFound = false
			for _, msg in ipairs(debugCalls) do
				if type(msg) == "string" and msg:find("timer update") then
					timerLogFound = true
					break
				end
			end
			assert.is_true(timerLogFound, "Expected at least one LogDebug call with 'timer update'")
		end)

		it("LogDebug is called with timer info on pending dispatch", function()
			local debugCalls = {}
			ns.LogDebug = function(self, msg, ...)
				debugCalls[#debugCalls + 1] = msg
			end
			LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
			LootRolls._lootRollsAdapter = makeAdapter(function()
				return makePendingDropWithTimer(0, 60)
			end)
			LootRolls._dropStates = {}
			LootRolls._stagedRollValidity = {}
			LootRolls._buttonValidityCache = {}

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local timerLogFound = false
			for _, msg in ipairs(debugCalls) do
				if type(msg) == "string" and msg:find("timer update") then
					timerLogFound = true
					break
				end
			end
			assert.is_true(timerLogFound, "Expected LogDebug 'timer update' for pending dispatch")
		end)
	end)
end)
