---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's full
-- dependency surface on G_RLF / ns is visible in one place.  Tests pass a
-- minimal mock ns to loadfile("ItemLoot.lua") to control these at
-- injection time without the full nsMocks framework.
-- NOTE: G_RLF.db, G_RLF.equipSlotMap, G_RLF.armorClassMapping and
-- G_RLF.AuctionIntegrations are intentionally absent – they rely on runtime
-- state set after initialization or are mutable assignments by this module.
local LootElementBase = G_RLF.LootElementBase
local ItemQualEnum = G_RLF.ItemQualEnum
local FeatureBase = G_RLF.FeatureBase
local FeatureModule = G_RLF.FeatureModule
local Expansion = G_RLF.Expansion
local ItemInfo = G_RLF.ItemInfo
local AtlasIconCoefficients = G_RLF.AtlasIconCoefficients
local PricesEnum = G_RLF.PricesEnum
local DbAccessor = G_RLF.DbAccessor
local Frames = G_RLF.Frames
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

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- Wraps bare WoW globals and C.Item.* calls so tests can inject mocks without
-- patching _G or LibStub.
local C = LibStub("C_Everywhere")
local ItemLootAdapter = {
	GetExpansionLevel = function()
		return GetExpansionLevel()
	end,
	UnitName = function(unit)
		return UnitName(unit)
	end,
	UnitClass = function(unit)
		return UnitClass(unit)
	end,
	UnitLevel = function(unit)
		return UnitLevel(unit)
	end,
	IssecretValue = function(msg)
		return issecretvalue and issecretvalue(msg)
	end,
	GetPlayerGuid = function()
		return GetPlayerGuid()
	end,
	GetInventoryItemLink = function(unit, slot)
		return GetInventoryItemLink(unit, slot)
	end,
	GetItemQualityColor = function(quality)
		return C_Item.GetItemQualityColor(quality)
	end,
	GetCoinTextureString = function(price)
		return C_CurrencyInfo.GetCoinTextureString(price)
	end,
	CreateAtlasMarkup = function(icon, w, h, x, y)
		return CreateAtlasMarkup(icon, w, h, x, y)
	end,
	PlaySoundFile = function(sound)
		return PlaySoundFile(sound)
	end,
	GetAHPrice = function(itemLink)
		local ai = G_RLF.AuctionIntegrations
		if ai and ai.activeIntegration then
			return ai.activeIntegration:GetAHPrice(itemLink)
		end
		return nil
	end,
	GetItemInfo = function(link)
		return C.Item.GetItemInfo(link)
	end,
	GetItemIDForItemInfo = function(link)
		return C.Item.GetItemIDForItemInfo(link)
	end,
	GetItemCount = function(link, ...)
		return C.Item.GetItemCount(link, ...)
	end,
	GetItemStatDelta = function(link1, link2)
		return C.Item.GetItemStatDelta(link1, link2)
	end,
}

---@class RLF_ItemLoot: RLF_Module, AceEvent-3.0, AceBucket-3.0
local ItemLoot = FeatureBase:new(FeatureModule.ItemLoot, "AceEvent-3.0", "AceBucket-3.0")

ItemLoot._itemLootAdapter = ItemLootAdapter

ItemLoot.Element = {}

--- Convert params into a string with an icon and price
--- @param icon string
--- @param fontSize number
--- @param price number
--- @return string
local function getPriceString(icon, fontSize, price)
	if not icon or not fontSize or not price then
		return ""
	end
	local sizeCoeff = AtlasIconCoefficients[icon] or 1
	local atlasIconSize = fontSize * sizeCoeff
	return ItemLoot._itemLootAdapter.CreateAtlasMarkup(icon, atlasIconSize, atlasIconSize, 0, 0)
		.. " "
		.. ItemLoot._itemLootAdapter.GetCoinTextureString(price)
end

function ItemLoot:ItemQualityName(enumValue)
	for k, v in pairs(Enum.ItemQuality) do
		if v == enumValue then
			return k
		end
	end
	return nil
end

local function IsBetterThanEquipped(info)
	if info:IsEligibleEquipment() then
		local equippedLink
		local slot = G_RLF.equipSlotMap[info.itemEquipLoc]
		if type(slot) == "table" then
			for _, s in ipairs(slot) do
				equippedLink = ItemLoot._itemLootAdapter.GetInventoryItemLink("player", s)
				if equippedLink then
					break
				end
			end
		else
			equippedLink = ItemLoot._itemLootAdapter.GetInventoryItemLink("player", slot)
		end

		if not equippedLink then
			return false
		end

		local equippedId = ItemLoot._itemLootAdapter.GetItemIDForItemInfo(equippedLink)
		local equippedInfo = ItemInfo:new(equippedId, ItemLoot._itemLootAdapter.GetItemInfo(equippedLink))
		if not equippedInfo then
			return false
		end

		if equippedInfo.itemQuality > ItemQualEnum.Poor and info.itemQuality == ItemQualEnum.Poor then
			-- If the equipped item is better than poor and the new item is poor, we don't consider it an upgrade
			return false
		end
		if equippedInfo.itemQuality > ItemQualEnum.Common and info.itemQuality == ItemQualEnum.Common then
			-- If the equipped item is better than common and the new item is common, we don't consider it an upgrade
			return false
		end
		if equippedInfo.itemLevel and equippedInfo.itemLevel < info.itemLevel then
			return true
		elseif equippedInfo.itemLevel == info.itemLevel then
			local statDelta = ItemLoot._itemLootAdapter.GetItemStatDelta(equippedLink, info.itemLink)
			for k, v in pairs(statDelta) do
				-- Has a Tertiary Stat
				if k:find("ITEM_MOD_CR_") and v > 0 then
					return true
				end
				-- Has a Gem Socket
				if k:find("EMPTY_SOCKET_") and v > 0 then
					return true
				end
			end
		end
	end

	return false
end

---@param info RLF_ItemInfo
---@param quantity number
---@param fromLink? string
function ItemLoot.Element:new(info, quantity, fromLink)
	---@class ItemLoot.Element: RLF_BaseLootElement
	local element = LootElementBase:new()

	element.type = FeatureModule.ItemLoot
	element.IsEnabled = function()
		return ItemLoot:IsEnabled()
	end

	element.isLink = true
	element.quantity = quantity

	local itemLink = info.itemLink

	element.key = info.itemLink
	local fromInfo = nil
	if fromLink then
		element.key = "UPGRADE_" .. element.key
		fromInfo = ItemInfo:new(
			ItemLoot._itemLootAdapter.GetItemIDForItemInfo(fromLink),
			ItemLoot._itemLootAdapter.GetItemInfo(fromLink)
		)
	end

	element.icon = info.itemTexture
	if not G_RLF.db.global.item.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		element.icon = nil
	end
	element.sellPrice = info.sellPrice
	local itemQualitySettings = G_RLF.db.global.item.itemQualitySettings[info.itemQuality]
	if itemQualitySettings and itemQualitySettings.enabled and itemQualitySettings.duration > 0 then
		element.showForSeconds = itemQualitySettings.duration
	end
	-- Keystone specifics now handled via ItemInfo
	element.isKeystone = info:IsKeystone()
	if element.isKeystone then
		-- Force display quality to Epic for keystones
		element.quality = info:GetDisplayQuality()
	end

	element.itemCount = ItemLoot._itemLootAdapter.GetItemCount(info.itemLink, true, false, true, true)

	element.topLeftText = nil
	element.topLeftColor = nil
	if info:IsEquippableItem() and info.itemQuality > ItemQualEnum.Poor then
		element.topLeftText = tostring(info.itemLevel)
		local r, g, b = ItemLoot._itemLootAdapter.GetItemQualityColor(info.itemQuality)
		element.topLeftColor = { r, g, b }
	end

	function element:isPassingFilter(itemName, itemQuality)
		if not G_RLF.db.global.item.itemQualitySettings[itemQuality].enabled then
			LogDebug(
				itemName .. " ignored by quality: " .. ItemLoot:ItemQualityName(itemQuality),
				addonName,
				"ItemLoot",
				"",
				nil,
				self.quantity
			)
			return false
		end

		return true
	end

	element.textFn = function(existingQuantity, truncatedLink)
		if not truncatedLink then
			return itemLink
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
		if element.isQuestItem and G_RLF.db.global.item.textStyleOverrides.quest.enabled then
			local r, g, b, a = unpack(G_RLF.db.global.item.textStyleOverrides.quest.color)
			-- Replace the color in the link portion of the text with the quest color
			text = text:gsub("|c.-|", RGBAToHexFormat(r, g, b, a) .. "|")
		end
		return text
	end

	element.secondaryTextFn = function(...)
		local stylingDb = DbAccessor:Styling(Frames.MAIN)
		local secondaryFontSize = stylingDb.secondaryFontSize

		if fromLink ~= "" and fromLink ~= nil then
			return info:GetUpgradeText(fromInfo, secondaryFontSize)
		end

		if info:IsEquippableItem() then
			local secondaryText = ""
			if info:HasItemRollBonus() then
				secondaryText = info:GetItemRollText()
			end
			local equipmentTypeText = info:GetEquipmentTypeText()
			if equipmentTypeText then
				return secondaryText .. equipmentTypeText
			end
			return secondaryText
		end

		local quantity = ...
		local effectiveQuantity = quantity or 1
		local vendorIcon = G_RLF.db.global.item.vendorIconTexture
		local auctionIcon = G_RLF.db.global.item.auctionHouseIconTexture
		local vendorPrice, auctionPrice = 0, 0
		local pricesForSellableItems = G_RLF.db.global.item.pricesForSellableItems
		if element.sellPrice and element.sellPrice > 0 then
			vendorPrice = element.sellPrice
		end
		local marketPrice = ItemLoot._itemLootAdapter.GetAHPrice(itemLink)
		if marketPrice and marketPrice > 0 then
			auctionPrice = marketPrice
		end
		local showVendorPrice = vendorPrice > 0
		local showAuctionPrice = auctionPrice > 0
		local str = ""
		if pricesForSellableItems == PricesEnum.Vendor and showVendorPrice then
			str = str .. getPriceString(vendorIcon, secondaryFontSize, vendorPrice * effectiveQuantity)
		elseif pricesForSellableItems == PricesEnum.AH and showAuctionPrice then
			str = str .. getPriceString(auctionIcon, secondaryFontSize, auctionPrice * effectiveQuantity)
		elseif pricesForSellableItems == PricesEnum.VendorAH then
			if showVendorPrice then
				str = str .. getPriceString(vendorIcon, secondaryFontSize, vendorPrice * effectiveQuantity) .. "    "
			end
			if showAuctionPrice then
				str = str .. getPriceString(auctionIcon, secondaryFontSize, auctionPrice * effectiveQuantity)
			end
		elseif pricesForSellableItems == PricesEnum.AHVendor then
			if showAuctionPrice then
				str = str .. getPriceString(auctionIcon, secondaryFontSize, auctionPrice * effectiveQuantity) .. "    "
			end
			if showVendorPrice then
				str = str .. getPriceString(vendorIcon, secondaryFontSize, vendorPrice * effectiveQuantity)
			end
		elseif pricesForSellableItems == PricesEnum.Highest then
			if auctionPrice > vendorPrice then
				str = str .. getPriceString(auctionIcon, secondaryFontSize, auctionPrice * effectiveQuantity)
			elseif showVendorPrice then
				str = str .. getPriceString(vendorIcon, secondaryFontSize, vendorPrice * effectiveQuantity)
			end
		end

		return str
	end

	element.isMount = info:IsMount()
	element.isLegendary = info:IsLegendary()
	element.isBetterThanEquipped = IsBetterThanEquipped(info)
	element.hasTertiaryOrSocket = info:HasItemRollBonus()
	element.isQuestItem = info:IsQuestItem()
	element.isNewTransmog = not info:IsAppearanceCollected()

	if element.isQuestItem and G_RLF.db.global.item.textStyleOverrides.quest.enabled then
		-- This should change the color of the quantity text
		element.r, element.g, element.b, element.a = unpack(G_RLF.db.global.item.textStyleOverrides.quest.color)
	end

	function element:PlaySoundIfEnabled()
		local soundsConfig = G_RLF.db.global.item.sounds
		if self.isMount and soundsConfig.mounts.enabled and soundsConfig.mounts.sound ~= "" then
			local willPlay, handle = ItemLoot._itemLootAdapter.PlaySoundFile(soundsConfig.mounts.sound)
			if not willPlay then
				LogWarn("Failed to play sound " .. soundsConfig.mounts.sound, addonName, ItemLoot.moduleName)
			else
				LogDebug(
					"Sound queued to play " .. soundsConfig.mounts.sound .. " " .. handle,
					addonName,
					ItemLoot.moduleName
				)
			end
		elseif self.isLegendary and soundsConfig.legendary.enabled and soundsConfig.legendary.sound ~= "" then
			local willPlay, handle = ItemLoot._itemLootAdapter.PlaySoundFile(soundsConfig.legendary.sound)
			if not willPlay then
				LogWarn("Failed to play sound " .. soundsConfig.legendary.sound, addonName, ItemLoot.moduleName)
			else
				LogDebug(
					"Sound queued to play " .. soundsConfig.legendary.sound .. " " .. handle,
					addonName,
					ItemLoot.moduleName
				)
			end
		elseif
			self.isBetterThanEquipped
			and soundsConfig.betterThanEquipped.enabled
			and soundsConfig.betterThanEquipped.sound ~= ""
		then
			local willPlay, handle = ItemLoot._itemLootAdapter.PlaySoundFile(soundsConfig.betterThanEquipped.sound)
			if not willPlay then
				LogWarn(
					"Failed to play sound " .. soundsConfig.betterThanEquipped.sound,
					addonName,
					ItemLoot.moduleName
				)
			else
				LogDebug(
					"Sound queued to play " .. soundsConfig.betterThanEquipped.sound .. " " .. handle,
					addonName,
					ItemLoot.moduleName
				)
			end
		elseif self.isNewTransmog and soundsConfig.transmog.enabled and soundsConfig.transmog.sound ~= "" then
			local willPlay, handle = ItemLoot._itemLootAdapter.PlaySoundFile(soundsConfig.transmog.sound)
			if not willPlay then
				LogWarn("Failed to play sound " .. soundsConfig.transmog.sound, addonName, ItemLoot.moduleName)
			else
				LogDebug(
					"Sound queued to play " .. soundsConfig.transmog.sound .. " " .. handle,
					addonName,
					ItemLoot.moduleName
				)
			end
		end
	end

	function element:SetHighlight()
		local itemHighlights = G_RLF.db.global.item.itemHighlights
		local reason = (self.isMount and itemHighlights.mounts and "Mount")
			or (self.isLegendary and itemHighlights.legendary and "Legendary")
			or (self.isBetterThanEquipped and itemHighlights.betterThanEquipped and "Better than Equipped")
			or (self.isQuestItem and itemHighlights.quest and "Quest Item")
			or (self.hasTertiaryOrSocket and itemHighlights.tertiaryOrSocket and "Tertiary or Socket")
			or (self.isNewTransmog and itemHighlights.transmog and "New Transmog")
			or ""

		self.highlight = reason ~= ""
		if self.highlight then
			LogDebug("Highlighted because of " .. reason, addonName, ItemLoot.moduleName, self.key)
		end
	end

	return element
end

function ItemLoot:OnInitialize()
	self.pendingItemRequests = {}
	if G_RLF.db.global.item.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function ItemLoot:OnDisable()
	self:UnregisterEvent("CHAT_MSG_LOOT")
	self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

function ItemLoot:OnEnable()
	self:RegisterEvent("CHAT_MSG_LOOT")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	LogDebug("OnEnable", addonName, self.moduleName)
	if
		ItemLoot._itemLootAdapter.GetExpansionLevel() >= Expansion.CATA
		and ItemLoot._itemLootAdapter.GetExpansionLevel() <= Expansion.MOP
	then
		self:SetEquippableArmorClass()
	end
end

function ItemLoot:SetEquippableArmorClass()
	local _, playerClass = ItemLoot._itemLootAdapter.UnitClass("player")

	if
		playerClass == "ROGUE"
		or playerClass == "DRUID"
		or playerClass == "PRIEST"
		or playerClass == "MAGE"
		or playerClass == "WARLOCK"
	then
		return
	end

	local playerLevel = ItemLoot._itemLootAdapter.UnitLevel("player")
	if playerLevel < 40 then
		if not self.armorLevelListener then
			self.armorLevelListener = self:RegisterBucketEvent("PLAYER_LEVEL_UP", 1, "SetEquippableArmorClass")
		end
		G_RLF.armorClassMapping = G_RLF.legacyArmorClassMappingLowLevel
		return
	end

	if self.armorLevelListener then
		self:UnregisterBucket(self.armorLevelListener)
		self.armorLevelListener = nil
	end

	G_RLF.armorClassMapping = G_RLF.standardArmorClassMapping
end

---@param info RLF_ItemInfo
---@param amount number
---@param fromLink? string
function ItemLoot:OnItemReadyToShow(info, amount, fromLink)
	self.pendingItemRequests[info.itemId] = nil
	local e = ItemLoot.Element:new(info, amount, fromLink)
	e:SetHighlight()
	e:Show(info.itemName, info.itemQuality)
	e:PlaySoundIfEnabled()
end

function ItemLoot:GET_ITEM_INFO_RECEIVED(eventName, itemID, success)
	LogInfo(eventName, "WOWEVENT", self.moduleName, nil, eventName .. " " .. itemID)
	if self.pendingItemRequests[itemID] then
		local itemLink, amount, fromLink = unpack(self.pendingItemRequests[itemID])

		if not success then
			error("Failed to load item: " .. itemID .. " " .. itemLink .. " x" .. amount)
		else
			local info = ItemInfo:new(itemID, ItemLoot._itemLootAdapter.GetItemInfo(itemLink))
			if info == nil then
				LogDebug("ItemInfo is nil for " .. itemLink, addonName, self.moduleName)
				return
			end
			self:OnItemReadyToShow(info, amount, fromLink)
		end
	end
end

function ItemLoot:ShowItemLoot(msg, itemLink, fromLink)
	local amount = tonumber(msg:match("r ?x(%d+)") or 1) or 1
	local itemId = ItemLoot._itemLootAdapter.GetItemIDForItemInfo(itemLink)
	self.pendingItemRequests[itemId] = { itemLink, amount, fromLink }
	local info = ItemInfo:new(itemId, ItemLoot._itemLootAdapter.GetItemInfo(itemLink))
	if info ~= nil then
		self:OnItemReadyToShow(info, amount, fromLink)
	end
end

-- Function to extract item links from the message
local function extractItemLinks(message)
	local itemLinks = {}
	for itemLink in message:gmatch("|c.-|Hitem:.-|h%[.-%]|h|r") do
		table.insert(itemLinks, itemLink)
	end
	return itemLinks
end

function ItemLoot:CHAT_MSG_LOOT(eventName, ...)
	local msg, playerName, _, _, playerName2, _, _, _, _, _, _, guid = ...
	if ItemLoot._itemLootAdapter.IssecretValue(msg) then
		LogWarn("(" .. eventName .. ") Secret value detected, ignoring chat message", "WOWEVENT", self.moduleName, "")
		return
	end

	LogInfo(eventName, "WOWEVENT", self.moduleName, nil, eventName .. " " .. msg)

	local raidLoot = msg:match("HlootHistory:")
	if raidLoot then
		-- Ignore this message as it's a raid loot message
		LogDebug("Raid Loot Ignored", "WOWEVENT", self.moduleName, "", msg)
		return
	end

	local me = false
	if IsRetail() then
		me = guid == ItemLoot._itemLootAdapter.GetPlayerGuid()
	-- So far, MoP Classic and below doesn't work with GetPlayerGuid()
	else
		me = playerName2 == ItemLoot._itemLootAdapter.UnitName("player")
	end

	-- Only process our own loot now, party loot is handled by PartyLoot module
	if not me then
		LogDebug("Loot ignored, not me", "WOWEVENT", self.moduleName, "", msg)
		return
	end

	local itemLink, fromLink = nil, nil
	local itemLinks = extractItemLinks(msg)

	-- Item Upgrades
	if #itemLinks == 2 then
		fromLink = itemLinks[1]
		itemLink = itemLinks[2]
	else
		itemLink = itemLinks[1]
	end

	if itemLink then
		self:ShowItemLoot(msg, itemLink, fromLink)
	end
end

return ItemLoot
