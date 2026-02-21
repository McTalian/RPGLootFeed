require("RPGLootFeed_spec._mocks.LuaCompat")
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local spy = busted.spy
local stub = busted.stub
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

describe("Transmog module", function()
	local _ = match._
	local TransmogModule, ns
	local sendMessageSpy, logWarnSpy

	before_each(function()
		-- Spies on ns methods that tests need to assert against.
		sendMessageSpy = spy.new(function() end)
		logWarnSpy = spy.new(function() end)

		-- Build a minimal ns from scratch – no nsMocks framework needed.
		-- Only the fields actually referenced by Transmog.lua and LootElementBase.lua
		-- are included; everything else is intentionally absent.
		ns = {
			-- Captured as locals by Transmog.lua at load time.
			DefaultIcons = { TRANSMOG = "Interface/Icons/Inv_misc_questionmark" },
			ItemQualEnum = { Epic = 4 },
			FeatureModule = { Transmog = "Transmog" },
			-- Closure wrappers in Transmog.lua call these as G_RLF:Method(...).
			LogDebug = function() end,
			LogInfo = function() end,
			LogWarn = logWarnSpy,
			IsRetail = function()
				return true
			end,
			SendMessage = sendMessageSpy,
			-- Runtime lookup by LootElementBase:new() and Transmog lifecycle methods.
			db = {
				global = {
					animations = { exit = { fadeOutDelay = 3 } },
					transmog = { enableIcon = true, enabled = true },
					misc = { hideAllIcons = false },
				},
			},
		}

		-- Load real LootElementBase so elements are fully constructed.
		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
		assert.is_not_nil(ns.LootElementBase)

		-- Mock FeatureBase – returns a minimal stub module so Transmog tests
		-- are completely independent of AceAddon plumbing.
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

		-- Load Transmog – the FeatureBase mock above is captured at load time.
		TransmogModule = assert(loadfile("RPGLootFeed/Features/Transmog.lua"))("TestAddon", ns)

		-- Inject fresh mock adapters for full test isolation.
		-- Tests that need specific behaviour swap in their own adapter table.
		TransmogModule._transmogCollectionAdapter = {
			GetAppearanceSourceInfo = function(_id)
				return nil
			end,
			CreateItemFromItemLink = function(_link)
				return nil
			end,
		}
		TransmogModule._globalStringsAdapter = {
			GetErrLearnTransmogS = function()
				return "%s has been added to your appearance collection."
			end,
		}
	end)

	describe("Element creation", function()
		it("creates element with correct properties", function()
			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"
			local icon = "Interface\\Icons\\TestIcon"

			local element = TransmogModule.Element:new(transmogLink, icon)

			assert.is_not_nil(element)
			assert.are.equal("Transmog", element.type)
			assert.are.equal("TMOG_" .. transmogLink, element.key)
			assert.are.equal(icon, element.icon)
			assert.are.equal(ns.ItemQualEnum.Epic, element.quality)
			assert.is_true(element.isLink)
			assert.is_function(element.textFn)
			assert.is_function(element.secondaryTextFn)
		end)

		it("uses default icon when none provided", function()
			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"

			local element = TransmogModule.Element:new(transmogLink)

			assert.are.equal(ns.DefaultIcons.TRANSMOG, element.icon)
		end)

		it("textFn returns transmogLink when no truncatedLink provided", function()
			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"

			local element = TransmogModule.Element:new(transmogLink)
			local result = element.textFn()

			assert.are.equal(transmogLink, result)
		end)

		it("textFn returns truncatedLink when provided", function()
			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"
			local truncatedLink = "[Test Transmog]"

			local element = TransmogModule.Element:new(transmogLink)
			local result = element.textFn(nil, truncatedLink)

			assert.are.equal(truncatedLink, result)
		end)

		it("secondaryTextFn returns formatted transmog learn message", function()
			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"

			local element = TransmogModule.Element:new(transmogLink)
			local result = element.secondaryTextFn()

			assert.are.equal("has been added to your appearance collection", result)
		end)

		it("secondaryTextFn returns formatted transmog learn message for ruRU", function()
			TransmogModule._globalStringsAdapter = {
				GetErrLearnTransmogS = function()
					return "Модель %s добавлена в вашу коллекцию."
				end,
			}

			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"

			local element = TransmogModule.Element:new(transmogLink)
			local result = element.secondaryTextFn()

			assert.are.equal("Модель добавлена в вашу коллекцию", result)
		end)

		it("IsEnabled function returns module enabled state", function()
			local element = TransmogModule.Element:new("|cff9d9d9d|Htransmogappearance:12345|h[Test]|h|r")

			-- Test when enabled
			local enabledStub = stub(TransmogModule, "IsEnabled").returns(true)
			assert.is_true(element.IsEnabled())
			enabledStub:revert()

			-- Test when disabled
			local disabledStub = stub(TransmogModule, "IsEnabled").returns(false)
			assert.is_false(element.IsEnabled())
			disabledStub:revert()
		end)
	end)

	describe("Module lifecycle", function()
		it("OnInitialize enables module when transmog is enabled in config", function()
			ns.db.global.transmog.enabled = true
			local enableSpy = spy.on(TransmogModule, "Enable")

			TransmogModule:OnInitialize()

			assert.spy(enableSpy).was.called(1)
		end)

		it("OnInitialize disables module when transmog is disabled in config", function()
			ns.db.global.transmog.enabled = false
			local disableSpy = spy.on(TransmogModule, "Disable")

			TransmogModule:OnInitialize()

			assert.spy(disableSpy).was.called(1)
		end)

		it("OnEnable registers TRANSMOG_COLLECTION_SOURCE_ADDED event", function()
			local registerEventSpy = spy.on(TransmogModule, "RegisterEvent")

			TransmogModule:OnEnable()

			assert.spy(registerEventSpy).was.called_with(_, "TRANSMOG_COLLECTION_SOURCE_ADDED")
		end)

		it("OnDisable unregisters TRANSMOG_COLLECTION_SOURCE_ADDED event", function()
			local unregisterEventSpy = spy.on(TransmogModule, "UnregisterEvent")

			TransmogModule:OnDisable()

			assert.spy(unregisterEventSpy).was.called_with(_, "TRANSMOG_COLLECTION_SOURCE_ADDED")
		end)
	end)

	describe("Event handling", function()
		it("TRANSMOG_COLLECTION_SOURCE_ADDED creates and shows element when data is valid", function()
			local itemModifiedAppearanceID = 12345
			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"
			local icon = "Interface\\Icons\\TestIcon"

			-- Inject adapter with a successful response.
			TransmogModule._transmogCollectionAdapter = {
				GetAppearanceSourceInfo = function(_id)
					return {
						category = 1,
						itemApperanceID = 67890,
						canHaveIllusion = false,
						icon = icon,
						isCollected = true,
						itemLink = "|cffffffff|Hitem:12345::::::::80:::::|h[Test Item]|h|r",
						-- Yes, the casing is inconsistent, but it's what the API returns
						transmoglink = transmogLink,
						sourceType = 1,
						itemSubclass = "Armor",
					}
				end,
				CreateItemFromItemLink = function(_link)
					return nil
				end,
			}

			local elementNewSpy = spy.on(TransmogModule.Element, "new")

			TransmogModule:TRANSMOG_COLLECTION_SOURCE_ADDED(
				"TRANSMOG_COLLECTION_SOURCE_ADDED",
				itemModifiedAppearanceID
			)

			assert.spy(elementNewSpy).was.called_with(_, transmogLink, icon)
			assert.spy(sendMessageSpy).was.called_with(_, "RLF_NEW_LOOT", _)
		end)

		it("TRANSMOG_COLLECTION_SOURCE_ADDED does not create element when GetAppearanceSourceInfo fails", function()
			local itemModifiedAppearanceID = 12345

			-- Default adapter already returns nil; no override needed.
			local elementNewSpy = spy.on(TransmogModule.Element, "new")

			TransmogModule:TRANSMOG_COLLECTION_SOURCE_ADDED(
				"TRANSMOG_COLLECTION_SOURCE_ADDED",
				itemModifiedAppearanceID
			)

			assert.spy(elementNewSpy).was.not_called()
			assert
				.spy(logWarnSpy).was
				.called_with(_, "Could not get appearance source info", "TestAddon", TransmogModule.moduleName)
		end)

		it(
			"TRANSMOG_COLLECTION_SOURCE_ADDED does not create element when transmogLink and itemLink are empty",
			function()
				local itemModifiedAppearanceID = 12345

				-- Inject adapter with both links empty.
				TransmogModule._transmogCollectionAdapter = {
					GetAppearanceSourceInfo = function(_id)
						return {
							category = 1,
							itemAppearanceID = 67890,
							canHaveIllusion = false,
							icon = "Interface\\Icons\\TestIcon",
							isCollected = true,
							itemLink = "",
							transmoglink = "",
							sourceType = 1,
							itemSubclass = "Armor",
						}
					end,
					CreateItemFromItemLink = function(_link)
						return nil
					end,
				}

				local elementNewSpy = spy.on(TransmogModule.Element, "new")

				TransmogModule:TRANSMOG_COLLECTION_SOURCE_ADDED(
					"TRANSMOG_COLLECTION_SOURCE_ADDED",
					itemModifiedAppearanceID
				)

				assert.spy(elementNewSpy).was.not_called()
				assert
					.spy(logWarnSpy).was
					.called_with(
						_,
						"Item link is also empty for " .. itemModifiedAppearanceID,
						"TestAddon",
						TransmogModule.moduleName
					)
			end
		)

		it("TRANSMOG_COLLECTION_SOURCE_ADDED logs warning when element creation fails", function()
			local itemModifiedAppearanceID = 12345
			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"

			-- Inject adapter with a successful response.
			TransmogModule._transmogCollectionAdapter = {
				GetAppearanceSourceInfo = function(_id)
					return {
						category = 1,
						itemAppearanceID = 67890,
						canHaveIllusion = false,
						icon = "Interface\\Icons\\TestIcon",
						isCollected = true,
						itemLink = "|cffffffff|Hitem:12345::::::::80:::::|h[Test Item]|h|r",
						transmoglink = transmogLink,
						sourceType = 1,
						itemSubclass = "Armor",
					}
				end,
				CreateItemFromItemLink = function(_link)
					return nil
				end,
			}

			-- Force element creation to return nil to trigger the warning path.
			stub(TransmogModule.Element, "new").returns(nil)

			TransmogModule:TRANSMOG_COLLECTION_SOURCE_ADDED(
				"TRANSMOG_COLLECTION_SOURCE_ADDED",
				itemModifiedAppearanceID
			)

			assert
				.spy(logWarnSpy).was
				.called_with(_, "Could not create Transmog Element", "TestAddon", TransmogModule.moduleName)
		end)
	end)
end)
