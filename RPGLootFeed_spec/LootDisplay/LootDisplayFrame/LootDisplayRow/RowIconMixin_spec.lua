local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local rowFrameMocks = require("RPGLootFeed_spec._mocks.Internal.LootDisplayRowFrame")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local stub = busted.stub

local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowIconMixin.lua"

describe("RLF_RowIconMixin", function()
	local ns, row

	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		assert(loadfile(MIXIN_FILE))("TestAddon", ns)
		row = rowFrameMocks.new()
	end)

	describe("load order", function()
		it("loads the file and exposes the global mixin table", function()
			assert.is_not_nil(_G.RLF_RowIconMixin)
			assert.is_function(RLF_RowIconMixin.StyleIcon)
			assert.is_function(RLF_RowIconMixin.UpdateIcon)
		end)
	end)

	-- ── StyleIcon ──────────────────────────────────────────────────────────

	describe("StyleIcon", function()
		local sizingDb, stylingDb

		before_each(function()
			sizingDb = { iconSize = 32 }
			stylingDb = { leftAlign = true }
			stub(ns.DbAccessor, "Sizing").returns(sizingDb)
			stub(ns.DbAccessor, "Styling").returns(stylingDb)
		end)

		it("calls SetSize on first call", function()
			RLF_RowIconMixin.StyleIcon(row)
			assert.stub(row.Icon.SetSize).was.called(1)
		end)

		it("calls SetPoint on first call", function()
			RLF_RowIconMixin.StyleIcon(row)
			assert.stub(row.Icon.SetPoint).was.called(1)
		end)

		it("calls ClearAllPoints on first call", function()
			RLF_RowIconMixin.StyleIcon(row)
			assert.stub(row.Icon.ClearAllPoints).was.called(1)
		end)

		it("skips SetSize on a second call when nothing changed (cache hit)", function()
			RLF_RowIconMixin.StyleIcon(row)
			row.Icon.SetSize:clear()
			RLF_RowIconMixin.StyleIcon(row)
			assert.stub(row.Icon.SetSize).was_not.called()
		end)

		it("calls SetSize again when iconSize changes", function()
			RLF_RowIconMixin.StyleIcon(row)
			row.Icon.SetSize:clear()
			sizingDb.iconSize = 64
			RLF_RowIconMixin.StyleIcon(row)
			assert.stub(row.Icon.SetSize).was.called(1)
		end)

		it("calls SetSize again when leftAlign changes", function()
			RLF_RowIconMixin.StyleIcon(row)
			row.Icon.SetSize:clear()
			stylingDb.leftAlign = false
			RLF_RowIconMixin.StyleIcon(row)
			assert.stub(row.Icon.SetSize).was.called(1)
		end)

		it("calls PerfPixel.PScale to scale the icon size", function()
			RLF_RowIconMixin.StyleIcon(row)
			assert.stub(nsMocks.PerfPixel.PScale).was.called()
		end)

		it("shows the Icon when self.icon is set", function()
			local capturedArg
			stub(row.Icon, "SetShown", function(_, val)
				capturedArg = val
			end)
			row.icon = "Interface/Icons/INV_Misc_QuestionMark"
			RLF_RowIconMixin.StyleIcon(row)
			assert.is_true(capturedArg)
		end)

		it("hides the Icon when self.icon is nil", function()
			local capturedArg
			stub(row.Icon, "SetShown", function(_, val)
				capturedArg = val
			end)
			row.icon = nil
			RLF_RowIconMixin.StyleIcon(row)
			assert.is_false(capturedArg)
		end)

		it("adds Icon to Masque iconGroup when both are available", function()
			-- ns.iconGroup is not set by the namespace mock (Core.lua sets it at
			-- runtime via Masque:Group); wire it up here so StyleIcon can reach it.
			local called = false
			ns.iconGroup = {
				AddButton = function()
					called = true
				end,
			}
			RLF_RowIconMixin.StyleIcon(row)
			assert.is_true(called)
		end)
	end)

	-- ── UpdateIcon ─────────────────────────────────────────────────────────
	-- RunNextFrame executes synchronously in tests, so the deferred callback runs.

	describe("UpdateIcon", function()
		before_each(function()
			stub(ns.DbAccessor, "Sizing").returns({ iconSize = 32 })
			stub(ns.DbAccessor, "Styling").returns({
				enableTopLeftIconText = false,
				topLeftIconTextUseQualityColor = false,
				topLeftIconTextColor = { 1, 1, 1, 1 },
			})
		end)

		it("stores the icon on self", function()
			RLF_RowIconMixin.UpdateIcon(row, "key1", "Interface/Icons/Foo", nil)
			assert.equal("Interface/Icons/Foo", row.icon)
		end)

		it("calls SetItemButtonTexture when quality is provided", function()
			row.link = "|Hitem:123|h[Foo]|h"
			RLF_RowIconMixin.UpdateIcon(row, "key1", "Interface/Icons/Foo", 4)
			assert.stub(row.Icon.SetItemButtonTexture).was.called(1)
		end)

		it("calls SetItem (no quality) when quality is nil", function()
			row.link = "|Hitem:123|h[Foo]|h"
			RLF_RowIconMixin.UpdateIcon(row, "key1", "Interface/Icons/Foo", nil)
			assert.stub(row.Icon.SetItem).was.called(1)
		end)

		it("hides topLeftText when enableTopLeftIconText is false", function()
			RLF_RowIconMixin.UpdateIcon(row, "key1", "Interface/Icons/Foo", 2)
			assert.stub(row.Icon.topLeftText.Hide).was.called(1)
		end)

		it("shows topLeftText when conditions are met", function()
			stub(ns.DbAccessor, "Styling").returns({
				enableTopLeftIconText = true,
				topLeftIconTextUseQualityColor = false,
				topLeftIconTextColor = { 1, 1, 1, 1 },
			})
			row.topLeftText = "x5"
			row.topLeftColor = { 1, 0.82, 0 }
			RLF_RowIconMixin.UpdateIcon(row, "key1", "Interface/Icons/Foo", 2)
			assert.stub(row.Icon.topLeftText.Show).was.called(1)
		end)
	end)
end)
