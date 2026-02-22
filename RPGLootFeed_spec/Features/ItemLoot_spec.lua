---@diagnostic disable: need-check-nil
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local stub = busted.stub

describe("ItemLoot Module", function()
	local _ = match._
	---@type RLF_ItemLoot, table
	local ItemLoot, ns, sendMessageSpy

	--- Build a minimal ItemInfo-like stub with sensible defaults.
	--- @param overrides? table
	local function makeItemInfo(overrides)
		local base = {
			itemId = 18803,
			itemName = "Finkle's Lava Dredger",
			itemQuality = 2,
			itemTexture = 123456,
			sellPrice = 10000,
			itemLevel = 60,
			itemEquipLoc = "",
			itemLink = "|cffa335ee|Hitem:18803::::::::60:::::|h[Finkle's Lava Dredger]|h|r",
			IsMount = function()
				return false
			end,
			IsLegendary = function()
				return false
			end,
			IsEligibleEquipment = function()
				return false
			end,
			IsEquippableItem = function()
				return false
			end,
			IsQuestItem = function()
				return false
			end,
			IsAppearanceCollected = function()
				return true
			end,
			IsKeystone = function()
				return false
			end,
			HasItemRollBonus = function()
				return false
			end,
			GetDisplayQuality = function()
				return 4
			end,
			GetEquipmentTypeText = function()
				return nil
			end,
			GetItemRollText = function()
				return ""
			end,
			GetUpgradeText = function()
				return ""
			end,
		}
		if overrides then
			for k, v in pairs(overrides) do
				base[k] = v
			end
		end
		return base
	end

	before_each(function()
		sendMessageSpy = spy.new(function() end)

		-- Build minimal ns from scratch – no nsMocks framework needed.
		-- Only fields actually referenced by ItemLoot.lua and LootElementBase.lua
		-- at load time or as G_RLF.X lookups in function bodies are included.
		-- G_RLF.db, G_RLF.equipSlotMap, G_RLF.AuctionIntegrations are intentionally
		-- present as runtime stubs but absent from the "captured as locals" block.
		ns = {
			-- Captured as locals by ItemLoot.lua at load time.
			ItemQualEnum = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 },
			FeatureModule = { ItemLoot = "ItemLoot" },
			Expansion = { CATA = 10, MOP = 11 },
			AtlasIconCoefficients = {},
			PricesEnum = {
				Vendor = "Vendor",
				AH = "AH",
				VendorAH = "VendorAH",
				AHVendor = "AHVendor",
				Highest = "Highest",
			},
			DbAccessor = {
				Styling = function(_, _)
					return { secondaryFontSize = 12 }
				end,
			},
			Frames = { MAIN = "MAIN" },
			-- Log closure wrappers call these as G_RLF:Method(...) so self is ns.
			LogDebug = spy.new(function() end),
			LogInfo = spy.new(function() end),
			LogWarn = spy.new(function() end),
			LogError = spy.new(function() end),
			IsRetail = function()
				return false
			end,
			RGBAToHexFormat = function()
				return "|cFFFFFFFF"
			end,
			SendMessage = sendMessageSpy,
			-- ItemInfo stub: default returns nil (item not in cache).
			-- Tests that exercise loot paths override ns.ItemInfo.new directly.
			ItemInfo = {
				new = function()
					return nil
				end,
			},
			-- Runtime lookups inside function bodies (not captured as locals).
			equipSlotMap = { INVTYPE_HEAD = 1, INVTYPE_CHEST = 5 },
			AuctionIntegrations = {
				activeIntegration = {
					GetAHPrice = function()
						return nil
					end,
				},
			},
			db = {
				global = {
					animations = { exit = { fadeOutDelay = 3 } },
					item = {
						enabled = true,
						enableIcon = true,
						itemQualitySettings = {
							[0] = { enabled = true, duration = 0 },
							[1] = { enabled = true, duration = 0 },
							[2] = { enabled = true, duration = 3 },
							[3] = { enabled = true, duration = 3 },
							[4] = { enabled = true, duration = 3 },
							[5] = { enabled = true, duration = 3 },
						},
						textStyleOverrides = {
							quest = { enabled = false, color = { 1, 0.82, 0, 1 } },
						},
						pricesForSellableItems = "Vendor",
						vendorIconTexture = "Interface/Icons/inv_misc_coin_01",
						auctionHouseIconTexture = "Interface/Icons/inv_misc_coin_02",
						sounds = {
							mounts = { enabled = false, sound = "" },
							legendary = { enabled = false, sound = "" },
							betterThanEquipped = { enabled = false, sound = "" },
							transmog = { enabled = false, sound = "" },
						},
						itemHighlights = {
							mounts = false,
							legendary = false,
							betterThanEquipped = false,
							quest = false,
							tertiaryOrSocket = false,
							transmog = false,
						},
					},
					misc = {
						hideAllIcons = false,
						showOneQuantity = false,
					},
				},
			},
		}

		-- LibStub must be available before loadfile: ItemLoot.lua calls
		-- LibStub("C_Everywhere") at module root to capture the C library into the
		-- ItemLootAdapter closure.  The adapter's API methods are replaced after
		-- loadfile so the actual C_Everywhere mock content doesn't matter.
		require("RPGLootFeed_spec._mocks.Libs.LibStub")

		-- Load real LootElementBase so elements are fully constructed.
		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
		assert.is_not_nil(ns.LootElementBase)

		-- FeatureBase stub – independent of AceAddon plumbing.
		-- ItemLoot uses AceBucket so RegisterBucketEvent / UnregisterBucket are needed.
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
					RegisterBucketEvent = function() end,
					UnregisterBucket = function() end,
				}
			end,
		}

		-- Load ItemLoot – all external dependency locals are captured from ns
		-- at load time.
		ItemLoot = assert(loadfile("RPGLootFeed/Features/ItemLoot/ItemLoot.lua"))("TestAddon", ns)

		-- Inject a fresh no-op adapter per-test so WoW API calls are controlled
		-- without patching _G directly.  Tests override individual methods as needed.
		ItemLoot._itemLootAdapter = {
			GetExpansionLevel = function()
				return 0
			end,
			UnitName = function()
				return "Player"
			end,
			UnitClass = function()
				return "Warrior", "WARRIOR"
			end,
			UnitLevel = function()
				return 60
			end,
			IssecretValue = function()
				return false
			end,
			GetPlayerGuid = function()
				return "Player-1234-ABCD1234"
			end,
			GetInventoryItemLink = function()
				return nil
			end,
			GetItemQualityColor = function()
				return 1, 1, 1
			end,
			GetCoinTextureString = function(p)
				return tostring(p)
			end,
			CreateAtlasMarkup = function(icon)
				return "[" .. icon .. "]"
			end,
			PlaySoundFile = function()
				return true, 1
			end,
			GetAHPrice = function()
				return nil
			end,
			GetItemInfo = function()
				return nil
			end,
			GetItemIDForItemInfo = function()
				return 18803
			end,
			GetItemCount = function()
				return 1
			end,
			GetItemStatDelta = function()
				return {}
			end,
		}
	end)

	describe("lifecycle", function()
		it("has expected interface functions after load", function()
			assert.is_function(ItemLoot.OnInitialize)
			assert.is_function(ItemLoot.OnEnable)
			assert.is_function(ItemLoot.OnDisable)
			assert.is_function(ItemLoot.SetEquippableArmorClass)
			assert.is_function(ItemLoot.OnItemReadyToShow)
			assert.is_function(ItemLoot.ShowItemLoot)
		end)

		it("exposes _itemLootAdapter on the module", function()
			assert.is_table(ItemLoot._itemLootAdapter)
		end)

		it("enables when db.global.item.enabled is true", function()
			ns.db.global.item.enabled = true
			spy.on(ItemLoot, "Enable")
			spy.on(ItemLoot, "Disable")

			ItemLoot:OnInitialize()

			assert.spy(ItemLoot.Enable).was.called(1)
			assert.spy(ItemLoot.Disable).was_not.called()
		end)

		it("disables when db.global.item.enabled is false", function()
			ns.db.global.item.enabled = false
			spy.on(ItemLoot, "Enable")
			spy.on(ItemLoot, "Disable")

			ItemLoot:OnInitialize()

			assert.spy(ItemLoot.Disable).was.called(1)
			assert.spy(ItemLoot.Enable).was_not.called()
		end)

		it("initializes pendingItemRequests on OnInitialize", function()
			ItemLoot:OnInitialize()

			assert.is_table(ItemLoot.pendingItemRequests)
		end)

		it("registers events on OnEnable", function()
			spy.on(ItemLoot, "RegisterEvent")

			ItemLoot:OnEnable()

			assert.spy(ItemLoot.RegisterEvent).was.called_with(_, "CHAT_MSG_LOOT")
			assert.spy(ItemLoot.RegisterEvent).was.called_with(_, "GET_ITEM_INFO_RECEIVED")
		end)

		it("unregisters events on OnDisable", function()
			spy.on(ItemLoot, "UnregisterEvent")

			ItemLoot:OnDisable()

			assert.spy(ItemLoot.UnregisterEvent).was.called_with(_, "CHAT_MSG_LOOT")
			assert.spy(ItemLoot.UnregisterEvent).was.called_with(_, "GET_ITEM_INFO_RECEIVED")
		end)

		it("calls SetEquippableArmorClass when expansion is in CATA-MOP range", function()
			ItemLoot._itemLootAdapter.GetExpansionLevel = function()
				return 10 -- CATA
			end
			spy.on(ItemLoot, "SetEquippableArmorClass")

			ItemLoot:OnEnable()

			assert.spy(ItemLoot.SetEquippableArmorClass).was.called(1)
		end)

		it("does not call SetEquippableArmorClass outside CATA-MOP range", function()
			ItemLoot._itemLootAdapter.GetExpansionLevel = function()
				return 9 -- before CATA
			end
			spy.on(ItemLoot, "SetEquippableArmorClass")

			ItemLoot:OnEnable()

			assert.spy(ItemLoot.SetEquippableArmorClass).was_not.called()
		end)
	end)

	describe("SetEquippableArmorClass", function()
		it("returns early for caster classes (MAGE)", function()
			ItemLoot._itemLootAdapter.UnitClass = function()
				return "Mage", "MAGE"
			end
			-- Should not error and should not set armorClassMapping
			ItemLoot:SetEquippableArmorClass()
			-- No error = pass
		end)

		it("registers bucket event at low level for non-casters", function()
			ItemLoot._itemLootAdapter.UnitClass = function()
				return "Warrior", "WARRIOR"
			end
			ItemLoot._itemLootAdapter.UnitLevel = function()
				return 20 -- below 40
			end
			spy.on(ItemLoot, "RegisterBucketEvent")

			ItemLoot:SetEquippableArmorClass()

			assert.spy(ItemLoot.RegisterBucketEvent).was.called_with(_, "PLAYER_LEVEL_UP", 1, "SetEquippableArmorClass")
		end)

		it("sets legacy armor class mapping below level 40", function()
			ItemLoot._itemLootAdapter.UnitClass = function()
				return "Warrior", "WARRIOR"
			end
			ItemLoot._itemLootAdapter.UnitLevel = function()
				return 20
			end
			ns.legacyArmorClassMappingLowLevel = { sentinel = true }

			ItemLoot:SetEquippableArmorClass()

			assert.equals(ns.legacyArmorClassMappingLowLevel, ns.armorClassMapping)
		end)

		it("sets standard armor class mapping at level 40+", function()
			ItemLoot._itemLootAdapter.UnitClass = function()
				return "Warrior", "WARRIOR"
			end
			ItemLoot._itemLootAdapter.UnitLevel = function()
				return 60
			end
			ns.standardArmorClassMapping = { sentinel = true }

			ItemLoot:SetEquippableArmorClass()

			assert.equals(ns.standardArmorClassMapping, ns.armorClassMapping)
		end)
	end)

	describe("CHAT_MSG_LOOT", function()
		local GUID = "Player-1234-ABCD1234"
		local ITEM_LINK = "|cffa335ee|Hitem:18803::::::::60:::::|h[Finkle's Lava Dredger]|h|r"

		before_each(function()
			ItemLoot:OnInitialize()
			ItemLoot._itemLootAdapter.GetPlayerGuid = function()
				return GUID
			end
		end)

		it("ignores messages flagged as secret values", function()
			ItemLoot._itemLootAdapter.IssecretValue = function()
				return true
			end
			spy.on(ItemLoot, "ShowItemLoot")
			local msg = "You receive loot: " .. ITEM_LINK

			ItemLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", msg, "Player", nil, nil, nil, nil, nil, nil, nil, nil, nil, GUID)

			assert.spy(ItemLoot.ShowItemLoot).was_not.called()
		end)

		it("ignores raid loot history messages", function()
			spy.on(ItemLoot, "ShowItemLoot")
			local msg = "|HlootHistory:1:18803:" .. ITEM_LINK

			ItemLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", msg, "Player", nil, nil, nil, nil, nil, nil, nil, nil, nil, GUID)

			assert.spy(ItemLoot.ShowItemLoot).was_not.called()
		end)

		it("ignores loot from other players (Retail: guid mismatch)", function()
			ns.IsRetail = function()
				return true
			end
			spy.on(ItemLoot, "ShowItemLoot")
			local msg = "You receive loot: " .. ITEM_LINK
			local otherGuid = "Other-1234-DEADBEEF"

			ItemLoot:CHAT_MSG_LOOT(
				"CHAT_MSG_LOOT",
				msg,
				"Player",
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
				otherGuid
			)

			assert.spy(ItemLoot.ShowItemLoot).was_not.called()
		end)

		it("ignores loot from other players (Classic: playerName2 mismatch)", function()
			ns.IsRetail = function()
				return false
			end
			ItemLoot._itemLootAdapter.UnitName = function()
				return "MyChar"
			end
			spy.on(ItemLoot, "ShowItemLoot")
			local msg = "You receive loot: " .. ITEM_LINK

			ItemLoot:CHAT_MSG_LOOT(
				"CHAT_MSG_LOOT",
				msg,
				"Player",
				nil,
				nil,
				"OtherChar",
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
				nil
			)

			assert.spy(ItemLoot.ShowItemLoot).was_not.called()
		end)

		it("processes own loot (Retail: guid match)", function()
			ns.IsRetail = function()
				return true
			end
			local showSpy = spy.on(ItemLoot, "ShowItemLoot")
			local msg = "You receive loot: " .. ITEM_LINK

			ItemLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", msg, "Player", nil, nil, nil, nil, nil, nil, nil, nil, nil, GUID)

			assert.spy(showSpy).was.called(1)
		end)

		it("processes own loot (Classic: playerName2 match)", function()
			ns.IsRetail = function()
				return false
			end
			ItemLoot._itemLootAdapter.UnitName = function()
				return "MyChar"
			end
			local showSpy = spy.on(ItemLoot, "ShowItemLoot")
			local msg = "You receive loot: " .. ITEM_LINK

			ItemLoot:CHAT_MSG_LOOT(
				"CHAT_MSG_LOOT",
				msg,
				"Player",
				nil,
				nil,
				"MyChar",
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
				nil
			)

			assert.spy(showSpy).was.called(1)
		end)

		it("passes correct itemLink to ShowItemLoot for single-item message", function()
			ns.IsRetail = function()
				return true
			end
			local capturedLink
			stub(ItemLoot, "ShowItemLoot", function(_, _, link, _)
				capturedLink = link
			end)
			local msg = "You receive loot: " .. ITEM_LINK

			ItemLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", msg, "Player", nil, nil, nil, nil, nil, nil, nil, nil, nil, GUID)

			assert.equals(ITEM_LINK, capturedLink)
		end)

		it("handles item upgrade (2 item links): fromLink and itemLink both passed", function()
			ns.IsRetail = function()
				return true
			end
			local capturedFrom, capturedLink
			stub(ItemLoot, "ShowItemLoot", function(_, _, link, from)
				capturedLink = link
				capturedFrom = from
			end)
			local fromLink = "|cffa335ee|Hitem:18789::::::::60:::::|h[Old Item]|h|r"
			local msg = "You upgrade " .. fromLink .. " to " .. ITEM_LINK

			ItemLoot:CHAT_MSG_LOOT("CHAT_MSG_LOOT", msg, "Player", nil, nil, nil, nil, nil, nil, nil, nil, nil, GUID)

			assert.equals(fromLink, capturedFrom)
			assert.equals(ITEM_LINK, capturedLink)
		end)
	end)

	describe("GET_ITEM_INFO_RECEIVED", function()
		local ITEM_ID = 18803
		local ITEM_LINK = "|cffa335ee|Hitem:18803::::::::60:::::|h[Finkle's Lava Dredger]|h|r"

		before_each(function()
			ItemLoot:OnInitialize()
		end)

		it("ignores unknown itemIDs not in pendingItemRequests", function()
			spy.on(ItemLoot, "OnItemReadyToShow")

			ItemLoot:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", ITEM_ID, true)

			assert.spy(ItemLoot.OnItemReadyToShow).was_not.called()
		end)

		it("calls OnItemReadyToShow on success with valid ItemInfo", function()
			local info = makeItemInfo()
			ns.ItemInfo.new = function()
				return info
			end
			ItemLoot.pendingItemRequests[ITEM_ID] = { ITEM_LINK, 1, nil }
			spy.on(ItemLoot, "OnItemReadyToShow")

			ItemLoot:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", ITEM_ID, true)

			assert.spy(ItemLoot.OnItemReadyToShow).was.called(1)
			assert.is_nil(ItemLoot.pendingItemRequests[ITEM_ID])
		end)

		it("errors when success=false for a pending item", function()
			ItemLoot.pendingItemRequests[ITEM_ID] = { ITEM_LINK, 1, nil }

			assert.has_error(function()
				ItemLoot:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", ITEM_ID, false)
			end)
		end)

		it("returns early without calling OnItemReadyToShow when ItemInfo:new returns nil", function()
			ns.ItemInfo.new = function()
				return nil
			end
			ItemLoot.pendingItemRequests[ITEM_ID] = { ITEM_LINK, 1, nil }
			spy.on(ItemLoot, "OnItemReadyToShow")

			ItemLoot:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", ITEM_ID, true)

			assert.spy(ItemLoot.OnItemReadyToShow).was_not.called()
		end)
	end)

	describe("Element:new", function()
		it("constructs with base element fields", function()
			local info = makeItemInfo()
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.equals("ItemLoot", element.type)
			assert.equals(1, element.quantity)
			assert.is_function(element.IsEnabled)
			assert.is_function(element.textFn)
			assert.is_function(element.secondaryTextFn)
			assert.is_function(element.isPassingFilter)
			assert.is_function(element.PlaySoundIfEnabled)
			assert.is_function(element.SetHighlight)
		end)

		it("sets element.key to itemLink", function()
			local info = makeItemInfo()
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.equals(info.itemLink, element.key)
		end)

		it("sets element.icon when icons are enabled", function()
			local info = makeItemInfo()
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.equals(info.itemTexture, element.icon)
		end)

		it("sets icon to nil when item icons are disabled", function()
			ns.db.global.item.enableIcon = false
			local info = makeItemInfo()
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.is_nil(element.icon)
		end)

		it("sets icon to nil when hideAllIcons is set", function()
			ns.db.global.misc.hideAllIcons = true
			local info = makeItemInfo()
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.is_nil(element.icon)
		end)

		it("sets showForSeconds from quality settings when duration > 0", function()
			ns.db.global.item.itemQualitySettings[2] = { enabled = true, duration = 7 }
			local info = makeItemInfo({ itemQuality = 2 })
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.equals(7, element.showForSeconds)
		end)

		it("does not override showForSeconds when quality duration is 0 (LootElementBase default preserved)", function()
			ns.db.global.item.itemQualitySettings[2] = { enabled = true, duration = 0 }
			local info = makeItemInfo({ itemQuality = 2 })
			local element = ItemLoot.Element:new(info, 1, nil)

			-- LootElementBase:new() defaults showForSeconds to animations.exit.fadeOutDelay (3)
			-- The quality setting with duration=0 should NOT override it
			assert.equals(ns.db.global.animations.exit.fadeOutDelay, element.showForSeconds)
		end)

		it("sets isLink = true", function()
			local info = makeItemInfo()
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.is_true(element.isLink)
		end)

		it("sets itemCount from adapter", function()
			ItemLoot._itemLootAdapter.GetItemCount = function()
				return 5
			end
			local info = makeItemInfo()
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.equals(5, element.itemCount)
		end)

		it("sets isMount from ItemInfo", function()
			local info = makeItemInfo({
				IsMount = function()
					return true
				end,
			})
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.is_true(element.isMount)
		end)

		it("sets isLegendary from ItemInfo", function()
			local info = makeItemInfo({
				IsLegendary = function()
					return true
				end,
			})
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.is_true(element.isLegendary)
		end)

		it("sets isQuestItem from ItemInfo", function()
			ns.db.global.item.textStyleOverrides.quest.enabled = false
			local info = makeItemInfo({
				IsQuestItem = function()
					return true
				end,
			})
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.is_true(element.isQuestItem)
		end)

		it("applies quest color when quest style override is enabled", function()
			ns.db.global.item.textStyleOverrides.quest.enabled = true
			ns.db.global.item.textStyleOverrides.quest.color = { 1, 0.82, 0, 1 }
			local info = makeItemInfo({
				IsQuestItem = function()
					return true
				end,
			})
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.equals(1, element.r)
			assert.equals(0.82, element.g)
			assert.equals(0, element.b)
			assert.equals(1, element.a)
		end)

		it("does not override color for non-quest items", function()
			local info = makeItemInfo()
			local element = ItemLoot.Element:new(info, 1, nil)

			-- LootElementBase:new() defaults to white (1,1,1,1)
			assert.equals(1, element.r)
			assert.equals(1, element.g)
			assert.equals(1, element.b)
		end)

		it("sets topLeftText and topLeftColor for equippable non-poor items", function()
			ItemLoot._itemLootAdapter.GetItemQualityColor = function()
				return 0.5, 0.5, 1
			end
			local info = makeItemInfo({
				itemQuality = 3,
				itemLevel = 55,
				IsEquippableItem = function()
					return true
				end,
			})
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.equals("55", element.topLeftText)
			assert.same({ 0.5, 0.5, 1 }, element.topLeftColor)
		end)

		it("does not set topLeftText for non-equippable items", function()
			local info = makeItemInfo({ itemQuality = 3 })
			-- IsEquippableItem defaults to false in makeItemInfo
			local element = ItemLoot.Element:new(info, 1, nil)

			assert.is_nil(element.topLeftText)
		end)

		it("key gets UPGRADE_ prefix when fromLink is provided", function()
			local info = makeItemInfo()
			local fromLink = "|cffa335ee|Hitem:18789::::::::60:::::|h[Old]|h|r"
			local element = ItemLoot.Element:new(info, 1, fromLink)

			assert.matches("^UPGRADE_", element.key)
		end)

		describe("textFn", function()
			it("returns bare itemLink when no truncatedLink is provided", function()
				local info = makeItemInfo()
				local element = ItemLoot.Element:new(info, 1, nil)

				assert.equals(info.itemLink, element.textFn(nil, nil))
			end)

			it("appends quantity when showOneQuantity is true and quantity > 1", function()
				ns.db.global.misc.showOneQuantity = true
				local info = makeItemInfo()
				local element = ItemLoot.Element:new(info, 3, nil)

				local text = element.textFn(0, "[Link]")
				assert.matches("x3", text)
			end)

			it("omits quantity suffix when showOneQuantity is false and quantity is 1", function()
				ns.db.global.misc.showOneQuantity = false
				local info = makeItemInfo()
				local element = ItemLoot.Element:new(info, 1, nil)

				local text = element.textFn(0, "[Link]")
				assert.not_matches("x1", text)
			end)
		end)

		describe("isPassingFilter", function()
			it("returns false for disabled quality tier", function()
				ns.db.global.item.itemQualitySettings[2] = { enabled = false, duration = 3 }
				local info = makeItemInfo({ itemQuality = 2 })
				local element = ItemLoot.Element:new(info, 1, nil)

				assert.is_false(element:isPassingFilter("Finkle's Lava Dredger", 2))
			end)

			it("returns true for enabled quality tier", function()
				ns.db.global.item.itemQualitySettings[2] = { enabled = true, duration = 3 }
				local info = makeItemInfo({ itemQuality = 2 })
				local element = ItemLoot.Element:new(info, 1, nil)

				assert.is_true(element:isPassingFilter("Finkle's Lava Dredger", 2))
			end)
		end)

		describe("SetHighlight", function()
			it("sets highlight = false when no conditions match", function()
				local info = makeItemInfo()
				local element = ItemLoot.Element:new(info, 1, nil)

				element:SetHighlight()

				assert.is_false(element.highlight)
			end)

			it("sets highlight = true for mounts when itemHighlights.mounts is enabled", function()
				ns.db.global.item.itemHighlights.mounts = true
				local info = makeItemInfo({
					IsMount = function()
						return true
					end,
				})
				local element = ItemLoot.Element:new(info, 1, nil)

				element:SetHighlight()

				assert.is_true(element.highlight)
			end)

			it("sets highlight = true for legendary items when itemHighlights.legendary is enabled", function()
				ns.db.global.item.itemHighlights.legendary = true
				local info = makeItemInfo({
					IsLegendary = function()
						return true
					end,
				})
				local element = ItemLoot.Element:new(info, 1, nil)

				element:SetHighlight()

				assert.is_true(element.highlight)
			end)
		end)

		describe("PlaySoundIfEnabled", function()
			it("plays mount sound when mount sound is enabled and item is a mount", function()
				ns.db.global.item.sounds.mounts = { enabled = true, sound = "Interface/Sounds/mount.ogg" }
				local playSpy = spy.new(function()
					return true, 1
				end)
				ItemLoot._itemLootAdapter.PlaySoundFile = playSpy
				local info = makeItemInfo({
					IsMount = function()
						return true
					end,
				})
				local element = ItemLoot.Element:new(info, 1, nil)

				element:PlaySoundIfEnabled()

				assert.spy(playSpy).was.called_with("Interface/Sounds/mount.ogg")
			end)

			it("plays legendary sound when legendary sound is enabled and item is legendary", function()
				ns.db.global.item.sounds.legendary = { enabled = true, sound = "Interface/Sounds/legendary.ogg" }
				local playSpy = spy.new(function()
					return true, 1
				end)
				ItemLoot._itemLootAdapter.PlaySoundFile = playSpy
				local info = makeItemInfo({
					IsLegendary = function()
						return true
					end,
				})
				local element = ItemLoot.Element:new(info, 1, nil)

				element:PlaySoundIfEnabled()

				assert.spy(playSpy).was.called_with("Interface/Sounds/legendary.ogg")
			end)

			it("does not play sound when no conditions match", function()
				local playSpy = spy.new(function()
					return true, 1
				end)
				ItemLoot._itemLootAdapter.PlaySoundFile = playSpy
				local info = makeItemInfo()
				local element = ItemLoot.Element:new(info, 1, nil)

				element:PlaySoundIfEnabled()

				assert.spy(playSpy).was_not.called()
			end)
		end)
	end)
end)
