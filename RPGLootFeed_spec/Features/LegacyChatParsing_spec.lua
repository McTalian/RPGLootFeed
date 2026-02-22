---@diagnostic disable: need-check-nil
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

-- ── Pure-Lua helper implementations ──────────────────────────────────────────
-- Inlined from AddonMethods.lua so parse tests validate the real extraction
-- logic without pulling in the full WoW-dependent AddonMethods chain.

local function createPatternSegments(localeString)
	local preStart, preEnd = string.find(localeString, "%%s")
	if preStart == nil then
		preStart, preEnd = string.find(localeString, "%%1$s")
	end
	local prePattern = string.sub(localeString, 1, preStart - 1)
	local midStart, midEnd = string.find(localeString, "%%d", preEnd + 1)
	if midStart == nil then
		midStart, midEnd = string.find(localeString, "%%2$d", preEnd + 1)
	end
	local midPattern = string.sub(localeString, preEnd + 1, midStart - 1)
	local postPattern = string.sub(localeString, midEnd + 1)
	if string.find(postPattern, "%%") then
		local postStart = string.find(postPattern, "%%")
		if postStart then
			postPattern = string.sub(postPattern, 1, postStart - 1)
		end
	end
	return { prePattern, midPattern, postPattern }
end

local function extractDynamics(localeString, segments)
	local prePattern, midPattern, postPattern = unpack(segments)
	local preMatchStart, preMatchEnd = string.find(localeString, prePattern, 1, true)
	if preMatchStart then
		local msgLoop = localeString:sub(preMatchEnd + 1)
		local midMatchStart, midMatchEnd = string.find(msgLoop, midPattern, 1, true)
		if midMatchStart then
			local postMatchStart = string.find(msgLoop, postPattern, midMatchEnd, true)
			if postMatchStart then
				local str = msgLoop:sub(1, midMatchStart - 1)
				local num
				if midMatchEnd == postMatchStart then
					num = msgLoop:sub(midMatchEnd + 1)
				else
					num = msgLoop:sub(midMatchEnd + 1, postMatchStart - 1)
				end
				return str, tonumber(num)
			end
		end
	end
	return nil, nil
end

-- ── Test suite ────────────────────────────────────────────────────────────────

describe("LegacyChatParsingImpl", function()
	---@type LegacyRepParsing, table
	local LegacyRepParsing, ns

	before_each(function()
		ns = {
			-- IsRetail is called as G_RLF:IsRetail() so receives ns as self.
			IsRetail = function()
				return false
			end,
			LogDebug = function() end,
			LogWarn = function() end,
			-- Pattern utilities injected as real implementations so parse
			-- tests exercise the actual extraction logic end-to-end.
			CreatePatternSegmentsForStringNumber = function(_, pattern)
				return createPatternSegments(pattern)
			end,
			ExtractDynamicsFromPattern = function(_, msg, segs)
				return extractDynamics(msg, segs)
			end,
			ClassicToRetail = {
				ConvertFactionInfoByIndex = function(self, i)
					return nil
				end,
			},
			db = {
				locale = {
					factionMap = {},
					accountWideFactionMap = {},
				},
			},
		}

		LegacyRepParsing =
			assert(loadfile("RPGLootFeed/Features/Reputation/LegacyChatParsingImpl.lua"))("TestAddon", ns)

		-- Default adapter – overridden per-test as needed.
		LegacyRepParsing._legacyAdapter = {
			GetLocale = function()
				return "enUS"
			end,
			RunNextFrame = function(fn)
				fn()
			end,
			GetFactionDataByIndex = function(i)
				return nil
			end,
			GetFactionInfoByIndex = function(i)
				return nil
			end,
			ConvertFactionInfoByIndex = function(i)
				return nil
			end,
			HasRetailFactionDataAPI = function()
				return false
			end,
			GetFactionStandingIncreasePatterns = function()
				return { "Your reputation with %s has increased by %d." }
			end,
			GetFactionStandingDecreasePatterns = function()
				return { "Your reputation with %s has decreased by %d." }
			end,
		}
	end)

	-- ── InitializeLegacyReputationChatParsing ─────────────────────────────────

	describe("InitializeLegacyReputationChatParsing", function()
		it("calls RunNextFrame to schedule initial faction map build", function()
			local runNextFrameSpy = spy.on(LegacyRepParsing._legacyAdapter, "RunNextFrame")
			LegacyRepParsing.InitializeLegacyReputationChatParsing()
			assert.spy(runNextFrameSpy).was.called(1)
		end)

		it("invokes buildFactionLocaleMap inside RunNextFrame", function()
			local buildSpy = spy.on(LegacyRepParsing, "buildFactionLocaleMap")
			LegacyRepParsing.InitializeLegacyReputationChatParsing()
			assert.spy(buildSpy).was.called(1)
		end)

		it("fetches increase and decrease patterns from the adapter", function()
			local increaseSpy = spy.on(LegacyRepParsing._legacyAdapter, "GetFactionStandingIncreasePatterns")
			local decreaseSpy = spy.on(LegacyRepParsing._legacyAdapter, "GetFactionStandingDecreasePatterns")
			LegacyRepParsing.InitializeLegacyReputationChatParsing()
			assert.spy(increaseSpy).was.called(1)
			assert.spy(decreaseSpy).was.called(1)
		end)
	end)

	-- ── buildFactionLocaleMap ─────────────────────────────────────────────────

	describe("buildFactionLocaleMap", function()
		it("returns early when there are no new factions and findName is nil", function()
			-- GetFactionInfoByIndex returns nil -> hasMoreFactions = false
			LegacyRepParsing._legacyAdapter.GetFactionInfoByIndex = function(i)
				return nil
			end
			local callCount = 0
			LegacyRepParsing._legacyAdapter.RunNextFrame = function(fn)
				callCount = callCount + 1
				fn()
			end

			LegacyRepParsing.buildFactionLocaleMap(nil, nil)

			assert.equals(0, callCount)
		end)

		it("populates factionMap via Classic path (no Retail API)", function()
			local factions = {
				{ name = "Stormwind", factionID = 72, isAccountWide = false },
				{ name = "Ironforge", factionID = 47, isAccountWide = false },
			}
			LegacyRepParsing._legacyAdapter.HasRetailFactionDataAPI = function()
				return false
			end
			LegacyRepParsing._legacyAdapter.GetFactionInfoByIndex = function(i)
				return factions[i] ~= nil
			end
			LegacyRepParsing._legacyAdapter.ConvertFactionInfoByIndex = function(i)
				return factions[i]
			end

			LegacyRepParsing.buildFactionLocaleMap(nil, nil)

			assert.equals(72, ns.db.locale.factionMap["Stormwind"])
			assert.equals(47, ns.db.locale.factionMap["Ironforge"])
		end)

		it("populates factionMap via Retail API path", function()
			local factions = {
				{ name = "Valdrakken Accord", factionID = 2507, isAccountWide = false },
			}
			LegacyRepParsing._legacyAdapter.HasRetailFactionDataAPI = function()
				return true
			end
			LegacyRepParsing._legacyAdapter.GetFactionDataByIndex = function(i)
				return factions[i]
			end

			LegacyRepParsing.buildFactionLocaleMap(nil, nil)

			assert.equals(2507, ns.db.locale.factionMap["Valdrakken Accord"])
		end)

		it("stores account-wide factions in accountWideFactionMap (isRetail=true)", function()
			ns.IsRetail = function()
				return true
			end
			local factions = {
				{ name = "Warband", factionID = 9999, isAccountWide = true },
			}
			LegacyRepParsing._legacyAdapter.HasRetailFactionDataAPI = function()
				return true
			end
			LegacyRepParsing._legacyAdapter.GetFactionInfoByIndex = function(i)
				return factions[i] ~= nil
			end
			LegacyRepParsing._legacyAdapter.GetFactionDataByIndex = function(i)
				return factions[i]
			end

			-- findName path uses IsRetail to route account-wide into accountWideFactionMap
			LegacyRepParsing.buildFactionLocaleMap("Warband", false)

			assert.equals(9999, ns.db.locale.accountWideFactionMap["Warband"])
			assert.is_nil(ns.db.locale.factionMap["Warband"])
		end)

		it("stops iterating once findName faction is located", function()
			local callCount = 0
			local factions = {
				{ name = "Faction A", factionID = 1, isAccountWide = false },
				{ name = "Faction B", factionID = 2, isAccountWide = false },
				{ name = "Faction C", factionID = 3, isAccountWide = false },
			}
			LegacyRepParsing._legacyAdapter.HasRetailFactionDataAPI = function()
				return false
			end
			LegacyRepParsing._legacyAdapter.GetFactionInfoByIndex = function(i)
				return factions[i] ~= nil
			end
			LegacyRepParsing._legacyAdapter.ConvertFactionInfoByIndex = function(i)
				callCount = callCount + 1
				return factions[i]
			end

			LegacyRepParsing.buildFactionLocaleMap("Faction A", false)

			-- Should stop after the first faction is found
			assert.equals(1, callCount)
			assert.equals(1, ns.db.locale.factionMap["Faction A"])
		end)
	end)

	-- ── ParseFactionChangeMessage ─────────────────────────────────────────────

	describe("ParseFactionChangeMessage", function()
		before_each(function()
			-- Initialise patterns so ParseFactionChangeMessage can extract values
			LegacyRepParsing.InitializeLegacyReputationChatParsing()
		end)

		it("returns faction and positive repChange for an increase message", function()
			local faction, repChange, isDelve, isAccountWide =
				LegacyRepParsing.ParseFactionChangeMessage("Your reputation with Stormwind has increased by 250.", nil)

			assert.equals("Stormwind", faction)
			assert.equals(250, repChange)
			assert.is_false(isDelve)
			assert.is_false(isAccountWide)
		end)

		it("returns faction and negative repChange for a decrease message", function()
			local faction, repChange, isDelve, isAccountWide =
				LegacyRepParsing.ParseFactionChangeMessage("Your reputation with Horde has decreased by 100.", nil)

			assert.equals("Horde", faction)
			assert.equals(-100, repChange)
			assert.is_false(isDelve)
			assert.is_false(isAccountWide)
		end)

		it("returns nils for an unrecognised message", function()
			local faction, repChange, isDelve, isAccountWide =
				LegacyRepParsing.ParseFactionChangeMessage("You bought a hat.", nil)

			assert.is_nil(faction)
			assert.is_nil(repChange)
			assert.is_false(isDelve)
			assert.is_false(isAccountWide)
		end)

		it("matches a Delves companion message when companionFactionName is provided", function()
			-- extractFactionAndRepForDelves: finds name in message then reads trailing digit
			local msg = "Brann Bronzebeard 500 reputation gained."

			local faction, repChange, isDelve, isAccountWide =
				LegacyRepParsing.ParseFactionChangeMessage(msg, "Brann Bronzebeard")

			assert.equals("Brann Bronzebeard", faction)
			assert.equals(500, repChange)
			assert.is_true(isDelve)
			assert.is_true(isAccountWide)
		end)

		it("returns nil when companion name does not appear in delves message", function()
			local faction, repChange, isDelve, isAccountWide =
				LegacyRepParsing.ParseFactionChangeMessage("Some random message 50.", "Brann Bronzebeard")

			assert.is_nil(faction)
			assert.is_nil(repChange)
			assert.is_false(isDelve)
			assert.is_false(isAccountWide)
		end)

		it("skips delves companion extraction when companionFactionName is nil", function()
			local faction, repChange =
				LegacyRepParsing.ParseFactionChangeMessage("Brann Bronzebeard 500 reputation gained.", nil)

			assert.is_nil(faction)
			assert.is_nil(repChange)
		end)
	end)

	-- ── GetLocaleFactionMapData ───────────────────────────────────────────────

	describe("GetLocaleFactionMapData", function()
		before_each(function()
			LegacyRepParsing.InitializeLegacyReputationChatParsing()
		end)

		it("returns ID from factionMap when faction is already cached", function()
			ns.db.locale.factionMap["Stormwind"] = 72

			local result = LegacyRepParsing.GetLocaleFactionMapData("Stormwind", false)

			assert.equals(72, result)
		end)

		it("returns ID from accountWideFactionMap for account-wide factions", function()
			ns.db.locale.accountWideFactionMap["Alliance"] = 469

			local result = LegacyRepParsing.GetLocaleFactionMapData("Alliance", true)

			assert.equals(469, result)
		end)

		it("attempts buildFactionLocaleMap and returns ID when faction found on retry", function()
			-- Faction not cached initially; buildFactionLocaleMap will populate via Classic path.
			local factions = { { name = "Ironforge", factionID = 47, isAccountWide = false } }
			LegacyRepParsing._legacyAdapter.HasRetailFactionDataAPI = function()
				return false
			end
			LegacyRepParsing._legacyAdapter.GetFactionInfoByIndex = function(i)
				return factions[i] ~= nil
			end
			LegacyRepParsing._legacyAdapter.ConvertFactionInfoByIndex = function(i)
				return factions[i]
			end

			local result = LegacyRepParsing.GetLocaleFactionMapData("Ironforge", false)

			assert.equals(47, result)
		end)

		it("returns nil when faction is unknown even after buildFactionLocaleMap", function()
			-- All faction lookups return nil → faction stays unknown
			LegacyRepParsing._legacyAdapter.GetFactionInfoByIndex = function(i)
				return nil
			end
			LegacyRepParsing._legacyAdapter.ConvertFactionInfoByIndex = function(i)
				return nil
			end

			local result = LegacyRepParsing.GetLocaleFactionMapData("CryptoKitties", false)

			assert.is_nil(result)
		end)
	end)
end)
