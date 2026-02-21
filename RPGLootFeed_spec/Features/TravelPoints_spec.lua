local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local spy = busted.spy
local stub = busted.stub
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

describe("TravelPoints module", function()
	local _ = match._
	local TravelPointsModule, ns, perksActivitiesMocks

	before_each(function()
		perksActivitiesMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_PerksActivities")
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		nsMocks.RGBAToHexFormat.returns("|cFFFFFFFF")

		-- Set up globals
		_G["MONTHLY_ACTIVITIES_POINTS"] = "Traveler's Log"

		-- Load internal feature modules to populate `ns`
		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/Features/_Internals/LootDisplayProperties.lua"))("TestAddon", ns)

		-- Ensure `ns` has been populated correctly
		assert.is_not_nil(ns.LootElementBase)

		-- Load the travel points module before each test
		TravelPointsModule = assert(loadfile("RPGLootFeed/Features/TravelPoints.lua"))("TestAddon", ns)
	end)

	describe("Element creation", function()
		it("creates element with correct properties", function()
			local quantity = 25

			local element = TravelPointsModule.Element:new(quantity)

			assert.is_not_nil(element)
			assert.are.equal("TravelPoints", element.type)
			assert.are.equal("TRAVELPOINTS", element.key)
			assert.are.equal(quantity, element.quantity)
			assert.are.equal(ns.DefaultIcons.TRAVELPOINTS, element.icon)
			assert.are.equal(ns.ItemQualEnum.Common, element.quality)
			assert.is_function(element.textFn)
			assert.is_function(element.secondaryTextFn)
		end)

		it("textFn returns correct format with existing amount", function()
			local quantity = 25
			local existingAmount = 50

			local element = TravelPointsModule.Element:new(quantity)
			local result = element.textFn(existingAmount)

			assert.are.equal("Traveler's Log + 75", result)
		end)

		it("textFn returns correct format with no existing amount", function()
			local quantity = 25

			local element = TravelPointsModule.Element:new(quantity)
			local result = element.textFn()

			assert.are.equal("Traveler's Log + 25", result)
		end)

		it("secondaryTextFn returns progress when journey values are set", function()
			local quantity = 25

			-- Mock the journey values being set
			local element = TravelPointsModule.Element:new(quantity)

			-- Set up the module's internal journey values
			-- We need to trigger calcTravelersJourneyVal to set these values
			perksActivitiesMocks.GetPerksActivitiesInfo.returns({
				activities = {
					{ ID = 1, completed = true, thresholdContributionAmount = 10 },
					{ ID = 2, completed = false, thresholdContributionAmount = 20 },
				},
				thresholds = {
					{ requiredContributionAmount = 100 },
					{ requiredContributionAmount = 150 },
				},
			})

			-- Trigger PERKS_ACTIVITY_COMPLETED to set the journey values
			perksActivitiesMocks.GetPerksActivityInfo.returns({
				thresholdContributionAmount = 20,
			})

			TravelPointsModule:PERKS_ACTIVITY_COMPLETED("PERKS_ACTIVITY_COMPLETED", 2)

			local result = element.secondaryTextFn()

			-- Should show progress: currentTravelersJourney/maxTravelersJourney
			-- current = 10 (completed) + 20 (activity 2) = 30
			-- max = 150 (highest threshold)
			assert.matches("30/150", result)
		end)

		it("secondaryTextFn returns empty string when no journey data", function()
			local quantity = 25

			local element = TravelPointsModule.Element:new(quantity)
			local result = element.secondaryTextFn()

			assert.are.equal("", result)
		end)

		it("IsEnabled function returns module enabled state", function()
			local element = TravelPointsModule.Element:new(25)

			-- Test when enabled
			local enabledStub = stub(TravelPointsModule, "IsEnabled").returns(true)
			assert.is_true(element.IsEnabled())
			enabledStub:revert()

			-- Test when disabled
			local disabledStub = stub(TravelPointsModule, "IsEnabled").returns(false)
			assert.is_false(element.IsEnabled())
			disabledStub:revert()
		end)
	end)

	describe("Module lifecycle", function()
		it("OnInitialize enables module when retail and travel points enabled", function()
			ns.db.global.travelPoints.enabled = true
			local isRetailStub = stub(ns, "IsRetail").returns(true)
			local enableSpy = spy.on(TravelPointsModule, "Enable")

			TravelPointsModule:OnInitialize()

			assert.spy(enableSpy).was.called(1)
			isRetailStub:revert()
		end)

		it("OnInitialize disables module when not retail", function()
			ns.db.global.travelPoints.enabled = true
			local isRetailStub = stub(ns, "IsRetail").returns(false)
			local disableSpy = spy.on(TravelPointsModule, "Disable")

			TravelPointsModule:OnInitialize()

			assert.spy(disableSpy).was.called(1)
			isRetailStub:revert()
		end)

		it("OnInitialize disables module when travel points disabled in config", function()
			ns.db.global.travelPoints.enabled = false
			local isRetailStub = stub(ns, "IsRetail").returns(true)
			local disableSpy = spy.on(TravelPointsModule, "Disable")

			TravelPointsModule:OnInitialize()

			assert.spy(disableSpy).was.called(1)
			isRetailStub:revert()
		end)

		it("OnEnable registers PERKS_ACTIVITY_COMPLETED event when retail", function()
			local isRetailStub = stub(ns, "IsRetail").returns(true)
			local registerEventSpy = spy.on(TravelPointsModule, "RegisterEvent")

			TravelPointsModule:OnEnable()

			assert.spy(registerEventSpy).was.called_with(_, "PERKS_ACTIVITY_COMPLETED")
			isRetailStub:revert()
		end)

		it("OnEnable does nothing when not retail", function()
			local isRetailStub = stub(ns, "IsRetail").returns(false)
			local registerEventSpy = spy.on(TravelPointsModule, "RegisterEvent")

			TravelPointsModule:OnEnable()

			assert.spy(registerEventSpy).was.not_called()
			isRetailStub:revert()
		end)

		it("OnDisable unregisters PERKS_ACTIVITY_COMPLETED event when retail", function()
			local isRetailStub = stub(ns, "IsRetail").returns(true)
			local unregisterEventSpy = spy.on(TravelPointsModule, "UnregisterEvent")

			TravelPointsModule:OnDisable()

			assert.spy(unregisterEventSpy).was.called_with(_, "PERKS_ACTIVITY_COMPLETED")
			isRetailStub:revert()
		end)

		it("OnDisable does nothing when not retail", function()
			local isRetailStub = stub(ns, "IsRetail").returns(false)
			local unregisterEventSpy = spy.on(TravelPointsModule, "UnregisterEvent")

			TravelPointsModule:OnDisable()

			assert.spy(unregisterEventSpy).was.not_called()
			isRetailStub:revert()
		end)
	end)

	describe("Event handling", function()
		it("PERKS_ACTIVITY_COMPLETED creates and shows element with valid amount", function()
			local activityID = 123
			local contributionAmount = 25

			-- Mock successful API responses
			perksActivitiesMocks.GetPerksActivityInfo.returns({
				thresholdContributionAmount = contributionAmount,
			})

			perksActivitiesMocks.GetPerksActivitiesInfo.returns({
				activities = {
					{ ID = 1, completed = true, thresholdContributionAmount = 10 },
					{ ID = activityID, completed = false, thresholdContributionAmount = contributionAmount },
				},
				thresholds = {
					{ requiredContributionAmount = 100 },
				},
			})

			local elementNewSpy = spy.on(TravelPointsModule.Element, "new")
			local elementShowStub = stub()
			elementNewSpy.callback = function()
				return { Show = elementShowStub }
			end

			TravelPointsModule:PERKS_ACTIVITY_COMPLETED("PERKS_ACTIVITY_COMPLETED", activityID)

			assert.spy(elementNewSpy).was.called_with(_, contributionAmount)
			assert.stub(elementShowStub).was.called(1)
		end)

		it("PERKS_ACTIVITY_COMPLETED logs warning when GetPerksActivityInfo fails", function()
			local activityID = 123

			-- Mock API failure
			perksActivitiesMocks.GetPerksActivityInfo.returns(nil)

			local elementNewSpy = spy.on(TravelPointsModule.Element, "new")
			local logWarnSpy = spy.on(ns, "LogWarn")

			TravelPointsModule:PERKS_ACTIVITY_COMPLETED("PERKS_ACTIVITY_COMPLETED", activityID)

			assert.spy(elementNewSpy).was.not_called()
			assert
				.spy(logWarnSpy).was
				.called_with(_, "Could not get activity info", "TestAddon", TravelPointsModule.moduleName)
		end)

		it("PERKS_ACTIVITY_COMPLETED logs warning when amount is not positive", function()
			local activityID = 123

			-- Mock API response with zero amount
			perksActivitiesMocks.GetPerksActivityInfo.returns({
				thresholdContributionAmount = 0,
			})

			perksActivitiesMocks.GetPerksActivitiesInfo.returns({
				activities = {},
				thresholds = {},
			})

			local elementNewSpy = spy.on(TravelPointsModule.Element, "new")
			local logWarnSpy = spy.on(ns, "LogWarn")

			TravelPointsModule:PERKS_ACTIVITY_COMPLETED("PERKS_ACTIVITY_COMPLETED", activityID)

			assert.spy(elementNewSpy).was.not_called()
			assert.spy(logWarnSpy).was.called_with(
				_,
				"PERKS_ACTIVITY_COMPLETED fired but amount was not positive",
				"TestAddon",
				TravelPointsModule.moduleName
			)
		end)

		it("PERKS_ACTIVITY_COMPLETED logs warning when GetPerksActivitiesInfo fails", function()
			local activityID = 123

			-- Mock successful activity info but failed activities info
			perksActivitiesMocks.GetPerksActivityInfo.returns({
				thresholdContributionAmount = 25,
			})

			perksActivitiesMocks.GetPerksActivitiesInfo.returns(nil)

			local logWarnSpy = spy.on(ns, "LogWarn")

			TravelPointsModule:PERKS_ACTIVITY_COMPLETED("PERKS_ACTIVITY_COMPLETED", activityID)

			assert
				.spy(logWarnSpy).was
				.called_with(_, "Could not get all activity info", "TestAddon", TravelPointsModule.moduleName)
		end)
	end)

	describe("calcTravelersJourneyVal function", function()
		it("calculates progress correctly with completed and current activities", function()
			local activityID = 2

			perksActivitiesMocks.GetPerksActivitiesInfo.returns({
				activities = {
					{ ID = 1, completed = true, thresholdContributionAmount = 10 },
					{ ID = activityID, completed = false, thresholdContributionAmount = 20 },
					{ ID = 3, completed = false, thresholdContributionAmount = 15 },
				},
				thresholds = {
					{ requiredContributionAmount = 100 },
					{ requiredContributionAmount = 150 },
				},
			})

			perksActivitiesMocks.GetPerksActivityInfo.returns({
				thresholdContributionAmount = 20,
			})

			-- Call the event which triggers calcTravelersJourneyVal
			TravelPointsModule:PERKS_ACTIVITY_COMPLETED("PERKS_ACTIVITY_COMPLETED", activityID)

			-- Test that the journey values were calculated correctly
			-- Create a new element to test the secondaryTextFn
			local element = TravelPointsModule.Element:new(20)
			local result = element.secondaryTextFn()

			-- Expected: 10 (completed) + 20 (current activity) = 30 progress
			-- Max: 150 (highest threshold)
			assert.matches("30/150", result)
		end)
	end)
end)
