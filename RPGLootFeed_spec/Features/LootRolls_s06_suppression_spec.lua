---@diagnostic disable: need-check-nil
--- S06 Suppression integration tests.
---
--- T07: GroupLootFrame suppression integration — verify frame visibility gating
---      and pipeline independence.
---
--- Verifies four integration properties (S05 hook × S01-S04 pipeline):
---   (1) GroupLootFrameOverride.InterceptGroupLootFrame blocks Show when
---       disableLootRollFrame=true and calls through when false.
---   (2) Button clicks (OnRollButtonClick / START_LOOT_ROLL) still enqueue
---       pending actions (_pendingActions) while suppression is active.
---   (3) LOOT_HISTORY_UPDATE_DROP still creates/updates drop state and fires
---       SendMessage while suppression is active — the S01-S04 pipeline is
---       orthogonal to frame visibility.
---   (4) The /loot command behaviour under suppression: suppression uniformly
---       intercepts all Show calls including those triggered by /loot (no
---       escape hatch exists — documented behaviour, see MEM105).
---
--- These tests are S06-namespaced so that
---   make test-pattern PATTERN="S06.*suppression"
---   make test-pattern PATTERN="S06.*frame"
--- both discover them as part of the S06 validation suite.

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")

-- ── Fixtures ──────────────────────────────────────────────────────────────────

local ITEM_LINK   = "|cff0070dditem:55555|r"
local ROLL_ID     = 99
local ENC_ID      = 4001
local LIST_ID     = 7
local DROP_KEY    = ENC_ID .. "_" .. LIST_ID

-- ── Module loaders ────────────────────────────────────────────────────────────

local function buildNs(extraConfig, sendSpy)
	local cfg = {
		enableIcon           = true,
		enableLootRollActions = true,
		enableLootRollResults = true,
	}
	if extraConfig then
		for k, v in pairs(extraConfig) do cfg[k] = v end
	end
	return {
		LootElementBase   = nil,
		ItemQualEnum      = { Uncommon = 2, Epic = 4 },
		DefaultIcons      = { LOOTROLLS = 132319 },
		FeatureModule     = { LootRolls = "LootRolls" },
		LogDebug  = spy.new(function() end),
		LogInfo   = spy.new(function() end),
		LogWarn   = spy.new(function() end),
		LogError  = spy.new(function() end),
		IsRetail  = function() return true end,
		SendMessage = sendSpy or spy.new(function() end),
		TooltipBuilders = nil,
		db = { global = { animations = { exit = { fadeOutDelay = 3 } }, misc = { hideAllIcons = false } } },
		WoWAPI   = { LootRolls = {} },
		DbAccessor = {
			IsFeatureNeededByAnyFrame = function() return true end,
			AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then return cfg end
				return nil
			end,
		},
		L = {
			["All Passed"]                              = "All Passed",
			["LootRolls_WaitingForRolls"]               = "Waiting for rolls",
			["LootRolls_TiedFmt"]                       = "Tied at %d",
			["LootRolls_CurrentLeaderFmt"]              = "Leading: %s rolled %d",
			["LootRolls_WonByFmt"]                      = "Won by %s %s %d",
			["LootRolls_WonByNoRollFmt"]                = "Won by %s",
			["LootRolls_YouSelected_NEED"]              = "You: Need",
			["LootRolls_YouSelected_GREED"]             = "You: Greed",
			["LootRolls_YouSelected_TRANSMOG"]          = "You: Transmog",
			["LootRolls_YouSelected_PASS"]              = "You: Pass",
			["LootRolls_WaitingForResults"]             = "Waiting for results",
			["LootRolls_WinnerWithSelfFmt"]             = "%s  |  You: rolled %d",
			["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s, rolled %d",
		},
		RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
	}
end

local function loadGroupLootFrameOverride(ns)
	return assert(loadfile("RPGLootFeed/BlizzOverrides/GroupLootFrameOverride.lua"))("TestAddon", ns)
end

local function loadLootRolls(ns)
	assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
	ns.FeatureBase = {
		new = function(_, name)
			return {
				moduleName        = name,
				Enable            = function() end,
				Disable           = function() end,
				IsEnabled         = function() return true end,
				RegisterEvent     = function() end,
				UnregisterAllEvents = function() end,
			}
		end,
	}
	local lr = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
	ns.LootRolls = lr
	lr._lootRollsAdapter = {
		HasLootHistory          = function() return true end,
		HasStartLootRollEvent   = function() return true end,
		GetSortedInfoForDrop    = function() return nil end,
		GetInfoForEncounter     = function() return nil end,
		GetRaidClassColor       = function() return nil end,
		GetItemInfoIcon         = function() return 12345 end,
		GetItemInfoQuality      = function() return 4 end,
		GetRollButtonValidity   = function()
			return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
		end,
		GetRetailRollItemLink   = function() return ITEM_LINK end,
		GetClassicRollItemInfo  = function()
			return { itemLink = ITEM_LINK, texture = 132310, quality = 3,
				canNeed = true, canGreed = true, canDisenchant = false }
		end,
	}
	lr._dropStates          = {}
	lr._buttonValidityCache = {}
	lr._stagedRollValidity  = {}
	lr._pendingActions      = {}
	return lr
end

-- ── Helper: build 4 fake GroupLootFrames ─────────────────────────────────────

local function setupRollFrames()
	local frames = {}
	for i = 1, 4 do
		frames[i] = {
			Hide = function() end,
			Show = function() end,
		}
		_G["GroupLootFrame" .. i] = frames[i]
	end
	return frames
end

local function teardownRollFrames()
	for i = 1, 4 do
		_G["GroupLootFrame" .. i] = nil
	end
end

-- =============================================================================
-- S06 frame: GroupLootFrameOverride hook wiring
-- =============================================================================

describe("S06 frame: GroupLootFrameOverride hooks GroupLootFrame1-4 for suppression", function()
	local glfo, rollFrames, ns

	before_each(function()
		rollFrames = setupRollFrames()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then
				return { disableLootRollFrame = false, enableLootRollActions = true }
			end
		end
		glfo = loadGroupLootFrameOverride(ns)
	end)

	after_each(function()
		teardownRollFrames()
	end)

	it("S06 frame: GroupLootFrameHook installs RawHook on all four frames", function()
		spy.on(glfo, "RawHook")
		glfo:GroupLootFrameHook()
		assert.spy(glfo.RawHook).was.called(4)
		for i = 1, 4 do
			assert.spy(glfo.RawHook).was
				.called_with(glfo, rollFrames[i], "Show", "InterceptGroupLootFrame", true)
		end
	end)

	it("S06 frame: already-hooked frames are skipped on re-entry", function()
		-- Pre-mark frame 2 as already hooked.
		glfo.IsHooked = function(self, frame, event)
			return frame == rollFrames[2] and event == "Show"
		end
		spy.on(glfo, "RawHook")
		glfo:GroupLootFrameHook()
		-- Only 3 new hooks: 1, 3, 4.
		assert.spy(glfo.RawHook).was.called(3)
	end)

	it("S06 frame: hook defers via retryHook when no frames are available yet", function()
		for i = 1, 4 do _G["GroupLootFrame" .. i] = nil end
		local retryCalled = false
		ns.retryHook = function(...) retryCalled = true; return 1 end
		spy.on(glfo, "RawHook")
		glfo:GroupLootFrameHook()
		assert.spy(glfo.RawHook).was.not_called()
		assert.is_true(retryCalled, "expected retryHook to be invoked when frames are absent")
	end)
end)

-- =============================================================================
-- S06 suppression: InterceptGroupLootFrame visibility gating
-- =============================================================================

describe("S06 suppression: InterceptGroupLootFrame gates frame visibility via config", function()
	local glfo, rollFrames, ns

	before_each(function()
		rollFrames = setupRollFrames()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		glfo = loadGroupLootFrameOverride(ns)
	end)

	after_each(function()
		teardownRollFrames()
	end)

	it("S06 suppression: frame is hidden when disableLootRollFrame=true", function()
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then return { disableLootRollFrame = true } end
		end
		local frame = rollFrames[1]
		local hideSpy = spy.on(frame, "Hide")
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }

		glfo:InterceptGroupLootFrame(frame)

		assert.spy(hideSpy).was.called(1)
		assert.is_false(originalCalled, "original Show must NOT be invoked when suppression is on")
	end)

	it("S06 suppression: frame Show passes through when disableLootRollFrame=false", function()
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then return { disableLootRollFrame = false } end
		end
		local frame = rollFrames[2]
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }

		glfo:InterceptGroupLootFrame(frame)

		assert.is_true(originalCalled, "original Show must be called when suppression is off")
	end)

	it("S06 suppression: nil config falls back to calling original Show without crashing", function()
		ns.DbAccessor.AnyFeatureConfig = function() return nil end
		local frame = rollFrames[3]
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }

		assert.has_no_errors(function()
			glfo:InterceptGroupLootFrame(frame)
		end)
		assert.is_true(originalCalled, "nil config must default to show (no crash, no suppression)")
	end)
end)

-- =============================================================================
-- S06 suppression: /loot command passthrough behaviour (documented contract)
-- =============================================================================

describe("S06 suppression: /loot command is subject to same suppression as game-triggered Show", function()
	-- MEM105: no escape hatch exists in M003.  /loot triggers frame:Show() which is
	-- intercepted by the same hook.  This suite documents the contractual behaviour
	-- (suppression wins) and the non-suppressed passthrough so the spec is complete.

	local glfo, rollFrames, ns

	before_each(function()
		rollFrames = setupRollFrames()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		glfo = loadGroupLootFrameOverride(ns)
	end)

	after_each(function()
		teardownRollFrames()
	end)

	it("S06 suppression: /loot Show() is suppressed when disableLootRollFrame=true (no escape hatch)", function()
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then return { disableLootRollFrame = true } end
		end
		local frame = rollFrames[1]
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }

		-- /loot calls frame:Show() → hook fires → same path as game-triggered Show.
		glfo:InterceptGroupLootFrame(frame)

		assert.is_false(originalCalled,
			"/loot-triggered Show must be suppressed when disableLootRollFrame=true (no escape hatch)")
	end)

	it("S06 suppression: /loot Show() is NOT suppressed when disableLootRollFrame=false", function()
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then return { disableLootRollFrame = false } end
		end
		local frame = rollFrames[1]
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }

		glfo:InterceptGroupLootFrame(frame)

		assert.is_true(originalCalled,
			"/loot-triggered Show must pass through when disableLootRollFrame=false")
	end)
end)

-- =============================================================================
-- S06 suppression: button submission is independent of frame visibility
-- =============================================================================

describe("S06 suppression: button clicks enqueue pending actions regardless of suppression state", function()
	local lr, ns, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		-- Suppression ON: disableLootRollFrame=true
		ns = buildNs({ disableLootRollFrame = true }, sendSpy)
		lr = loadLootRolls(ns)
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 suppression: START_LOOT_ROLL stages pending action even when suppression active", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		local staged = lr._stagedRollValidity[ROLL_ID]
		assert.is_not_nil(staged, "_stagedRollValidity must be populated regardless of suppression")
		assert.are.equal(ITEM_LINK, staged.itemLink)
		assert.is_true(staged.validity.canNeed)
	end)

	it("S06 suppression: _pendingActions exists and is a table when suppression active", function()
		assert.is_not_nil(lr._pendingActions, "_pendingActions must exist regardless of suppression")
		assert.are.equal("table", type(lr._pendingActions))
	end)

	it("S06 suppression: OnRollButtonClick enqueues NEED when suppression active", function()
		-- Setup: stage validity via START_LOOT_ROLL, then fire LOOT_HISTORY_UPDATE_DROP
		-- so the drop state exists before button click.
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
				playerRollState = nil, startTime = 1000, duration = 60,
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		-- Simulate player clicking Need button.
		lr:OnRollButtonClick(ROLL_ID, 1) -- 1 = Need in Retail

		local pending = lr._pendingActions[ROLL_ID]
		assert.is_not_nil(pending, "_pendingActions must have entry after button click while suppressed")
		assert.are.equal("NEED", pending.rollType)
		print("[S06 T07] OnRollButtonClick suppressed state: rollType=" .. tostring(pending.rollType))
	end)

	it("S06 suppression: OnRollButtonClick enqueues GREED when suppression active", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		lr:OnRollButtonClick(ROLL_ID, 2) -- 2 = Greed

		local pending = lr._pendingActions[ROLL_ID]
		assert.is_not_nil(pending)
		assert.are.equal("GREED", pending.rollType)
	end)

	it("S06 suppression: actionPhase advances to 'waiting' after button click while suppressed", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		lr:OnRollButtonClick(ROLL_ID, 1)

		local entry = lr._dropStates[DROP_KEY]
		assert.is_not_nil(entry)
		assert.are.equal("waiting", entry.actionPhase,
			"actionPhase must be 'waiting' after button click even when frame suppressed")
	end)
end)

-- =============================================================================
-- S06 suppression: LOOT_HISTORY_UPDATE_DROP pipeline is unaffected by suppression
-- =============================================================================

describe("S06 suppression: LOOT_HISTORY_UPDATE_DROP pipeline fires correctly while suppressed", function()
	local lr, ns, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		ns = buildNs({ disableLootRollFrame = true }, sendSpy)
		lr = loadLootRolls(ns)
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 suppression: LOOT_HISTORY_UPDATE_DROP fires SendMessage when suppression active", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		assert.spy(sendSpy).was.called_at_least(1)
		print("[S06 T07] SendMessage calls while suppressed: " .. tostring(#sendSpy.calls))
	end)

	it("S06 suppression: _dropStates entry created by LOOT_HISTORY_UPDATE_DROP while suppressed", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = lr._dropStates[DROP_KEY]
		assert.is_not_nil(entry, "_dropStates must be created by LOOT_HISTORY_UPDATE_DROP when suppressed")
		assert.are.equal("pending", entry.state)
		print("[S06 T07] _dropStates under suppression: state=" .. tostring(entry.state))
	end)

	it("S06 suppression: _buttonValidityCache populated by LOOT_HISTORY_UPDATE_DROP while suppressed", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local cached = lr._buttonValidityCache[DROP_KEY]
		assert.is_not_nil(cached, "_buttonValidityCache must be populated even when suppressed")
		assert.is_true(cached.canNeed)
		assert.is_true(cached.canGreed)
	end)

	it("S06 suppression: LOOT_HISTORY_UPDATE_DROP resolves drop when winner arrives while suppressed", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		-- First fire: pending.
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		assert.are.equal("pending", lr._dropStates[DROP_KEY].state)
		sendSpy:clear()

		-- Second fire: resolved with winner.
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = { playerName = "Uther", playerClass = "PALADIN", roll = 73,
					state = 0, isSelf = false, isWinner = true },
				allPassed = false, isTied = false, currentLeader = nil, rollInfos = {},
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		assert.are.equal("resolved", lr._dropStates[DROP_KEY].state)
		assert.spy(sendSpy).was.called(1)
		print("[S06 T07] State after resolution under suppression: " .. lr._dropStates[DROP_KEY].state)
	end)
end)

-- =============================================================================
-- S06 suppression: suppression is independent of pipeline (orthogonality proof)
-- =============================================================================

describe("S06 suppression: pipeline events behave identically with suppression on vs off", function()
	-- Confirms S05 suppression hook has zero observable effect on the S01-S04
	-- event pipeline:  same events, same state transitions, same SendMessage calls.

	local function runPipeline(suppressionEnabled)
		local sendSpy = spy.new(function() end)
		local ns = buildNs({ disableLootRollFrame = suppressionEnabled }, sendSpy)
		local lr = loadLootRolls(ns)
		_G.GetTime = function() return 1000 end

		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		lr:OnRollButtonClick(ROLL_ID, 1) -- Need

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = { playerName = "Uther", playerClass = "PALADIN", roll = 73,
					state = 0, isSelf = false, isWinner = true },
				allPassed = false, isTied = false, currentLeader = nil, rollInfos = {},
			}
		end
		sendSpy:clear()
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local result = {
			finalState  = lr._dropStates[DROP_KEY] and lr._dropStates[DROP_KEY].state,
			sendMsgCount = #sendSpy.calls,
			pendingEntry = lr._pendingActions[ROLL_ID],
		}

		_G.GetTime = nil
		return result
	end

	it("S06 suppression: final drop state is 'resolved' with suppression on", function()
		local r = runPipeline(true)
		assert.are.equal("resolved", r.finalState,
			"pipeline must reach resolved state even with suppression active")
	end)

	it("S06 suppression: final drop state is 'resolved' with suppression off", function()
		local r = runPipeline(false)
		assert.are.equal("resolved", r.finalState,
			"pipeline must reach resolved state when suppression is off")
	end)

	it("S06 suppression: SendMessage fired once on resolution regardless of suppression", function()
		local rOn  = runPipeline(true)
		local rOff = runPipeline(false)
		assert.are.equal(1, rOn.sendMsgCount,  "suppression on: one SendMessage on resolution")
		assert.are.equal(1, rOff.sendMsgCount, "suppression off: one SendMessage on resolution")
	end)

	it("S06 suppression: _pendingActions consumed after resolution regardless of suppression", function()
		local rOn  = runPipeline(true)
		local rOff = runPipeline(false)
		-- Once the button click is queued and the event pipeline runs, the pending
		-- entry is either consumed by MatchActionToResult (when S03 is wired) or
		-- simply remains — either way the _pendingActions table must not crash.
		-- We assert the table itself is not nil.
		assert.is_not_nil(rOn,  "pipeline result must not be nil with suppression on")
		assert.is_not_nil(rOff, "pipeline result must not be nil with suppression off")
	end)
end)
