-- Unit tests for WoWAPIAdapters.LootRolls — Classic-specific adapter methods.
-- Covers GetClassicRollItemInfo, ClassicRollOnLoot, HasStartLootRollEvent,
-- DecodeClassicRollType, plus the existing Retail-gated methods for regression.
-- Run subset: busted RPGLootFeed_spec/utils/WoWAPIAdapters_spec.lua --pattern 'Classic'

local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function loadAdapters(ns)
	-- WoWAPIAdapters requires LibStub via G_RLF (ns).  The nsMocks setup
	-- injects the LibStub stub into _G when UtilsAddonMethods load level is
	-- requested.
	require("RPGLootFeed_spec._mocks.Libs.LibStub")
	assert(loadfile("RPGLootFeed/utils/WoWAPIAdapters.lua"))("TestAddon", ns)
	return ns.WoWAPI
end

-- ── WoWAPI.LootRolls — Classic adapter methods ───────────────────────────────

describe("WoWAPI.LootRolls Classic methods", function()
	local ns
	local WoWAPI
	local stubIsRetail
	local stubIsClassic

	before_each(function()
		-- Default: simulate Classic (non-Retail) client
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
		stubIsRetail = nsMocks.IsRetail.returns(false)
		stubIsClassic = nsMocks.IsClassic.returns(true)

		-- Classic loot roll globals
		_G.GetLootRollItemInfo = function(_rollID)
			-- texture, name, count, quality, canNeed, canGreed, canDisenchant
			return "Interface\\Icons\\INV_Sword", "Sword of Testing", 1, 4, true, true, false
		end
		_G.GetLootRollItemLink = function(_rollID)
			return "|cff0070dd|Hitem:12345|h[Sword of Testing]|h|r"
		end
		_G.RollOnLoot = function(_rollID, _rollType) end

		WoWAPI = loadAdapters(ns)
	end)

	after_each(function()
		stubIsRetail:revert()
		stubIsClassic:revert()
		_G.GetLootRollItemInfo = nil
		_G.GetLootRollItemLink = nil
		_G.RollOnLoot = nil
	end)

	-- ── GetClassicRollItemInfo ─────────────────────────────────────────────

	describe("GetClassicRollItemInfo on Classic client", function()
		it("returns item info table on Classic", function()
			local info = WoWAPI.LootRolls.GetClassicRollItemInfo(7)

			assert.is_not_nil(info)
			assert.equals("Interface\\Icons\\INV_Sword", info.texture)
			assert.equals("Sword of Testing", info.name)
			assert.equals(1, info.count)
			assert.equals(4, info.quality)
		end)

		it("returns canNeed=true when player can need the item", function()
			local info = WoWAPI.LootRolls.GetClassicRollItemInfo(7)
			assert.is_true(info.canNeed)
		end)

		it("returns canGreed=true when player can greed the item", function()
			local info = WoWAPI.LootRolls.GetClassicRollItemInfo(7)
			assert.is_true(info.canGreed)
		end)

		it("returns canDisenchant=false when item cannot be disenchanted", function()
			local info = WoWAPI.LootRolls.GetClassicRollItemInfo(7)
			assert.is_false(info.canDisenchant)
		end)

		it("returns the itemLink from GetLootRollItemLink", function()
			local info = WoWAPI.LootRolls.GetClassicRollItemInfo(7)
			assert.equals("|cff0070dd|Hitem:12345|h[Sword of Testing]|h|r", info.itemLink)
		end)

		it("returns itemLink=nil when GetLootRollItemLink global is absent", function()
			_G.GetLootRollItemLink = nil
			-- Re-use the already-loaded WoWAPI from before_each (IsRetail=false).
			-- The adapter reads _G.GetLootRollItemLink at call time, so clearing
			-- it above is sufficient — no reload needed.
			local info = WoWAPI.LootRolls.GetClassicRollItemInfo(7)
			assert.is_not_nil(info)
			assert.is_nil(info.itemLink)
		end)

		it("returns canDisenchant=true when item can be disenchanted", function()
			_G.GetLootRollItemInfo = function(_rollID)
				return "Interface\\Icons\\INV_Wand", "Wand", 1, 3, false, true, true
			end

			local info = WoWAPI.LootRolls.GetClassicRollItemInfo(7)
			assert.is_true(info.canDisenchant)
		end)
	end)

	describe("GetClassicRollItemInfo on Retail client", function()
		it("returns nil on Retail", function()
			stubIsRetail:revert()
			stubIsRetail = nsMocks.IsRetail.returns(true)
			-- Reload so the guard sees IsRetail=true
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
			WoWAPI = loadAdapters(ns)

			local info = WoWAPI.LootRolls.GetClassicRollItemInfo(7)
			assert.is_nil(info)
		end)
	end)

	-- ── ClassicRollOnLoot ──────────────────────────────────────────────────

	describe("ClassicRollOnLoot on Classic client", function()
		it("calls RollOnLoot with the given rollID and rollType, returns true", function()
			local capturedID, capturedType
			_G.RollOnLoot = function(id, rt)
				capturedID = id
				capturedType = rt
			end

			local ok = WoWAPI.LootRolls.ClassicRollOnLoot(42, 1)

			assert.is_true(ok)
			assert.equals(42, capturedID)
			assert.equals(1, capturedType)
		end)

		it("returns false and error when rollType is not a number", function()
			local ok, err = WoWAPI.LootRolls.ClassicRollOnLoot(1, "NEED")

			assert.is_false(ok)
			assert.truthy(string.find(err, "invalid rollType", 1, true))
		end)

		it("returns false and error when RollOnLoot global is absent", function()
			_G.RollOnLoot = nil

			local ok, err = WoWAPI.LootRolls.ClassicRollOnLoot(1, 1)

			assert.is_false(ok)
			assert.truthy(string.find(err, "not available", 1, true))
		end)
	end)

	describe("ClassicRollOnLoot on Retail client", function()
		it("returns false and error on Retail", function()
			stubIsRetail:revert()
			stubIsRetail = nsMocks.IsRetail.returns(true)
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
			WoWAPI = loadAdapters(ns)

			local ok, err = WoWAPI.LootRolls.ClassicRollOnLoot(1, 1)

			assert.is_false(ok)
			assert.truthy(string.find(err, "Retail", 1, true))
		end)
	end)

	-- ── HasStartLootRollEvent ──────────────────────────────────────────────

	describe("HasStartLootRollEvent on Classic client", function()
		it("returns true on Classic", function()
			assert.is_true(WoWAPI.LootRolls.HasStartLootRollEvent())
		end)
	end)

	describe("HasStartLootRollEvent on Retail client", function()
		it("returns false on Retail", function()
			stubIsRetail:revert()
			stubIsRetail = nsMocks.IsRetail.returns(true)
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
			WoWAPI = loadAdapters(ns)

			assert.is_false(WoWAPI.LootRolls.HasStartLootRollEvent())
		end)
	end)

	-- ── DecodeClassicRollType ──────────────────────────────────────────────

	describe("DecodeClassicRollType on Classic client", function()
		it("decodes 0 to PASS", function()
			assert.equals("PASS", WoWAPI.LootRolls.DecodeClassicRollType(0))
		end)

		it("decodes 1 to NEED", function()
			assert.equals("NEED", WoWAPI.LootRolls.DecodeClassicRollType(1))
		end)

		it("decodes 2 to GREED", function()
			assert.equals("GREED", WoWAPI.LootRolls.DecodeClassicRollType(2))
		end)

		it("decodes 3 to DISENCHANT on Classic (not TRANSMOG)", function()
			assert.equals("DISENCHANT", WoWAPI.LootRolls.DecodeClassicRollType(3))
		end)

		it("returns nil and error for unknown numeric type", function()
			local label, err = WoWAPI.LootRolls.DecodeClassicRollType(99)
			assert.is_nil(label)
			assert.truthy(string.find(err, "unknown roll type", 1, true))
		end)

		it("returns nil and error when rollType is not a number", function()
			local label, err = WoWAPI.LootRolls.DecodeClassicRollType("GREED")
			assert.is_nil(label)
			assert.truthy(string.find(err, "invalid rollType", 1, true))
		end)
	end)

	describe("DecodeClassicRollType on Retail client", function()
		it("decodes 3 to TRANSMOG on Retail (not DISENCHANT)", function()
			stubIsRetail:revert()
			stubIsRetail = nsMocks.IsRetail.returns(true)
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
			WoWAPI = loadAdapters(ns)

			assert.equals("TRANSMOG", WoWAPI.LootRolls.DecodeClassicRollType(3))
		end)

		it("still decodes 0 PASS, 1 NEED, 2 GREED on Retail", function()
			stubIsRetail:revert()
			stubIsRetail = nsMocks.IsRetail.returns(true)
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
			WoWAPI = loadAdapters(ns)

			assert.equals("PASS", WoWAPI.LootRolls.DecodeClassicRollType(0))
			assert.equals("NEED", WoWAPI.LootRolls.DecodeClassicRollType(1))
			assert.equals("GREED", WoWAPI.LootRolls.DecodeClassicRollType(2))
		end)
	end)
end)

-- ── WoWAPI.LootRolls — existing Retail methods (regression) ─────────────────

describe("WoWAPI.LootRolls Retail methods", function()
	local ns
	local WoWAPI
	local stubIsRetail

	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
		stubIsRetail = nsMocks.IsRetail.returns(true)

		_G.C_LootHistory = {}
		_G.GetLootRollItemInfo = function(_rollID)
			return "|cff0070dd|Hitem:12345|h[Test Item]|h|r", 1, true, true, false, true
		end
		_G.RollOnLoot = function(_rollID, _rollType) end
		_G.RAID_CLASS_COLORS = {}

		require("RPGLootFeed_spec._mocks.Libs.LibStub")
		assert(loadfile("RPGLootFeed/utils/WoWAPIAdapters.lua"))("TestAddon", ns)
		WoWAPI = ns.WoWAPI
	end)

	after_each(function()
		stubIsRetail:revert()
		_G.C_LootHistory = nil
		_G.GetLootRollItemInfo = nil
		_G.RollOnLoot = nil
	end)

	describe("HasLootHistory", function()
		it("returns true when C_LootHistory is present", function()
			assert.is_true(WoWAPI.LootRolls.HasLootHistory())
		end)

		it("returns false when C_LootHistory is absent", function()
			_G.C_LootHistory = nil
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
			require("RPGLootFeed_spec._mocks.Libs.LibStub")
			assert(loadfile("RPGLootFeed/utils/WoWAPIAdapters.lua"))("TestAddon", ns)

			assert.is_false(ns.WoWAPI.LootRolls.HasLootHistory())
		end)
	end)

	describe("GetRollButtonValidity", function()
		it("returns correct flags when all actions are available", function()
			-- Retail GetLootRollItemInfo signature:
			-- texture, name, count, quality, bindOnPickUp,
			-- canNeed, canGreed, canDisenchant,
			-- reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired,
			-- canTransmog
			_G.GetLootRollItemInfo = function(_rollID)
				return "texture", "Sword", 1, 4, false, true, true, false, 0, 0, 0, 0, true
			end
			local result = WoWAPI.LootRolls.GetRollButtonValidity(1)
			assert.is_true(result.canNeed)
			assert.is_true(result.canGreed)
			assert.is_true(result.canTransmog)
			assert.is_true(result.canPass)
		end)

		it("returns nil when C_LootHistory is absent (Classic — no Retail validity needed)", function()
			_G.C_LootHistory = nil
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
			require("RPGLootFeed_spec._mocks.Libs.LibStub")
			assert(loadfile("RPGLootFeed/utils/WoWAPIAdapters.lua"))("TestAddon", ns)

			local result = ns.WoWAPI.LootRolls.GetRollButtonValidity(1)
			assert.is_nil(result)
		end)
	end)

	describe("SubmitLootRoll", function()
		it("calls RollOnLoot and returns true", function()
			local capturedID, capturedType
			_G.RollOnLoot = function(id, rt)
				capturedID = id
				capturedType = rt
			end
			local ok = WoWAPI.LootRolls.SubmitLootRoll(42, 1)
			assert.is_true(ok)
			assert.equals(42, capturedID)
			assert.equals(1, capturedType)
		end)

		it("returns false and error when rollType is not a number", function()
			local ok, err = WoWAPI.LootRolls.SubmitLootRoll(1, "NEED")
			assert.is_false(ok)
			assert.truthy(string.find(err, "invalid rollType", 1, true))
		end)

		it("returns false on Classic (no C_LootHistory)", function()
			_G.C_LootHistory = nil
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsAddonMethods)
			require("RPGLootFeed_spec._mocks.Libs.LibStub")
			assert(loadfile("RPGLootFeed/utils/WoWAPIAdapters.lua"))("TestAddon", ns)

			local ok, err = ns.WoWAPI.LootRolls.SubmitLootRoll(1, 1)
			assert.is_false(ok)
			assert.truthy(string.find(err, "not available", 1, true))
		end)
	end)

	describe("DecodeRollType", function()
		it("decodes NEED to 1", function()
			assert.equals(1, WoWAPI.LootRolls.DecodeRollType("NEED"))
		end)
		it("decodes GREED to 2", function()
			assert.equals(2, WoWAPI.LootRolls.DecodeRollType("GREED"))
		end)
		it("decodes PASS to 0", function()
			assert.equals(0, WoWAPI.LootRolls.DecodeRollType("PASS"))
		end)
		it("decodes TRANSMOG to 4 (TransmogButton id in GroupLootFrame.xml)", function()
			assert.equals(4, WoWAPI.LootRolls.DecodeRollType("TRANSMOG"))
		end)
		it("returns nil and error for unknown roll type", function()
			local v, err = WoWAPI.LootRolls.DecodeRollType("DISENCHANT")
			assert.is_nil(v)
			assert.truthy(string.find(err, "unknown roll type", 1, true))
		end)
	end)
end)
