local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local setup = busted.setup
local spy = busted.spy

describe("AlphaHelpers", function()
	local ns

	setup(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		assert(loadfile("RPGLootFeed/utils/AlphaHelpers.lua"))("TestAddon", ns)
	end)

	describe("dump", function()
		local function parse_dumped_table(dump_string)
			---@diagnostic disable-next-line: undefined-global
			local func, err = load("return " .. dump_string)
			if not func then
				error("Failed to parse dumped table: " .. err)
			end
			return func()
		end

		it("dumps a table to a string", function()
			local t = { key = "value", nested = { 1, 2, 3 } }
			local result = ns.dump(t)

			local parsed = parse_dumped_table(result)

			assert.are.same(parsed, t)
		end)

		it("dumps a non-table value to a string", function()
			local result = ns.dump(123)
			assert.are.equal(result, "123")
		end)
	end)

	describe("ProfileFunction", function()
		it("profiles a function and prints if it takes too long", function()
			local func = function() end
			local profiledFunc = ns:ProfileFunction(func, "testFunc")
			spy.on(ns, "Print")
			profiledFunc()
			assert.spy(ns.Print).was.not_called()
		end)
	end)
end)
