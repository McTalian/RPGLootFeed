---@diagnostic disable: need-check-nil
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

describe("TooltipBuilders module", function()
	local ns, TooltipBuilders

	-- Captured AddLine calls: { {text, r, g, b, wrap?}, ... }
	local addLineCalls

	before_each(function()
		addLineCalls = {}

		-- Minimal GameTooltip mock — records AddLine calls for assertion.
		_G.GameTooltip = {
			AddLine = function(_, text, r, g, b, wrap)
				table.insert(addLineCalls, { text = text, r = r, g = g, b = b, wrap = wrap })
			end,
			Show = function() end,
		}

		-- Null out RAID_CLASS_COLORS so name-coloring falls back to plain strings
		-- by default. Tests that exercise class-coloring set it explicitly.
		_G.RAID_CLASS_COLORS = nil

		ns = {
			L = {
				["All Passed"] = "All Passed",
				["LootRolls_WaitingOn"] = "Waiting on:",
			},
		}

		TooltipBuilders = assert(loadfile("RPGLootFeed/LootDisplay/TooltipBuilders.lua"))("TestAddon", ns)
		assert.is_not_nil(TooltipBuilders)
	end)

	-- ── Helpers ───────────────────────────────────────────────────────────────

	--- Returns the text of every AddLine call that contains the given substring.
	local function linesContaining(substr)
		local found = {}
		for _, call in ipairs(addLineCalls) do
			if type(call.text) == "string" and call.text:find(substr, 1, true) then
				table.insert(found, call.text)
			end
		end
		return found
	end

	local function anyLineContains(substr)
		return #linesContaining(substr) > 0
	end

	local function makeRoll(playerName, playerClass, roll, state, isSelf, isWinner)
		return {
			playerName = playerName,
			playerClass = playerClass,
			roll = roll,
			state = state,
			isSelf = isSelf or false,
			isWinner = isWinner or false,
		}
	end

	-- ── allPassed state ───────────────────────────────────────────────────────

	describe("allPassed state", function()
		local dropInfo

		before_each(function()
			dropInfo = { allPassed = true, winner = nil, rollInfos = {} }
		end)

		it("adds a blank separator line", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "allPassed")
			assert.is_true(anyLineContains(" "))
		end)

		it("adds the All Passed line", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "allPassed")
			assert.is_true(anyLineContains("All Passed"))
		end)

		it("includes encounter name when provided", function()
			TooltipBuilders:LootRolls(dropInfo, "Ragnaros", "allPassed")
			assert.is_true(anyLineContains("Ragnaros"))
		end)

		it("omits encounter name when nil", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "allPassed")
			assert.is_false(anyLineContains("Ragnaros"))
		end)

		it("omits encounter name when empty string", function()
			TooltipBuilders:LootRolls(dropInfo, "", "allPassed")
			-- only the blank separator and "All Passed" should be present
			assert.are.equal(2, #addLineCalls)
		end)

		it("calls GameTooltip:Show", function()
			local showSpy = spy.on(_G.GameTooltip, "Show")
			TooltipBuilders:LootRolls(dropInfo, nil, "allPassed")
			assert.spy(showSpy).was.called(1)
		end)
	end)

	-- ── resolved state ────────────────────────────────────────────────────────

	describe("resolved state", function()
		local dropInfo

		before_each(function()
			dropInfo = {
				allPassed = false,
				winner = { playerName = "Arthas", playerClass = "DEATHKNIGHT", roll = 87, state = 0 },
				rollInfos = {
					makeRoll("Arthas", "DEATHKNIGHT", 87, 0, false, true),
					makeRoll("Thrall", "SHAMAN", 42, 3, false, false),
				},
			}
		end)

		it("adds a line containing the winner's name", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			assert.is_true(anyLineContains("Arthas"))
		end)

		it("adds a line containing a non-winner's name", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			assert.is_true(anyLineContains("Thrall"))
		end)

		it("includes the roll numbers when present", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			assert.is_true(anyLineContains("87"))
			assert.is_true(anyLineContains("42"))
		end)

		it("includes encounter name when provided", function()
			TooltipBuilders:LootRolls(dropInfo, "Icecrown Citadel", "resolved")
			assert.is_true(anyLineContains("Icecrown Citadel"))
		end)

		it("skips NoRoll entries for non-self players", function()
			dropInfo.rollInfos = {
				makeRoll("Arthas", "DEATHKNIGHT", 87, 0, false, true),
				makeRoll("Ghost", "MAGE", nil, 4, false, false), -- NoRoll, not self
			}
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			assert.is_false(anyLineContains("Ghost"))
		end)

		it("includes NoRoll entry for self even when no roll value", function()
			dropInfo.rollInfos = {
				makeRoll("Arthas", "DEATHKNIGHT", 87, 0, false, true),
				makeRoll("Me", "WARRIOR", nil, 4, true, false), -- NoRoll, isSelf
			}
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			assert.is_true(anyLineContains("Me"))
		end)

		it("skips a roll that lost to win protection (higher roll than winner's)", function()
			-- Thrall rolled 99 > winner's 87 but lost due to win protection
			dropInfo.rollInfos = {
				makeRoll("Arthas", "DEATHKNIGHT", 87, 0, false, true),
				makeRoll("Thrall", "SHAMAN", 99, 3, false, false),
			}
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			assert.is_false(anyLineContains("99"))
		end)

		it("uses class color when RAID_CLASS_COLORS is available", function()
			_G.RAID_CLASS_COLORS = {
				DEATHKNIGHT = {
					WrapTextInColorCode = function(_, name)
						return "|cffC41E3A" .. name .. "|r"
					end,
				},
				SHAMAN = {
					WrapTextInColorCode = function(_, name)
						return "|cff0070DE" .. name .. "|r"
					end,
				},
			}
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			assert.is_true(anyLineContains("|cffC41E3A"))
		end)

		it("falls back to plain name when RAID_CLASS_COLORS is nil", function()
			_G.RAID_CLASS_COLORS = nil
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			-- Plain name present, no color escape
			assert.is_true(anyLineContains("Arthas"))
		end)

		it("does not add a Waiting on footer", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			assert.is_false(anyLineContains("Waiting on:"))
		end)

		it("calls GameTooltip:Show", function()
			local showSpy = spy.on(_G.GameTooltip, "Show")
			TooltipBuilders:LootRolls(dropInfo, nil, "resolved")
			assert.spy(showSpy).was.called(1)
		end)
	end)

	-- ── pending state ─────────────────────────────────────────────────────────

	describe("pending state", function()
		local dropInfo

		before_each(function()
			dropInfo = {
				allPassed = false,
				winner = nil,
				rollInfos = {
					makeRoll("Thrall", "SHAMAN", 42, 3, false, false),
					makeRoll("Jaina", "MAGE", nil, 4, false, false), -- still deciding
				},
			}
		end)

		it("shows rolled entries", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "pending")
			assert.is_true(anyLineContains("Thrall"))
		end)

		it("adds a Waiting on footer with names of undecided players", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "pending")
			assert.is_true(anyLineContains("Waiting on:"))
			assert.is_true(anyLineContains("Jaina"))
		end)

		it("does not add Waiting on footer when everyone has rolled", function()
			dropInfo.rollInfos = {
				makeRoll("Thrall", "SHAMAN", 42, 3, false, false),
				makeRoll("Arthas", "DEATHKNIGHT", 87, 0, false, false),
			}
			TooltipBuilders:LootRolls(dropInfo, nil, "pending")
			assert.is_false(anyLineContains("Waiting on:"))
		end)

		it("adds blank separator before Waiting on footer", function()
			TooltipBuilders:LootRolls(dropInfo, nil, "pending")
			-- Find the index of "Waiting on:" and check the line before it is blank
			local waitingIdx = nil
			for i, call in ipairs(addLineCalls) do
				if type(call.text) == "string" and call.text:find("Waiting on:", 1, true) then
					waitingIdx = i
					break
				end
			end
			assert.is_not_nil(waitingIdx)
			assert.is_true(waitingIdx > 1)
			assert.are.equal(" ", addLineCalls[waitingIdx - 1].text)
		end)

		it("calls GameTooltip:Show", function()
			local showSpy = spy.on(_G.GameTooltip, "Show")
			TooltipBuilders:LootRolls(dropInfo, nil, "pending")
			assert.spy(showSpy).was.called(1)
		end)
	end)

	-- ── state derivation (no state arg) ──────────────────────────────────────

	describe("state derivation when state arg is nil", function()
		it("derives allPassed from dropInfo.allPassed", function()
			local dropInfo = { allPassed = true, winner = nil, rollInfos = {} }
			TooltipBuilders:LootRolls(dropInfo, nil, nil)
			assert.is_true(anyLineContains("All Passed"))
		end)

		it("derives resolved from dropInfo.winner", function()
			local dropInfo = {
				allPassed = false,
				winner = { playerName = "Arthas", playerClass = "DEATHKNIGHT", roll = 87, state = 0 },
				rollInfos = { makeRoll("Arthas", "DEATHKNIGHT", 87, 0, false, true) },
			}
			TooltipBuilders:LootRolls(dropInfo, nil, nil)
			assert.is_true(anyLineContains("Arthas"))
			assert.is_false(anyLineContains("Waiting on:"))
		end)

		it("derives pending when no winner and not allPassed", function()
			local dropInfo = {
				allPassed = false,
				winner = nil,
				rollInfos = {
					makeRoll("Jaina", "MAGE", nil, 4, false, false),
				},
			}
			TooltipBuilders:LootRolls(dropInfo, nil, nil)
			assert.is_true(anyLineContains("Waiting on:"))
		end)
	end)

	-- ── off-spec suffix ───────────────────────────────────────────────────────

	describe("off-spec suffix", function()
		it("appends (OS) for NeedOffSpec rolls (state 1)", function()
			local dropInfo = {
				allPassed = false,
				winner = nil,
				rollInfos = { makeRoll("Thrall", "SHAMAN", 55, 1, false, false) },
			}
			TooltipBuilders:LootRolls(dropInfo, nil, "pending")
			assert.is_true(anyLineContains("(OS)"))
		end)

		it("does not append (OS) for NeedMainSpec rolls (state 0)", function()
			local dropInfo = {
				allPassed = false,
				winner = nil,
				rollInfos = { makeRoll("Arthas", "DEATHKNIGHT", 87, 0, false, false) },
			}
			TooltipBuilders:LootRolls(dropInfo, nil, "pending")
			assert.is_false(anyLineContains("(OS)"))
		end)
	end)
end)
