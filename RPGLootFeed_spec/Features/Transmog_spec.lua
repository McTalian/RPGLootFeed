local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
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
	local TransmogModule, ns, transmogCollectionMocks, functionMocks

	before_each(function()
		transmogCollectionMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_TransmogCollection")
		functionMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.Functions")
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)

		-- Set up ERR_LEARN_TRANSMOG_S global
		_G["ERR_LEARN_TRANSMOG_S"] = "%s has been added to your appearance collection."

		-- Load the LootDisplayProperties module to populate `ns`
		assert(loadfile("RPGLootFeed/Features/_Internals/LootDisplayProperties.lua"))("TestAddon", ns)

		-- Ensure `ns` has been populated correctly by LootDisplayProperties
		assert.is_not_nil(ns.InitializeLootDisplayProperties)

		-- Load the transmog module before each test
		TransmogModule = assert(loadfile("RPGLootFeed/Features/Transmog.lua"))("TestAddon", ns)
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
			_G["ERR_LEARN_TRANSMOG_S"] = "Модель %s добавлена в вашу коллекцию."

			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"

			local element = TransmogModule.Element:new(transmogLink)
			local result = element.secondaryTextFn()

			assert.are.equal("Модель добавлена в вашу коллекцию", result)

			_G["ERR_LEARN_TRANSMOG_S"] = "%s has been added to your appearance collection."
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
		before_each(function()
			-- Set up C_TransmogCollection.GetAppearanceSourceInfo mock
			transmogCollectionMocks.GetAppearanceSourceInfo = stub(_G.C_TransmogCollection, "GetAppearanceSourceInfo")
		end)

		it("TRANSMOG_COLLECTION_SOURCE_ADDED creates and shows element when data is valid", function()
			local itemModifiedAppearanceID = 12345
			local transmogLink = "|cff9d9d9d|Htransmogappearance:12345|h[Test Transmog]|h|r"
			local icon = "Interface\\Icons\\TestIcon"

			-- Mock successful API response
			transmogCollectionMocks.GetAppearanceSourceInfo.returns({
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
			})

			local elementNewSpy = spy.on(TransmogModule.Element, "new")
			local elementShowStub = stub()
			elementNewSpy.callback = function()
				return { Show = elementShowStub }
			end

			TransmogModule:TRANSMOG_COLLECTION_SOURCE_ADDED(
				"TRANSMOG_COLLECTION_SOURCE_ADDED",
				itemModifiedAppearanceID
			)

			assert.spy(elementNewSpy).was.called_with(_, transmogLink, icon)
			assert.stub(elementShowStub).was.called(1)
		end)

		it("TRANSMOG_COLLECTION_SOURCE_ADDED does not create element when GetAppearanceSourceInfo fails", function()
			local itemModifiedAppearanceID = 12345

			-- Mock API failure (returns nil for itemAppearanceId)
			transmogCollectionMocks.GetAppearanceSourceInfo.returns(nil)

			local elementNewSpy = spy.on(TransmogModule.Element, "new")
			local logWarnSpy = spy.on(ns, "LogWarn")

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

				-- Mock successful API response but with empty transmogLink
				transmogCollectionMocks.GetAppearanceSourceInfo.returns({
					category = 1,
					itemAppearanceID = 67890,
					canHaveIllusion = false,
					icon = "Interface\\Icons\\TestIcon",
					isCollected = true,
					itemLink = "",
					transmoglink = "",
					sourceType = 1,
					itemSubclass = "Armor",
				})

				local elementNewSpy = spy.on(TransmogModule.Element, "new")
				local logWarnSpy = spy.on(ns, "LogWarn")

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

			-- Mock successful API response
			transmogCollectionMocks.GetAppearanceSourceInfo.returns({
				category = 1,
				itemAppearanceID = 67890,
				canHaveIllusion = false,
				icon = "Interface\\Icons\\TestIcon",
				isCollected = true,
				itemLink = "|cffffffff|Hitem:12345::::::::80:::::|h[Test Item]|h|r",
				transmoglink = transmogLink,
				sourceType = 1,
				itemSubclass = "Armor",
			})

			-- Mock element creation failure
			local elementNewSpy = spy.on(TransmogModule.Element, "new")
			elementNewSpy.callback = function()
				return nil
			end

			local logWarnSpy = spy.on(ns, "LogWarn")

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
