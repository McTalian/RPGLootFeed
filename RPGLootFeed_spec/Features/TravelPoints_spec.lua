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
	local TravelPointsModule, ns
	local mockPerksAdapter, mockGlobalStringsAdapter

	before_each(function()
		-- Use UtilsEnums section: gives us Enums (DefaultIcons, ItemQualEnum, FeatureModule)
		-- and method stubs (LogDebug, LogInfo, LogWarn, SendMessage, IsRetail, RGBAToHexFormat).
		-- This avoids the full nsMocks framework for this feature's tests.
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.UtilsEnums)
		nsMocks.RGBAToHexFormat.returns("|cFFFFFFFF")

		-- Provide db manually – AceDB is not available in this lightweight setup.
		ns.db = {
			global = {
				animations = { exit = { fadeOutDelay = 3 } },
				travelPoints = { textColor = { 1, 1, 1, 1 }, enableIcon = true, enabled = true },
				misc = { hideAllIcons = false },
			},
		}

		-- Load real LootElementBase so elements are fully constructed
		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
		assert.is_not_nil(ns.LootElementBase)

		-- Mock FeatureBase – returns a minimal stub module so TravelPoints tests
		-- are completely independent of AceAddon plumbing.  The stub includes the
		-- Ace lifecycle methods that TravelPoints.lua calls (Enable, Disable, etc.)
		-- so spy.on() has something to wrap.
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

		-- Load TravelPoints – the FeatureBase mock above is captured at load time
		TravelPointsModule = assert(loadfile("RPGLootFeed/Features/TravelPoints.lua"))("TestAddon", ns)

		-- Inject fresh mock adapters for full test isolation.
		-- Tests that need specific behaviour swap in their own adapter table via
		-- TravelPointsModule._*Adapter = { ... } before the act step.
		mockPerksAdapter = {
			GetPerksActivitiesInfo = function()
				return nil
			end,
			GetPerksActivityInfo = function(_activityID)
				return nil
			end,
		}
		mockGlobalStringsAdapter = {
			GetMonthlyActivitiesPointsLabel = function()
				return "Traveler's Log"
			end,
		}
		TravelPointsModule._perksActivitiesAdapter = mockPerksAdapter
		TravelPointsModule._globalStringsAdapter = mockGlobalStringsAdapter
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

			TravelPointsModule._perksActivitiesAdapter = {
				GetPerksActivitiesInfo = function()
					return {
						activities = {
							{ ID = 1, completed = true, thresholdContributionAmount = 10 },
							{ ID = 2, completed = false, thresholdContributionAmount = 20 },
						},
						thresholds = {
							{ requiredContributionAmount = 100 },
							{ requiredContributionAmount = 150 },
						},
					}
				end,
				GetPerksActivityInfo = function(_activityID)
					return { thresholdContributionAmount = 20 }
				end,
			}

			-- Trigger the event to populate internal journey values
			TravelPointsModule:PERKS_ACTIVITY_COMPLETED("PERKS_ACTIVITY_COMPLETED", 2)

			local element = TravelPointsModule.Element:new(quantity)
			local result = element.secondaryTextFn()

			-- current = 10 (completed) + 20 (activity 2) = 30, max = 150
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

			TravelPointsModule._perksActivitiesAdapter = {
				GetPerksActivityInfo = function(_activityID)
					return { thresholdContributionAmount = contributionAmount }
				end,
				GetPerksActivitiesInfo = function()
					return {
						activities = {
							{ ID = 1, completed = true, thresholdContributionAmount = 10 },
							{ ID = activityID, completed = false, thresholdContributionAmount = contributionAmount },
						},
						thresholds = {
							{ requiredContributionAmount = 100 },
						},
					}
				end,
			}

			local elementNewSpy = spy.on(TravelPointsModule.Element, "new")

			TravelPointsModule:PERKS_ACTIVITY_COMPLETED("PERKS_ACTIVITY_COMPLETED", activityID)

			-- Element:new was called with the correct contribution amount
			assert.spy(elementNewSpy).was.called_with(_, contributionAmount)
			-- Show() dispatches via G_RLF:SendMessage — verify the element was routed
			assert.stub(nsMocks.SendMessage).was.called(1)
			assert.stub(nsMocks.SendMessage).was.called_with(_, "RLF_NEW_LOOT", _)
		end)

		it("PERKS_ACTIVITY_COMPLETED logs warning when GetPerksActivityInfo fails", function()
			local activityID = 123
			-- mockPerksAdapter.GetPerksActivityInfo already returns nil from before_each

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

			TravelPointsModule._perksActivitiesAdapter = {
				GetPerksActivityInfo = function(_activityID)
					return { thresholdContributionAmount = 0 }
				end,
				GetPerksActivitiesInfo = function()
					return { activities = {}, thresholds = {} }
				end,
			}

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

			TravelPointsModule._perksActivitiesAdapter = {
				GetPerksActivityInfo = function(_activityID)
					return { thresholdContributionAmount = 25 }
				end,
				GetPerksActivitiesInfo = function()
					return nil
				end,
			}

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

			TravelPointsModule._perksActivitiesAdapter = {
				GetPerksActivitiesInfo = function()
					return {
						activities = {
							{ ID = 1, completed = true, thresholdContributionAmount = 10 },
							{ ID = activityID, completed = false, thresholdContributionAmount = 20 },
							{ ID = 3, completed = false, thresholdContributionAmount = 15 },
						},
						thresholds = {
							{ requiredContributionAmount = 100 },
							{ requiredContributionAmount = 150 },
						},
					}
				end,
				GetPerksActivityInfo = function(_activityID)
					return { thresholdContributionAmount = 20 }
				end,
			}

			-- Trigger the event which internally calls calcTravelersJourneyVal
			TravelPointsModule:PERKS_ACTIVITY_COMPLETED("PERKS_ACTIVITY_COMPLETED", activityID)

			-- Verify journey values via secondaryTextFn on a fresh element
			local element = TravelPointsModule.Element:new(20)
			local result = element.secondaryTextFn()

			-- current = 10 (completed) + 20 (activity 2 = current) = 30, max = 150
			assert.matches("30/150", result)
		end)
	end)
end)
