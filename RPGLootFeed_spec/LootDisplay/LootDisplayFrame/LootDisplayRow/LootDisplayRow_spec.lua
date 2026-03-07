local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local rowFrameMocks = require("RPGLootFeed_spec._mocks.Internal.LootDisplayRowFrame")
local assert = require("luassert")
local busted = require("busted")
local match = require("luassert.match")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local stub = busted.stub

local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootDisplayRow.lua"

describe("LootDisplayRowMixin", function()
	local ns, row
	before_each(function()
		-- Define the global G_RLF
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)

		-- Load the module before each test
		assert(loadfile(MIXIN_FILE))("TestAddon", ns)
	end)

	it("loads the file and exposes the global mixin table", function()
		assert.is_not_nil(_G.LootDisplayRowMixin)
	end)

	-- Helper: build a mock row with all the mixin methods mixed in and the
	-- minimal stubs that UpdateQuantity / BootstrapFromElement call.
	-- Returns: row, captures
	-- captures.showText = { r, g, b, a } from the last ShowText call
	-- captures.showAmountText = { text, r, g, b, a } from the last ShowAmountText call
	local function buildRow()
		local r = rowFrameMocks.new()
		local captures = { showText = {}, showAmountText = {} }
		-- Mix LootDisplayRowMixin methods into the mock row
		for k, v in pairs(LootDisplayRowMixin) do
			r[k] = v
		end
		-- Mix RowTextMixin methods (ShowText, ShowAmountText, UpdateSecondaryText, etc.)
		assert(loadfile("RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua"))("TestAddon", ns)
		for k, v in pairs(RLF_RowTextMixin) do
			r[k] = v
		end
		-- Replace ShowText/ShowAmountText with capturing fakes
		r.ShowText = function(self, rawText, cr, cg, cb, ca)
			captures.showText = { text = rawText, r = cr, g = cg, b = cb, a = ca }
		end
		r.ShowAmountText = function(self, amountText, cr, cg, cb, ca)
			captures.showAmountText = { text = amountText, r = cr, g = cg, b = cb, a = ca }
		end
		-- Stub mixin methods that touch UI internals we don't need to exercise
		stub(r, "UpdateSecondaryText")
		stub(r, "UpdateItemCount")
		stub(r, "UpdateStyles")
		stub(r, "StyleText")
		stub(r, "UpdateIcon")
		stub(r, "SetupTooltip")
		stub(r, "LogRow")
		stub(r, "StyleExitAnimation")
		stub(r, "Enter")
		-- PrimaryText:GetAlpha returns 1 so UpdateQuantity doesn't defer
		r.PrimaryText.GetAlpha = function()
			return 1
		end
		-- EnterAnimation / ElementFadeInAnimation not playing
		r.EnterAnimation = {
			IsPlaying = function()
				return false
			end,
		}
		r.ElementFadeInAnimation = {
			IsPlaying = function()
				return false
			end,
		}
		-- ExitAnimation stubs
		r.ExitAnimation = {
			IsPlaying = function()
				return false
			end,
			Stop = function() end,
			Play = function() end,
		}
		-- HighlightAnimation stubs
		r.HighlightAnimation = {
			Stop = function() end,
			Play = function() end,
		}
		-- Stub RunNextFrame to execute immediately
		_G.RunNextFrame = function(fn)
			fn()
		end
		-- Default db settings for animations
		ns.db.global.animations = ns.db.global.animations or {}
		ns.db.global.animations.update = ns.db.global.animations.update or {}
		ns.db.global.animations.update.disableHighlight = true
		-- Make DbAccessor:Animations() return the mock animations table
		ns.DbAccessor.Animations = function(_, frameType)
			return ns.db.global.animations
		end
		return r, captures
	end

	-- ── UpdateQuantity ─────────────────────────────────────────────────────

	describe("UpdateQuantity", function()
		describe("amount accumulation", function()
			it("passes the OLD amount to amountTextFn, not the already-updated value", function()
				local captures
				row, captures = buildRow()
				row.amount = 1

				local receivedAmount
				local element = {
					textFn = function()
						return "text"
					end,
					quantity = 2,
					itemCount = nil,
					r = 1,
					g = 1,
					b = 1,
					a = 1,
					amountTextFn = function(existingQuantity)
						receivedAmount = existingQuantity
						return "x" .. ((existingQuantity or 0) + 2)
					end,
				}

				row:UpdateQuantity(element)

				-- amountTextFn should have received the old amount (1), not 3
				assert.equal(1, receivedAmount)
			end)

			it("updates self.amount to old + element.quantity", function()
				local captures
				row, captures = buildRow()
				row.amount = 5

				local element = {
					textFn = function()
						return "text"
					end,
					quantity = 3,
					itemCount = nil,
					r = 1,
					g = 1,
					b = 1,
					a = 1,
				}

				row:UpdateQuantity(element)

				assert.equal(8, row.amount)
			end)

			it("displays correct cumulative amount text after multiple updates", function()
				local captures
				row, captures = buildRow()
				row.amount = 1

				-- Simulate the real amountTextFn pattern from ItemLoot/Currency/PartyLoot
				local function makeElement(qty)
					return {
						textFn = function()
							return "text"
						end,
						quantity = qty,
						itemCount = nil,
						r = 1,
						g = 1,
						b = 1,
						a = 1,
						amountTextFn = function(existingQuantity)
							local effective = (existingQuantity or 0) + qty
							return "x" .. effective
						end,
					}
				end

				-- First update: 1 existing + 2 new = 3
				row:UpdateQuantity(makeElement(2))
				assert.equal("x3", captures.showAmountText.text)
				assert.equal(3, row.amount)

				-- Second update: 3 existing + 4 new = 7
				row:UpdateQuantity(makeElement(4))
				assert.equal("x7", captures.showAmountText.text)
				assert.equal(7, row.amount)
			end)
		end)

		describe("negative amount coloring", function()
			it("overrides color to red when net amount is negative", function()
				local captures
				row, captures = buildRow()
				row.amount = 5

				local element = {
					textFn = function()
						return "-100 Faction"
					end,
					quantity = -10,
					itemCount = nil,
					r = 0.5,
					g = 0.8,
					b = 0.3,
					a = 1,
				}

				row:UpdateQuantity(element)

				assert.equal(1, captures.showText.r)
				assert.equal(0, captures.showText.g)
				assert.equal(0, captures.showText.b)
				assert.equal(0.8, captures.showText.a)
			end)

			it("preserves element color when net amount is positive", function()
				local captures
				row, captures = buildRow()
				row.amount = 10

				local element = {
					textFn = function()
						return "+5 Faction"
					end,
					quantity = 5,
					itemCount = nil,
					r = 0.2,
					g = 0.6,
					b = 0.9,
					a = 1,
				}

				row:UpdateQuantity(element)

				assert.equal(0.2, captures.showText.r)
				assert.equal(0.6, captures.showText.g)
				assert.equal(0.9, captures.showText.b)
				assert.equal(1, captures.showText.a)
			end)

			it("uses colorFn result when net amount is positive and colorFn is provided", function()
				local captures
				row, captures = buildRow()
				row.amount = -3

				local element = {
					textFn = function()
						return "+10 Money"
					end,
					quantity = 10,
					itemCount = nil,
					r = 1,
					g = 0,
					b = 0,
					a = 1,
					colorFn = function(netQty)
						if netQty < 0 then
							return 1, 0, 0, 1
						else
							return 1, 1, 1, 1
						end
					end,
				}

				row:UpdateQuantity(element)

				-- Net is 7 (positive), colorFn returns white, negative override doesn't trigger
				assert.equal(1, captures.showText.r)
				assert.equal(1, captures.showText.g)
				assert.equal(1, captures.showText.b)
				assert.equal(1, captures.showText.a)
			end)

			it("overrides colorFn color when net amount is still negative", function()
				local captures
				row, captures = buildRow()
				row.amount = -20

				local element = {
					textFn = function()
						return "-15 Money"
					end,
					quantity = -15,
					itemCount = nil,
					r = 0.5,
					g = 0.5,
					b = 0.5,
					a = 1,
					colorFn = function(netQty)
						-- colorFn returns some non-red color
						return 0.5, 0.5, 0.5, 1
					end,
				}

				row:UpdateQuantity(element)

				-- Net is -35 (negative), red override takes priority over colorFn
				assert.equal(1, captures.showText.r)
				assert.equal(0, captures.showText.g)
				assert.equal(0, captures.showText.b)
				assert.equal(0.8, captures.showText.a)
			end)
		end)
	end)

	-- ── BootstrapFromElement ───────────────────────────────────────────────

	describe("BootstrapFromElement", function()
		describe("negative amount coloring", function()
			it("overrides color to red when element quantity is negative", function()
				local captures
				row, captures = buildRow()

				local element = {
					key = "REP_123",
					textFn = function()
						return "-100 Faction"
					end,
					quantity = -100,
					quality = 1,
					r = 0.5,
					g = 0.8,
					b = 0.3,
					a = 1,
					highlight = false,
				}

				row:BootstrapFromElement(element)

				assert.equal(1, captures.showText.r)
				assert.equal(0, captures.showText.g)
				assert.equal(0, captures.showText.b)
				assert.equal(0.8, captures.showText.a)
			end)

			it("preserves element color when element quantity is positive", function()
				local captures
				row, captures = buildRow()

				local element = {
					key = "REP_456",
					textFn = function()
						return "+50 Faction"
					end,
					quantity = 50,
					quality = 1,
					r = 0.2,
					g = 0.6,
					b = 0.9,
					a = 1,
					highlight = false,
				}

				row:BootstrapFromElement(element)

				assert.equal(0.2, captures.showText.r)
				assert.equal(0.6, captures.showText.g)
				assert.equal(0.9, captures.showText.b)
				assert.equal(1, captures.showText.a)
			end)

			it("overrides color to red when element quantity is negative even with nil colors", function()
				local captures
				row, captures = buildRow()

				local element = {
					key = "MONEY",
					textFn = function()
						return "-5g"
					end,
					quantity = -5,
					quality = 1,
					highlight = false,
				}

				row:BootstrapFromElement(element)

				assert.equal(1, captures.showText.r)
				assert.equal(0, captures.showText.g)
				assert.equal(0, captures.showText.b)
				assert.equal(0.8, captures.showText.a)
			end)
		end)
	end)
end)
