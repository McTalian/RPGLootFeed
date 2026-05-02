local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local before_each = busted.before_each
local setup = busted.setup
local stub = require("luassert.stub")

describe("LootRollsConfig module", function()
	local ns, lootRollsDb

	setup(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeaturesInit)
		assert(loadfile("RPGLootFeed/config/common/common.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/common/db.utils.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/common/styling.base.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Features/LootRollsConfig.lua"))("TestAddon", ns)

		-- Stub LootDisplay and DbAccessor used by set handlers
		ns.LootDisplay = ns.LootDisplay or {}
		ns.LootDisplay.RefreshSampleRowsIfShown = function() end
		ns.DbAccessor = ns.DbAccessor or {}
		ns.DbAccessor.UpdateFeatureModuleState = function() end
	end)

	before_each(function()
		-- Fresh per-frame lootRolls db from defaults for each test
		local defaults = ns.defaults.global.frames["**"].features.lootRolls
		lootRollsDb = {
			enabled = defaults.enabled,
			enableIcon = defaults.enableIcon,
			enableLootRollActions = defaults.enableLootRollActions,
			disableLootRollFrame = defaults.disableLootRollFrame,
			enableLootRollResults = defaults.enableLootRollResults,
			backgroundOverride = {
				enabled = false,
				gradientStart = { 0.1, 0.1, 0.1, 0.8 },
				gradientEnd = { 0.1, 0.1, 0.1, 0 },
				textureColor = { 0, 0, 0, 1 },
			},
		}
		ns.db = {
			global = {
				frames = { [1] = { features = { lootRolls = lootRollsDb } } },
				misc = { hideAllIcons = false },
			},
		}
	end)

	describe("defaults", function()
		it("includes enableLootRollActions defaulting to false", function()
			local defaults = ns.defaults.global.frames["**"].features.lootRolls
			assert.is_boolean(defaults.enableLootRollActions)
			assert.is_false(defaults.enableLootRollActions)
		end)

		it("includes disableLootRollFrame defaulting to false", function()
			local defaults = ns.defaults.global.frames["**"].features.lootRolls
			assert.is_boolean(defaults.disableLootRollFrame)
			assert.is_false(defaults.disableLootRollFrame)
		end)

		it("includes enableLootRollResults defaulting to true", function()
			local defaults = ns.defaults.global.frames["**"].features.lootRolls
			assert.is_boolean(defaults.enableLootRollResults)
			assert.is_true(defaults.enableLootRollResults)
		end)
	end)

	describe("BuildLootRollsArgs", function()
		it("exports a BuildLootRollsArgs builder function", function()
			assert.is_function(ns.BuildLootRollsArgs)
		end)

		it("returns a valid options group", function()
			local group = ns.BuildLootRollsArgs(1, 11)
			assert.is_table(group)
			assert.equal("group", group.type)
			assert.equal(11, group.order)
			assert.is_table(group.args)
		end)

		describe("hidden function (Retail guard)", function()
			it("is hidden on non-Retail clients", function()
				stub(ns, "IsRetail").returns(false)
				local group = ns.BuildLootRollsArgs(1, 11)
				assert.is_true(group.hidden())
				ns.IsRetail:revert()
			end)

			it("is visible on Retail clients", function()
				-- IsRetail already returns true in the mock (default)
				local group = ns.BuildLootRollsArgs(1, 11)
				assert.is_false(group.hidden())
			end)
		end)

		describe("enableLootRollActions toggle", function()
			it("is present in lootRollsOptions args", function()
				local group = ns.BuildLootRollsArgs(1, 11)
				local toggle = group.args.lootRollsOptions.args.enableLootRollActions
				assert.is_table(toggle)
				assert.equal("toggle", toggle.type)
			end)

			it("has order 3", function()
				local group = ns.BuildLootRollsArgs(1, 11)
				assert.equal(3, group.args.lootRollsOptions.args.enableLootRollActions.order)
			end)

			it("get returns false by default", function()
				local group = ns.BuildLootRollsArgs(1, 11)
				local toggle = group.args.lootRollsOptions.args.enableLootRollActions
				assert.is_false(toggle.get())
			end)

			it("set writes to db and calls RefreshSampleRowsIfShown", function()
				local refreshCalled = false
				ns.LootDisplay.RefreshSampleRowsIfShown = function()
					refreshCalled = true
				end
				local group = ns.BuildLootRollsArgs(1, 11)
				group.args.lootRollsOptions.args.enableLootRollActions.set(nil, true)
				assert.is_true(lootRollsDb.enableLootRollActions)
				assert.is_true(refreshCalled)
			end)

			it("get reflects value set in db", function()
				lootRollsDb.enableLootRollActions = true
				local group = ns.BuildLootRollsArgs(1, 11)
				assert.is_true(group.args.lootRollsOptions.args.enableLootRollActions.get())
			end)
		end)

		describe("disableLootRollFrame toggle", function()
			it("is present in lootRollsOptions args", function()
				local group = ns.BuildLootRollsArgs(1, 11)
				local toggle = group.args.lootRollsOptions.args.disableLootRollFrame
				assert.is_table(toggle)
				assert.equal("toggle", toggle.type)
			end)

			it("has order 4", function()
				local group = ns.BuildLootRollsArgs(1, 11)
				assert.equal(4, group.args.lootRollsOptions.args.disableLootRollFrame.order)
			end)

			it("get returns false by default", function()
				local group = ns.BuildLootRollsArgs(1, 11)
				local toggle = group.args.lootRollsOptions.args.disableLootRollFrame
				assert.is_false(toggle.get())
			end)

			it("is disabled when enableLootRollActions is false", function()
				lootRollsDb.enableLootRollActions = false
				local group = ns.BuildLootRollsArgs(1, 11)
				local toggle = group.args.lootRollsOptions.args.disableLootRollFrame
				assert.is_true(toggle.disabled())
			end)

			it("is enabled when enableLootRollActions is true", function()
				lootRollsDb.enableLootRollActions = true
				local group = ns.BuildLootRollsArgs(1, 11)
				local toggle = group.args.lootRollsOptions.args.disableLootRollFrame
				assert.is_false(toggle.disabled())
			end)

			it("set writes to db and calls RefreshSampleRowsIfShown", function()
				local refreshCalled = false
				ns.LootDisplay.RefreshSampleRowsIfShown = function()
					refreshCalled = true
				end
				local group = ns.BuildLootRollsArgs(1, 11)
				group.args.lootRollsOptions.args.disableLootRollFrame.set(nil, true)
				assert.is_true(lootRollsDb.disableLootRollFrame)
				assert.is_true(refreshCalled)
			end)

			it("get reflects value set in db", function()
				lootRollsDb.disableLootRollFrame = true
				local group = ns.BuildLootRollsArgs(1, 11)
				assert.is_true(group.args.lootRollsOptions.args.disableLootRollFrame.get())
			end)

			it("set toggles off correctly", function()
				lootRollsDb.disableLootRollFrame = true
				local group = ns.BuildLootRollsArgs(1, 11)
				group.args.lootRollsOptions.args.disableLootRollFrame.set(nil, false)
				assert.is_false(lootRollsDb.disableLootRollFrame)
			end)
		end)

		describe("enableLootRollResults toggle", function()
			it("is present in lootRollsOptions args", function()
				local group = ns.BuildLootRollsArgs(1, 11)
				local toggle = group.args.lootRollsOptions.args.enableLootRollResults
				assert.is_table(toggle)
				assert.equal("toggle", toggle.type)
			end)

			it("has order 5", function()
				local group = ns.BuildLootRollsArgs(1, 11)
				assert.equal(5, group.args.lootRollsOptions.args.enableLootRollResults.order)
			end)

			it("get returns true by default (backward compat)", function()
				local group = ns.BuildLootRollsArgs(1, 11)
				local toggle = group.args.lootRollsOptions.args.enableLootRollResults
				assert.is_true(toggle.get())
			end)

			it("set writes to db and calls RefreshSampleRowsIfShown", function()
				local refreshCalled = false
				ns.LootDisplay.RefreshSampleRowsIfShown = function()
					refreshCalled = true
				end
				local group = ns.BuildLootRollsArgs(1, 11)
				group.args.lootRollsOptions.args.enableLootRollResults.set(nil, false)
				assert.is_false(lootRollsDb.enableLootRollResults)
				assert.is_true(refreshCalled)
			end)

			it("get reflects value set in db", function()
				lootRollsDb.enableLootRollResults = false
				local group = ns.BuildLootRollsArgs(1, 11)
				assert.is_false(group.args.lootRollsOptions.args.enableLootRollResults.get())
			end)

			it("set toggles back on correctly", function()
				lootRollsDb.enableLootRollResults = false
				local group = ns.BuildLootRollsArgs(1, 11)
				group.args.lootRollsOptions.args.enableLootRollResults.set(nil, true)
				assert.is_true(lootRollsDb.enableLootRollResults)
			end)
		end)
	end)
end)
