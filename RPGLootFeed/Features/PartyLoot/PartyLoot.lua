---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_PartyLoot: RLF_Module, AceEvent-3.0
local PartyLoot = G_RLF.RLF:NewModule("PartyLoot", "AceEvent-3.0")

local C = LibStub("C_Everywhere")
local ItemInfo = G_RLF.ItemInfo
local onlyEpicPartyLoot = false

-- Create PartyLoot.Element namespace
PartyLoot.Element = {}

function PartyLoot.Element:new(...)
	---@class PartyLoot.Element: RLF_BaseLootElement
	local element = {}
	G_RLF.InitializeLootDisplayProperties(element)

	element.type = "PartyLoot"
	element.IsEnabled = function()
		return PartyLoot:IsEnabled()
	end

	element.isLink = true
	element.eventChannel = "RLF_NEW_PARTY_LOOT"

	---@type RLF_ItemInfo
	local info
	info, element.quantity, element.unit = ...
	local itemLink = info.itemLink

	element.itemId = info.itemId
	element.key = info.itemLink
	element.icon = info.itemTexture

	if info.keystoneInfo ~= nil then
		element.quality = Enum.ItemQuality.Epic
	end

	function element:isPassingFilter(itemName, itemQuality)
		if not G_RLF.db.global.partyLoot.itemQualityFilter[itemQuality] then
			G_RLF:LogDebug(
				itemName .. " ignored by quality in party loot",
				addonName,
				"PartyLoot",
				"",
				nil,
				self.quantity
			)
			return false
		end

		local ignoredIds = G_RLF.db.global.partyLoot.ignoreItemIds

		if #ignoredIds == 0 then
			G_RLF:LogDebug(
				itemName .. " passed because there are no configured ignored item ids",
				addonName,
				PartyLoot.moduleName,
				self.itemId,
				nil,
				self.quantity
			)
			return true
		end

		for _, id in ipairs(G_RLF.db.global.partyLoot.ignoreItemIds) do
			if tonumber(id) == tonumber(self.itemId) then
				G_RLF:LogDebug(
					itemName .. " ignored by item id in party loot",
					addonName,
					PartyLoot.moduleName,
					self.itemId,
					nil,
					self.quantity
				)
				return false
			else
				G_RLF:LogDebug(
					itemName .. " passed because it does not match the configured ignored item id: " .. id,
					addonName,
					PartyLoot.moduleName,
					self.itemId,
					nil,
					self.quantity
				)
			end
		end

		return true
	end

	element.textFn = function(existingQuantity, truncatedLink)
		if not truncatedLink then
			return itemLink
		end
		return truncatedLink .. " x" .. ((existingQuantity or 0) + element.quantity)
	end

	element.secondaryText = "A former party member"
	local name, server = UnitName(element.unit)
	if name then
		if server and G_RLF.db.global.partyLoot.hideServerNames == false then
			element.secondaryText = "    " .. name .. "-" .. server
		else
			element.secondaryText = "    " .. name
		end
	end

	element.unitClass = select(2, UnitClass(element.unit))
	if GetExpansionLevel() >= G_RLF.Expansion.BFA then
		element.secondaryTextColor = C_ClassColor.GetClassColor(select(2, UnitClass(element.unit)))
	else
		element.secondaryTextColor = RAID_CLASS_COLORS[select(2, UnitClass(element.unit))]
	end

	element.secondaryTextFn = function()
		return element.secondaryText
	end

	return element
end

function PartyLoot:OnInitialize()
	self.pendingItemRequests = {}
	self.pendingPartyRequests = {}
	self.nameUnitMap = {}
	if G_RLF.db.global.partyLoot.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function PartyLoot:OnDisable()
	self:UnregisterEvent("CHAT_MSG_LOOT")
	self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	self:UnregisterEvent("GROUP_ROSTER_UPDATE")
end

function PartyLoot:OnEnable()
	self:RegisterEvent("CHAT_MSG_LOOT")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:SetNameUnitMap()
	self:SetPartyLootFilters()
	G_RLF:LogDebug("OnEnable", addonName, self.moduleName)
end

function PartyLoot:SetNameUnitMap()
	local units = {}
	local groupMembers = GetNumGroupMembers()
	if IsInRaid() then
		for i = 1, groupMembers do
			table.insert(units, "raid" .. i)
		end
	else
		table.insert(units, "player")

		for i = 2, groupMembers do
			table.insert(units, "party" .. (i - 1))
		end
	end

	self.nameUnitMap = {}
	for _, unit in ipairs(units) do
		local name, server = UnitName(unit)
		if name then
			self.nameUnitMap[name] = unit
		else
			G_RLF:LogError("Failed to get name for unit: " .. unit, addonName, self.moduleName)
		end
	end
end

function PartyLoot:SetPartyLootFilters()
	if IsInRaid() and G_RLF.db.global.partyLoot.onlyEpicAndAboveInRaid then
		onlyEpicPartyLoot = true
		return
	end

	if IsInInstance() and G_RLF.db.global.partyLoot.onlyEpicAndAboveInInstance then
		onlyEpicPartyLoot = true
		return
	end

	onlyEpicPartyLoot = false
end

function PartyLoot:OnPartyReadyToShow(info, amount, unit)
	if not unit then
		return
	end
	if onlyEpicPartyLoot and info.itemQuality < Enum.ItemQuality.Epic then
		return
	end
	if G_RLF.db.global.partyLoot.itemQualityFilter[info.itemQuality] == false then
		return
	end
	self.pendingPartyRequests[info.itemId] = nil

	-- Create element using PartyLoot's own Element class
	local e = PartyLoot.Element:new(info, amount, unit)
	e:Show(info.itemName, info.itemQuality)
end

function PartyLoot:ShowPartyLoot(msg, itemLink, unit)
	local amount = tonumber(msg:match("r ?x(%d+)") or 1)
	local itemId = itemLink:match("Hitem:(%d+)")
	self.pendingPartyRequests[itemId] = { itemLink, amount, unit }
	local info = ItemInfo:new(itemId, C.Item.GetItemInfo(itemLink))
	if info ~= nil then
		self:OnPartyReadyToShow(info, amount, unit)
	end
end

-- Function to extract item links from the message
local function extractItemLinks(message)
	local itemLinks = {}
	for itemLink in message:gmatch("|c%x+|Hitem:.-|h%[.-%]|h|r") do
		table.insert(itemLinks, itemLink)
	end
	return itemLinks
end

function PartyLoot:CHAT_MSG_LOOT(eventName, ...)
	if not G_RLF.db.global.partyLoot.enabled then
		return
	end

	local msg, playerName, _, _, playerName2, _, _, _, _, _, _, guid = ...
	G_RLF:LogInfo(eventName, "WOWEVENT", self.moduleName, nil, eventName .. " " .. msg)
	local raidLoot = msg:match("HlootHistory:")
	if raidLoot then
		-- Ignore this message as it's a raid loot message
		return
	end

	local me = false
	if G_RLF:IsRetail() then
		me = guid == GetPlayerGuid()
	elseif G_RLF:IsClassic() or G_RLF:IsCataClassic() then
		me = playerName2 == UnitName("player")
	end

	if me then
		-- Ignore our own loot, handled by ItemLoot
		return
	end

	local name = playerName
	if name == "" or name == nil then
		name = playerName2
	end
	local sanitizedPlayerName = name:gsub("%-.+", "")
	local unit = self.nameUnitMap[sanitizedPlayerName]
	if not unit then
		G_RLF:LogDebug(
			"Party Loot Ignored - no matching party member (" .. sanitizedPlayerName .. ")",
			"WOWEVENT",
			self.moduleName,
			"",
			msg
		)
		return
	end

	local itemLinks = extractItemLinks(msg)
	local itemLink = itemLinks[1]

	if #itemLinks == 2 then
		-- Item upgrades are not supported for party members currently
		G_RLF:LogDebug(
			"Party item upgrades are apparently captured in CHAT_MSG_LOOT. TODO: may need to support this.",
			addonName,
			self.moduleName
		)
		return
	end

	if itemLink then
		self:fn(self.ShowPartyLoot, self, msg, itemLink, unit)
	end
end

function PartyLoot:GET_ITEM_INFO_RECEIVED(eventName, itemID, success)
	if self.pendingPartyRequests[itemID] then
		local itemLink, amount, unit = unpack(self.pendingPartyRequests[itemID])

		if not success then
			error("Failed to load item: " .. itemID .. " " .. itemLink .. " x" .. amount .. " for " .. unit)
		else
			local info = ItemInfo:new(itemID, C.Item.GetItemInfo(itemLink))
			self:OnPartyReadyToShow(info, amount, unit)
		end
	end
end

function PartyLoot:GROUP_ROSTER_UPDATE(eventName, ...)
	G_RLF:LogInfo(eventName, "WOWEVENT", self.moduleName, nil, eventName)
	self:SetNameUnitMap()
	self:SetPartyLootFilters()
end

return PartyLoot
