local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local rowFrameMocks = require("RPGLootFeed_spec._mocks.Internal.LootDisplayRowFrame")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local stub = busted.stub

local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTooltipMixin.lua"

describe("RLF_RowTooltipMixin", function()
	local ns, row

	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		assert(loadfile(MIXIN_FILE))("TestAddon", ns)
		row = rowFrameMocks.new()
	end)

	describe("load order", function()
		it("loads the file and exposes the global mixin table", function()
			assert.is_not_nil(_G.RLF_RowTooltipMixin)
			assert.is_function(RLF_RowTooltipMixin.SetupTooltip)
		end)
	end)

	-- ── SetupTooltip ───────────────────────────────────────────────────────

	describe("SetupTooltip", function()
		describe("when self.link is nil", function()
			before_each(function()
				row.link = nil
			end)

			it("returns early without touching ClickableButton", function()
				RLF_RowTooltipMixin.SetupTooltip(row)
				assert.stub(row.ClickableButton.ClearAllPoints).was_not.called()
				assert.stub(row.ClickableButton.SetScript).was_not.called()
			end)

			it("does not show ClickableButton", function()
				RLF_RowTooltipMixin.SetupTooltip(row)
				assert.stub(row.ClickableButton.Show).was_not.called()
			end)
		end)

		describe("when self.link is set", function()
			before_each(function()
				row.link = "|Hitem:18803|h[Finkle's Lava Dredger]|h"
			end)

			it("clears existing anchors on ClickableButton", function()
				RLF_RowTooltipMixin.SetupTooltip(row)
				assert.stub(row.ClickableButton.ClearAllPoints).was.called(1)
			end)

			it("sets ClickableButton position via SetPoint", function()
				RLF_RowTooltipMixin.SetupTooltip(row)
				assert.stub(row.ClickableButton.SetPoint).was.called(1)
			end)

			it("sizes ClickableButton to match PrimaryText dimensions", function()
				-- PrimaryText:GetStringWidth() returns 100, GetStringHeight() returns 20.
				RLF_RowTooltipMixin.SetupTooltip(row)
				assert.stub(row.ClickableButton.SetSize).was.called(1)
			end)

			it("shows ClickableButton", function()
				RLF_RowTooltipMixin.SetupTooltip(row)
				assert.stub(row.ClickableButton.Show).was.called(1)
			end)

			it("installs OnEnter, OnLeave, OnEvent, OnMouseUp scripts on ClickableButton", function()
				RLF_RowTooltipMixin.SetupTooltip(row)
				-- Four SetScript calls: OnEnter, OnLeave, OnEvent, OnMouseUp.
				assert.stub(row.ClickableButton.SetScript).was.called(4)
			end)

			it("installs scripts on Icon when self.Icon is present", function()
				RLF_RowTooltipMixin.SetupTooltip(row)
				-- Four SetScript calls on Icon: OnEnter, OnLeave, OnEvent, OnMouseUp.
				assert.stub(row.Icon.SetScript).was.called(4)
			end)

			it("does not error when self.Icon is nil", function()
				row.Icon = nil
				assert.has_no.errors(function()
					RLF_RowTooltipMixin.SetupTooltip(row)
				end)
			end)

			it("accepts isHistoryFrame=true without errors", function()
				assert.has_no.errors(function()
					RLF_RowTooltipMixin.SetupTooltip(row, true)
				end)
			end)
		end)
	end)
end)
