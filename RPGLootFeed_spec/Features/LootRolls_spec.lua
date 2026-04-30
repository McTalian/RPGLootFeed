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
				["LootRolls_WaitingForResults"] = "Waiting for results...",
				["LootRolls_WaitingForRolls"] = "Waiting for rolls",
				["LootRolls_TiedFmt"] = "Tied at %d",
				["LootRolls_CurrentLeaderFmt"] = "Leading: %s rolled %d",
				["LootRolls_WonByFmt"] = "Won by %s %s %d",
				["LootRolls_WonByNoRollFmt"] = "Won by %s",
				["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
				["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s  |  You: rolled %d",
				["LootRolls_YouSelected_NEED"] = "You: Need",
				["LootRolls_YouSelected_GREED"] = "You: Greed",
				["LootRolls_YouSelected_PASS"] = "You: Pass",
				["LootRolls_YouSelected_TRANSMOG"] = "You: Transmog",
			},
			RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
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
			GetRollButtonValidity = function()
				return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
			end,
			GetRetailRollItemLink = function(_rollID)
				return "|cff0070dditem:12345|r"
			end,
		}

		-- Reset drop state between tests
		LootRolls._dropStates = {}
		LootRolls._stagedRollValidity = {}

		-- ScanUnmatchedPendingActions (triggered by LOOT_HISTORY_UPDATE_DROP)
		-- requires GetTime() via CurrentTimestamp().  Provide a default stub so
		-- tests that fire LOOT_HISTORY_UPDATE_DROP don't crash on nil GetTime.
		-- Tests that need a specific time value override this locally.
		if not _G.GetTime then
			_G.GetTime = function()
				return 1000
			end
		end
	end)

	after_each(function()
		_G.GetTime = nil
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
			assert.spy(regSpy).was.called_with(LootRolls, "START_LOOT_ROLL")
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

			it("uses WonByNoRollFmt when winner has no roll value", function()
				local winner = {
					playerName = "Sylvanas",
					playerClass = "HUNTER",
					roll = nil,
					state = 3, -- master loot / no roll
					isSelf = false,
					isWinner = true,
				}
				local drop = makeResolvedDrop(winner)
				local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
				assert.is_not_nil(payload.secondaryText)
				assert.is_truthy(payload.secondaryText:find("Sylvanas"))
				-- Should NOT contain a numeric roll value in the "Won by" portion
				assert.is_falsy(payload.secondaryText:find("Won by %S+ %S+ %d"))
			end)

			it("appends WinnerWithSelfFmt (no playerSelection) when self rolled and lost", function()
				local selfRoll = { roll = 42, state = 0, isSelf = true, isWinner = false }
				local drop = makeResolvedDrop(nil, selfRoll)
				-- No playerSelection on _dropStates entry → WinnerWithSelfFmt branch
				LootRolls._dropStates["1_1"] = { state = "resolved", playerSelection = nil }
				local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
				assert.is_truthy(payload.secondaryText:find("42"))
				assert.is_truthy(payload.secondaryText:find("You: rolled"))
				assert.is_falsy(payload.secondaryText:find("You: Need"))
			end)

			it("appends WinnerWithSelfAndSelectionFmt when self rolled, lost, and has playerSelection", function()
				local selfRoll = { roll = 33, state = 0, isSelf = true, isWinner = false }
				local drop = makeResolvedDrop(nil, selfRoll)
				-- playerSelection recorded on _dropStates → WinnerWithSelfAndSelectionFmt branch
				LootRolls._dropStates["1_1"] = { state = "resolved", playerSelection = "NEED" }
				local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
				assert.is_truthy(payload.secondaryText:find("33"))
				assert.is_truthy(payload.secondaryText:find("You: Need"))
			end)

			it("does not append player roll when selfRoll.state is NO_ROLL (4)", function()
				-- state=4 means the player selected Pass/did not roll; suppress "You: rolled" suffix
				local selfRoll = { roll = 0, state = 4, isSelf = true, isWinner = false }
				local drop = makeResolvedDrop(nil, selfRoll)
				local payload = LootRolls:BuildPayload(1, 1, drop, "resolved")
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

			-- ── Waiting state (player already clicked a button) ─────────────

			it("shows 'Waiting for results' text when actionPhase=='waiting'", function()
				LootRolls._dropStates["1_1"] = { state = "pending", actionPhase = "waiting", playerSelection = nil }
				local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
				assert.is_truthy(payload.secondaryText:find("Waiting for results"))
			end)

			it("includes player selection label in secondaryText when actionPhase=='waiting' and selection set", function()
				LootRolls._dropStates["1_1"] = { state = "pending", actionPhase = "waiting", playerSelection = "NEED" }
				local payload = LootRolls:BuildPayload(1, 1, makePendingDrop(), "pending")
				assert.is_truthy(payload.secondaryText:find("Need"))
				assert.is_truthy(payload.secondaryText:find("Waiting for results"))
			end)

			it("suppresses buttonValidity when actionPhase=='waiting'", function()
				LootRolls._dropStates["2_5"] = { state = "pending", actionPhase = "waiting" }
				LootRolls._buttonValidityCache["2_5"] = { canNeed = true, canGreed = true, canPass = true, isCached = true }
				local payload = LootRolls:BuildPayload(2, 5, makePendingDrop(), "pending")
				assert.is_nil(payload.buttonValidity)
			end)

			it("keeps buttonValidity when actionPhase is nil (not yet clicked)", function()
				LootRolls._dropStates["2_6"] = { state = "pending" }
				LootRolls._buttonValidityCache["2_6"] = { canNeed = true, canGreed = false, canPass = true, isCached = true }
				local payload = LootRolls:BuildPayload(2, 6, makePendingDrop(), "pending")
				assert.is_not_nil(payload.buttonValidity)
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

		-- ── state transition: waiting → resolved ──────────────────────────────

		describe("state transition: waiting → resolved", function()
			local ITEM_LINK_A = "|cff0070dditem:12345|r"

			local function makeResolvedDropWithItem(itemLink)
				return {
					itemHyperlink = itemLink or ITEM_LINK_A,
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

			before_each(function()
				_G.GetTime = function()
					return 1000
				end
				LootRolls.CurrentTimestamp = function()
					return 1000
				end
				LootRolls._pendingActions = {}
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
					return makeResolvedDropWithItem(ITEM_LINK_A)
				end
				-- Extra locale keys needed when BuildPayload hits self+winner+selection paths.
				ns.L["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s  |  You: rolled %d"
			end)

			it("state transition: clears actionPhase when matched action is consumed", function()
				-- Player submitted NEED, row is "waiting"; result arrives and matches.
				LootRolls._dropStates["7_3"] = { state = "pending", actionPhase = "waiting", playerSelection = "NEED" }
				LootRolls._pendingActions[42] = {
					itemLink = ITEM_LINK_A,
					rollType = "NEED",
					rollValue = 87,
					timestamp = 995,
				}
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
					return {
						itemHyperlink = ITEM_LINK_A,
						winner = {
							playerName = "Arthas",
							playerClass = "DEATHKNIGHT",
							roll = 87,
							state = 0,
							isSelf = true,
							isWinner = true,
						},
						allPassed = false,
						isTied = false,
						currentLeader = nil,
						rollInfos = { { isSelf = true, state = 0, roll = 87 } },
					}
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 7, 3)
				assert.is_nil(LootRolls._dropStates["7_3"].actionPhase)
			end)

			it("state transition: preserves playerSelection after actionPhase cleared", function()
				LootRolls._dropStates["7_3"] = { state = "pending", actionPhase = "waiting", playerSelection = "GREED" }
				LootRolls._pendingActions[43] = {
					itemLink = ITEM_LINK_A,
					rollType = "GREED",
					rollValue = nil,
					timestamp = 995,
				}
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
					return {
						itemHyperlink = ITEM_LINK_A,
						winner = { playerName = "Arthas", playerClass = "DEATHKNIGHT", roll = nil, state = 3, isSelf = false, isWinner = true },
						allPassed = false,
						isTied = false,
						currentLeader = nil,
						rollInfos = { { isSelf = true, state = 3, roll = nil } },
					}
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 7, 3)
				assert.are.equal("GREED", LootRolls._dropStates["7_3"].playerSelection)
			end)

			it("state transition: _dropStates.state becomes 'resolved' on match", function()
				LootRolls._dropStates["8_1"] = { state = "pending", actionPhase = "waiting", playerSelection = "NEED" }
				LootRolls._pendingActions[50] = {
					itemLink = ITEM_LINK_A,
					rollType = "NEED",
					rollValue = 87,
					timestamp = 995,
				}
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
					return {
						itemHyperlink = ITEM_LINK_A,
						winner = { playerName = "Arthas", playerClass = "DEATHKNIGHT", roll = 87, state = 0, isSelf = true, isWinner = true },
						allPassed = false,
						isTied = false,
						currentLeader = nil,
						rollInfos = { { isSelf = true, state = 0, roll = 87 } },
					}
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 8, 1)
				assert.are.equal("resolved", LootRolls._dropStates["8_1"].state)
			end)

			it("state transition: DispatchPayload called with 'resolved' state after match", function()
				LootRolls._dropStates["9_2"] = { state = "pending", actionPhase = "waiting", playerSelection = "NEED" }
				LootRolls._pendingActions[55] = {
					itemLink = ITEM_LINK_A,
					rollType = "NEED",
					rollValue = 87,
					timestamp = 995,
				}
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
					return {
						itemHyperlink = ITEM_LINK_A,
						winner = { playerName = "Arthas", playerClass = "DEATHKNIGHT", roll = 87, state = 0, isSelf = true, isWinner = true },
						allPassed = false,
						isTied = false,
						currentLeader = nil,
						rollInfos = { { isSelf = true, state = 0, roll = 87 } },
					}
				end
				local capturedState
				stub(LootRolls, "DispatchPayload", function(_, eID, lID, di, st)
					capturedState = st
				end)
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 9, 2)
				assert.are.equal("resolved", capturedState)
			end)

			it("state transition: actionPhase NOT cleared when no match found (stays nil)", function()
				-- Row has no actionPhase (no button clicked) — result arrives unmatched;
				-- entry.actionPhase stays nil, state becomes resolved normally.
				LootRolls._dropStates["11_1"] = { state = "pending" }
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
					return makeResolvedDropWithItem(ITEM_LINK_A)
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 11, 1)
				assert.is_nil(LootRolls._dropStates["11_1"].actionPhase)
				assert.are.equal("resolved", LootRolls._dropStates["11_1"].state)
			end)

			it("state transition: allPassed result without pending action leaves actionPhase nil", function()
				LootRolls._dropStates["12_1"] = { state = "pending" }
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
					return {
						itemHyperlink = ITEM_LINK_A,
						winner = nil,
						allPassed = true,
						isTied = false,
						currentLeader = nil,
						rollInfos = {},
					}
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 12, 1)
				assert.is_nil(LootRolls._dropStates["12_1"].actionPhase)
				assert.are.equal("allPassed", LootRolls._dropStates["12_1"].state)
			end)

			it("state transition: waiting actionPhase cleared on allPassed match", function()
				-- Player clicked Pass and allPassed fires — action is consumed.
				LootRolls._dropStates["13_1"] = { state = "pending", actionPhase = "waiting", playerSelection = "PASS" }
				LootRolls._pendingActions[60] = {
					itemLink = ITEM_LINK_A,
					rollType = "PASS",
					rollValue = nil,
					timestamp = 995,
				}
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
					return {
						itemHyperlink = ITEM_LINK_A,
						winner = nil,
						allPassed = true,
						isTied = false,
						currentLeader = nil,
						rollInfos = { { isSelf = true, state = 5, roll = nil } },
					}
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 13, 1)
				assert.is_nil(LootRolls._dropStates["13_1"].actionPhase)
			end)

			it("state transition: waiting entry is terminal-guarded (re-fire does not re-process)", function()
				-- Simulate an entry already marked resolved — second fire should skip.
				LootRolls._dropStates["14_1"] = { state = "resolved", actionPhase = "waiting" }
				local dispatchSpy = spy.on(LootRolls, "DispatchPayload")
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 14, 1)
				assert.spy(dispatchSpy).was.not_called()
				-- actionPhase unchanged since early-exit guard fired before any transition.
				assert.are.equal("waiting", LootRolls._dropStates["14_1"].actionPhase)
			end)
		end)
	end)

	-- ── Retail START_LOOT_ROLL staging ────────────────────────────────────────

	describe("Retail START_LOOT_ROLL staging", function()
		before_each(function()
			ns.IsRetail = function()
				return true
			end
		end)

		it("stages validity and item link keyed by rollID", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 42, 60)
			assert.is_not_nil(LootRolls._stagedRollValidity[42])
			assert.is_not_nil(LootRolls._stagedRollValidity[42].validity)
			assert.is_true(LootRolls._stagedRollValidity[42].validity.canNeed)
			assert.are.equal("|cff0070dditem:12345|r", LootRolls._stagedRollValidity[42].itemLink)
		end)

		it("does not stage when GetRetailRollItemLink returns nil", function()
			LootRolls._lootRollsAdapter.GetRetailRollItemLink = function()
				return nil
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 7, 60)
			assert.is_nil(LootRolls._stagedRollValidity[7])
		end)

		it("does not stage when GetRollButtonValidity returns nil", function()
			LootRolls._lootRollsAdapter.GetRollButtonValidity = function()
				return nil
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 8, 60)
			assert.is_nil(LootRolls._stagedRollValidity[8])
		end)

		it("LOOT_HISTORY_UPDATE_DROP absorbs staged validity by item link match", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			-- Stage via START_LOOT_ROLL first.
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 55, 60)
			assert.is_not_nil(LootRolls._stagedRollValidity[55])
			-- LOOT_HISTORY_UPDATE_DROP absorbs by item link.
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 3, 1)
			assert.is_not_nil(LootRolls._buttonValidityCache["3_1"])
			assert.is_true(LootRolls._buttonValidityCache["3_1"].canNeed)
			-- Staging entry removed after absorption.
			assert.is_nil(LootRolls._stagedRollValidity[55])
			-- rollID stored on drop state entry for payload propagation.
			assert.are.equal(55, LootRolls._dropStates["3_1"].rollID)
		end)

		it("BuildPayload includes rollID from drop state when present", function()
			LootRolls._dropStates["3_1"] = { state = "pending", rollID = 55 }
			local payload = LootRolls:BuildPayload(3, 1, makePendingDrop(), "pending")
			assert.are.equal(55, payload.rollID)
		end)

		it("BuildPayload does not set rollID when drop state has none (Classic)", function()
			LootRolls._dropStates["3_1"] = { state = "pending" }
			local payload = LootRolls:BuildPayload(3, 1, makePendingDrop(), "pending")
			assert.is_nil(payload.rollID)
		end)

		it("LOOT_HISTORY_UPDATE_DROP does not absorb when no staged item link matches", function()
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				local drop = makePendingDrop()
				drop.itemHyperlink = "|cff0070dditem:99999|r"
				return drop
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 55, 60) -- staged with ITEM_LINK
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 3, 1)
			assert.is_nil(LootRolls._buttonValidityCache["3_1"])
			-- Staged entry is still there (not consumed).
			assert.is_not_nil(LootRolls._stagedRollValidity[55])
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

		-- ── Classic waiting state (player already clicked a button) ──────────

		it("shows 'Waiting for results' text when Classic actionPhase=='waiting'", function()
			LootRolls._dropStates["50_50"] = {
				state = "pending",
				actionPhase = "waiting",
				playerSelection = nil,
				_isClassic = true,
			}
			local payload = LootRolls:BuildClassicPayload(50, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.is_truthy(payload.secondaryText:find("Waiting for results"))
		end)

		it("includes selection label in Classic secondaryText when actionPhase=='waiting'", function()
			LootRolls._dropStates["51_51"] = {
				state = "pending",
				actionPhase = "waiting",
				playerSelection = "GREED",
				_isClassic = true,
			}
			local payload = LootRolls:BuildClassicPayload(51, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.is_truthy(payload.secondaryText:find("Greed"))
			assert.is_truthy(payload.secondaryText:find("Waiting for results"))
		end)

		it("suppresses Classic buttonValidity when actionPhase=='waiting'", function()
			LootRolls._dropStates["52_52"] = {
				state = "pending",
				actionPhase = "waiting",
				_isClassic = true,
			}
			LootRolls._buttonValidityCache["52_52"] = { canNeed = true, canPass = true, isCached = true }
			local payload = LootRolls:BuildClassicPayload(52, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.is_nil(payload.buttonValidity)
		end)

		it("keeps Classic buttonValidity when actionPhase is nil (not yet clicked)", function()
			LootRolls._dropStates["53_53"] = { state = "pending", _isClassic = true }
			LootRolls._buttonValidityCache["53_53"] = { canNeed = true, canGreed = false, canPass = true, isCached = true }
			local payload = LootRolls:BuildClassicPayload(53, makeClassicDropInfo(), "pending", makeClassicItemInfo())
			assert.is_not_nil(payload.buttonValidity)
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

	-- ── Pending action queue ──────────────────────────────────────────────────

	describe("pending action queue", function()
		local LINK_A = "|cff0070dditem:111|r"
		local LINK_B = "|cff0070dditem:222|r"

		before_each(function()
			-- Inject a deterministic clock: CurrentTimestamp returns 1000 by default.
			LootRolls.CurrentTimestamp = function()
				return 1000
			end
			LootRolls._pendingActions = {}
		end)

		-- ── EnqueueAction ────────────────────────────────────────────────────

		describe("EnqueueAction", function()
			it("stores entry keyed by rollID with correct fields", function()
				LootRolls:EnqueueAction(42, LINK_A, "NEED", nil)
				local entry = LootRolls._pendingActions[42]
				assert.is_not_nil(entry)
				assert.are.equal(LINK_A, entry.itemLink)
				assert.are.equal("NEED", entry.rollType)
				assert.is_nil(entry.rollValue)
				assert.are.equal(1000, entry.timestamp)
			end)

			it("stores rollValue when provided", function()
				LootRolls:EnqueueAction(7, LINK_A, "NEED", 95)
				assert.are.equal(95, LootRolls._pendingActions[7].rollValue)
			end)

			it("overwrites existing entry for the same rollID", function()
				LootRolls:EnqueueAction(5, LINK_A, "GREED", nil)
				LootRolls:EnqueueAction(5, LINK_B, "NEED", 80)
				local entry = LootRolls._pendingActions[5]
				assert.are.equal(LINK_B, entry.itemLink)
				assert.are.equal("NEED", entry.rollType)
				assert.are.equal(80, entry.rollValue)
			end)

			it("supports concurrent enqueues for different rollIDs", function()
				LootRolls:EnqueueAction(1, LINK_A, "NEED", nil)
				LootRolls:EnqueueAction(2, LINK_B, "GREED", nil)
				assert.is_not_nil(LootRolls._pendingActions[1])
				assert.is_not_nil(LootRolls._pendingActions[2])
				assert.are_not.equal(LootRolls._pendingActions[1].itemLink, LootRolls._pendingActions[2].itemLink)
			end)

			it("captures timestamp from CurrentTimestamp at enqueue time", function()
				local clock = 500
				LootRolls.CurrentTimestamp = function()
					return clock
				end
				LootRolls:EnqueueAction(10, LINK_A, "PASS", nil)
				assert.are.equal(500, LootRolls._pendingActions[10].timestamp)
			end)
		end)

		-- ── DequeueAction ────────────────────────────────────────────────────

		describe("DequeueAction", function()
			it("returns entry and removes it from queue", function()
				LootRolls._pendingActions[99] =
					{ itemLink = LINK_A, rollType = "GREED", rollValue = nil, timestamp = 1000 }
				local entry = LootRolls:DequeueAction(99)
				assert.is_not_nil(entry)
				assert.are.equal(LINK_A, entry.itemLink)
				assert.is_nil(LootRolls._pendingActions[99])
			end)

			it("returns nil when rollID not in queue", function()
				local result = LootRolls:DequeueAction(404)
				assert.is_nil(result)
			end)

			it("does not affect other entries when dequeuing one rollID", function()
				LootRolls._pendingActions[1] =
					{ itemLink = LINK_A, rollType = "NEED", rollValue = nil, timestamp = 1000 }
				LootRolls._pendingActions[2] =
					{ itemLink = LINK_B, rollType = "GREED", rollValue = nil, timestamp = 1000 }
				LootRolls:DequeueAction(1)
				assert.is_not_nil(LootRolls._pendingActions[2])
			end)

			it("returns nil on second call for the same rollID", function()
				LootRolls._pendingActions[3] =
					{ itemLink = LINK_A, rollType = "PASS", rollValue = nil, timestamp = 1000 }
				LootRolls:DequeueAction(3)
				local second = LootRolls:DequeueAction(3)
				assert.is_nil(second)
			end)
		end)

		-- ── ScanPendingActions ───────────────────────────────────────────────

		describe("ScanPendingActions", function()
			it("returns nil when queue is empty", function()
				local rollID, action = LootRolls:ScanPendingActions(function()
					return true
				end)
				assert.is_nil(rollID)
				assert.is_nil(action)
			end)

			it("returns matched rollID and action, removes from queue", function()
				LootRolls._pendingActions[11] =
					{ itemLink = LINK_A, rollType = "NEED", rollValue = nil, timestamp = 1000 }
				local rollID, action = LootRolls:ScanPendingActions(function(rID, act)
					return rID == 11 and act.itemLink == LINK_A
				end)
				assert.are.equal(11, rollID)
				assert.are.equal(LINK_A, action.itemLink)
				-- Entry removed after match.
				assert.is_nil(LootRolls._pendingActions[11])
			end)

			it("returns nil when matchFn never returns true", function()
				LootRolls._pendingActions[12] =
					{ itemLink = LINK_A, rollType = "GREED", rollValue = nil, timestamp = 1000 }
				local rollID, action = LootRolls:ScanPendingActions(function()
					return false
				end)
				assert.is_nil(rollID)
				assert.is_nil(action)
				-- Entry still present.
				assert.is_not_nil(LootRolls._pendingActions[12])
			end)

			it("stops at first match (does not visit later entries)", function()
				LootRolls._pendingActions[20] =
					{ itemLink = LINK_A, rollType = "NEED", rollValue = nil, timestamp = 1000 }
				LootRolls._pendingActions[21] =
					{ itemLink = LINK_B, rollType = "GREED", rollValue = nil, timestamp = 1000 }
				local visited = {}
				LootRolls:ScanPendingActions(function(rID, _act)
					visited[rID] = true
					return true -- match the very first entry visited
				end)
				-- Exactly one entry should have been visited (first match stops scan).
				local count = 0
				for _ in pairs(visited) do
					count = count + 1
				end
				assert.are.equal(1, count)
			end)

			it("leaves non-matched entries intact when one matches", function()
				LootRolls._pendingActions[30] =
					{ itemLink = LINK_A, rollType = "NEED", rollValue = nil, timestamp = 1000 }
				LootRolls._pendingActions[31] =
					{ itemLink = LINK_B, rollType = "GREED", rollValue = nil, timestamp = 1000 }
				LootRolls:ScanPendingActions(function(_rID, act)
					return act.rollType == "NEED"
				end)
				-- The GREED entry should remain.
				local remaining = 0
				for _ in pairs(LootRolls._pendingActions) do
					remaining = remaining + 1
				end
				assert.are.equal(1, remaining)
			end)

			it("iterates over a key snapshot so matchFn can safely remove other entries", function()
				LootRolls._pendingActions[40] =
					{ itemLink = LINK_A, rollType = "PASS", rollValue = nil, timestamp = 1000 }
				LootRolls._pendingActions[41] =
					{ itemLink = LINK_B, rollType = "PASS", rollValue = nil, timestamp = 1000 }
				-- matchFn removes 41 as a side-effect (simulating a concurrent cancel), then matches 40.
				LootRolls:ScanPendingActions(function(rID, _act)
					if rID == 40 then
						LootRolls._pendingActions[41] = nil -- side-effect
						return true
					end
					return false
				end)
				-- No crash; 40 matched and removed, 41 already removed inside matchFn.
				assert.is_nil(LootRolls._pendingActions[40])
				assert.is_nil(LootRolls._pendingActions[41])
			end)
		end)

		-- ── ClearAllPendingActions ───────────────────────────────────────────

		describe("ClearAllPendingActions", function()
			it("empties the queue", function()
				LootRolls._pendingActions[50] =
					{ itemLink = LINK_A, rollType = "NEED", rollValue = nil, timestamp = 1000 }
				LootRolls._pendingActions[51] =
					{ itemLink = LINK_B, rollType = "GREED", rollValue = nil, timestamp = 1000 }
				LootRolls:ClearAllPendingActions()
				assert.are.same({}, LootRolls._pendingActions)
			end)

			it("is a no-op on an empty queue", function()
				-- Should not error.
				LootRolls:ClearAllPendingActions()
				assert.are.same({}, LootRolls._pendingActions)
			end)

			it("uses key snapshot so Lua iteration is not corrupted mid-clear", function()
				-- Populate 5 entries and clear — verify all gone without error.
				for i = 60, 64 do
					LootRolls._pendingActions[i] =
						{ itemLink = LINK_A, rollType = "PASS", rollValue = nil, timestamp = 1000 }
				end
				LootRolls:ClearAllPendingActions()
				local count = 0
				for _ in pairs(LootRolls._pendingActions) do
					count = count + 1
				end
				assert.are.equal(0, count)
			end)
		end)

		-- ── TimestampDelta ───────────────────────────────────────────────────

		describe("TimestampDelta", function()
			it("returns elapsed seconds since stored timestamp", function()
				local clock = 1000
				LootRolls.CurrentTimestamp = function()
					return clock
				end
				local delta = LootRolls:TimestampDelta(990)
				assert.are.equal(10, delta)
			end)

			it("returns 0 when timestamp equals current time", function()
				LootRolls.CurrentTimestamp = function()
					return 500
				end
				assert.are.equal(0, LootRolls:TimestampDelta(500))
			end)
		end)

		-- ── OnDisable resets _pendingActions ─────────────────────────────────

		it("OnDisable resets _pendingActions", function()
			LootRolls._pendingActions[70] = { itemLink = LINK_A, rollType = "NEED", rollValue = nil, timestamp = 1000 }
			LootRolls:OnDisable()
			assert.are.same({}, LootRolls._pendingActions)
		end)
	end)

	-- ── START_LOOT_ROLL enqueue (Retail) ──────────────────────────────────────

	describe("Retail START_LOOT_ROLL enqueue", function()
		before_each(function()
			LootRolls._pendingActions = {}
			LootRolls._stagedRollValidity = {}
			LootRolls._dropStates = {}
			-- Reset to Retail mode.
			ns.IsRetail = function()
				return true
			end
			-- Deterministic clock.
			LootRolls.CurrentTimestamp = function()
				return 1000
			end
		end)

		it("START_LOOT_ROLL enqueue: pre-enqueues pending action with itemLink and nil rollType", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 42, 60)
			local entry = LootRolls._pendingActions[42]
			assert.is_not_nil(entry)
			assert.are.equal("|cff0070dditem:12345|r", entry.itemLink)
			assert.is_nil(entry.rollType)
			assert.is_nil(entry.rollValue)
			assert.are.equal(1000, entry.timestamp)
		end)

		it("START_LOOT_ROLL enqueue: does not enqueue when GetRetailRollItemLink returns nil", function()
			LootRolls._lootRollsAdapter.GetRetailRollItemLink = function()
				return nil
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 99, 60)
			assert.is_nil(LootRolls._pendingActions[99])
		end)

		it("START_LOOT_ROLL enqueue: enqueues even when GetRollButtonValidity returns nil", function()
			LootRolls._lootRollsAdapter.GetRollButtonValidity = function()
				return nil
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 77, 60)
			-- itemLink is available, so we should still enqueue.
			local entry = LootRolls._pendingActions[77]
			assert.is_not_nil(entry)
			assert.is_nil(entry.rollType)
		end)

		it("START_LOOT_ROLL enqueue: second call for same rollID overwrites pending slot", function()
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 5, 60)
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 5, 60)
			local count = 0
			for _ in pairs(LootRolls._pendingActions) do
				count = count + 1
			end
			assert.are.equal(1, count)
		end)

		it("START_LOOT_ROLL enqueue: concurrent rollIDs produce independent queue entries", function()
			LootRolls._lootRollsAdapter.GetRetailRollItemLink = function(rID)
				return "|cff0070dditem:" .. rID .. "|r"
			end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 10, 60)
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 11, 60)
			assert.is_not_nil(LootRolls._pendingActions[10])
			assert.is_not_nil(LootRolls._pendingActions[11])
			assert.are_not.equal(LootRolls._pendingActions[10].itemLink, LootRolls._pendingActions[11].itemLink)
		end)
	end)

	-- ── START_LOOT_ROLL Classic enqueue ───────────────────────────────────────

	describe("Classic START_LOOT_ROLL enqueue", function()
		before_each(function()
			LootRolls._pendingActions = {}
			LootRolls._stagedRollValidity = {}
			LootRolls._dropStates = {}
			ns.IsRetail = function()
				return false
			end
			LootRolls.CurrentTimestamp = function()
				return 2000
			end
			LootRolls._lootRollsAdapter.HasStartLootRollEvent = function()
				return true
			end
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function(rID)
				return {
					itemLink = "|cff0070dditem:" .. rID .. "|r",
					canNeed = true,
					canGreed = true,
					canDisenchant = false,
					texture = 132319,
					quality = 4,
				}
			end
			LootRolls._lootRollsAdapter.DispatchClassicPayload = function() end
		end)

		it("Classic START_LOOT_ROLL enqueue: pre-enqueues pending action with itemLink", function()
			LootRolls.DispatchClassicPayload = function() end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 42, 60)
			local entry = LootRolls._pendingActions[42]
			assert.is_not_nil(entry)
			assert.are.equal("|cff0070dditem:42|r", entry.itemLink)
			assert.is_nil(entry.rollType)
			assert.is_nil(entry.rollValue)
			assert.are.equal(2000, entry.timestamp)
		end)

		it("Classic START_LOOT_ROLL enqueue: no enqueue when GetClassicRollItemInfo returns nil", function()
			LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function()
				return nil
			end
			LootRolls.DispatchClassicPayload = function() end
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 55, 60)
			assert.is_nil(LootRolls._pendingActions[55])
		end)
	end)

	-- ── MAIN_SPEC_NEED_ROLL handler ───────────────────────────────────────────

	describe("MAIN_SPEC_NEED_ROLL", function()
		before_each(function()
			LootRolls._pendingActions = {}
			LootRolls.CurrentTimestamp = function()
				return 1000
			end
		end)

		it("MAIN_SPEC_NEED_ROLL: sets rollType=NEED and rollValue on existing pending action", function()
			-- Pre-enqueue a slot as START_LOOT_ROLL would.
			LootRolls._pendingActions[42] = {
				itemLink = "|cff0070dditem:12345|r",
				rollType = nil,
				rollValue = nil,
				timestamp = 1000,
			}
			LootRolls:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", 42, 87)
			local entry = LootRolls._pendingActions[42]
			assert.is_not_nil(entry)
			assert.are.equal("NEED", entry.rollType)
			assert.are.equal(87, entry.rollValue)
		end)

		it("MAIN_SPEC_NEED_ROLL: does not error when no pending action exists for rollID", function()
			-- Player may have used Blizzard UI — no entry in queue.
			assert.has_no.errors(function()
				LootRolls:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", 999, 42)
			end)
			-- No phantom entry created.
			assert.is_nil(LootRolls._pendingActions[999])
		end)

		it("MAIN_SPEC_NEED_ROLL: preserves itemLink and timestamp on update", function()
			local link = "|cff0070dditem:99999|r"
			LootRolls._pendingActions[7] = {
				itemLink = link,
				rollType = nil,
				rollValue = nil,
				timestamp = 500,
			}
			LootRolls:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", 7, 55)
			local entry = LootRolls._pendingActions[7]
			assert.are.equal(link, entry.itemLink)
			assert.are.equal(500, entry.timestamp)
		end)

		it("MAIN_SPEC_NEED_ROLL: overwrites previous rollValue if fired twice for same rollID", function()
			LootRolls._pendingActions[3] = {
				itemLink = "|cff0070dditem:111|r",
				rollType = "NEED",
				rollValue = 33,
				timestamp = 1000,
			}
			LootRolls:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", 3, 77)
			assert.are.equal(77, LootRolls._pendingActions[3].rollValue)
		end)

		it("MAIN_SPEC_NEED_ROLL: does not affect other pending actions", function()
			LootRolls._pendingActions[1] =
				{ itemLink = "|cff0070dditem:1|r", rollType = nil, rollValue = nil, timestamp = 1000 }
			LootRolls._pendingActions[2] =
				{ itemLink = "|cff0070dditem:2|r", rollType = nil, rollValue = nil, timestamp = 1000 }
			LootRolls:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", 1, 66)
			assert.is_nil(LootRolls._pendingActions[2].rollType)
			assert.is_nil(LootRolls._pendingActions[2].rollValue)
		end)
	end)

	-- ── OnEnable registers MAIN_SPEC_NEED_ROLL on Retail ─────────────────────

	describe("OnEnable MAIN_SPEC_NEED_ROLL registration", function()
		it("registers MAIN_SPEC_NEED_ROLL on Retail", function()
			ns.IsRetail = function()
				return true
			end
			local regSpy = spy.on(LootRolls, "RegisterEvent")
			LootRolls:OnEnable()
			assert.spy(regSpy).was.called_with(LootRolls, "MAIN_SPEC_NEED_ROLL")
		end)

		it("does not register MAIN_SPEC_NEED_ROLL on Classic", function()
			ns.IsRetail = function()
				return false
			end
			LootRolls._lootRollsAdapter.HasStartLootRollEvent = function()
				return true
			end
			local registered = {}
			LootRolls.RegisterEvent = function(_, e)
				registered[e] = true
			end
			LootRolls:OnEnable()
			assert.is_nil(registered["MAIN_SPEC_NEED_ROLL"])
		end)
	end)

	-- ── CANCEL_LOOT_ROLL handler ──────────────────────────────────────────────

	describe("CANCEL_LOOT_ROLL", function()
		before_each(function()
			LootRolls._pendingActions = {}
			LootRolls.CurrentTimestamp = function()
				return 1000
			end
		end)

		it("CANCEL_LOOT_ROLL: removes a pending action entry for the given rollID", function()
			LootRolls._pendingActions[42] = {
				itemLink = "|cff0070dditem:12345|r",
				rollType = "NEED",
				rollValue = nil,
				timestamp = 990,
			}
			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 42)
			assert.is_nil(LootRolls._pendingActions[42])
		end)

		it("CANCEL_LOOT_ROLL: does not error when no pending entry exists for rollID", function()
			-- Player used built-in UI — no entry in queue; should be silent no-op.
			assert.has_no.errors(function()
				LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 999)
			end)
		end)

		it("CANCEL_LOOT_ROLL: does not affect other pending actions", function()
			LootRolls._pendingActions[1] =
				{ itemLink = "|cff0070dditem:1|r", rollType = nil, rollValue = nil, timestamp = 1000 }
			LootRolls._pendingActions[2] =
				{ itemLink = "|cff0070dditem:2|r", rollType = nil, rollValue = nil, timestamp = 1000 }
			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 1)
			assert.is_nil(LootRolls._pendingActions[1])
			assert.is_not_nil(LootRolls._pendingActions[2])
		end)

		it("CANCEL_LOOT_ROLL: handles nil rollType gracefully (slot pre-enqueued but not yet updated)", function()
			LootRolls._pendingActions[7] = {
				itemLink = "|cff0070dditem:7|r",
				rollType = nil,
				rollValue = nil,
				timestamp = 1000,
			}
			assert.has_no.errors(function()
				LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 7)
			end)
			assert.is_nil(LootRolls._pendingActions[7])
		end)
	end)

	-- ── CANCEL_ALL_LOOT_ROLLS handler (iteration-safe) ───────────────────────

	describe("CANCEL_ALL_LOOT_ROLL iteration safe", function()
		before_each(function()
			LootRolls._pendingActions = {}
			LootRolls.CurrentTimestamp = function()
				return 2000
			end
		end)

		it("CANCEL_ALL_LOOT_ROLL: clears all pending actions", function()
			LootRolls._pendingActions[10] =
				{ itemLink = "|cff0070dditem:10|r", rollType = "NEED", rollValue = nil, timestamp = 1990 }
			LootRolls._pendingActions[11] =
				{ itemLink = "|cff0070dditem:11|r", rollType = "GREED", rollValue = nil, timestamp = 1995 }
			LootRolls:CANCEL_ALL_LOOT_ROLLS("CANCEL_ALL_LOOT_ROLLS")
			assert.are.same({}, LootRolls._pendingActions)
		end)

		it("CANCEL_ALL_LOOT_ROLL: is safe when queue is already empty", function()
			assert.has_no.errors(function()
				LootRolls:CANCEL_ALL_LOOT_ROLLS("CANCEL_ALL_LOOT_ROLLS")
			end)
			assert.are.same({}, LootRolls._pendingActions)
		end)

		it("CANCEL_ALL_LOOT_ROLL: does not corrupt iteration — all entries removed", function()
			for i = 1, 5 do
				LootRolls._pendingActions[i] =
					{ itemLink = "|cff0070dditem:" .. i .. "|r", rollType = nil, rollValue = nil, timestamp = 2000 }
			end
			LootRolls:CANCEL_ALL_LOOT_ROLLS("CANCEL_ALL_LOOT_ROLLS")
			local count = 0
			for _ in pairs(LootRolls._pendingActions) do
				count = count + 1
			end
			assert.are.equal(0, count)
		end)

		it("CANCEL_ALL_LOOT_ROLL: single entry is removed cleanly", function()
			LootRolls._pendingActions[99] =
				{ itemLink = "|cff0070dditem:99|r", rollType = "PASS", rollValue = nil, timestamp = 1900 }
			LootRolls:CANCEL_ALL_LOOT_ROLLS("CANCEL_ALL_LOOT_ROLLS")
			assert.is_nil(LootRolls._pendingActions[99])
		end)
	end)

	-- ── OnEnable registers CANCEL events ─────────────────────────────────────

	describe("OnEnable CANCEL_LOOT_ROLL registration", function()
		it("registers CANCEL_LOOT_ROLL and CANCEL_ALL_LOOT_ROLLS on Retail", function()
			ns.IsRetail = function()
				return true
			end
			local regSpy = spy.on(LootRolls, "RegisterEvent")
			LootRolls:OnEnable()
			assert.spy(regSpy).was.called_with(LootRolls, "CANCEL_LOOT_ROLL")
			assert.spy(regSpy).was.called_with(LootRolls, "CANCEL_ALL_LOOT_ROLLS")
		end)

		it("registers CANCEL_LOOT_ROLL and CANCEL_ALL_LOOT_ROLLS on Classic", function()
			ns.IsRetail = function()
				return false
			end
			LootRolls._lootRollsAdapter.HasStartLootRollEvent = function()
				return true
			end
			local regSpy = spy.on(LootRolls, "RegisterEvent")
			LootRolls:OnEnable()
			assert.spy(regSpy).was.called_with(LootRolls, "CANCEL_LOOT_ROLL")
			assert.spy(regSpy).was.called_with(LootRolls, "CANCEL_ALL_LOOT_ROLLS")
		end)
	end)

	-- ── MatchActionToResult ───────────────────────────────────────────────────

	describe("LootRolls match: MatchActionToResult", function()
		local ITEM_A = "|cff0070dditem:111|r"
		local ITEM_B = "|cff0070dditem:222|r"
		-- EncounterLootDropRollState enum values:
		--   0 = NeedMainSpec, 1 = NeedOffSpec, 2 = Transmog,
		--   3 = Greed,        4 = NoRoll,      5 = Pass
		local ROLL_STATE_NEED = 0
		local ROLL_STATE_NEED_OFF = 1
		local ROLL_STATE_TRANSMOG = 2
		local ROLL_STATE_GREED = 3
		local ROLL_STATE_NO_ROLL = 4
		local ROLL_STATE_PASS = 5

		local function makeDropInfo(itemHyperlink, rollState, rollValue)
			return {
				itemHyperlink = itemHyperlink,
				rollInfos = {
					{ isSelf = true, state = rollState, roll = rollValue },
				},
			}
		end

		before_each(function()
			LootRolls.CurrentTimestamp = function()
				return 1000
			end
			LootRolls._pendingActions = {}
		end)

		-- ── temporal match: single-drop NEED ─────────────────────────────────

		it("LootRolls multi-drop: matches single NEED pending action by itemLink + rollValue", function()
			LootRolls._pendingActions[1] = {
				itemLink = ITEM_A,
				rollType = "NEED",
				rollValue = 95,
				timestamp = 994,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NEED, 95)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(1, rollID)
			assert.are.equal("NEED", action.rollType)
			assert.are.equal(95, action.rollValue)
		end)

		it("LootRolls match: matched NEED action is removed from queue", function()
			LootRolls._pendingActions[1] = {
				itemLink = ITEM_A,
				rollType = "NEED",
				rollValue = 95,
				timestamp = 994,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NEED, 95)
			LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.is_nil(LootRolls._pendingActions[1])
		end)

		-- ── temporal match: single-drop GREED ────────────────────────────────

		it("LootRolls match: matches single GREED pending action by itemLink + rollType", function()
			LootRolls._pendingActions[5] = {
				itemLink = ITEM_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 995,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_GREED, nil)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(5, rollID)
			assert.are.equal("GREED", action.rollType)
		end)

		it("LootRolls match: matches PASS pending action by itemLink + rollType", function()
			LootRolls._pendingActions[9] = {
				itemLink = ITEM_A,
				rollType = "PASS",
				rollValue = nil,
				timestamp = 995,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_PASS, nil)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(9, rollID)
			assert.are.equal("PASS", action.rollType)
		end)

		it("LootRolls match: matches TRANSMOG pending action by itemLink + rollType", function()
			LootRolls._pendingActions[3] = {
				itemLink = ITEM_A,
				rollType = "TRANSMOG",
				rollValue = nil,
				timestamp = 998,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_TRANSMOG, nil)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(3, rollID)
			assert.are.equal("TRANSMOG", action.rollType)
		end)

		-- ── multi-drop: different rollTypes disambiguates ─────────────────────

		it("LootRolls multi-drop: two pending actions on same item, NEED matched by rollValue", function()
			-- Player A: NEED roll=85 on ITEM_A (rollID 10)
			-- Player B: GREED on ITEM_A (rollID 11) — wrong type, should not match
			LootRolls._pendingActions[10] = {
				itemLink = ITEM_A,
				rollType = "NEED",
				rollValue = 85,
				timestamp = 996,
			}
			LootRolls._pendingActions[11] = {
				itemLink = ITEM_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 996,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NEED, 85)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(10, rollID)
			assert.are.equal("NEED", action.rollType)
			-- GREED slot must remain
			assert.is_not_nil(LootRolls._pendingActions[11])
		end)

		it("LootRolls multi-drop: two pending NEED on same item, different rollValues, correct one matched", function()
			-- Two NEED rolls on the same item with different numeric results.
			-- The drop result carries rollValue=72; only rollID 20 matches.
			LootRolls._pendingActions[20] = {
				itemLink = ITEM_A,
				rollType = "NEED",
				rollValue = 72,
				timestamp = 997,
			}
			LootRolls._pendingActions[21] = {
				itemLink = ITEM_A,
				rollType = "NEED",
				rollValue = 35,
				timestamp = 997,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NEED, 72)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(20, rollID)
			assert.are.equal(72, action.rollValue)
			-- The other NEED slot must remain
			assert.is_not_nil(LootRolls._pendingActions[21])
		end)

		it("LootRolls multi-drop: NeedOffSpec (state=1) pending NEED matched by rollValue", function()
			-- NeedOffSpec still maps to rollType "NEED" in the pending queue.
			LootRolls._pendingActions[30] = {
				itemLink = ITEM_A,
				rollType = "NEED",
				rollValue = 50,
				timestamp = 995,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NEED_OFF, 50)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(30, rollID)
			assert.are.equal("NEED", action.rollType)
		end)

		-- ── temporal: out-of-window actions skipped ───────────────────────────

		it("LootRolls temporal: action older than 12s is not matched (out-of-window)", function()
			-- CurrentTimestamp returns 1000; timestamp=987 → age=13s > 12s window.
			LootRolls._pendingActions[7] = {
				itemLink = ITEM_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 987,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_GREED, nil)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.is_nil(rollID)
			assert.is_nil(action)
		end)

		it("LootRolls temporal: action exactly 12s old is matched (boundary inside window)", function()
			-- age = 1000 - 988 = 12 — equal to MATCH_WINDOW_SECONDS, should still pass.
			LootRolls._pendingActions[8] = {
				itemLink = ITEM_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 988,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_GREED, nil)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(8, rollID)
			assert.are.equal("GREED", action.rollType)
		end)

		it("LootRolls temporal: valid and stale actions coexist; only fresh one matched", function()
			-- rollID 100: stale (age=15s)
			LootRolls._pendingActions[100] = {
				itemLink = ITEM_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 985,
			}
			-- rollID 101: fresh (age=5s)
			LootRolls._pendingActions[101] = {
				itemLink = ITEM_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 995,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_GREED, nil)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(101, rollID)
			assert.are.equal("GREED", action.rollType)
		end)

		-- ── no-match scenarios ────────────────────────────────────────────────

		it("LootRolls match: returns nil when queue is empty", function()
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NEED, 80)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.is_nil(rollID)
			assert.is_nil(action)
		end)

		it("LootRolls match: returns nil when itemLink does not match", function()
			LootRolls._pendingActions[2] = {
				itemLink = ITEM_B,
				rollType = "NEED",
				rollValue = 80,
				timestamp = 998,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NEED, 80)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.is_nil(rollID)
			assert.is_nil(action)
		end)

		it("LootRolls match: returns nil when rollType mismatches (pending=GREED, drop=PASS)", function()
			LootRolls._pendingActions[4] = {
				itemLink = ITEM_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 999,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_PASS, nil)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.is_nil(rollID)
			assert.is_nil(action)
		end)

		it("LootRolls match: returns nil when NEED rollValue mismatches", function()
			LootRolls._pendingActions[6] = {
				itemLink = ITEM_A,
				rollType = "NEED",
				rollValue = 42,
				timestamp = 999,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NEED, 99)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.is_nil(rollID)
			assert.is_nil(action)
		end)

		it("LootRolls match: returns nil when dropInfo.itemHyperlink is nil", function()
			LootRolls._pendingActions[12] = {
				itemLink = ITEM_A,
				rollType = "NEED",
				rollValue = 80,
				timestamp = 999,
			}
			local dropInfo = { itemHyperlink = nil, rollInfos = {} }
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.is_nil(rollID)
			assert.is_nil(action)
		end)

		it("LootRolls match: returns nil when selfRoll state is NoRoll (player still deciding)", function()
			LootRolls._pendingActions[13] = {
				itemLink = ITEM_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 999,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NO_ROLL, nil)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.is_nil(rollID)
			assert.is_nil(action)
		end)

		it("LootRolls match: returns nil when rollInfos has no self entry", function()
			LootRolls._pendingActions[14] = {
				itemLink = ITEM_A,
				rollType = "GREED",
				rollValue = nil,
				timestamp = 999,
			}
			local dropInfo = {
				itemHyperlink = ITEM_A,
				rollInfos = { { isSelf = false, state = ROLL_STATE_GREED, roll = nil } },
			}
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.is_nil(rollID)
			assert.is_nil(action)
		end)

		-- ── multi-item (different items in queue) ─────────────────────────────

		it("LootRolls multi-drop: multiple items in queue, matches only correct itemLink", function()
			LootRolls._pendingActions[50] = {
				itemLink = ITEM_B,
				rollType = "NEED",
				rollValue = 60,
				timestamp = 998,
			}
			LootRolls._pendingActions[51] = {
				itemLink = ITEM_A,
				rollType = "NEED",
				rollValue = 60,
				timestamp = 998,
			}
			local dropInfo = makeDropInfo(ITEM_A, ROLL_STATE_NEED, 60)
			local rollID, action = LootRolls:MatchActionToResult(1, 1, dropInfo)
			assert.are.equal(51, rollID)
			assert.are.equal(ITEM_A, action.itemLink)
			-- ITEM_B slot must remain
			assert.is_not_nil(LootRolls._pendingActions[50])
		end)
	end)

	-- ── OnRollButtonClick ────────────────────────────────────────────────────

	describe("OnRollButtonClick", function()
		local LINK_A = "|cff0070dditem:111|r"

		before_each(function()
			LootRolls.CurrentTimestamp = function()
				return 1000
			end
			LootRolls._pendingActions = {}
		end)

		it("updates pending entry rollType to NEED when numericType=1", function()
			LootRolls._pendingActions[10] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls:OnRollButtonClick(10, 1)
			assert.are.equal("NEED", LootRolls._pendingActions[10].rollType)
		end)

		it("updates pending entry rollType to GREED when numericType=2", function()
			LootRolls._pendingActions[11] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls:OnRollButtonClick(11, 2)
			assert.are.equal("GREED", LootRolls._pendingActions[11].rollType)
		end)

		it("updates pending entry rollType to PASS when numericType=0", function()
			LootRolls._pendingActions[12] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls:OnRollButtonClick(12, 0)
			assert.are.equal("PASS", LootRolls._pendingActions[12].rollType)
		end)

		it("updates pending entry rollType to TRANSMOG when numericType=4", function()
			LootRolls._pendingActions[13] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls:OnRollButtonClick(13, 4)
			assert.are.equal("TRANSMOG", LootRolls._pendingActions[13].rollType)
		end)

		it("updates pending entry timestamp to CurrentTimestamp on click", function()
			LootRolls._pendingActions[14] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 500 }
			LootRolls:OnRollButtonClick(14, 2)
			assert.are.equal(1000, LootRolls._pendingActions[14].timestamp)
		end)

		it("creates fallback entry when no pending slot exists for rollID", function()
			LootRolls:OnRollButtonClick(99, 2)
			local entry = LootRolls._pendingActions[99]
			assert.is_not_nil(entry)
			assert.are.equal("GREED", entry.rollType)
		end)

		it("does not update entry when numericType is unrecognised", function()
			LootRolls._pendingActions[20] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls:OnRollButtonClick(20, 99)
			-- Entry should be unchanged (rollType stays nil)
			assert.is_nil(LootRolls._pendingActions[20].rollType)
		end)

		it("does not affect other pending entries when clicking for one rollID", function()
			LootRolls._pendingActions[30] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls._pendingActions[31] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls:OnRollButtonClick(30, 1)
			assert.are.equal("NEED", LootRolls._pendingActions[30].rollType)
			assert.is_nil(LootRolls._pendingActions[31].rollType)
		end)

		-- ── State transition: pending → waiting ───────────────────────────────

		it("sets actionPhase='waiting' on _dropStates entry matched by _rollID (Retail)", function()
			LootRolls._pendingActions[40] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls._dropStates["5_3"] = { state = "pending", rollID = 40 }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return nil
			end
			LootRolls:OnRollButtonClick(40, 1)
			assert.are.equal("waiting", LootRolls._dropStates["5_3"].actionPhase)
		end)

		it("sets playerSelection on _dropStates entry when state transitions to waiting", function()
			LootRolls._pendingActions[41] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls._dropStates["6_4"] = { state = "pending", rollID = 41 }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return nil
			end
			LootRolls:OnRollButtonClick(41, 2)
			assert.are.equal("GREED", LootRolls._dropStates["6_4"].playerSelection)
		end)

		it("sets actionPhase='waiting' on Classic _dropStates entry matched by _rollID", function()
			LootRolls._pendingActions[42] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls._dropStates["42_42"] = { state = "pending", _isClassic = true, _rollID = 42, _dropInfo = nil }
			LootRolls:OnRollButtonClick(42, 0)
			assert.are.equal("waiting", LootRolls._dropStates["42_42"].actionPhase)
		end)

		it("sets playerSelection=PASS on Classic _dropStates entry when PASS clicked", function()
			LootRolls._pendingActions[43] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls._dropStates["43_43"] = { state = "pending", _isClassic = true, _rollID = 43, _dropInfo = nil }
			LootRolls:OnRollButtonClick(43, 0)
			assert.are.equal("PASS", LootRolls._dropStates["43_43"].playerSelection)
		end)

		it("re-dispatches Classic payload via DispatchClassicPayload when _dropInfo cached", function()
			LootRolls._pendingActions[44] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			local fakeDropInfo = { itemHyperlink = LINK_A, startTime = nil, duration = nil, winner = nil, allPassed = false }
			LootRolls._dropStates["44_44"] = {
				state = "pending",
				_isClassic = true,
				_rollID = 44,
				_dropInfo = fakeDropInfo,
			}
			local dispatchSpy = spy.on(LootRolls, "DispatchClassicPayload")
			LootRolls:OnRollButtonClick(44, 1)
			assert.spy(dispatchSpy).was.called()
			dispatchSpy:revert()
		end)

		it("re-dispatches Retail payload via DispatchPayload when GetSortedInfoForDrop returns data", function()
			LootRolls._pendingActions[45] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls._dropStates["7_2"] = { state = "pending", rollID = 45 }
			local fakeDropInfo =
				{ itemHyperlink = LINK_A, startTime = nil, duration = nil, winner = nil, allPassed = false }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function(encID, llID)
				if encID == 7 and llID == 2 then
					return fakeDropInfo
				end
				return nil
			end
			local dispatchSpy = spy.on(LootRolls, "DispatchPayload")
			LootRolls:OnRollButtonClick(45, 4)
			assert.spy(dispatchSpy).was.called()
			dispatchSpy:revert()
		end)

		it("does not set actionPhase when numericType is unrecognised", function()
			LootRolls._pendingActions[46] = { itemLink = LINK_A, rollType = nil, rollValue = nil, timestamp = 999 }
			LootRolls._dropStates["8_2"] = { state = "pending", rollID = 46 }
			LootRolls:OnRollButtonClick(46, 99)
			assert.is_nil(LootRolls._dropStates["8_2"].actionPhase)
		end)
	end)

	-- ── Multi-drop button validity routing by itemLink matching ───────────────
	--
	-- These tests cover Retail and Classic scenarios where the same item drops
	-- more than once in the same session.  Each roll gets its own START_LOOT_ROLL
	-- event with a distinct rollID; button validity must be scoped to the
	-- individual drop, not shared across all drops of the same item.

	describe("multi-drop button validity routing", function()
		-- ── Retail ─────────────────────────────────────────────────────────────

		describe("Retail: two rolls of the same item, independent validity snapshots", function()
			before_each(function()
				ns.IsRetail = function()
					return true
				end
			end)

			-- The game can change player state (e.g. equip/unequip) between two
			-- rolls of the same item.  The adapter mock returns different validity
			-- per rollID so we can assert each drop cached the correct snapshot.
			it("each drop absorbs its own staged validity entry", function()
				-- Roll 71: canNeed=true, canGreed=true  (item not yet equipped)
				-- Roll 72: canNeed=false, canGreed=true  (item now equipped)
				local validityByRollID = {
					[71] = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
					[72] = { canNeed = false, canGreed = true, canTransmog = false, canPass = true },
				}
				LootRolls._lootRollsAdapter.GetRollButtonValidity = function(rollID)
					return validityByRollID[rollID]
				end

				-- Both START_LOOT_ROLL events fire before either LOOT_HISTORY_UPDATE_DROP.
				LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 71, 60)
				LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 72, 60)

				-- Two staged entries should exist, keyed by rollID.
				assert.is_not_nil(LootRolls._stagedRollValidity[71])
				assert.is_not_nil(LootRolls._stagedRollValidity[72])

				-- First LOOT_HISTORY_UPDATE_DROP (encounterID=10, lootListID=1).
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function(encID, llID)
					if encID == 10 and llID == 1 then
						return makePendingDrop()
					end
					return nil
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 10, 1)

				-- One staged entry consumed; the other remains.
				local absorbedRollID = LootRolls._dropStates["10_1"] and LootRolls._dropStates["10_1"].rollID
				assert.is_not_nil(absorbedRollID)
				assert.is_nil(LootRolls._stagedRollValidity[absorbedRollID])

				-- Second LOOT_HISTORY_UPDATE_DROP (encounterID=10, lootListID=2).
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function(encID, llID)
					if encID == 10 and llID == 2 then
						return makePendingDrop()
					end
					return nil
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 10, 2)

				-- Both drops now have cached button validity.
				assert.is_not_nil(LootRolls._buttonValidityCache["10_1"])
				assert.is_not_nil(LootRolls._buttonValidityCache["10_2"])

				-- Both staged entries should have been consumed.
				assert.is_nil(LootRolls._stagedRollValidity[71])
				assert.is_nil(LootRolls._stagedRollValidity[72])
			end)

			it("each drop caches distinct validity (game state changed between rolls)", function()
				-- Roll 81: canNeed=true  (not equipped yet)
				-- Roll 82: canNeed=false (equipped between drops)
				local validityByRollID = {
					[81] = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
					[82] = { canNeed = false, canGreed = true, canTransmog = false, canPass = true },
				}
				LootRolls._lootRollsAdapter.GetRollButtonValidity = function(rollID)
					return validityByRollID[rollID]
				end

				-- Stage both rolls.
				LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 81, 60)
				LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 82, 60)

				-- Absorb into two separate drops.
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function(encID, _llID)
					if encID == 20 then
						return makePendingDrop()
					end
					return nil
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 20, 1)
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 20, 2)

				-- Determine which rollID landed in which drop key.
				local rollID_20_1 = LootRolls._dropStates["20_1"] and LootRolls._dropStates["20_1"].rollID
				local rollID_20_2 = LootRolls._dropStates["20_2"] and LootRolls._dropStates["20_2"].rollID

				assert.is_not_nil(rollID_20_1)
				assert.is_not_nil(rollID_20_2)
				-- Each drop owns a different rollID (the staged entries are distinct).
				assert.are_not.equal(rollID_20_1, rollID_20_2)

				-- canNeed must reflect the snapshot captured at START_LOOT_ROLL time.
				local need_20_1 = LootRolls._buttonValidityCache["20_1"].canNeed
				local need_20_2 = LootRolls._buttonValidityCache["20_2"].canNeed
				-- One of the drops has canNeed=true and the other canNeed=false.
				assert.are_not.equal(need_20_1, need_20_2)
			end)

			it("second drop is not blocked when first drop has already been absorbed", function()
				-- Simulate START_LOOT_ROLL for two sequential rolls of the same item.
				LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 91, 60)
				-- First LOOT_HISTORY_UPDATE_DROP fires and absorbs roll 91's staged entry.
				LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
					return makePendingDrop()
				end
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 30, 1)
				assert.is_not_nil(LootRolls._buttonValidityCache["30_1"])
				assert.is_nil(LootRolls._stagedRollValidity[91])

				-- Second START_LOOT_ROLL fires after the first drop is already absorbed.
				LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 92, 60)
				assert.is_not_nil(LootRolls._stagedRollValidity[92])

				-- Second LOOT_HISTORY_UPDATE_DROP absorbs the newly staged entry.
				LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 30, 2)
				assert.is_not_nil(LootRolls._buttonValidityCache["30_2"])
				assert.is_nil(LootRolls._stagedRollValidity[92])

				-- The two drops are independent: each has its own validity entry.
				assert.are_not.equal(LootRolls._dropStates["30_1"].rollID, LootRolls._dropStates["30_2"].rollID)
			end)

			it("BuildPayload returns independent buttonValidity per drop key", function()
				LootRolls._buttonValidityCache["40_1"] = {
					canNeed = true,
					canGreed = false,
					canTransmog = false,
					canPass = true,
					isCached = true,
				}
				LootRolls._buttonValidityCache["40_2"] = {
					canNeed = false,
					canGreed = true,
					canTransmog = false,
					canPass = true,
					isCached = true,
				}
				LootRolls._dropStates["40_1"] = { state = "pending" }
				LootRolls._dropStates["40_2"] = { state = "pending" }

				local payload1 = LootRolls:BuildPayload(40, 1, makePendingDrop(), "pending")
				local payload2 = LootRolls:BuildPayload(40, 2, makePendingDrop(), "pending")

				assert.is_true(payload1.buttonValidity.canNeed)
				assert.is_false(payload1.buttonValidity.canGreed)
				assert.is_false(payload2.buttonValidity.canNeed)
				assert.is_true(payload2.buttonValidity.canGreed)
			end)
		end)

		-- ── Classic ────────────────────────────────────────────────────────────

		describe("Classic: two rolls of the same item, independent validity snapshots", function()
			-- Classic item info per rollID (simulates different game state per roll).
			local classicItemInfoByRollID = {
				[101] = {
					itemLink = ITEM_LINK,
					canNeed = true,
					canGreed = false,
					canDisenchant = false,
					texture = 12345,
					name = "Sword",
					count = 1,
					quality = 4,
				},
				[102] = {
					itemLink = ITEM_LINK,
					canNeed = false,
					canGreed = true,
					canDisenchant = false,
					texture = 12345,
					name = "Sword",
					count = 1,
					quality = 4,
				},
			}

			before_each(function()
				ns.IsRetail = function()
					return false
				end
				LootRolls._lootRollsAdapter.GetClassicRollItemInfo = function(rollID)
					return classicItemInfoByRollID[rollID]
				end
				_G.GetTime = function()
					return 1000
				end
			end)

			it("each Classic START_LOOT_ROLL caches validity under its own dropKey", function()
				LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 101, 60)
				LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", 102, 60)

				-- Each Classic roll caches validity synchronously under rollID_rollID.
				assert.is_not_nil(LootRolls._buttonValidityCache["101_101"])
				assert.is_not_nil(LootRolls._buttonValidityCache["102_102"])

				-- Validity is independent: reflects game state at time of each event.
				assert.is_true(LootRolls._buttonValidityCache["101_101"].canNeed)
				assert.is_false(LootRolls._buttonValidityCache["101_101"].canGreed)
				assert.is_false(LootRolls._buttonValidityCache["102_102"].canNeed)
				assert.is_true(LootRolls._buttonValidityCache["102_102"].canGreed)
			end)

			it("Classic BuildClassicPayload returns independent buttonValidity per rollID", function()
				LootRolls._buttonValidityCache["111_111"] = {
					canNeed = true,
					canGreed = false,
					canTransmog = false,
					canPass = true,
					isCached = true,
				}
				LootRolls._buttonValidityCache["112_112"] = {
					canNeed = false,
					canGreed = true,
					canTransmog = false,
					canPass = true,
					isCached = true,
				}

				local fakeDropInfo = {
					itemHyperlink = ITEM_LINK,
					winner = nil,
					allPassed = false,
					isTied = false,
					startTime = 1000,
					duration = 60,
					rollInfos = {},
				}
				local fakeItemInfo = {
					itemLink = ITEM_LINK,
					canNeed = true,
					canGreed = false,
					canDisenchant = false,
					texture = 12345,
					name = "Sword",
					count = 1,
					quality = 4,
				}

				local payload1 = LootRolls:BuildClassicPayload(111, fakeDropInfo, "pending", fakeItemInfo)
				local payload2 = LootRolls:BuildClassicPayload(112, fakeDropInfo, "pending", fakeItemInfo)

				assert.is_true(payload1.buttonValidity.canNeed)
				assert.is_false(payload1.buttonValidity.canGreed)
				assert.is_false(payload2.buttonValidity.canNeed)
				assert.is_true(payload2.buttonValidity.canGreed)
			end)
		end)
	end)
end)
