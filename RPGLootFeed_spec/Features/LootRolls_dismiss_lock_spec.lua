---@diagnostic disable: need-check-nil
-- Integration tests for S04/T02: dismiss lock gating via SetClickThrough.
--
-- Contract (task plan must-haves):
--   pending phase  → SetClickThrough(true)  — dismiss DISABLED
--   result  phase  → SetClickThrough(true)  — dismiss DISABLED
--   resolved phase → SetClickThrough(false) — dismiss ENABLED
--   cancelled phase→ SetClickThrough(false) — dismiss ENABLED
--   dismiss state persists across LOOT_HISTORY_UPDATE_DROP re-fires (same drop)

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootRollsButtonsMixin.lua"

-- Load the mixin once at module level using a temporary ns to avoid
-- re-executing the file (and touching _G.RLF_LootRollsButtonsMixin) on every test.
-- Individual tests share the same mixin table — mutations to per-row state are
-- isolated through the row mock, not the mixin definition.
local _initNs = {
	DbAccessor = {
		AnyFeatureConfig = function() return {} end,
		Sizing = function() return { padding = 2, iconSize = 20 } end,
		Styling = function() return { textAlignment = "LEFT" } end,
	},
	TextAlignment = { LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER" },
	LogDebug = function() end,
}
assert(loadfile(MIXIN_FILE))("TestAddon", _initNs)
-- RLF_LootRollsButtonsMixin is now in _G; don't reload it per-test.

local ITEM_LINK = "|cff0070dditem:99999|r"
local ENC_ID = 1001
local LIST_ID = 2
local DROP_KEY = ENC_ID .. "_" .. LIST_ID
local ROW_KEY = "LR_" .. DROP_KEY
local ROLL_ID = 42

-- ── Fixtures ─────────────────────────────────────────────────────────────────

local function makePendingDrop()
	return {
		itemHyperlink = ITEM_LINK,
		winner = nil,
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		startTime = nil,
		duration = nil,
	}
end

local function makeResolvedDrop()
	return {
		itemHyperlink = ITEM_LINK,
		winner = {
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
		HasLootHistory = function()
			return true
		end,
		GetSortedInfoForDrop = dropInfoFn or function()
			return makePendingDrop()
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
			return ITEM_LINK
		end,
	}
end

local function makeNs(sendSpy)
	local n = {
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
		SendMessage = sendSpy or function() end,
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
					return { enableIcon = false, enableLootRollActions = true }
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
			["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  You selected %s and rolled %d",
		},
		RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
		TextAlignment = { LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER" },
	}

	assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", n)
	assert.is_not_nil(n.LootElementBase)

	n.FeatureBase = {
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

	return n
end

--- Build a minimal mock row that delegates SetClickThrough to a spy.
local function buildMockRow(ns)

	local clickThroughSpy = spy.new(function() end)
	local row = {
		frameType = "MAIN",
		type = nil,
		rollID = nil,
		_isClickThrough = false,
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
		SetClickThrough = function(self, enabled)
			self._isClickThrough = enabled
			clickThroughSpy(enabled)
		end,
	}

	for k, v in pairs(RLF_LootRollsButtonsMixin) do
		row[k] = v
	end

	row.LogDebug = function() end
	row.LogWarn = function() end

	ns.DbAccessor.Sizing = function(_, _ft)
		return { padding = 2, iconSize = 20 }
	end
	ns.DbAccessor.Styling = function(_, _ft)
		return { textAlignment = "LEFT" }
	end

	return row, clickThroughSpy
end

-- ── Tests ─────────────────────────────────────────────────────────────────────

describe("LootRolls dismiss lock (SetClickThrough via rowPhase)", function()
	---@type RLF_LootRolls
	local LootRolls, ns

	before_each(function()
		_G.GetTime = function()
			return 0
		end
		ns = makeNs()
		LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
		LootRolls._lootRollsAdapter = makeAdapter()
		LootRolls._dropStates = {}
		LootRolls._stagedRollValidity = {}
		LootRolls._buttonValidityCache = {}
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- ── UpdateLootRollButtons SetClickThrough contract ────────────────────────

	describe("UpdateLootRollButtons SetClickThrough contract", function()
		it("locks dismiss (SetClickThrough=true) when rowPhase='pending'", function()
			local row, ctSpy = buildMockRow(ns)

			row:UpdateLootRollButtons({
				key = ROW_KEY,
				rollState = "pending",
				rowPhase = "pending",
				lootListID = LIST_ID,
				buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			})

			assert.is_true(row._isClickThrough, "dismiss should be locked (click-through=true) for pending phase")
			assert.spy(ctSpy).was.called_with(true)
		end)

		it("locks dismiss (SetClickThrough=true) when rowPhase='result'", function()
			local row, ctSpy = buildMockRow(ns)

			row:UpdateLootRollButtons({
				key = ROW_KEY,
				rollState = "pending",
				rowPhase = "result",
				lootListID = LIST_ID,
				buttonValidity = {},
			})

			assert.is_true(row._isClickThrough, "dismiss should be locked for result phase")
			assert.spy(ctSpy).was.called_with(true)
		end)

		it("unlocks dismiss (SetClickThrough=false) when rowPhase='resolved'", function()
			local row, ctSpy = buildMockRow(ns)

			row:UpdateLootRollButtons({
				key = ROW_KEY,
				rollState = "resolved",
				rowPhase = "resolved",
				lootListID = LIST_ID,
				buttonValidity = {},
			})

			assert.is_false(row._isClickThrough, "dismiss should be unlocked for resolved phase")
			assert.spy(ctSpy).was.called_with(false)
		end)

		it("unlocks dismiss (SetClickThrough=false) when rowPhase='cancelled'", function()
			local row, ctSpy = buildMockRow(ns)

			row:UpdateLootRollButtons({
				key = ROW_KEY,
				rollState = "resolved",
				rowPhase = "cancelled",
				lootListID = LIST_ID,
				buttonValidity = {},
			})

			assert.is_false(row._isClickThrough, "dismiss should be unlocked for cancelled phase")
			assert.spy(ctSpy).was.called_with(false)
		end)

		it("locks dismiss by default when rowPhase is absent (safety default)", function()
			local row, ctSpy = buildMockRow(ns)

			row:UpdateLootRollButtons({
				key = ROW_KEY,
				rollState = "pending",
				-- rowPhase intentionally omitted
				lootListID = LIST_ID,
				buttonValidity = {},
			})

			assert.is_true(row._isClickThrough, "absent rowPhase should default to locked")
			assert.spy(ctSpy).was.called_with(true)
		end)

		it("locks dismiss even when enableLootRollActions=false (feature disabled path)", function()
			local ns2 = makeNs()
			ns2.DbAccessor.AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return { enableLootRollActions = false }
				end
				return nil
			end
			local row, ctSpy = buildMockRow(ns2)

			row:UpdateLootRollButtons({
				key = ROW_KEY,
				rollState = "pending",
				rowPhase = "pending",
				lootListID = LIST_ID,
			})

			-- Dismiss lock runs BEFORE the feature-disabled early return.
			assert.is_true(row._isClickThrough, "dismiss should be locked even when buttons are hidden")
			assert.spy(ctSpy).was.called_with(true)
		end)
	end)

	-- ── Dismiss state persists across re-fires ────────────────────────────────

	describe("dismiss state persistence across LOOT_HISTORY_UPDATE_DROP re-fires", function()
		it("payload.rowPhase reflects 'result' on second fire (same pending drop)", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end

			-- First fire: entry created (pending→result)
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
			-- Second fire: same data re-fires
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, makePendingDrop(), "pending")
			assert.is_not_nil(payload)
			-- Phase should remain 'result' (not reset to 'pending' on re-fire).
			assert.equals("result", payload.rowPhase, "rowPhase must remain 'result' across re-fires")
		end)

		it("payload.rowPhase is 'resolved' after winner detected, remains so on re-fire", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			-- Re-fire with winner again — phase must not regress from 'resolved'.
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, makeResolvedDrop(), "resolved")
			assert.equals("resolved", payload.rowPhase, "rowPhase must stay 'resolved' on re-fires")
		end)
	end)

	-- ── CANCEL_LOOT_ROLL phase transition ────────────────────────────────────

	describe("CANCEL_LOOT_ROLL dismiss unlock", function()
		it("advances phase to 'cancelled' so next UpdateLootRollButtons unlocks dismiss", function()
			-- Setup: a 'result' phase entry with a known rollID.
			LootRolls._dropStates[DROP_KEY] = {
				state = "pending",
				phase = "result",
				rollID = ROLL_ID,
			}

			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

			assert.equals("cancelled", LootRolls._dropStates[DROP_KEY].phase)

			-- Simulate row re-render: rowPhase should now unlock dismiss.
			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, makePendingDrop(), "pending")
			-- payload.rowPhase must reflect the cancelled phase.
			assert.equals("cancelled", payload.rowPhase)
		end)

		it("ReleaseDismissLock calls SetClickThrough(false) on matching row via LootDisplay frames", function()
			-- Wire up a mock frame with a mock row.
			local setCTSpy = spy.new(function() end)
			local mockRow = {
				SetClickThrough = function(self, enabled)
					setCTSpy(enabled)
				end,
			}
			local mockFrame = {
				GetRow = function(self, key)
					if key == ROW_KEY then
						return mockRow
					end
					return nil
				end,
			}
			-- Inject a mock LootDisplay with GetAllFrames.
			ns.LootDisplay = {
				GetAllFrames = function()
					return pairs({ [1] = mockFrame })
				end,
			}

			LootRolls._dropStates[DROP_KEY] = {
				state = "pending",
				phase = "result",
				rollID = ROLL_ID,
			}

			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

			assert.spy(setCTSpy).was.called_with(false)
		end)

		it("does not call SetClickThrough for already-resolved rows on CANCEL_LOOT_ROLL", function()
			local setCTSpy = spy.new(function() end)
			local mockRow = {
				SetClickThrough = function(self, enabled)
					setCTSpy(enabled)
				end,
			}
			local mockFrame = {
				GetRow = function(self, key)
					if key == ROW_KEY then
						return mockRow
					end
					return nil
				end,
			}
			ns.LootDisplay = {
				GetAllFrames = function()
					return pairs({ [1] = mockFrame })
				end,
			}

			-- Already resolved — cancel should be a no-op for dismiss gating.
			LootRolls._dropStates[DROP_KEY] = {
				state = "resolved",
				phase = "resolved",
				rollID = ROLL_ID,
			}

			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

			-- Phase stays resolved, no SetClickThrough called.
			assert.equals("resolved", LootRolls._dropStates[DROP_KEY].phase)
			assert.spy(setCTSpy).was_not.called()
		end)

		it("clears pending action slot on CANCEL_LOOT_ROLL", function()
			LootRolls._pendingActions[ROLL_ID] = {
				rollType = "NEED",
				itemLink = ITEM_LINK,
				timestamp = 0,
			}

			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

			assert.is_nil(LootRolls._pendingActions[ROLL_ID], "pending action must be cleared on cancel")
		end)
	end)

	-- ── GetRowPhase helper ────────────────────────────────────────────────────

	describe("GetRowPhase helper", function()
		it("returns 'pending' when no entry exists for dropKey", function()
			assert.equals("pending", LootRolls:GetRowPhase("nonexistent_key"))
		end)

		it("returns current phase from _dropStates", function()
			LootRolls._dropStates["1_2"] = { state = "pending", phase = "result" }
			assert.equals("result", LootRolls:GetRowPhase("1_2"))
		end)

		it("returns 'resolved' after phase advances to resolved", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			assert.equals("resolved", LootRolls:GetRowPhase(DROP_KEY))
		end)
	end)

	-- ── allPassed terminal phase ──────────────────────────────────────────────

	describe("allPassed drop dismiss unlock", function()
		it("rowPhase is 'resolved' when allPassed — dismiss unlocked", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeAllPassedDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, makeAllPassedDrop(), "allPassed")
			assert.equals("resolved", payload.rowPhase, "allPassed drop should produce rowPhase='resolved'")

			-- Verify dismiss would be unlocked via UpdateLootRollButtons.
			local row, _ = buildMockRow(ns)
			row:UpdateLootRollButtons(payload)
			assert.is_false(row._isClickThrough, "allPassed rows should have dismiss unlocked")
		end)
	end)
end)
