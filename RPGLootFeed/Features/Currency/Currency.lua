---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's full
-- dependency surface on G_RLF / ns is visible in one place.  Tests pass a
-- minimal mock ns to loadfile("Currency.lua") to control these at injection
-- time without the full nsMocks framework.
-- NOTE: G_RLF.db and G_RLF.hiddenCurrencies are intentionally absent –
-- they must remain runtime lookups so per-test overrides work correctly.
local LootElementBase = G_RLF.LootElementBase
local FeatureBase = G_RLF.FeatureBase
local FeatureModule = G_RLF.FeatureModule
local Expansion = G_RLF.Expansion
local LogDebug = function(...)
	G_RLF:LogDebug(...)
end
local LogInfo = function(...)
	G_RLF:LogInfo(...)
end
local LogWarn = function(...)
	G_RLF:LogWarn(...)
end
local IsRetail = function()
	return G_RLF:IsRetail()
end
local RGBAToHexFormat = function(...)
	return G_RLF:RGBAToHexFormat(...)
end
local ExtractCurrencyID = function(msg)
	return G_RLF:ExtractCurrencyID(msg)
end

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- Wraps GetExpansionLevel, currency info APIs (C_Everywhere + direct), honor
-- tracking, locale patterns, Constants, and Ethereal-Strands UI behind
-- testable functions so tests can inject mocks without patching _G.
local C = LibStub("C_Everywhere")
local CurrencyAdapter = {
	GetExpansionLevel = function()
		return GetExpansionLevel()
	end,
	IssecretValue = function(msg)
		return issecretvalue and issecretvalue(msg)
	end,
	-- C_Everywhere unified queries used in Process (CURRENCY_DISPLAY_UPDATE path)
	GetCurrencyInfo = function(currencyType)
		return C.CurrencyInfo.GetCurrencyInfo(currencyType)
	end,
	GetBasicCurrencyInfo = function(currencyType, amount)
		return C.CurrencyInfo.GetBasicCurrencyInfo(currencyType, amount)
	end,
	GetCurrencyLinkFromLib = function(currencyType)
		return C.CurrencyInfo.GetCurrencyLink(currencyType)
	end,
	-- Predicate: does the modern C_CurrencyInfo.GetCurrencyLink API exist?
	HasGetCurrencyLinkAPI = function()
		return C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink ~= nil
	end,
	-- Classic fallback (bare global) for GetCurrencyLink
	GetCurrencyLinkFromGlobal = function(currencyId, quantity)
		return GetCurrencyLink(currencyId, quantity)
	end,
	-- Honor tracking for the Account-Wide Honor currency element
	GetUnitHonorLevel = function(unit)
		return UnitHonorLevel(unit)
	end,
	GetUnitHonorMax = function(unit)
		return UnitHonorMax(unit)
	end,
	GetUnitHonor = function(unit)
		return UnitHonor(unit)
	end,
	-- WoW Constants tables
	GetAccountWideHonorCurrencyID = function()
		return Constants and Constants.CurrencyConsts and Constants.CurrencyConsts.ACCOUNT_WIDE_HONOR_CURRENCY_ID
	end,
	GetPerksProgramCurrencyID = function()
		return Constants
			and Constants.CurrencyConsts
			and Constants.CurrencyConsts.CURRENCY_ID_PERKS_PROGRAM_DISPLAY_INFO
	end,
	-- Classic locale patterns used in OnInitialize to build classicCurrencyPatterns
	GetCurrencyGainedMultiplePattern = function()
		return CURRENCY_GAINED_MULTIPLE
	end,
	GetCurrencyGainedMultipleBonusPattern = function()
		return CURRENCY_GAINED_MULTIPLE_BONUS
	end,
	-- Ethereal Strands UI (3278) custom link handler
	GenericTraitToggle = function()
		GenericTraitUI_LoadUI()
		GenericTraitFrame:SetSystemID(29)
		GenericTraitFrame:SetTreeID(1115)
		ToggleFrame(GenericTraitFrame)
	end,
}

---@class RLF_Currency: RLF_Module, AceEvent-3.0
local Currency = FeatureBase:new(FeatureModule.Currency, "AceEvent-3.0")

Currency._currencyAdapter = CurrencyAdapter

--- @param content string
--- @param message string
--- @param id? string
--- @param amount? string|number
function Currency:LogDebug(content, message, id, amount)
	LogDebug(message, addonName, self.moduleName, id, content, amount)
end

Currency.Element = {}

local ETHEREAL_STRANDS_CURRENCY_ID = 3278

--- @param currencyLink string
--- @param currencyInfo CurrencyInfo
--- @param basicInfo CurrencyDisplayInfo
function Currency.Element:new(currencyLink, currencyInfo, basicInfo)
	---@class Currency.Element: RLF_BaseLootElement
	local element = LootElementBase:new()

	element.type = "Currency"
	element.IsEnabled = function()
		return Currency:IsEnabled()
	end

	element.isLink = true
	-- Ethereal Strands
	element.isCustomLink = currencyInfo.currencyID == ETHEREAL_STRANDS_CURRENCY_ID

	if not currencyLink or not currencyInfo or not basicInfo then
		Currency:LogDebug(
			"Skip showing currency",
			"SKIP: Missing currencyLink, currencyInfo, or basicInfo - " .. tostring(currencyLink)
		)
		return
	end

	element.key = "CURRENCY_" .. currencyInfo.currencyID
	element.icon = currencyInfo.iconFileID
	if not G_RLF.db.global.currency.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		element.icon = nil
	end
	element.quantity = basicInfo.displayAmount
	element.itemCount = currencyInfo.quantity
	element.quality = currencyInfo.quality
	element.totalEarned = currencyInfo.totalEarned
	element.cappedQuantity = currencyInfo.maxQuantity

	if element.key == Currency._currencyAdapter.GetAccountWideHonorCurrencyID() then
		element.itemCount = Currency._currencyAdapter.GetUnitHonorLevel("player")
		element.cappedQuantity = Currency._currencyAdapter.GetUnitHonorMax("player")
		element.totalEarned = Currency._currencyAdapter.GetUnitHonor("player")
		---@diagnostic disable-next-line: undefined-field
		currencyLink = currencyLink:gsub(currencyInfo.name, _G.LIFETIME_HONOR)
	end

	element.textFn = function(existingQuantity, truncatedLink)
		if not truncatedLink then
			return currencyLink
		end
		local text = truncatedLink
		local quantityText
		local effectiveQuantity = (existingQuantity or 0) + element.quantity
		if effectiveQuantity == 1 and not G_RLF.db.global.misc.showOneQuantity then
			quantityText = ""
		else
			quantityText = " x" .. effectiveQuantity
		end
		text = text .. quantityText
		return text
	end

	element.secondaryTextFn = function(...)
		if element.cappedQuantity and element.cappedQuantity > 0 then
			local percentage, numerator
			if element.totalEarned > 0 then
				numerator = element.totalEarned
				percentage = element.totalEarned / element.cappedQuantity
			else
				numerator = element.itemCount
				percentage = element.itemCount / element.cappedQuantity
			end
			local currencyDb = G_RLF.db.global.currency
			local lowThreshold = currencyDb.lowerThreshold
			local upperThreshold = currencyDb.upperThreshold
			local lowestColor = currencyDb.lowestColor
			local midColor = currencyDb.midColor
			local upperColor = currencyDb.upperColor
			local color = RGBAToHexFormat(unpack(lowestColor))
			if element.key ~= Currency._currencyAdapter.GetAccountWideHonorCurrencyID() then
				if percentage < lowThreshold then
					color = RGBAToHexFormat(unpack(lowestColor))
				elseif percentage >= lowThreshold and percentage < upperThreshold then
					color = RGBAToHexFormat(unpack(midColor))
				else
					color = RGBAToHexFormat(unpack(upperColor))
				end
			end

			local secondaryText = "    " .. color .. numerator .. " / " .. element.cappedQuantity .. "|r"
			local id = element.key:match("CURRENCY_(%d+)")
			if id and id ~= "" and tonumber(id) == ETHEREAL_STRANDS_CURRENCY_ID then
				secondaryText = secondaryText .. "    (" .. G_RLF.L["ClickToOpenCloakTree"] .. ")"
			end
			return secondaryText
		end

		return ""
	end

	if element.isCustomLink then
		element.customBehavior = function()
			local id = element.key:match("CURRENCY_(%d+)")
			if id == nil or id == "" then
				Currency:LogDebug("Custom behavior", "SKIP: No ID found in custom currency link")
				return
			end
			local customCurrencyId = tonumber(id)

			if customCurrencyId == ETHEREAL_STRANDS_CURRENCY_ID then
				Currency._currencyAdapter.GenericTraitToggle()
			else
				Currency:LogDebug("Custom behavior", "SKIP: unhandled custom currency link", element.key)
			end
		end
	end

	return element
end

local function isHiddenCurrency(id)
	return G_RLF.hiddenCurrencies[id] == true
end

local function extractAmount(message, patterns)
	for _, segments in ipairs(patterns) do
		local prePattern, postPattern = unpack(segments)
		local preMatchStart, _ = string.find(message, prePattern, 1, true)
		if not preMatchStart then
			-- If the prePattern is not found, skip to the next pattern
		else
			local subString = string.sub(message, preMatchStart)
			local amount = string.match(subString, prePattern .. "(%d+)" .. postPattern)
			if amount and amount ~= "" and tonumber(amount) > 0 then
				return tonumber(amount)
			end
		end
	end
	return nil
end

-- Precompute pattern segments to optimize runtime message parsing
local function precomputeAmountPatternSegments(patterns)
	local computedPatterns = {}
	for _, pattern in ipairs(patterns) do
		local _, stringPlaceholderEnd = string.find(pattern, "%%s")
		if stringPlaceholderEnd then
			local numberPlaceholderStart, numberPlaceholderEnd = string.find(pattern, "%%d", stringPlaceholderEnd + 1)
			if numberPlaceholderEnd then
				local midPattern = string.sub(pattern, stringPlaceholderEnd + 1, numberPlaceholderStart - 1)
				local postPattern = string.sub(pattern, numberPlaceholderEnd + 1)
				table.insert(computedPatterns, { midPattern, postPattern })
			else
				Currency:LogDebug("Invalid pattern", "No number placeholder found in pattern " .. pattern)
			end
		end
	end
	return computedPatterns
end

local classicCurrencyPatterns
function Currency:OnInitialize()
	if G_RLF.db.global.currency.enabled and Currency._currencyAdapter.GetExpansionLevel() >= Expansion.WOTLK then
		self:Enable()
	else
		self:Disable()
	end

	if Currency._currencyAdapter.GetExpansionLevel() < Expansion.BFA then
		local currencyConsts = {
			Currency._currencyAdapter.GetCurrencyGainedMultiplePattern(),
			Currency._currencyAdapter.GetCurrencyGainedMultipleBonusPattern(),
		}
		classicCurrencyPatterns = precomputeAmountPatternSegments(currencyConsts)
	else
		classicCurrencyPatterns = nil
	end
end

function Currency:OnDisable()
	if Currency._currencyAdapter.GetExpansionLevel() < Expansion.WOTLK then
		self:LogDebug("OnEnable", "Disabled because expansion is below WOTLK")
		return
	end
	if Currency._currencyAdapter.GetExpansionLevel() < Expansion.BFA then
		self:UnregisterEvent("CHAT_MSG_CURRENCY")
	else
		self:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
	end
	if IsRetail() then
		self:UnregisterEvent("PERKS_PROGRAM_CURRENCY_AWARDED")
		self:UnregisterEvent("PERKS_PROGRAM_CURRENCY_REFRESH")
	end
end

function Currency:OnEnable()
	if Currency._currencyAdapter.GetExpansionLevel() < Expansion.WOTLK then
		self:LogDebug("OnEnable", "Disabled because expansion is below WOTLK")
		return
	end
	if Currency._currencyAdapter.GetExpansionLevel() < Expansion.BFA then
		self:RegisterEvent("CHAT_MSG_CURRENCY")
	else
		self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
	end
	if IsRetail() then
		self:RegisterEvent("PERKS_PROGRAM_CURRENCY_AWARDED")
	end
	self:LogDebug("OnEnable", "Currency module is enabled")
end

function Currency:Process(eventName, currencyType, quantityChange)
	LogInfo(eventName, "WOWEVENT", self.moduleName, currencyType, eventName, quantityChange)

	if currencyType == nil or not quantityChange or quantityChange == 0 then
		self:LogDebug(
			"Skip showing currency",
			"SKIP: Something was missing, don't display",
			currencyType,
			quantityChange
		)
		return
	end

	if isHiddenCurrency(currencyType) then
		self:LogDebug(
			"Skip showing currency",
			"SKIP: This is a known hidden currencyType",
			currencyType,
			quantityChange
		)
		return
	end

	---@type CurrencyInfo
	local info = Currency._currencyAdapter.GetCurrencyInfo(currencyType)
	if info == nil or info.description == "" or info.iconFileID == nil then
		self:LogDebug("Skip showing currency", "SKIP: Description or icon was empty", currencyType, quantityChange)
		return
	end

	---@type CurrencyDisplayInfo
	local basicInfo = Currency._currencyAdapter.GetBasicCurrencyInfo(currencyType, quantityChange)
	local link
	if Currency._currencyAdapter.HasGetCurrencyLinkAPI() then
		link = Currency._currencyAdapter.GetCurrencyLinkFromLib(currencyType)
	else
		-- Fallback for pre-SL clients
		link = Currency._currencyAdapter.GetCurrencyLinkFromGlobal(currencyType, quantityChange)
	end
	local e = self.Element:new(link, info, basicInfo)
	if e then
		e:Show()
	else
		self:LogDebug("Skip showing currency", "SKIP: Element was nil", currencyType, quantityChange)
	end
end

function Currency:CURRENCY_DISPLAY_UPDATE(eventName, ...)
	local currencyType, _quantity, quantityChange, _quantityGainSource, _quantityLostSource = ...

	self:Process(eventName, currencyType, quantityChange)
end

---@param msg string
---@return number? quantityChange
function Currency:ParseCurrencyChangeMessage(msg)
	if not classicCurrencyPatterns or #classicCurrencyPatterns == 0 then
		self:LogDebug("Skip showing currency", "SKIP: No classic currency patterns available")
		return nil
	end

	local quantityChange = extractAmount(msg, classicCurrencyPatterns)

	quantityChange = quantityChange or 1

	return quantityChange
end

function Currency:CHAT_MSG_CURRENCY(eventName, ...)
	local msg = ...
	if Currency._currencyAdapter.IssecretValue(msg) then
		LogWarn("(" .. eventName .. ") Secret value detected, ignoring chat message", "WOWEVENT", self.moduleName, "")
		return
	end

	LogInfo(eventName, "WOWEVENT", self.moduleName, nil, msg)

	local currencyId = ExtractCurrencyID(msg)
	if currencyId == 0 or currencyId == nil then
		self:LogDebug("Skip showing currency", "SKIP: No currency ID found for links in msg = " .. tostring(msg))
		return
	end

	if currencyId and isHiddenCurrency(currencyId) then
		self:LogDebug(
			"Skip showing currency",
			"SKIP: This is a known hidden currency " .. tostring(msg),
			tostring(currencyId)
		)
		return
	end

	local quantityChange = self:ParseCurrencyChangeMessage(msg)
	if quantityChange == nil or quantityChange <= 0 then
		self:LogDebug(
			"Skip showing currency",
			"SKIP: there was a problem determining the quantity change " .. tostring(msg),
			tostring(currencyId)
		)
		return
	end

	local currencyInfo = Currency._currencyAdapter.GetCurrencyInfo(currencyId)
	if not currencyInfo then
		self:LogDebug("Skip showing currency", "SKIP: No currency info found for msg = " .. msg, tostring(currencyId))
		return
	end

	if currencyInfo.currencyID == 0 then
		self:LogDebug(
			"Currency info has no ID",
			"Overriding " .. tostring(currencyInfo.name) .. " currencyID",
			tostring(currencyId)
		)
		currencyInfo.currencyID = currencyId
	end

	if currencyInfo.quantity == 0 then
		self:LogDebug(
			"Currency info has no quantity",
			"Overriding " .. tostring(currencyInfo.name) .. " quantity to " .. tostring(quantityChange),
			tostring(currencyId)
		)
		currencyInfo.quantity = quantityChange
	end

	local basicInfo = {
		displayAmount = quantityChange,
	}

	local currencyLink = Currency._currencyAdapter.GetCurrencyLinkFromGlobal(currencyId, currencyInfo.quantity)
	local e = self.Element:new(currencyLink, currencyInfo, basicInfo)
	if e then
		e:Show()
	else
		self:LogDebug("Skip showing currency", "SKIP: Element was nil", tostring(currencyInfo.currencyID))
	end
end

function Currency:PERKS_PROGRAM_CURRENCY_AWARDED(eventName, quantityChange)
	self:RegisterEvent("PERKS_PROGRAM_CURRENCY_REFRESH")
	local currencyType = Currency._currencyAdapter.GetPerksProgramCurrencyID()
	LogInfo(eventName, "WOWEVENT", self.moduleName, tostring(currencyType), eventName, quantityChange)
	self:UnregisterEvent("PERKS_PROGRAM_CURRENCY_AWARDED")
end

function Currency:PERKS_PROGRAM_CURRENCY_REFRESH(eventName, oldQuantity, newQuantity)
	local currencyType = Currency._currencyAdapter.GetPerksProgramCurrencyID()

	local quantityChange = newQuantity - oldQuantity
	if quantityChange == 0 then
		return
	end
	self:Process(eventName, currencyType, quantityChange)
end

return Currency
