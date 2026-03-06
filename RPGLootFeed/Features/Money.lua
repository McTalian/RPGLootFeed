---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's full
-- dependency surface on G_RLF / ns is visible in one place.  Tests pass a
-- minimal mock ns to loadfile("Money.lua") to control these at
-- injection time without the full nsMocks framework.
-- NOTE: G_RLF.db is intentionally absent – AceDB populates it in
-- OnInitialize, so it must remain a runtime lookup inside function bodies.
local LootElementBase = G_RLF.LootElementBase
local DefaultIcons = G_RLF.DefaultIcons
local ItemQualEnum = G_RLF.ItemQualEnum
local FeatureBase = G_RLF.FeatureBase
local FeatureModule = G_RLF.FeatureModule
local TextTemplateEngine = G_RLF.TextTemplateEngine
local LogDebug = function(...)
	G_RLF:LogDebug(...)
end
local LogWarn = function(...)
	G_RLF:LogWarn(...)
end

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- Shared adapter from G_RLF.WoWAPI; tests override Money._moneyAdapter after load.
local MoneyAdapter = G_RLF.WoWAPI.Money

---@class RLF_Money: RLF_Module, AceEvent-3.0
local Money = FeatureBase:new(FeatureModule.Money, "AceEvent-3.0")

Money._moneyAdapter = MoneyAdapter

--- Plays the configured money loot sound if the override is enabled.
--- Calls Money._moneyAdapter.PlaySoundFile so tests can inject a mock.
function Money:PlaySoundIfEnabled()
	if G_RLF.db.global.money.overrideMoneyLootSound and G_RLF.db.global.money.moneyLootSound ~= "" then
		local willPlay, handle = Money._moneyAdapter.PlaySoundFile(G_RLF.db.global.money.moneyLootSound)
		if not willPlay then
			LogWarn(
				"Failed to play sound " .. G_RLF.db.global.money.moneyLootSound,
				addonName,
				Money.moduleName or "Money"
			)
		else
			LogDebug(
				"Sound queued to play " .. G_RLF.db.global.money.moneyLootSound .. " " .. handle,
				addonName,
				Money.moduleName or "Money"
			)
		end
	end
end

-- Context provider function to be registered when module is enabled.
-- Defined after Money so the inner closure can reference Money._moneyAdapter.
local function createMoneyContextProvider()
	return function(context, data)
		-- Get coin string for the total amount
		context.coinString = Money._moneyAdapter.GetCoinTextureString(context.absTotal)

		-- Support for accountant mode
		if G_RLF.db.global.money.accountantMode then
			context.coinString = "(" .. context.coinString .. ")"
		end

		-- Current money total for secondary text
		if G_RLF.db.global.money.showMoneyTotal then
			local currentMoney = Money._moneyAdapter.GetMoney()
			if currentMoney > 10000000 then -- More than 1000 gold
				currentMoney = math.floor(currentMoney / 10000) * 10000 -- truncate silver and copper
			end
			context.currentMoney = Money._moneyAdapter.GetCoinTextureString(currentMoney)

			-- Handle abbreviation if enabled
			if G_RLF.db.global.money.abbreviateTotal and currentMoney > 10000000 then
				local goldOnly = math.floor(currentMoney / 10000)
				context.currentMoney =
					context.currentMoney:gsub(tostring(goldOnly), TextTemplateEngine:AbbreviateNumber(goldOnly))
			end
		else
			-- When showMoneyTotal is disabled, provide empty currentMoney
			-- This will cause row 2 to be only spacers, which ProcessRowElements will detect and return ""
			context.currentMoney = ""
		end
	end
end

--- Build a uniform payload for a money loot event.
--- Returns nil when the amount is zero or nil (nothing to display).
---@param quantity number The copper amount (positive = income, negative = loss)
---@return RLF_ElementPayload?
function Money:BuildPayload(quantity)
	if not quantity or quantity == 0 then
		return nil
	end

	local icon = DefaultIcons.MONEY
	if not G_RLF.db.global.money.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		icon = nil
	end

	local r, g, b = 1, 1, 1
	if quantity < 0 then
		r, g, b = 1, 0, 0
	end

	local textElements = Money:GenerateTextElements(quantity)

	---@type RLF_LootElementData
	local elementData = {
		key = "MONEY_LOOT",
		type = FeatureModule.Money,
		textElements = textElements,
		quantity = quantity,
		icon = icon,
		quality = ItemQualEnum.Poor,
	}

	---@type RLF_ElementPayload
	local payload = {
		key = "MONEY_LOOT",
		type = FeatureModule.Money,
		icon = icon,
		quality = ItemQualEnum.Poor,
		quantity = quantity,
		r = r,
		g = g,
		b = b,
		-- Recompute color based on net quantity when an existing row is updated.
		-- The net is (existing accumulated amount) + (this element's quantity).
		colorFn = function(netQuantity)
			if netQuantity < 0 then
				return 1, 0, 0, 1
			else
				return 1, 1, 1, 1
			end
		end,
		textFn = function(existingCopper)
			return TextTemplateEngine:ProcessRowElements(1, elementData, existingCopper)
		end,
		secondaryTextFn = function(existingCopper)
			return TextTemplateEngine:ProcessRowElements(2, elementData, existingCopper)
		end,
		IsEnabled = function()
			return Money:IsEnabled()
		end,
	}

	if G_RLF.db.global.money.overrideMoneyLootSound and G_RLF.db.global.money.moneyLootSound ~= "" then
		payload.sound = G_RLF.db.global.money.moneyLootSound
	end

	return payload
end

--- Generate text elements for Money type using the new data-driven approach
---@param quantity number The money amount in copper
---@return table<number, table<string, RLF_TextElement>> textElements Row-indexed elements: [row][elementKey] = element
function Money:GenerateTextElements(quantity)
	local elements = {}

	-- Row 1: Primary money display
	elements[1] = {}
	elements[1].primary = {
		type = "primary",
		template = "{sign}{coinString}",
		order = 1,
		color = nil, -- Will use default color
	}

	-- Row 2: Context text element (money total) - only if enabled
	elements[2] = {}
	elements[2].contextSpacer = {
		type = "spacer",
		spacerCount = 4, -- "    " spacing
		order = 1,
	}

	elements[2].context = {
		type = "context",
		template = "{currentMoney}",
		order = 2,
		color = nil,
	}

	return elements
end

function Money:OnInitialize()
	self.startingMoney = 0
	if G_RLF.db.global.money.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function Money:OnEnable()
	-- Register our context provider with the TextTemplateEngine
	TextTemplateEngine:RegisterContextProvider("Money", createMoneyContextProvider())

	self:RegisterEvent("PLAYER_MONEY")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self.startingMoney = Money._moneyAdapter.GetMoney()
end

function Money:OnDisable()
	-- Unregister our context provider
	TextTemplateEngine.contextProviders["Money"] = nil

	self:UnregisterEvent("PLAYER_MONEY")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function Money:PLAYER_ENTERING_WORLD(eventName)
	self.startingMoney = Money._moneyAdapter.GetMoney()
end

function Money:PLAYER_MONEY(eventName)
	local newMoney = Money._moneyAdapter.GetMoney()
	local amountInCopper = newMoney - self.startingMoney
	if amountInCopper == 0 then
		return
	end
	self.startingMoney = newMoney
	if G_RLF.db.global.money.onlyIncome and amountInCopper < 0 then
		return
	end

	local payload = Money:BuildPayload(amountInCopper)
	if payload then
		LootElementBase:fromPayload(payload):Show()
		Money:PlaySoundIfEnabled()
	end
end

return Money
