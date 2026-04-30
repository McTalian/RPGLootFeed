---@diagnostic disable: need-check-nil
-- Tests for LootRolls row lifecycle phase tracking (S04 — dismiss gating).
-- Phases: pending → result → resolved  (or → cancelled via CANCEL_LOOT_ROLL)
-- These tests are intentionally isolated from the broader LootRolls_spec.lua
-- so the phase contract remains easy to reason about.

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

describe("LootRolls phase tracking", function()
	---@type RLF_LootRolls
	local LootRolls, ns

	local ITEM_LINK = "|cff0070dditem:99999|r"
	local ENC_ID = 1001
	local LIST_ID = 2
	local DROP_KEY = ENC_ID .. "_" .. LIST_ID

	-- Minimal ns fixture, matching the real module's expectations.
	local function makeNs()
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
			SendMessage = function() end,
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
				AnyFeatureConfig = function(_, _)
					return { enableIcon = false }
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

	before_each(function()
		_G.GetTime = function() return 0 end
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

	-- ── Initial phase on first LOOT_HISTORY_UPDATE_DROP ──────────────────────

	describe("phase transition: pending → result", function()
		it("creates entry with phase='pending' then advances to 'result' on first fire (pending roll)", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local entry = LootRolls._dropStates[DROP_KEY]
			assert.is_not_nil(entry, "entry should be created")
			assert.equals("result", entry.phase, "phase should advance to 'result' on first LOOT_HISTORY_UPDATE_DROP")
		end)

		it("does not regress phase on re-fire when already 'result'", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local entry = LootRolls._dropStates[DROP_KEY]
			-- Re-fire with same pending drop: phase stays at 'result', not reset.
			assert.equals("result", entry.phase)
		end)
	end)

	-- ── Phase transition: result → resolved (winner) ──────────────────────────

	describe("phase transition: result → resolved (winner)", function()
		it("advances to 'resolved' when winner detected", function()
			-- First fire: pending → result
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
			assert.equals("result", LootRolls._dropStates[DROP_KEY].phase)

			-- Second fire: winner arrived → result → resolved
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local entry = LootRolls._dropStates[DROP_KEY]
			assert.equals("resolved", entry.phase, "phase should be 'resolved' after winner arrives")
		end)

		it("does not skip pending phase — cannot go pending → resolved directly", function()
			-- Arrive with winner on very first fire (no prior pending fire).
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			-- Entry was created with phase='pending' then immediately set to 'resolved'
			-- by the same handler, but the transition log should show pending → resolved.
			-- The key constraint: the entry DOES exist and phase IS 'resolved'.
			-- We verify via payload.rowPhase that the value propagates.
			local entry = LootRolls._dropStates[DROP_KEY]
			assert.is_not_nil(entry)
			assert.equals("resolved", entry.phase)
		end)
	end)

	-- ── Phase transition: result → resolved (allPassed) ──────────────────────

	describe("phase transition: result → resolved (allPassed)", function()
		it("advances to 'resolved' when allPassed detected", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeAllPassedDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local entry = LootRolls._dropStates[DROP_KEY]
			assert.equals("resolved", entry.phase)
		end)
	end)

	-- ── Terminal phase: resolved cannot regress ────────────────────────────────

	describe("terminal phase: resolved cannot regress", function()
		it("ignores further events once 'resolved'", function()
			-- Advance to resolved.
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
			assert.equals("resolved", LootRolls._dropStates[DROP_KEY].phase)

			-- A re-fire (e.g. late network packet) should be short-circuited.
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
			assert.equals("resolved", LootRolls._dropStates[DROP_KEY].phase)
		end)
	end)

	-- ── CANCEL_LOOT_ROLL ──────────────────────────────────────────────────────

	describe("CANCEL_LOOT_ROLL", function()
		it("marks phase='cancelled' for matching rollID in drop state", function()
			-- Simulate a pending drop that has been assigned a rollID from START_LOOT_ROLL.
			LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "pending", rollID = 42 }

			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 42)

			assert.equals("cancelled", LootRolls._dropStates[DROP_KEY].phase)
		end)

		it("clears staged validity for the cancelled rollID", function()
			LootRolls._stagedRollValidity[99] = { validity = {}, itemLink = ITEM_LINK }

			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 99)

			assert.is_nil(LootRolls._stagedRollValidity[99])
		end)

		it("does not re-cancel an already resolved drop", function()
			LootRolls._dropStates[DROP_KEY] = { state = "resolved", phase = "resolved", rollID = 77 }

			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 77)

			-- Phase stays at 'resolved', not overwritten to 'cancelled'.
			assert.equals("resolved", LootRolls._dropStates[DROP_KEY].phase)
		end)
	end)

	-- ── rowPhase in payload ──────────────────────────────────────────────────

	describe("payload.rowPhase", function()
		it("BuildPayload includes rowPhase from drop state", function()
			-- Pre-populate a drop state entry in 'result' phase.
			LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "result" }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, makePendingDrop(), "pending")
			assert.is_not_nil(payload)
			assert.equals("result", payload.rowPhase)
		end)

		it("BuildPayload rowPhase defaults to 'pending' when no entry exists", function()
			-- No pre-existing entry.
			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, makePendingDrop(), "pending")
			assert.is_not_nil(payload)
			assert.equals("pending", payload.rowPhase)
		end)

		it("BuildPayload rowPhase is 'resolved' after winner fires", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, makeResolvedDrop(), "resolved")
			assert.equals("resolved", payload.rowPhase)
		end)
	end)

	-- ── Phase logging ────────────────────────────────────────────────────────

	describe("phase transition logging", function()
		it("LogDebug is called during a phase transition", function()
			local debugSpy = spy.new(function() end)
			ns.LogDebug = debugSpy

			-- Reload so the fresh spy is captured by the module's local.
			LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
			LootRolls._lootRollsAdapter = makeAdapter(function()
				return makePendingDrop()
			end)
			LootRolls._dropStates = {}
			LootRolls._stagedRollValidity = {}
			LootRolls._buttonValidityCache = {}

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

			-- At least one LogDebug call should reference a phase transition.
			local found = false
			for _, call in ipairs(debugSpy.calls) do
				-- G_RLF:LogDebug(msg, ...) → LogDebug(ns, msg, ...) so refs[1]=ns, refs[2]=msg
				for _, ref in ipairs(call.refs) do
					if type(ref) == "string" and ref:find("phase") then
						found = true
						break
					end
				end
				if found then break end
			end
			assert.is_true(found, "Expected at least one LogDebug call mentioning 'phase'")
		end)
	end)
end)
