---@diagnostic disable: need-check-nil
require("RPGLootFeed_spec._mocks.LuaCompat")
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local stub = busted.stub

describe("PartyLoot Module", function()
	local _ = match._
	---@type RLF_PartyLoot, table
	local PartyLoot, ns, sendMessageSpy

	before_each(function()
		sendMessageSpy = spy.new(function() end)

		-- Build minimal ns from scratch – no nsMocks framework needed.
		-- Only fields actually referenced by PartyLoot.lua and LootElementBase.lua
		-- are included.  G_RLF.db is present because LootElementBase:new() reads
		-- db.global.animations at construction time and feature code reads partyLoot
		-- config at runtime.
		ns = {
			-- Captured as locals by PartyLoot.lua at load time.
			ItemQualEnum = { Epic = 4 },
			FeatureModule = { PartyLoot = "PartyLoot" },
			Expansion = { BFA = 8 },
			-- Log closure wrappers call these as G_RLF:Method(...) so self is ns.
			LogDebug = spy.new(function() end),
			LogInfo = spy.new(function() end),
			LogWarn = spy.new(function() end),
			LogError = spy.new(function() end),
			IsRetail = function()
				return false
			end,
			SendMessage = sendMessageSpy,
			-- ItemInfo stub: default returns nil (item not in cache).
			-- Tests that exercise loot paths override ns.ItemInfo.new via stub().
			ItemInfo = {
				new = function()
					return nil
				end,
			},
			-- Runtime lookup by LootElementBase:new() and lifecycle code.
			db = {
				global = {
					animations = { exit = { fadeOutDelay = 3 } },
					partyLoot = {
						enabled = true,
						enableIcon = true,
						hideServerNames = true,
						onlyEpicAndAboveInRaid = false,
						onlyEpicAndAboveInInstance = false,
						itemQualityFilter = {},
						ignoreItemIds = {},
					},
					misc = {
						hideAllIcons = false,
						showOneQuantity = false,
					},
				},
			},
		}

		-- LibStub must be available before loadfile: PartyLoot.lua calls
		-- LibStub("C_Everywhere") at module root to capture the C library into the
		-- PartyLootAdapter closure.  The adapter's GetItemInfo is replaced after
		-- loadfile so the actual C_Everywhere mock content doesn't matter.
		require("RPGLootFeed_spec._mocks.Libs.LibStub")

		-- Load real LootElementBase so elements are fully constructed.
		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
		assert.is_not_nil(ns.LootElementBase)

		-- FeatureBase stub – independent of AceAddon plumbing.
		-- PartyLoot does not use AceBucket, so no RegisterBucketEvent needed.
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
					UnregisterEvent = function() end,
				}
			end,
		}

		-- Load PartyLoot – FeatureBase, LootElementBase, ItemInfo, Expansion,
		-- and ItemQualEnum are all captured as locals at load time.
		PartyLoot = assert(loadfile("RPGLootFeed/Features/PartyLoot/PartyLoot.lua"))("TestAddon", ns)

		-- Inject a fresh mock adapter per-test so WoW API calls are controlled
		-- without patching _G directly.  Tests override individual methods as needed.
		PartyLoot._partyLootAdapter = {
			UnitName = function(unit)
				if unit == "player" then
					return "TestPlayer", nil
				elseif unit == "party1" then
					return "PartyMember", nil
				end
				return nil, nil
			end,
			UnitClass = function(unit)
				return "Warrior", "WARRIOR"
			end,
			IssecretValue = function()
				return false
			end,
			GetNumGroupMembers = function()
				return 2
			end,
			IsInRaid = function()
				return false
			end,
			IsInInstance = function()
				return false
			end,
			GetExpansionLevel = function()
				return 10 -- >= BFA (8)
			end,
			GetPlayerGuid = function()
				return "Player-GUID-1234"
			end,
			GetClassColor = function(className)
				return { r = 0.78, g = 0.61, b = 0.43, a = 1 }
			end,
			GetRaidClassColor = function(className)
				return nil
			end,
			GetItemInfo = function(itemLink)
				return "Finkle's Lava Dredger",
					itemLink,
					4,
					60,
					55,
					"Weapon",
					"Mace",
					1,
					"INVTYPE_2HWEAPON",
					123456,
					10000
			end,
		}
	end)

	-- ── Lifecycle ──────────────────────────────────────────────────────────────

	it("OnInitialize creates empty pending tables and nameUnitMap", function()
		PartyLoot:OnInitialize()
		assert.is_not_nil(PartyLoot.pendingItemRequests)
		assert.is_not_nil(PartyLoot.pendingPartyRequests)
		assert.is_not_nil(PartyLoot.nameUnitMap)
	end)

	it("OnEnable registers expected events", function()
		spy.on(PartyLoot, "RegisterEvent")
		PartyLoot:OnEnable()
		assert.spy(PartyLoot.RegisterEvent).was.called_with(_, "CHAT_MSG_LOOT")
		assert.spy(PartyLoot.RegisterEvent).was.called_with(_, "GET_ITEM_INFO_RECEIVED")
		assert.spy(PartyLoot.RegisterEvent).was.called_with(_, "GROUP_ROSTER_UPDATE")
	end)

	it("OnDisable unregisters expected events", function()
		spy.on(PartyLoot, "UnregisterEvent")
		PartyLoot:OnDisable()
		assert.spy(PartyLoot.UnregisterEvent).was.called_with(_, "CHAT_MSG_LOOT")
		assert.spy(PartyLoot.UnregisterEvent).was.called_with(_, "GET_ITEM_INFO_RECEIVED")
		assert.spy(PartyLoot.UnregisterEvent).was.called_with(_, "GROUP_ROSTER_UPDATE")
	end)

	it("OnInitialize enables when db flag is true", function()
		ns.db.global.partyLoot.enabled = true
		spy.on(PartyLoot, "Enable")
		spy.on(PartyLoot, "Disable")
		PartyLoot:OnInitialize()
		assert.spy(PartyLoot.Enable).was.called(1)
		assert.spy(PartyLoot.Disable).was_not.called()
	end)

	it("OnInitialize disables when db flag is false", function()
		ns.db.global.partyLoot.enabled = false
		spy.on(PartyLoot, "Enable")
		spy.on(PartyLoot, "Disable")
		PartyLoot:OnInitialize()
		assert.spy(PartyLoot.Disable).was.called(1)
		assert.spy(PartyLoot.Enable).was_not.called()
	end)

	-- ── SetNameUnitMap ─────────────────────────────────────────────────────────

	describe("SetNameUnitMap", function()
		it("builds nameUnitMap for party (non-raid)", function()
			PartyLoot._partyLootAdapter.IsInRaid = function()
				return false
			end
			PartyLoot._partyLootAdapter.GetNumGroupMembers = function()
				return 2
			end
			PartyLoot._partyLootAdapter.UnitName = function(unit)
				if unit == "player" then
					return "TestPlayer", nil
				end
				if unit == "party1" then
					return "PartyMember", nil
				end
				return nil, nil
			end
			PartyLoot:OnInitialize()
			PartyLoot:SetNameUnitMap()
			assert.equals("player", PartyLoot.nameUnitMap["TestPlayer"])
			assert.equals("party1", PartyLoot.nameUnitMap["PartyMember"])
		end)

		it("builds nameUnitMap for raid", function()
			PartyLoot._partyLootAdapter.IsInRaid = function()
				return true
			end
			PartyLoot._partyLootAdapter.GetNumGroupMembers = function()
				return 2
			end
			PartyLoot._partyLootAdapter.UnitName = function(unit)
				if unit == "raid1" then
					return "Raider1", nil
				end
				if unit == "raid2" then
					return "Raider2", nil
				end
				return nil, nil
			end
			PartyLoot:OnInitialize()
			PartyLoot:SetNameUnitMap()
			assert.equals("raid1", PartyLoot.nameUnitMap["Raider1"])
			assert.equals("raid2", PartyLoot.nameUnitMap["Raider2"])
		end)
	end)

	-- ── SetPartyLootFilters ────────────────────────────────────────────────────

	describe("SetPartyLootFilters", function()
		local itemInfoPoor

		before_each(function()
			itemInfoPoor = {
				itemId = 11111,
				itemName = "Cheap Sword",
				itemQuality = 1, -- below Epic (4)
				itemTexture = 1,
				itemLink = "|cFFFFFFFF|Hitem:11111|h[Cheap Sword]|h|r",
				keystoneInfo = nil,
				GetEquipmentTypeText = function()
					return nil
				end,
			}
			PartyLoot:OnInitialize()
		end)

		it("skips poor quality loot when in raid with epic filter", function()
			PartyLoot._partyLootAdapter.IsInRaid = function()
				return true
			end
			ns.db.global.partyLoot.onlyEpicAndAboveInRaid = true
			PartyLoot:SetPartyLootFilters()
			local elementNew = spy.on(PartyLoot.Element, "new")
			PartyLoot:OnPartyReadyToShow(itemInfoPoor, 1, "party1")
			assert.spy(elementNew).was_not.called()
		end)

		it("skips poor quality loot when in instance with epic filter", function()
			PartyLoot._partyLootAdapter.IsInRaid = function()
				return false
			end
			PartyLoot._partyLootAdapter.IsInInstance = function()
				return true
			end
			ns.db.global.partyLoot.onlyEpicAndAboveInInstance = true
			PartyLoot:SetPartyLootFilters()
			local elementNew = spy.on(PartyLoot.Element, "new")
			PartyLoot:OnPartyReadyToShow(itemInfoPoor, 1, "party1")
			assert.spy(elementNew).was_not.called()
		end)

		it("allows all quality when neither epic filter is active", function()
			PartyLoot._partyLootAdapter.IsInRaid = function()
				return false
			end
			PartyLoot._partyLootAdapter.IsInInstance = function()
				return false
			end
			ns.db.global.partyLoot.onlyEpicAndAboveInRaid = false
			ns.db.global.partyLoot.onlyEpicAndAboveInInstance = false
			ns.db.global.partyLoot.itemQualityFilter = { [1] = true }
			PartyLoot:SetPartyLootFilters()
			local shown = false
			stub(PartyLoot.Element, "new").returns({
				Show = function()
					shown = true
				end,
			})
			PartyLoot:OnPartyReadyToShow(itemInfoPoor, 1, "party1")
			assert.is_true(shown)
		end)
	end)

	-- ── GROUP_ROSTER_UPDATE ────────────────────────────────────────────────────

	it("GROUP_ROSTER_UPDATE logs info and refreshes the map", function()
		PartyLoot:OnInitialize()
		PartyLoot:GROUP_ROSTER_UPDATE("GROUP_ROSTER_UPDATE")
		assert.spy(ns.LogInfo).was.called_with(_, "GROUP_ROSTER_UPDATE", _, _, _, _)
	end)

	-- ── CHAT_MSG_LOOT ──────────────────────────────────────────────────────────

	describe("CHAT_MSG_LOOT", function()
		-- Canonical party loot message with a single item link.
		local chatMsg = "PartyMember received |cffa335ee|Hitem:18803::::::::60:::::|h[Finkle's Lava Dredger]|h|r"

		before_each(function()
			PartyLoot:OnInitialize()
			PartyLoot.nameUnitMap = { PartyMember = "party1" }
		end)

		it("returns early when partyLoot is disabled", function()
			ns.db.global.partyLoot.enabled = false
			local elementNew = spy.on(PartyLoot.Element, "new")
			PartyLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", chatMsg, "PartyMember")
			assert.spy(elementNew).was_not.called()
		end)

		it("ignores messages flagged as secret values", function()
			PartyLoot._partyLootAdapter.IssecretValue = function()
				return true
			end
			PartyLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", chatMsg, "PartyMember")
			assert.spy(ns.LogWarn).was.called(1)
		end)

		it("ignores raid loot history messages (HlootHistory)", function()
			local raidMsg = "Player received |cFFFFFFFF|HlootHistory:1:0|h[Item]|h|r"
			local elementNew = spy.on(PartyLoot.Element, "new")
			PartyLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", raidMsg, "PartyMember")
			assert.spy(elementNew).was_not.called()
		end)

		it("ignores own loot via GUID match (retail path)", function()
			ns.IsRetail = function()
				return true
			end
			-- guid is the 12th vararg after eventName
			local elementNew = spy.on(PartyLoot.Element, "new")
			PartyLoot:CHAT_MSG_LOOT(
				"CHAT_MSG_LOOT",
				chatMsg,
				"TestPlayer",
				nil,
				nil,
				nil, -- playerName2 (5th vararg)
				nil,
				nil,
				nil,
				nil,
				nil,
				nil, -- 11th vararg
				"Player-GUID-1234" -- guid (12th vararg)
			)
			assert.spy(elementNew).was_not.called()
		end)

		it("ignores own loot via playerName2 match (classic path)", function()
			ns.IsRetail = function()
				return false
			end
			PartyLoot._partyLootAdapter.UnitName = function(unit)
				if unit == "player" then
					return "TestPlayer", nil
				end
				return nil, nil
			end
			local elementNew = spy.on(PartyLoot.Element, "new")
			-- playerName2 at 5th vararg position matches UnitName("player")
			PartyLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", chatMsg, "TestPlayer", nil, nil, "TestPlayer")
			assert.spy(elementNew).was_not.called()
		end)

		it("ignores messages from players not in the nameUnitMap", function()
			PartyLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", chatMsg, "Stranger")
			assert.spy(ns.LogDebug).was.called_with(_, match.has_match("no matching party member"), _, _, _, _)
		end)

		it("ignores double-link messages (item upgrades)", function()
			local upgradeMsg = "PartyMember received"
				.. " |cffa335ee|Hitem:18803::::::::60:::::|h[Old Item]|h|r"
				.. " |cffa335ee|Hitem:18804::::::::60:::::|h[New Item]|h|r"
			local elementNew = spy.on(PartyLoot.Element, "new")
			PartyLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", upgradeMsg, "PartyMember")
			assert.spy(elementNew).was_not.called()
		end)

		it("shows loot element for valid single-item party loot", function()
			local itemInfo = {
				itemId = 18803,
				itemName = "Finkle's Lava Dredger",
				itemQuality = 4,
				itemTexture = 123456,
				itemLink = "|cffa335ee|Hitem:18803::::::::60:::::|h[Finkle's Lava Dredger]|h|r",
				keystoneInfo = nil,
				GetEquipmentTypeText = function()
					return nil
				end,
			}
			stub(ns.ItemInfo, "new").returns(itemInfo)
			local shown = false
			stub(PartyLoot.Element, "new").returns({
				Show = function()
					shown = true
				end,
			})
			PartyLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", chatMsg, "PartyMember")
			assert.is_true(shown)
		end)
	end)

	-- ── GET_ITEM_INFO_RECEIVED ─────────────────────────────────────────────────

	describe("GET_ITEM_INFO_RECEIVED", function()
		before_each(function()
			PartyLoot:OnInitialize()
		end)

		it("resolves pending request and shows the element", function()
			local itemLink = "|cffa335ee|Hitem:18803::::::::60:::::|h[Finkle's Lava Dredger]|h|r"
			local itemInfo = {
				itemId = 18803,
				itemName = "Finkle's Lava Dredger",
				itemQuality = 4,
				itemTexture = 123456,
				itemLink = itemLink,
				keystoneInfo = nil,
				GetEquipmentTypeText = function()
					return nil
				end,
			}
			stub(ns.ItemInfo, "new").returns(itemInfo)
			local shown = false
			stub(PartyLoot.Element, "new").returns({
				Show = function()
					shown = true
				end,
			})
			PartyLoot.pendingPartyRequests[18803] = { itemLink, 1, "party1" }
			PartyLoot:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", 18803, true)
			-- pendingPartyRequests entry must be cleared after resolution
			assert.is_nil(PartyLoot.pendingPartyRequests[18803])
			assert.is_true(shown)
		end)

		it("errors when item load fails", function()
			local itemLink = "|cffa335ee|Hitem:18803::::::::60:::::|h[Finkle's Lava Dredger]|h|r"
			PartyLoot.pendingPartyRequests[18803] = { itemLink, 1, "party1" }
			assert.has_error(function()
				PartyLoot:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", 18803, false)
			end)
		end)

		it("ignores events for items not in pendingPartyRequests", function()
			assert.has_no_error(function()
				PartyLoot:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", 99999, true)
			end)
		end)
	end)

	-- ── Element:new ───────────────────────────────────────────────────────────

	describe("Element", function()
		-- Helper to build a minimal info object; overrides are merged.
		local function makeInfo(overrides)
			local base = {
				itemId = 18803,
				itemLink = "|cffa335ee|Hitem:18803::::::::60:::::|h[Finkle's Lava Dredger]|h|r",
				itemTexture = 123456,
				itemName = "Finkle's Lava Dredger",
				itemQuality = 4,
				keystoneInfo = nil,
				GetEquipmentTypeText = function()
					return nil
				end,
			}
			if overrides then
				for k, v in pairs(overrides) do
					base[k] = v
				end
			end
			return base
		end

		it("sets type, isLink, and eventChannel", function()
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			assert.equals("PartyLoot", e.type)
			assert.is_true(e.isLink)
			assert.equals("RLF_NEW_PARTY_LOOT", e.eventChannel)
		end)

		it("sets itemId, key, and icon from itemInfo", function()
			local info = makeInfo()
			local e = PartyLoot.Element:new(info, 1, "party1")
			assert.equals(18803, e.itemId)
			assert.equals(info.itemLink, e.key)
			assert.equals(123456, e.icon)
		end)

		it("hides icon when partyLoot.enableIcon is false", function()
			ns.db.global.partyLoot.enableIcon = false
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			assert.is_nil(e.icon)
		end)

		it("hides icon when misc.hideAllIcons is true", function()
			ns.db.global.misc.hideAllIcons = true
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			assert.is_nil(e.icon)
		end)

		it("sets quality to Epic when keystoneInfo is non-nil", function()
			local e = PartyLoot.Element:new(makeInfo({ keystoneInfo = {} }), 1, "party1")
			assert.equals(4, e.quality) -- ItemQualEnum.Epic
		end)

		it("secondaryText is unit name only when hideServerNames is true", function()
			ns.db.global.partyLoot.hideServerNames = true
			PartyLoot._partyLootAdapter.UnitName = function()
				return "PartyMember", "ServerName"
			end
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			assert.equals("    PartyMember", e.secondaryText)
		end)

		it("secondaryText includes server when hideServerNames is false", function()
			ns.db.global.partyLoot.hideServerNames = false
			PartyLoot._partyLootAdapter.UnitName = function()
				return "PartyMember", "ServerName"
			end
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			assert.equals("    PartyMember-ServerName", e.secondaryText)
		end)

		it("secondaryText falls back to default when UnitName returns nil", function()
			PartyLoot._partyLootAdapter.UnitName = function()
				return nil, nil
			end
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			assert.equals("A former party member", e.secondaryText)
		end)

		it("textFn returns raw itemLink when no truncatedLink", function()
			local info = makeInfo()
			local e = PartyLoot.Element:new(info, 1, "party1")
			assert.equals(info.itemLink, e.textFn(nil, nil))
		end)

		it("textFn appends quantity when quantity > 1", function()
			local e = PartyLoot.Element:new(makeInfo(), 2, "party1")
			local result = e.textFn(0, "[Finkle's Lava Dredger]")
			assert.equals("[Finkle's Lava Dredger] x2", result)
		end)

		it("textFn omits quantity suffix for quantity 1 when showOneQuantity is false", function()
			ns.db.global.misc.showOneQuantity = false
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			local result = e.textFn(0, "[Finkle's Lava Dredger]")
			assert.equals("[Finkle's Lava Dredger]", result)
		end)

		it("unitClass is set from second return value of UnitClass", function()
			PartyLoot._partyLootAdapter.UnitClass = function()
				return "Warrior", "WARRIOR"
			end
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			assert.equals("WARRIOR", e.unitClass)
		end)

		it("secondaryTextColor uses GetClassColor when expansion >= BFA", function()
			PartyLoot._partyLootAdapter.GetExpansionLevel = function()
				return 10
			end
			local classColor = { r = 0.78, g = 0.61, b = 0.43, a = 1 }
			PartyLoot._partyLootAdapter.GetClassColor = function()
				return classColor
			end
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			assert.same(classColor, e.secondaryTextColor)
		end)

		it("secondaryTextColor uses GetRaidClassColor when expansion < BFA", function()
			PartyLoot._partyLootAdapter.GetExpansionLevel = function()
				return 5
			end -- 5 < BFA (8)
			local raidColor = { r = 0.78, g = 0.61, b = 0.43 }
			PartyLoot._partyLootAdapter.GetRaidClassColor = function()
				return raidColor
			end
			local e = PartyLoot.Element:new(makeInfo(), 1, "party1")
			assert.same(raidColor, e.secondaryTextColor)
		end)
	end)
end)
