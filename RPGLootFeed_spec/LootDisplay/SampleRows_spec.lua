---@diagnostic disable: need-check-nil
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

-- ── Helpers ───────────────────────────────────────────────────────────────────
-- Minimal text elements that mirror what Money:GenerateTextElements returns,
-- so we don't need to load the full Money module.
local function makeMockMoneyTextElements()
	return {
		[1] = { primary = { type = "primary", template = "{coinString}{sign}", order = 1 } },
		[2] = {
			contextSpacer = { type = "spacer", spacerCount = 4, order = 1 },
			context = { type = "context", template = "{currentMoney}", order = 2 },
		},
	}
end

describe("SampleRows", function()
	---@type table Captured payloads from LootElementBase:fromPayload stubs.
	local capturedPayloads
	---@type table Minimal addon namespace
	local ns
	---@type table Mock Money module
	local mockMoneyModule

	before_each(function()
		capturedPayloads = {}

		mockMoneyModule = {
			IsEnabled = function()
				return true
			end,
			GenerateTextElements = function(_, _quantity)
				return makeMockMoneyTextElements()
			end,
		}

		-- Build a minimal ns with only the fields actually referenced inside
		-- LootDisplay:CreateSampleRows.  All features except money are disabled
		-- so only the money branch executes.
		ns = {
			LootDisplay = {},
			DefaultIcons = { MONEY = 132279, CURRENCY = 131919, XP = 135925 },
			ItemQualEnum = { Poor = 0, Common = 1, Rare = 3, Epic = 4 },
			FeatureModule = {
				Money = "Money",
				Currency = "Currency",
				ItemLoot = "ItemLoot",
				PartyLoot = "PartyLoot",
				Experience = "Experience",
				Reputation = "Reputation",
				Profession = "Profession",
				TravelPoints = "TravelPoints",
				Transmog = "Transmog",
			},
			-- L falls back to the key itself so any string lookup works without a locale file.
			L = setmetatable({}, {
				__index = function(_, k)
					return k
				end,
			}),
			db = {
				global = {
					misc = { hideAllIcons = false },
					frames = {
						[1] = {
							features = {
								money = { enabled = true },
								itemLoot = { enabled = false },
								partyLoot = { enabled = false },
								currency = { enabled = false },
								experience = { enabled = false },
								reputation = { enabled = false },
								profession = { enabled = false },
								travelPoints = { enabled = false },
								transmog = { enabled = false },
							},
						},
					},
					money = {
						enabled = true,
						accountantMode = false,
						showMoneyTotal = true,
						abbreviateTotal = false,
					},
				},
			},
			RLF = {
				GetModule = function(_, name)
					if name == "Money" then
						return mockMoneyModule
					end
					return nil
				end,
			},
			DbAccessor = {
				Feature = function(_, _frame, _featureKey)
					-- Return empty table for all feature-specific config lookups.
					return {}
				end,
				AnyFeatureConfig = function(_, featureKey)
					if featureKey == "money" then
						return ns.db.global.money
					end
					return {}
				end,
			},
			TextTemplateEngine = {
				ProcessRowElements = function(_, _row, _elementData, _existingCopper)
					return ""
				end,
				AbbreviateNumber = function(_, n)
					return string.format("%.2fK", n / 1000)
				end,
			},
			-- Stub so RGBAToHexFormat calls in disabled-but-present code paths are safe.
			RGBAToHexFormat = function()
				return "|cFFFFFFFF"
			end,
		}

		-- fromPayload captures its argument so tests can inspect the payload.
		ns.LootElementBase = {
			fromPayload = function(self, payload)
				table.insert(capturedPayloads, payload)
				return { Show = function() end }
			end,
		}

		-- Loading SampleRows attaches CreateSampleRows to ns.LootDisplay.
		assert(loadfile("RPGLootFeed/LootDisplay/SampleRows.lua"))("TestAddon", ns)
	end)

	--- Run CreateSampleRows and return the money payload, or nil if not found.
	local function getMoneyPayload()
		capturedPayloads = {}
		ns.LootDisplay:CreateSampleRows(1)
		for _, p in ipairs(capturedPayloads) do
			if p.type == ns.FeatureModule.Money then
				return p
			end
		end
		return nil
	end

	-- ── Money sample row ──────────────────────────────────────────────────────

	describe("Money sample row payload structure", function()
		it("is produced when money is enabled", function()
			local payload = getMoneyPayload()
			assert.is_not_nil(payload)
		end)

		it("has the correct type and key", function()
			local payload = getMoneyPayload()
			assert.equal(ns.FeatureModule.Money, payload.type)
			assert.equal("sample_money_loot", payload.key)
		end)

		it("is flagged as a sample row", function()
			local payload = getMoneyPayload()
			assert.is_true(payload.isSampleRow)
		end)

		it("has textFn", function()
			local payload = getMoneyPayload()
			assert.is_function(payload.textFn)
		end)

		-- ── Coin display callbacks (regression guard for the coin-string refactor) ──

		it("has coinDataFn", function()
			local payload = getMoneyPayload()
			assert.is_function(payload.coinDataFn)
		end)

		it("has secondaryCoinDataFn", function()
			local payload = getMoneyPayload()
			assert.is_function(payload.secondaryCoinDataFn)
		end)

		it("has amountTextFn", function()
			local payload = getMoneyPayload()
			assert.is_function(payload.amountTextFn)
		end)
	end)

	describe("Money sample row coinDataFn", function()
		-- quantity = 12345 copper  →  1g 23s 45c
		it("returns correct gold for 12345 copper with no existing amount", function()
			local payload = getMoneyPayload()
			local gold = payload.coinDataFn(0)
			assert.equal(1, gold)
		end)

		it("returns correct silver for 12345 copper with no existing amount", function()
			local payload = getMoneyPayload()
			local _, silver = payload.coinDataFn(0)
			assert.equal(23, silver)
		end)

		it("returns correct copper for 12345 copper with no existing amount", function()
			local payload = getMoneyPayload()
			local _, _, copper = payload.coinDataFn(0)
			assert.equal(45, copper)
		end)

		it("uses absolute value so negative net amounts still display positive coins", function()
			local payload = getMoneyPayload()
			-- net = -12345 + 12345 = 0 → edge case; use a negative existing amount
			local gold, silver, copper = payload.coinDataFn(-100)
			-- abs(-100 + 12345) = 12245 → 1g 22s 45c
			assert.equal(1, gold)
			assert.equal(22, silver)
			assert.equal(45, copper)
		end)
	end)

	describe("Money sample row secondaryTextFn", function()
		it("returns a single space when showMoneyTotal is true", function()
			ns.db.global.money.showMoneyTotal = true
			local payload = getMoneyPayload()
			assert.equal(" ", payload.secondaryTextFn())
		end)

		it("returns empty string when showMoneyTotal is false", function()
			ns.db.global.money.showMoneyTotal = false
			local payload = getMoneyPayload()
			assert.equal("", payload.secondaryTextFn())
		end)
	end)

	describe("Money sample row secondaryCoinDataFn", function()
		it("returns nil when showMoneyTotal is false", function()
			ns.db.global.money.showMoneyTotal = false
			local payload = getMoneyPayload()
			assert.is_nil(payload.secondaryCoinDataFn())
		end)

		it("returns numeric denomination values when showMoneyTotal is true", function()
			ns.db.global.money.showMoneyTotal = true
			local payload = getMoneyPayload()
			local gold, silver, copper = payload.secondaryCoinDataFn()
			-- sampleTotal = 1234567 copper  →  123g 45s 67c
			assert.equal(123, gold)
			assert.equal(45, silver)
			assert.equal(67, copper)
		end)

		it("returns nil goldText when abbreviateTotal is false", function()
			ns.db.global.money.showMoneyTotal = true
			ns.db.global.money.abbreviateTotal = false
			local payload = getMoneyPayload()
			local _, _, _, _, _, goldText = payload.secondaryCoinDataFn()
			assert.is_nil(goldText)
		end)

		it("returns nil goldText when abbreviateTotal is true but gold < 1000", function()
			-- sampleTotal = 123g, which is below the 1000g abbreviation threshold
			ns.db.global.money.showMoneyTotal = true
			ns.db.global.money.abbreviateTotal = true
			local payload = getMoneyPayload()
			local _, _, _, _, _, goldText = payload.secondaryCoinDataFn()
			assert.is_nil(goldText)
		end)
	end)

	describe("Money sample row amountTextFn", function()
		-- The sample uses quantity = 12345 (positive), so accountant mode never
		-- wraps it in parens — positive amounts are always displayed plain.
		it("returns empty string in accountant mode for a positive sample amount", function()
			ns.db.global.money.accountantMode = true
			local payload = getMoneyPayload()
			assert.equal("", payload.amountTextFn())
		end)

		it("returns empty string when not in accountant mode", function()
			ns.db.global.money.accountantMode = false
			local payload = getMoneyPayload()
			assert.equal("", payload.amountTextFn())
		end)
	end)

	describe("Money sample row is suppressed when disabled", function()
		it("produces no money payload when money is disabled", function()
			ns.db.global.frames[1].features.money.enabled = false
			local payload = getMoneyPayload()
			assert.is_nil(payload)
		end)

		it("produces no money payload when Money module is not enabled", function()
			mockMoneyModule.IsEnabled = function()
				return false
			end
			local payload = getMoneyPayload()
			assert.is_nil(payload)
		end)
	end)
end)
