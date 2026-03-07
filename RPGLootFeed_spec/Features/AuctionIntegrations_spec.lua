local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local insulate = busted.insulate
local setup = busted.setup
local spy = busted.spy
local stub = busted.stub
local after_each = busted.after_each
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

describe("AuctionIntegrations module", function()
	local _ = match._
	---@type AuctionIntegrations, test_G_RLF
	local AuctionIntegrations, ns

	describe("load order", function()
		it("loads the file successfully", function()
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.FeatureInternals)
			local auctionIntegrationsModule =
				assert(loadfile("RPGLootFeed/Features/ItemLoot/AuctionIntegrations.lua"))("TestAddon", ns)
			assert.is_not_nil(auctionIntegrationsModule)
			assert.is_not_nil(auctionIntegrationsModule.Init)
			assert.is_not_nil(auctionIntegrationsModule.GetAHPrice)
		end)
	end)

	insulate("no integrations installed", function()
		before_each(function()
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
			ns.DbAccessor.AnyFeatureConfig = function(_, featureKey)
				if featureKey == "itemLoot" then
					return ns.db.global.item
				end
				return nil
			end
			ns.db.global.item.auctionHouseSource = nil

			_G.Auctionator = nil
			_G.TSM_API = nil

			-- Load the auction integrations module
			AuctionIntegrations =
				assert(loadfile("RPGLootFeed/Features/ItemLoot/AuctionIntegrations.lua"))("TestAddon", ns)
		end)

		it("initializes correctly with no integrations", function()
			AuctionIntegrations:Init()

			---@diagnostic disable-next-line: invisible
			assert.is_true(AuctionIntegrations.initialized)
			assert.equal(0, AuctionIntegrations.numActiveIntegrations)
			assert.is_nil(AuctionIntegrations.activeIntegration)
		end)

		it("doesn't initialize twice", function()
			AuctionIntegrations:Init()
			local spyLogDebug = spy.on(ns, "LogDebug")

			AuctionIntegrations:Init()

			assert.spy(spyLogDebug).was.not_called()
		end)

		it("falls back to nil integration when preferred source is not available", function()
			-- Set preference to an integration that doesn't exist
			ns.db.global.item.auctionHouseSource = "NonExistentIntegration"

			AuctionIntegrations:Init()

			assert.equal(0, AuctionIntegrations.numActiveIntegrations)
			assert.equal(AuctionIntegrations.activeIntegration, AuctionIntegrations.nilIntegration)
		end)

		it("GetAHPrice returns nil when no active integration", function()
			AuctionIntegrations:Init()

			local price = AuctionIntegrations:GetAHPrice("itemLink")

			assert.is_nil(price)
		end)
	end)

	insulate("only Auctionator installed", function()
		local mockInteg
		before_each(function()
			mockInteg = require("RPGLootFeed_spec._mocks.Libs.Auctionator")
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
			ns.DbAccessor.AnyFeatureConfig = function(_, featureKey)
				if featureKey == "itemLoot" then
					return ns.db.global.item
				end
				return nil
			end
			ns.db.global.item.auctionHouseSource = nil

			_G.TSM_API = nil

			-- Load the auction integrations module
			AuctionIntegrations =
				assert(loadfile("RPGLootFeed/Features/ItemLoot/AuctionIntegrations.lua"))("TestAddon", ns)
		end)

		it("initializes correctly with only Auctionator", function()
			AuctionIntegrations:Init()

			assert.equal(1, AuctionIntegrations.numActiveIntegrations)
			assert.is_not_nil(AuctionIntegrations.activeIntegration)
			assert.equal(AuctionIntegrations.activeIntegration:ToString(), ns.L["Auctionator"])
		end)

		it("calls the active integration's GetAHPrice method", function()
			mockInteg.API.v1.GetAuctionPriceByItemLink.returns(100)
			AuctionIntegrations:Init()
			local spyGetAHPrice = spy.on(AuctionIntegrations.activeIntegration, "GetAHPrice")

			local price = AuctionIntegrations:GetAHPrice("testItemLink")

			assert.spy(spyGetAHPrice).was.called_with(AuctionIntegrations.activeIntegration, "testItemLink")
			assert.equal(100, price)
		end)
	end)

	insulate("only TSM installed", function()
		local mockInteg
		before_each(function()
			mockInteg = require("RPGLootFeed_spec._mocks.Libs.TSM")
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
			ns.DbAccessor.AnyFeatureConfig = function(_, featureKey)
				if featureKey == "itemLoot" then
					return ns.db.global.item
				end
				return nil
			end
			ns.db.global.item.auctionHouseSource = nil

			_G.Auctionator = nil

			-- Load the auction integrations module
			AuctionIntegrations =
				assert(loadfile("RPGLootFeed/Features/ItemLoot/AuctionIntegrations.lua"))("TestAddon", ns)
		end)

		it("initializes correctly with only TSM", function()
			AuctionIntegrations:Init()

			assert.equal(1, AuctionIntegrations.numActiveIntegrations)
			assert.is_not_nil(AuctionIntegrations.activeIntegration)
			assert.equal(AuctionIntegrations.activeIntegration:ToString(), ns.L["TSM"])
		end)

		it("calls the active integration's GetAHPrice method", function()
			local mockInteg = require("RPGLootFeed_spec._mocks.Libs.TSM")
			mockInteg.ToItemString.returns("tsmTestItemString")
			mockInteg.GetCustomPriceValue.returns(200)
			AuctionIntegrations:Init()
			local spyGetAHPrice = spy.on(AuctionIntegrations.activeIntegration, "GetAHPrice")

			local price = AuctionIntegrations:GetAHPrice("testItemLink")

			assert.spy(spyGetAHPrice).was.called_with(AuctionIntegrations.activeIntegration, "testItemLink")
			assert.equal(200, price)
		end)
	end)

	insulate("both Auctionator and TSM installed", function()
		before_each(function()
			require("RPGLootFeed_spec._mocks.Libs.Auctionator")
			require("RPGLootFeed_spec._mocks.Libs.TSM")
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
			ns.DbAccessor.AnyFeatureConfig = function(_, featureKey)
				if featureKey == "itemLoot" then
					return ns.db.global.item
				end
				return nil
			end
			ns.db.global.item.auctionHouseSource = nil

			-- Load the auction integrations module
			AuctionIntegrations =
				assert(loadfile("RPGLootFeed/Features/ItemLoot/AuctionIntegrations.lua"))("TestAddon", ns)
		end)

		it("initializes correctly with both integrations available", function()
			AuctionIntegrations:Init()

			assert.equal(2, AuctionIntegrations.numActiveIntegrations)
			-- When multiple integrations are available but no preference is set,
			-- no specific integration should be selected
			assert.is_nil(AuctionIntegrations.activeIntegration)
		end)

		it("respects saved auction house source preference", function()
			-- Set preference to TSM
			ns.db.global.item.auctionHouseSource = ns.L["TSM"]

			AuctionIntegrations:Init()

			assert.equal(2, AuctionIntegrations.numActiveIntegrations)
			assert.is_not_nil(AuctionIntegrations.activeIntegration)
			assert.equal(AuctionIntegrations.activeIntegration:ToString(), ns.L["TSM"])
		end)

		it("calls the active integration's GetAHPrice method", function()
			ns.db.global.item.auctionHouseSource = ns.L["Auctionator"]

			AuctionIntegrations:Init()
			local spyGetAHPrice = spy.on(AuctionIntegrations.activeIntegration, "GetAHPrice")

			AuctionIntegrations:GetAHPrice("testItemLink")

			assert.spy(spyGetAHPrice).was.called_with(AuctionIntegrations.activeIntegration, "testItemLink")
		end)
	end)
end)
