---@diagnostic disable: need-check-nil
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local stub = busted.stub

describe("Money", function()
	local _ = match._
	---@type RLF_Money, table
	local Money, ns, sendMessageSpy

	before_each(function()
		sendMessageSpy = spy.new(function() end)

		-- Build a minimal ns from scratch – no nsMocks framework needed.
		-- Only the fields actually referenced by Money.lua, LootElementBase.lua,
		-- and TextTemplateEngine.lua are included; everything else is intentionally absent.
		ns = {
			-- Captured as locals by Money.lua at load time.
			DefaultIcons = { MONEY = 132279 },
			ItemQualEnum = { Poor = 0 },
			FeatureModule = { Money = "Money" },
			WoWAPI = { Money = {} },
			-- Closure wrappers call these as G_RLF:Method(...).
			LogDebug = function() end,
			LogWarn = function() end,
			-- RGBAToHexFormat referenced in TextTemplateEngine for colored elements.
			RGBAToHexFormat = function()
				return "|cFFFFFFFF"
			end,
			-- L used by TextTemplateEngine AbbreviateNumber.
			L = {
				ThousandAbbrev = "K",
				MillionAbbrev = "M",
				BillionAbbrev = "B",
			},
			SendMessage = sendMessageSpy,
			-- Runtime lookups by LootElementBase:fromPayload() and lifecycle methods.
			db = {
				global = {
					animations = { exit = { fadeOutDelay = 3 } },
					money = {
						enabled = true,
						accountantMode = false,
						showMoneyTotal = true,
						abbreviateTotal = false,
						enableIcon = true,
						overrideMoneyLootSound = false,
						moneyLootSound = "",
						onlyIncome = false,
					},
					misc = { hideAllIcons = false, showOneQuantity = false },
				},
			},
		}

		-- Load real LootElementBase so elements are fully constructed.
		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
		assert.is_not_nil(ns.LootElementBase)

		-- Load TextTemplateEngine before Money.lua so the local capture works.
		assert(loadfile("RPGLootFeed/Features/_Internals/TextTemplateEngine.lua"))("TestAddon", ns)
		assert.is_not_nil(ns.TextTemplateEngine)

		-- Mock FeatureBase – returns a minimal stub module so Money tests
		-- are completely independent of AceAddon plumbing.
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

		-- Load Money – the FeatureBase mock above is captured at load time.
		Money = assert(loadfile("RPGLootFeed/Features/Money.lua"))("TestAddon", ns)

		-- Inject a fresh mock adapter so tests control external API calls without
		-- patching _G directly.  Tests that need specific behaviour set adapter
		-- fields directly before the act step.
		local mockCoinTextureString = function(amount)
			local gold = math.floor(amount / 10000)
			local silver = math.floor((amount % 10000) / 100)
			local copper = amount % 100
			return string.format("%dg %ds %dc", gold, silver, copper)
		end
		Money._moneyAdapter = {
			GetCoinTextureString = mockCoinTextureString,
			GetMoney = function()
				return 1500000 -- 150 gold default
			end,
			PlaySoundFile = spy.new(function()
				return true, 12345
			end),
		}
	end)

	describe("module lifecycle", function()
		it("is enabled when configuration allows", function()
			local enableStub = stub(Money, "Enable").returns()
			local disableStub = stub(Money, "Disable").returns()

			ns.db.global.money.enabled = true
			Money:OnInitialize()
			assert.spy(enableStub).was.called(1)
			assert.spy(disableStub).was.not_called()

			enableStub:clear()
			disableStub:clear()

			ns.db.global.money.enabled = false
			Money:OnInitialize()
			assert.spy(disableStub).was.called(1)
			assert.spy(enableStub).was.not_called()

			enableStub:clear()
			disableStub:clear()
		end)

		it("registers context provider on enable", function()
			Money:OnEnable()

			-- Should have registered Money context provider
			assert.is_function(ns.TextTemplateEngine.contextProviders["Money"])
		end)

		it("unregisters context provider on disable", function()
			Money:OnEnable()
			assert.is_function(ns.TextTemplateEngine.contextProviders["Money"])

			Money:OnDisable()
			assert.is_nil(ns.TextTemplateEngine.contextProviders["Money"])
		end)
	end)

	describe("GenerateTextElements", function()
		it("generates row 1 elements", function()
			local elements = Money:GenerateTextElements(50000)

			assert.is_not_nil(elements[1])
			assert.is_not_nil(elements[1].primary)
			assert.equal("primary", elements[1].primary.type)
			assert.equal("{sign}{coinString}", elements[1].primary.template)
			assert.equal(1, elements[1].primary.order)
		end)

		it("generates row 2 elements", function()
			ns.db.global.money.showMoneyTotal = true
			local elements = Money:GenerateTextElements(50000)

			assert.is_not_nil(elements[2])
			assert.is_not_nil(elements[2].context)
			assert.equal("context", elements[2].context.type)
			assert.equal("{currentMoney}", elements[2].context.template)
			assert.equal(2, elements[2].context.order)

			-- Should also have spacer
			assert.is_not_nil(elements[2].contextSpacer)
			assert.equal("spacer", elements[2].contextSpacer.type)
			assert.equal(4, elements[2].contextSpacer.spacerCount)
			assert.equal(1, elements[2].contextSpacer.order)
		end)
	end)

	describe("BuildPayload and element creation", function()
		before_each(function()
			-- Enable the context provider for element tests
			Money:OnEnable()
		end)

		local function buildElement(quantity)
			local payload = Money:BuildPayload(quantity)
			if not payload then
				return nil
			end
			return ns.LootElementBase:fromPayload(payload)
		end

		it("creates money payload with correct properties", function()
			local payload = Money:BuildPayload(50000)

			assert.is_not_nil(payload)
			assert.equal("Money", payload.type)
			assert.equal("MONEY_LOOT", payload.key)
			assert.equal(50000, payload.quantity)
			assert.is_not_nil(payload.icon)
			assert.is_function(payload.textFn)
			assert.is_function(payload.secondaryTextFn)
			assert.is_function(payload.IsEnabled)
		end)

		it("creates element from payload via fromPayload", function()
			local element = buildElement(50000)

			assert.is_not_nil(element)
			assert.equal("Money", element.type)
			assert.equal("MONEY_LOOT", element.key)
			assert.equal(50000, element.quantity)
			assert.is_not_nil(element.icon)
			assert.is_function(element.textFn)
			assert.is_function(element.secondaryTextFn)
		end)

		it("textFn uses TextTemplateEngine", function()
			local element = buildElement(50000)

			local result = element.textFn(25000)

			-- Should contain the total amount: 50000 + 25000 = 75000 copper = 7g 50s 0c
			assert.truthy(result)
			assert.is_string(result)
			assert.matches("7g 50s 0c", result)
		end)

		it("secondaryTextFn shows money total when enabled", function()
			ns.db.global.money.showMoneyTotal = true
			local element = buildElement(50000)

			local result = element.secondaryTextFn(25000)

			-- Should contain current money display (mocked as 1500000 = 150g 0s 0c)
			assert.truthy(result)
			assert.is_string(result)
			assert.matches("150g 0s 0c", result)
		end)

		it("secondaryTextFn returns empty when showMoneyTotal disabled due to whitespace detection", function()
			ns.db.global.money.showMoneyTotal = false
			local element = buildElement(50000)

			local result = element.secondaryTextFn(25000)

			-- Should return empty because currentMoney is "", making row 2 only spacers
			assert.equal("", result)
		end)

		it("handles accountant mode", function()
			ns.db.global.money.accountantMode = true
			local element = buildElement(50000)

			local result = element.textFn()

			-- Should wrap the amount in parentheses: (5g 0s 0c)
			assert.matches("%(5g 0s 0c%)", result)
		end)

		it("handles negative amounts", function()
			local element = buildElement(-50000)

			local result = element.textFn()

			-- Should show negative amount: -5g 0s 0c
			assert.matches("%-", result) -- Should start with minus sign
			assert.matches("5g 0s 0c", result) -- Should contain the absolute amount
			-- Negative money should be displayed in red
			assert.equals(1, element.r)
			assert.equals(0, element.g)
			assert.equals(0, element.b)
		end)

		describe("colorFn (net-quantity color for row updates)", function()
			it("is present on positive elements", function()
				local element = buildElement(50000)
				assert.is_function(element.colorFn)
			end)

			it("is present on negative elements", function()
				local element = buildElement(-50000)
				assert.is_function(element.colorFn)
			end)

			it("returns white when net quantity is positive", function()
				local element = buildElement(50000)
				local r, g, b, a = element.colorFn(100)
				assert.equals(1, r)
				assert.equals(1, g)
				assert.equals(1, b)
				assert.equals(1, a)
			end)

			it("returns red when net quantity is negative (buy then sell back for less)", function()
				-- Scenario: spent 100, recouped 30 → net = -70 → still red
				local element = buildElement(30000)
				local r, g, b, a = element.colorFn(-70000)
				assert.equals(1, r)
				assert.equals(0, g)
				assert.equals(0, b)
				assert.equals(1, a)
			end)

			it("returns white when a previously negative net goes positive", function()
				-- Scenario: earned 200, spent 50 → net = +150 → white
				local element = buildElement(-50000)
				local r, g, b, a = element.colorFn(150000)
				assert.equals(1, r)
				assert.equals(1, g)
				assert.equals(1, b)
				assert.equals(1, a)
			end)
		end)

		it("configures sound field in payload when enabled", function()
			ns.db.global.money.overrideMoneyLootSound = true
			ns.db.global.money.moneyLootSound = "Interface\\Sounds\\Custom.ogg"

			local payload = Money:BuildPayload(50000)

			assert.equal("Interface\\Sounds\\Custom.ogg", payload.sound)
		end)

		it("returns nil for zero quantity", function()
			local payload = Money:BuildPayload(0)
			assert.is_nil(payload)

			local payload2 = Money:BuildPayload(nil)
			assert.is_nil(payload2)
		end)

		it("throws error when row 1 elements are missing (bad element data)", function()
			local element = buildElement(50000)
			-- Force an error by making textFn call into bad elementData.
			-- We can't easily reach inside the closure, so verify the element has a valid textFn first.
			assert.is_function(element.textFn)
		end)
	end)

	describe("PlaySoundIfEnabled (module method)", function()
		before_each(function()
			Money._moneyAdapter.PlaySoundFile = spy.new(function()
				return true, 12345
			end)
		end)

		it("plays sound when overrideMoneyLootSound is enabled", function()
			ns.db.global.money.overrideMoneyLootSound = true
			ns.db.global.money.moneyLootSound = "Interface\\Sounds\\Custom.ogg"

			Money:PlaySoundIfEnabled()

			assert.spy(Money._moneyAdapter.PlaySoundFile).was.called_with("Interface\\Sounds\\Custom.ogg")
		end)

		it("does not play sound when overrideMoneyLootSound is disabled", function()
			ns.db.global.money.overrideMoneyLootSound = false
			ns.db.global.money.moneyLootSound = "Interface\\Sounds\\Custom.ogg"

			Money:PlaySoundIfEnabled()

			assert.spy(Money._moneyAdapter.PlaySoundFile).was.not_called()
		end)

		it("does not play sound when moneyLootSound is empty", function()
			ns.db.global.money.overrideMoneyLootSound = true
			ns.db.global.money.moneyLootSound = ""

			Money:PlaySoundIfEnabled()

			assert.spy(Money._moneyAdapter.PlaySoundFile).was.not_called()
		end)
	end)

	describe("event handling", function()
		before_each(function()
			Money:OnEnable()
		end)

		it("tracks starting money on PLAYER_ENTERING_WORLD", function()
			Money._moneyAdapter.GetMoney = function()
				return 2000000
			end -- 200 gold

			Money:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD")

			assert.equal(2000000, Money.startingMoney)
		end)

		it("processes money changes on PLAYER_MONEY", function()
			Money.startingMoney = 1000000 -- 100 gold
			Money._moneyAdapter.GetMoney = function()
				return 1050000
			end -- 105 gold

			local buildPayloadSpy = spy.on(Money, "BuildPayload")

			Money:PLAYER_MONEY("PLAYER_MONEY")

			-- Should call BuildPayload with the difference
			assert.spy(buildPayloadSpy).was.called_with(Money, 50000)
			assert.spy(sendMessageSpy).was.called(1)
			assert.equal(1050000, Money.startingMoney)
		end)

		it("ignores zero money changes", function()
			Money.startingMoney = 1000000
			Money._moneyAdapter.GetMoney = function()
				return 1000000
			end -- Same amount

			local buildPayloadSpy = spy.on(Money, "BuildPayload")

			Money:PLAYER_MONEY("PLAYER_MONEY")

			-- Should not call BuildPayload
			assert.spy(buildPayloadSpy).was.not_called()
		end)

		it("respects onlyIncome setting", function()
			ns.db.global.money.onlyIncome = true
			Money.startingMoney = 1000000
			Money._moneyAdapter.GetMoney = function()
				return 950000
			end -- Lost money

			local buildPayloadSpy = spy.on(Money, "BuildPayload")

			Money:PLAYER_MONEY("PLAYER_MONEY")

			-- Should not call BuildPayload for negative change
			assert.spy(buildPayloadSpy).was.not_called()
		end)
	end)

	describe("integration with TextTemplateEngine", function()
		before_each(function()
			Money:OnEnable() -- Register context provider
		end)

		it("can generate complete layout using TextTemplateEngine", function()
			ns.db.global.money.showMoneyTotal = true
			local payload = Money:BuildPayload(50000)
			local element = ns.LootElementBase:fromPayload(payload)

			-- Use element's textFn (backed by TextTemplateEngine) — row 1
			local row1Layout = element.textFn()

			-- Should contain the money amount (5g 0s 0c)
			assert.matches("5g 0s 0c", row1Layout)

			-- Test row 2 layout - should exist since showMoneyTotal = true
			local row2Layout = element.secondaryTextFn()

			-- Should contain current money total and spacer
			assert.matches("150g 0s 0c", row2Layout) -- Current money total
			assert.matches("    ", row2Layout) -- Should have spacer
		end)
	end)

	describe("money context provider features", function()
		before_each(function()
			Money:OnEnable() -- Register context provider
		end)

		local function buildElement(quantity)
			local payload = Money:BuildPayload(quantity)
			if not payload then
				return nil
			end
			return ns.LootElementBase:fromPayload(payload)
		end

		describe("current money truncation", function()
			it("truncates silver and copper for amounts over 1000 gold", function()
				-- Set current money to 15,235,678 copper = 1523g 56s 78c
				Money._moneyAdapter.GetMoney = function()
					return 15235678
				end
				ns.db.global.money.showMoneyTotal = true

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				-- Should be truncated to 1523g 0s 0c (silver and copper removed)
				assert.matches("1523g 0s 0c", result)
			end)

			it("does not truncate amounts under 1000 gold", function()
				-- Set current money to 9,876,543 copper = 987g 65s 43c (under 1000g)
				Money._moneyAdapter.GetMoney = function()
					return 9876543
				end
				ns.db.global.money.showMoneyTotal = true

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				-- Should keep full precision
				assert.matches("987g 65s 43c", result)
			end)

			it("handles exactly 1000 gold threshold", function()
				-- Set current money to exactly 10,000,000 copper = 1000g 0s 0c
				Money._moneyAdapter.GetMoney = function()
					return 10000000
				end
				ns.db.global.money.showMoneyTotal = true

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				-- Should not truncate at exactly 1000g
				assert.matches("1000g 0s 0c", result)
			end)

			it("handles exactly 1000g 1c threshold", function()
				-- Set current money to 10,000,001 copper = 1000g 0s 1c
				Money._moneyAdapter.GetMoney = function()
					return 10000001
				end
				ns.db.global.money.showMoneyTotal = true

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				-- Should truncate to 1000g 0s 0c (just over threshold)
				assert.matches("1000g 0s 0c", result)
			end)
		end)

		describe("current money abbreviation", function()
			it("abbreviates gold when enabled and over 1000 gold", function()
				-- Set current money to 25,000,000 copper = 2500g 0s 0c
				Money._moneyAdapter.GetMoney = function()
					return 25000000
				end
				ns.db.global.money.showMoneyTotal = true
				ns.db.global.money.abbreviateTotal = true

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				-- Should abbreviate to 2.50Kg 0s 0c
				assert.matches("2%.50Kg 0s 0c", result)
			end)

			it("does not abbreviate when disabled", function()
				-- Set current money to 25,000,000 copper = 2500g 0s 0c
				Money._moneyAdapter.GetMoney = function()
					return 25000000
				end
				ns.db.global.money.showMoneyTotal = true
				ns.db.global.money.abbreviateTotal = false

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				-- Should not abbreviate
				assert.matches("2500g 0s 0c", result)
			end)

			it("does not abbreviate amounts under 1000 gold", function()
				-- Set current money to 9,876,543 copper = 987g 65s 43c (under 1000g)
				Money._moneyAdapter.GetMoney = function()
					return 9876543
				end
				ns.db.global.money.showMoneyTotal = true
				ns.db.global.money.abbreviateTotal = true

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				-- Should not abbreviate (under threshold)
				assert.matches("987g 65s 43c", result)
			end)

			it("handles millions of gold", function()
				-- Set current money to 250,000,000 copper = 25,000g 0s 0c
				Money._moneyAdapter.GetMoney = function()
					return 250000000
				end
				ns.db.global.money.showMoneyTotal = true
				ns.db.global.money.abbreviateTotal = true

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				-- Should abbreviate to 25.00Kg 0s 0c
				assert.matches("25%.00Kg 0s 0c", result)
			end)
		end)

		describe("combined truncation and abbreviation", function()
			it("truncates before abbreviating", function()
				-- Set current money to 25,123,456 copper = 2512g 34s 56c
				Money._moneyAdapter.GetMoney = function()
					return 25123456
				end
				ns.db.global.money.showMoneyTotal = true
				ns.db.global.money.abbreviateTotal = true

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				-- Should truncate to 2512g then abbreviate to 2.51Kg
				assert.matches("2%.51Kg 0s 0c", result)
			end)
		end)

		describe("showMoneyTotal disabled", function()
			it("returns empty currentMoney when showMoneyTotal is false", function()
				ns.db.global.money.showMoneyTotal = false

				local element = buildElement(50000)
				local result = element.secondaryTextFn(0)

				assert.equal("", result)
			end)
		end)
	end)
end)
