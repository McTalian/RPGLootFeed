---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's full
-- dependency surface on G_RLF / ns is visible in one place.  Tests pass a
-- minimal mock ns to loadfile("PartyLoot.lua") to control these at
-- injection time without the full nsMocks framework.
-- NOTE: G_RLF.db is intentionally absent – AceDB populates it in
-- OnInitialize, so it must remain a runtime lookup inside function bodies.
local LootElementBase = G_RLF.LootElementBase
local ItemQualEnum = G_RLF.ItemQualEnum
local FeatureBase = G_RLF.FeatureBase
local FeatureModule = G_RLF.FeatureModule
local Expansion = G_RLF.Expansion
local ItemInfo = G_RLF.ItemInfo
local LogDebug = function(...)
	G_RLF:LogDebug(...)
end
local LogInfo = function(...)
	G_RLF:LogInfo(...)
end
local LogWarn = function(...)
	G_RLF:LogWarn(...)
end
local LogError = function(...)
	G_RLF:LogError(...)
end
local IsRetail = function()
	return G_RLF:IsRetail()
end

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- Wraps UnitName, UnitClass, IsInRaid, IsInInstance, GetNumGroupMembers,
-- GetExpansionLevel, GetPlayerGuid, C_ClassColor, RAID_CLASS_COLORS, and the
-- C_Everywhere item query so tests can inject mocks without patching _G.
local C = LibStub("C_Everywhere")
local PartyLootAdapter = {
	UnitName = function(unit)
		return UnitName(unit)
	end,
	UnitClass = function(unit)
		return UnitClass(unit)
	end,
	IssecretValue = function(msg)
		return issecretvalue and issecretvalue(msg)
	end,
	GetNumGroupMembers = function()
		return GetNumGroupMembers()
	end,
	IsInRaid = function()
		return IsInRaid()
	end,
	IsInInstance = function()
		return IsInInstance()
	end,
	GetExpansionLevel = function()
		return GetExpansionLevel()
	end,
	GetPlayerGuid = function()
		return GetPlayerGuid()
	end,
	GetClassColor = function(className)
		return C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(className)
	end,
	GetRaidClassColor = function(className)
		return RAID_CLASS_COLORS and RAID_CLASS_COLORS[className]
	end,
	GetItemInfo = function(itemLink)
		return C.Item.GetItemInfo(itemLink)
	end,
}

---@class RLF_PartyLoot: RLF_Module, AceEvent-3.0
local PartyLoot = FeatureBase:new(FeatureModule.PartyLoot, "AceEvent-3.0")

PartyLoot._partyLootAdapter = PartyLootAdapter

local onlyEpicPartyLoot = false

-- Create PartyLoot.Element namespace
PartyLoot.Element = {}

function PartyLoot.Element:new(...)
	---@class PartyLoot.Element: RLF_BaseLootElement
	local element = LootElementBase:new()

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
	if not G_RLF.db.global.partyLoot.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		element.icon = nil
	end

	if info.keystoneInfo ~= nil then
		element.quality = ItemQualEnum.Epic
	end

	function element:isPassingFilter(itemName, itemQuality)
		if not G_RLF.db.global.partyLoot.itemQualityFilter[itemQuality] then
			LogDebug(itemName .. " ignored by quality in party loot", addonName, "PartyLoot", "", nil, self.quantity)
			return false
		end

		local ignoredIds = G_RLF.db.global.partyLoot.ignoreItemIds

		if #ignoredIds == 0 then
			LogDebug(
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
				LogDebug(
					itemName .. " ignored by item id in party loot",
					addonName,
					PartyLoot.moduleName,
					self.itemId,
					nil,
					self.quantity
				)
				return false
			else
				LogDebug(
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

	element.secondaryText = "A former party member"
	local name, server = PartyLoot._partyLootAdapter.UnitName(element.unit)
	if name then
		if server and G_RLF.db.global.partyLoot.hideServerNames == false then
			element.secondaryText = "    " .. name .. "-" .. server
		else
			element.secondaryText = "    " .. name
		end
	end

	local equipmentTypeText = info:GetEquipmentTypeText()
	if equipmentTypeText then
		element.secondaryText = element.secondaryText .. equipmentTypeText
	end

	element.unitClass = select(2, PartyLoot._partyLootAdapter.UnitClass(element.unit))
	if PartyLoot._partyLootAdapter.GetExpansionLevel() >= Expansion.BFA then
		element.secondaryTextColor =
			PartyLoot._partyLootAdapter.GetClassColor(select(2, PartyLoot._partyLootAdapter.UnitClass(element.unit)))
	else
		element.secondaryTextColor = PartyLoot._partyLootAdapter.GetRaidClassColor(
			select(2, PartyLoot._partyLootAdapter.UnitClass(element.unit))
		)
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
	LogDebug("OnEnable", addonName, self.moduleName)
end

function PartyLoot:SetNameUnitMap()
	local units = {}
	local groupMembers = PartyLoot._partyLootAdapter.GetNumGroupMembers()
	if PartyLoot._partyLootAdapter.IsInRaid() then
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
		local name, server = PartyLoot._partyLootAdapter.UnitName(unit)
		if name then
			self.nameUnitMap[name] = unit
		else
			LogError("Failed to get name for unit: " .. unit, addonName, self.moduleName)
		end
	end
end

function PartyLoot:SetPartyLootFilters()
	if PartyLoot._partyLootAdapter.IsInRaid() and G_RLF.db.global.partyLoot.onlyEpicAndAboveInRaid then
		onlyEpicPartyLoot = true
		return
	end

	if PartyLoot._partyLootAdapter.IsInInstance() and G_RLF.db.global.partyLoot.onlyEpicAndAboveInInstance then
		onlyEpicPartyLoot = true
		return
	end

	onlyEpicPartyLoot = false
end

function PartyLoot:OnPartyReadyToShow(info, amount, unit)
	if not unit then
		return
	end
	if onlyEpicPartyLoot and info.itemQuality < ItemQualEnum.Epic then
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
	local info = ItemInfo:new(itemId, PartyLoot._partyLootAdapter.GetItemInfo(itemLink))
	if info ~= nil then
		self:OnPartyReadyToShow(info, amount, unit)
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

function PartyLoot:CHAT_MSG_LOOT(eventName, ...)
	if not G_RLF.db.global.partyLoot.enabled then
		return
	end

	local msg, playerName, _, _, playerName2, _, _, _, _, _, _, guid = ...
	if PartyLoot._partyLootAdapter.IssecretValue(msg) then
		LogWarn("(" .. eventName .. ") Secret value detected, ignoring chat message", "WOWEVENT", self.moduleName, "")
		return
	end

	LogInfo(eventName, "WOWEVENT", self.moduleName, nil, eventName .. " " .. msg)

	local raidLoot = msg:match("HlootHistory:")
	if raidLoot then
		-- Ignore this message as it's a raid loot message
		return
	end

	local me = false
	if IsRetail() then
		me = guid == PartyLoot._partyLootAdapter.GetPlayerGuid()
	-- So far, MoP Classic and below doesn't work with GetPlayerGuid()
	else
		me = playerName2 == PartyLoot._partyLootAdapter.UnitName("player")
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
		LogDebug(
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
		LogDebug(
			"Party item upgrades are apparently captured in CHAT_MSG_LOOT. TODO: may need to support this.",
			addonName,
			self.moduleName
		)
		return
	end

	if itemLink then
		self.ShowPartyLoot(self, msg, itemLink, unit)
	end
end

function PartyLoot:GET_ITEM_INFO_RECEIVED(eventName, itemID, success)
	if self.pendingPartyRequests[itemID] then
		local itemLink, amount, unit = unpack(self.pendingPartyRequests[itemID])

		if not success then
			error("Failed to load item: " .. itemID .. " " .. itemLink .. " x" .. amount .. " for " .. unit)
		else
			local info = ItemInfo:new(itemID, PartyLoot._partyLootAdapter.GetItemInfo(itemLink))
			self:OnPartyReadyToShow(info, amount, unit)
		end
	end
end

function PartyLoot:GROUP_ROSTER_UPDATE(eventName, ...)
	LogInfo(eventName, "WOWEVENT", self.moduleName, nil, eventName)
	self:SetNameUnitMap()
	self:SetPartyLootFilters()
end

return PartyLoot
