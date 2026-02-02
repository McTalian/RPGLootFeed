---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local C = LibStub("C_Everywhere")

---@class RLF_Currency: RLF_Module, AceEvent-3.0
local Currency = G_RLF.RLF:NewModule(G_RLF.FeatureModule.Currency, "AceEvent-3.0")

--- @param content string
--- @param message string
--- @param id? string
--- @param amount? string|number
function Currency:LogDebug(content, message, id, amount)
	G_RLF:LogDebug(message, addonName, self.moduleName, id, content, amount)
end

Currency.Element = {}

local ETHEREAL_STRANDS_CURRENCY_ID = 3278

--- @param currencyLink string
--- @param currencyInfo CurrencyInfo
--- @param basicInfo CurrencyDisplayInfo
function Currency.Element:new(currencyLink, currencyInfo, basicInfo)
	---@class Currency.Element: RLF_BaseLootElement
	local element = {}
	G_RLF.InitializeLootDisplayProperties(element)

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

	if element.key == Constants.CurrencyConsts.ACCOUNT_WIDE_HONOR_CURRENCY_ID then
		element.itemCount = UnitHonorLevel("player")
		element.cappedQuantity = UnitHonorMax("player")
		element.totalEarned = UnitHonor("player")
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
			local color = G_RLF:RGBAToHexFormat(unpack(lowestColor))
			if element.key ~= Constants.CurrencyConsts.ACCOUNT_WIDE_HONOR_CURRENCY_ID then
				if percentage < lowThreshold then
					color = G_RLF:RGBAToHexFormat(unpack(lowestColor))
				elseif percentage >= lowThreshold and percentage < upperThreshold then
					color = G_RLF:RGBAToHexFormat(unpack(midColor))
				else
					color = G_RLF:RGBAToHexFormat(unpack(upperColor))
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
				GenericTraitUI_LoadUI()
				GenericTraitFrame:SetSystemID(29)
				GenericTraitFrame:SetTreeID(1115)
				ToggleFrame(GenericTraitFrame)
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
	if G_RLF.db.global.currency.enabled and GetExpansionLevel() >= G_RLF.Expansion.WOTLK then
		self:Enable()
	else
		self:Disable()
	end

	if GetExpansionLevel() < G_RLF.Expansion.BFA then
		local currencyConsts = {
			CURRENCY_GAINED_MULTIPLE,
			CURRENCY_GAINED_MULTIPLE_BONUS,
		}
		classicCurrencyPatterns = precomputeAmountPatternSegments(currencyConsts)
	else
		classicCurrencyPatterns = nil
	end
end

function Currency:OnDisable()
	if GetExpansionLevel() < G_RLF.Expansion.WOTLK then
		self:LogDebug("OnEnable", "Disabled because expansion is below WOTLK")
		return
	end
	if GetExpansionLevel() < G_RLF.Expansion.BFA then
		self:UnregisterEvent("CHAT_MSG_CURRENCY")
	else
		self:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
	end
	if G_RLF:IsRetail() then
		self:UnregisterEvent("PERKS_PROGRAM_CURRENCY_AWARDED")
		self:UnregisterEvent("PERKS_PROGRAM_CURRENCY_REFRESH")
	end
end

function Currency:OnEnable()
	if GetExpansionLevel() < G_RLF.Expansion.WOTLK then
		self:LogDebug("OnEnable", "Disabled because expansion is below WOTLK")
		return
	end
	if GetExpansionLevel() < G_RLF.Expansion.BFA then
		self:RegisterEvent("CHAT_MSG_CURRENCY")
	else
		self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
	end
	if G_RLF:IsRetail() then
		self:RegisterEvent("PERKS_PROGRAM_CURRENCY_AWARDED")
	end
	self:LogDebug("OnEnable", "Currency module is enabled")
end

function Currency:Process(eventName, currencyType, quantityChange)
	G_RLF:LogInfo(eventName, "WOWEVENT", self.moduleName, currencyType, eventName, quantityChange)

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
	local info = C.CurrencyInfo.GetCurrencyInfo(currencyType)
	if info == nil or info.description == "" or info.iconFileID == nil then
		self:LogDebug("Skip showing currency", "SKIP: Description or icon was empty", currencyType, quantityChange)
		return
	end

	self:fn(function()
		---@type CurrencyDisplayInfo
		local basicInfo = C.CurrencyInfo.GetBasicCurrencyInfo(currencyType, quantityChange)
		local link
		if C_CurrencyInfo.GetCurrencyLink then
			link = C.CurrencyInfo.GetCurrencyLink(currencyType)
		else
			-- Fallback for pre-SL clients
			link = GetCurrencyLink(currencyType, quantityChange)
		end
		local e = self.Element:new(link, info, basicInfo)
		if e then
			e:Show()
		else
			self:LogDebug("Skip showing currency", "SKIP: Element was nil", currencyType, quantityChange)
		end
	end)
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
	if issecretvalue and issecretvalue(msg) then
		G_RLF:LogWarn(
			"(" .. eventName .. ") Secret value detected, ignoring chat message",
			"WOWEVENT",
			self.moduleName,
			""
		)
		return
	end

	G_RLF:LogInfo(eventName, "WOWEVENT", self.moduleName, nil, msg)

	local currencyId = G_RLF:ExtractCurrencyID(msg)
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

	local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyId)
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

	local currencyLink = GetCurrencyLink(currencyId, currencyInfo.quantity)
	local e = self.Element:new(currencyLink, currencyInfo, basicInfo)
	if e then
		e:Show()
	else
		self:LogDebug("Skip showing currency", "SKIP: Element was nil", tostring(currencyInfo.currencyID))
	end
end

function Currency:PERKS_PROGRAM_CURRENCY_AWARDED(eventName, quantityChange)
	self:RegisterEvent("PERKS_PROGRAM_CURRENCY_REFRESH")
	local currencyType = Constants.CurrencyConsts.CURRENCY_ID_PERKS_PROGRAM_DISPLAY_INFO
	G_RLF:LogInfo(eventName, "WOWEVENT", self.moduleName, tostring(currencyType), eventName, quantityChange)
	self:UnregisterEvent("PERKS_PROGRAM_CURRENCY_AWARDED")
end

function Currency:PERKS_PROGRAM_CURRENCY_REFRESH(eventName, oldQuantity, newQuantity)
	local currencyType = Constants.CurrencyConsts.CURRENCY_ID_PERKS_PROGRAM_DISPLAY_INFO

	local quantityChange = newQuantity - oldQuantity
	if quantityChange == 0 then
		return
	end
	self:Process(eventName, currencyType, quantityChange)
end

return Currency
