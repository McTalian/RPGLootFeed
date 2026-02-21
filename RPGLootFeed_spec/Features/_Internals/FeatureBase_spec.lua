local assert = require("luassert")
local busted = require("busted")
local stub = busted.stub
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

describe("FeatureBase", function()
	local ns
	local newModuleStub, mockModule

	before_each(function()
		ns = {
			RLF = {
				NewModule = function() end,
			},
		}

		mockModule = { moduleName = "TestModule" }
		newModuleStub = stub(ns.RLF, "NewModule").returns(mockModule)

		-- Load FeatureBase for real
		assert(loadfile("RPGLootFeed/Features/_Internals/FeatureBase.lua"))("TestAddon", ns)
		assert.is_not_nil(ns.FeatureBase)
	end)

	describe("new()", function()
		it("calls G_RLF.RLF:NewModule with the module name", function()
			ns.FeatureBase:new("TestModule")

			assert.stub(newModuleStub).was.called_with(ns.RLF, "TestModule")
		end)

		it("forwards extra Ace mixin arguments to NewModule", function()
			ns.FeatureBase:new("TestModule", "AceEvent-3.0", "AceHook-3.0")

			assert.stub(newModuleStub).was.called_with(ns.RLF, "TestModule", "AceEvent-3.0", "AceHook-3.0")
		end)

		it("returns the module created by G_RLF.RLF:NewModule", function()
			local result = ns.FeatureBase:new("TestModule")

			assert.are.equal(mockModule, result)
		end)

		it("does not add fn to the returned module", function()
			ns.FeatureBase:new("TestModule")

			assert.is_nil(mockModule.fn)
		end)
	end)
end)
