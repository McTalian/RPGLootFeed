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
-- The shared adapter lives in WoWAPIAdapters.lua (G_RLF.WoWAPI.ItemLoot).
-- Captured here at module-load time so tests can override _itemLootAdapter
-- without patching _G directly.

---@class RLF_ItemLoot: RLF_Module, AceEvent-3.0, AceBucket-3.0
local ItemLoot = FeatureBase:new(FeatureModule.ItemLoot, "AceEvent-3.0", "AceBucket-3.0")

ItemLoot._itemLootAdapter = G_RLF.WoWAPI.ItemLoot

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
---@return RLF_ElementPayload|nil
function ItemLoot:BuildPayload(info, quantity, fromLink)
	-- Quality filter: return nil when the item's quality tier is disabled
	local itemConfig = G_RLF.DbAccessor:AnyFeatureConfig("itemLoot") or {}
	local itemQualitySettings = (itemConfig.itemQualitySettings or {})[info.itemQuality]
	if not itemQualitySettings or not itemQualitySettings.enabled then
		LogDebug(
			tostring(info.itemName) .. " ignored by quality: " .. tostring(ItemLoot:ItemQualityName(info.itemQuality)),
			addonName,
			"ItemLoot",
			"",
			nil,
			quantity
		)
		return nil
	end

	local itemLink = info.itemLink
	local key = itemLink
	local fromInfo = nil
	if fromLink then
		key = "UPGRADE_" .. key
		fromInfo = ItemInfo:new(
			ItemLoot._itemLootAdapter.GetItemIDForItemInfo(fromLink),
			ItemLoot._itemLootAdapter.GetItemInfo(fromLink)
		)
	end

	local icon = info.itemTexture
	if not itemConfig.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		icon = nil
	end

	local showForSeconds = nil
	if itemQualitySettings.duration > 0 then
		showForSeconds = itemQualitySettings.duration
	end

	-- Keystone: force display quality to Epic
	local quality = nil
	if info:IsKeystone() then
		quality = info:GetDisplayQuality()
	end

	local topLeftText = nil
	local topLeftColor = nil
	if info:IsEquippableItem() and info.itemQuality > ItemQualEnum.Poor then
		topLeftText = tostring(info.itemLevel)
		local r, g, b = ItemLoot._itemLootAdapter.GetItemQualityColor(info.itemQuality)
		topLeftColor = { r, g, b }
	end

	-- ── Compute item flags ────────────────────────────────────────────────────
	local isMount = info:IsMount()
	local isLegendary = info:IsLegendary()
	local isBetterThanEquipped = IsBetterThanEquipped(info)
	local hasTertiaryOrSocket = info:HasItemRollBonus()
	local isQuestItem = info:IsQuestItem()
	local isNewTransmog = not info:IsAppearanceCollected()

	-- ── Highlight ────────────────────────────────────────────────────────────
	local itemHighlights = itemConfig.itemHighlights or {}
	local highlightReason = (isMount and itemHighlights.mounts and "Mount")
		or (isLegendary and itemHighlights.legendary and "Legendary")
		or (isBetterThanEquipped and itemHighlights.betterThanEquipped and "Better than Equipped")
		or (isQuestItem and itemHighlights.quest and "Quest Item")
		or (hasTertiaryOrSocket and itemHighlights.tertiaryOrSocket and "Tertiary or Socket")
		or (isNewTransmog and itemHighlights.transmog and "New Transmog")
	local highlight = highlightReason and true or false
	if highlight then
		LogDebug("Highlighted because of " .. highlightReason, addonName, ItemLoot.moduleName, key)
	end

	-- ── Quest color override ─────────────────────────────────────────────────
	local r, g, b, a = nil, nil, nil, nil
	local textStyleOverrides = itemConfig.textStyleOverrides or {}
	if isQuestItem and textStyleOverrides.quest and textStyleOverrides.quest.enabled then
		r, g, b, a = unpack(textStyleOverrides.quest.color)
	end

	-- ── Sound: first matching condition wins ─────────────────────────────────
	local soundPath = nil
	local soundsConfig = itemConfig.sounds or {}
	if isMount and soundsConfig.mounts.enabled and soundsConfig.mounts.sound ~= "" then
		soundPath = soundsConfig.mounts.sound
	elseif isLegendary and soundsConfig.legendary.enabled and soundsConfig.legendary.sound ~= "" then
		soundPath = soundsConfig.legendary.sound
	elseif
		isBetterThanEquipped
		and soundsConfig.betterThanEquipped.enabled
		and soundsConfig.betterThanEquipped.sound ~= ""
	then
		soundPath = soundsConfig.betterThanEquipped.sound
	elseif isNewTransmog and soundsConfig.transmog.enabled and soundsConfig.transmog.sound ~= "" then
		soundPath = soundsConfig.transmog.sound
	end

	-- ── Payload ───────────────────────────────────────────────────────────────
	local payload = {
		key = key,
		type = FeatureModule.ItemLoot,
		icon = icon,
		quality = quality,
		topLeftText = topLeftText,
		topLeftColor = topLeftColor,
		isLink = true,
		quantity = quantity,
		showForSeconds = showForSeconds,
		highlight = highlight,
		sound = soundPath,
		r = r,
		g = g,
		b = b,
		a = a,
		IsEnabled = function()
			return ItemLoot:IsEnabled()
		end,
	}

	payload.textFn = function(existingQuantity, truncatedLink)
		if not truncatedLink then
			return itemLink
		end
		local text = truncatedLink
		local tso = (G_RLF.DbAccessor:AnyFeatureConfig("itemLoot") or {}).textStyleOverrides or {}
		if isQuestItem and tso.quest and tso.quest.enabled then
			local qr, qg, qb, qa = unpack(tso.quest.color)
			-- Replace the color in the link portion of the text with the quest color
			text = text:gsub("|c.-|", RGBAToHexFormat(qr, qg, qb, qa) .. "|")
		end
		return text
	end

	payload.amountTextFn = function(existingQuantity)
		local effectiveQuantity = (existingQuantity or 0) + quantity
		if effectiveQuantity == 1 and not G_RLF.db.global.misc.showOneQuantity then
			return ""
		end
		return "x" .. effectiveQuantity
	end

	payload.secondaryTextFn = function(...)
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

		local effectiveQuantity = ... or 1
		local itemCfg = G_RLF.DbAccessor:AnyFeatureConfig("itemLoot") or {}
		local vendorIcon = itemCfg.vendorIconTexture
		local auctionIcon = itemCfg.auctionHouseIconTexture
		local vendorPrice, auctionPrice = 0, 0
		local pricesForSellableItems = itemCfg.pricesForSellableItems
		if info.sellPrice and info.sellPrice > 0 then
			vendorPrice = info.sellPrice
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

	-- itemCountFn: replaces the ItemLoot branch in RowTextMixin:UpdateItemCount
	payload.itemCountFn = function()
		local itemDb = G_RLF.DbAccessor:AnyFeatureConfig("itemLoot") or {}
		if not itemDb.itemCountTextEnabled then
			return nil
		end
		local success, name = pcall(function()
			return ItemLoot._itemLootAdapter.GetItemInfo(itemLink)
		end)
		if not success or not name then
			return nil
		end
		local itemCount = ItemLoot._itemLootAdapter.GetItemCount(itemLink, true, false, true, true)
		return itemCount,
			{
				color = G_RLF:RGBAToHexFormat(unpack(itemDb.itemCountTextColor)),
				wrapChar = itemDb.itemCountTextWrapChar,
			}
	end

	return payload
end

--- Play the appropriate item sound if one is configured in the payload.
--- Called after Show() in the event handler pipeline.
---@param payload RLF_ElementPayload
function ItemLoot:PlaySoundIfEnabled(payload)
	if not payload or not payload.sound then
		return
	end
	local willPlay, handle = ItemLoot._itemLootAdapter.PlaySoundFile(payload.sound)
	if not willPlay then
		LogWarn("Failed to play sound " .. payload.sound, addonName, ItemLoot.moduleName)
	else
		LogDebug("Sound queued to play " .. payload.sound .. " " .. handle, addonName, ItemLoot.moduleName)
	end
end

function ItemLoot:OnInitialize()
	self.pendingItemRequests = {}
	if G_RLF.DbAccessor:IsFeatureNeededByAnyFrame("itemLoot") then
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
	local payload = self:BuildPayload(info, amount, fromLink)
	if not payload then
		return
	end
	LootElementBase:fromPayload(payload):Show(info.itemName, info.itemQuality)
	self:PlaySoundIfEnabled(payload)
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
