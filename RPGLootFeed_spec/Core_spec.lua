local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local setup = busted.setup
local spy = busted.spy
local stub = busted.stub

describe("Core module", function()
	local ns, RLF
	local _ = match._
	local libStubReturn

	setup(function()
		libStubReturn = require("RPGLootFeed_spec._mocks.Libs.LibStub")
	end)

	describe("load order", function()
		it("loads the file correctly", function()
			---@type test_G_RLF
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.None)
			RLF = assert(loadfile("RPGLootFeed/Core.lua"))("TestAddon", ns)
			assert.is_not_nil(RLF)
		end)
	end)

	describe("functionality", function()
		before_each(function()
			---@type test_G_RLF
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
			RLF = assert(loadfile("RPGLootFeed/Core.lua"))("TestAddon", ns)
		end)

		describe("addon initialization", function()
			it("should initialize correctly", function()
				spy.on(RLF, "OnInitialize")
				RLF:OnInitialize()
				assert.spy(RLF.OnInitialize).was.called(1)
			end)
		end)

		describe("OnSlashCommand", function()
			it("should handle test mode command correctly", function()
				local TestMode = {
					ToggleTestMode = function() end,
				}
				local spyToggleTestMode = spy.on(TestMode, "ToggleTestMode")
				RLF.GetModule = function(_, moduleName)
					if moduleName == "TestMode" then
						return TestMode
					end
				end

				RLF:OnInitialize()
				RLF:SlashCommand("test")
				assert.spy(spyToggleTestMode).was.called(1)
			end)

			it("should handle unknown command correctly", function()
				local acd = libStubReturn["AceConfigDialog-3.0"]
				spy.on(acd, "Open")
				RLF:OnInitialize()
				RLF:SlashCommand("unknown")
				assert.spy(acd.Open).was.called_with(_, "TestAddon")
			end)
		end)

		describe("PLAYER_ENTERING_WORLD", function()
			it("should handle PLAYER_ENTERING_WORLD event correctly", function()
				ns.db.global.blizzOverrides.enableAutoLoot = true
				ns.RLF_MainLootFrame = {
					UpdateTabVisibility = spy.new(function() end),
				}
				nsMocks.RGBAToHexFormat.returns("|cFFFFFFFF")
				local fakeNotifModule = {
					ViewAllNotifications = spy.new(function() end),
				}
				local stubGetModule = stub(RLF, "GetModule", function(_, moduleName)
					if moduleName == "Notifications" then
						return fakeNotifModule
					end
				end)
				spy.on(RLF, "PLAYER_ENTERING_WORLD")
				RLF:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", true, false)
				assert.spy(RLF.PLAYER_ENTERING_WORLD).was.called(1)
				assert.spy(fakeNotifModule.ViewAllNotifications).was.called(1)
				assert.spy(ns.RLF_MainLootFrame.UpdateTabVisibility).was.called(1)
			end)
		end)

		describe("OnOptionsOpen/OnOptionsClose", function()
			it("shows the bounding box when the options are opened", function()
				local spyScheduleTimer = spy.on(RLF, "ScheduleTimer")
				local spySetBoundingBoxViz = spy.on(ns.LootDisplay, "SetBoundingBoxVisibility")
				RLF:OnOptionsOpen(nil, "TestAddon", nil, nil)
				assert.spy(spyScheduleTimer).was.called(1)
				assert.spy(spySetBoundingBoxViz).was.called_with(_, true)
			end)

			it("does nothing if the options are already open", function()
				local spyScheduleTimer = spy.on(RLF, "ScheduleTimer")
				local spySetBoundingBoxViz = spy.on(ns.LootDisplay, "SetBoundingBoxVisibility")
				RLF:OnOptionsOpen(nil, "TestAddon", nil, nil)
				RLF:OnOptionsOpen(nil, "TestAddon", nil, nil)
				assert.spy(spyScheduleTimer).was.called(1)
				assert.spy(spySetBoundingBoxViz).was.called(1)
			end)

			it("hides the bounding box when the options are closed", function()
				local spySetBoundingBoxViz = spy.on(ns.LootDisplay, "SetBoundingBoxVisibility")
				local spyHook = spy.on(RLF, "Hook")
				local stubScheduleTimer = stub(RLF, "ScheduleTimer", function(self, func, delay)
					func()
				end)
				ns.acd = {
					OpenFrames = {
						TestAddon = {
							Hide = function() end,
						},
					},
				}
				RLF:OnOptionsOpen(nil, "TestAddon", nil, nil)
				RLF:OnOptionsClose(nil, "TestAddon", nil, nil)
				assert.spy(spySetBoundingBoxViz).was.called_with(_, false)
				assert.spy(spyHook).was.called(1)
			end)
		end)
	end)
end)
