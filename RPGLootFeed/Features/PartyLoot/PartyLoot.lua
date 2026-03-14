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

-- ── WoW API / Global abstraction adapter ─────────────────────────────────────
-- The shared adapter lives in WoWAPIAdapters.lua (G_RLF.WoWAPI.PartyLoot).
-- Captured here at module-load time so tests can override _partyLootAdapter
-- per-test without patching _G.

---@class RLF_PartyLoot: RLF_Module, AceEvent-3.0
local PartyLoot = FeatureBase:new(FeatureModule.PartyLoot, "AceEvent-3.0")

PartyLoot._partyLootAdapter = G_RLF.WoWAPI.PartyLoot

local onlyEpicPartyLoot = false

--- Builds a uniform payload table for a party loot event.
--- Filtering (quality, ignore list) must be applied by the caller before
--- invoking this method.  Returns nil when the module is disabled.
---@param info RLF_ItemInfo
---@param amount number
---@param unit string
---@return RLF_ElementPayload?
function PartyLoot:BuildPayload(info, amount, unit)
	if not PartyLoot:IsEnabled() then
		return nil
	end

	local payload = {}

	payload.key = info.itemLink
	payload.type = FeatureModule.PartyLoot
	payload.isLink = true
	payload.unit = unit

	payload.icon = info.itemTexture
	local partyConfig = G_RLF.DbAccessor:AnyFeatureConfig("partyLoot") or {}
	if not partyConfig.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		payload.icon = nil
	end

	if info.keystoneInfo ~= nil then
		payload.quality = ItemQualEnum.Epic
	end

	local itemLink = info.itemLink
	payload.textFn = function(existingQuantity, truncatedLink)
		if not truncatedLink then
			return itemLink
		end
		return truncatedLink
	end

	payload.quantity = amount
	payload.amountTextFn = function(existingQuantity)
		local effectiveQuantity = (existingQuantity or 0) + amount
		if effectiveQuantity == 1 and not G_RLF.db.global.misc.showOneQuantity then
			return ""
		end
		return "x" .. effectiveQuantity
	end

	payload.secondaryText = "A former party member"
	local name, server = PartyLoot._partyLootAdapter.UnitName(unit)
	if name then
		local pConfig = G_RLF.DbAccessor:AnyFeatureConfig("partyLoot") or {}
		if server and pConfig.hideServerNames == false then
			payload.secondaryText = "    " .. name .. "-" .. server
		else
			payload.secondaryText = "    " .. name
		end
	end

	local equipmentTypeText = info:GetEquipmentTypeText()
	if equipmentTypeText then
		payload.secondaryText = payload.secondaryText .. equipmentTypeText
	end

	payload.secondaryTextFn = function()
		return payload.secondaryText
	end

	if PartyLoot._partyLootAdapter.GetExpansionLevel() >= Expansion.BFA then
		payload.secondaryTextColor =
			PartyLoot._partyLootAdapter.GetClassColor(select(2, PartyLoot._partyLootAdapter.UnitClass(unit)))
	else
		payload.secondaryTextColor =
			PartyLoot._partyLootAdapter.GetRaidClassColor(select(2, PartyLoot._partyLootAdapter.UnitClass(unit)))
	end

	payload.IsEnabled = function()
		return PartyLoot:IsEnabled()
	end

	return payload
end

function PartyLoot:OnInitialize()
	self.pendingItemRequests = {}
	self.pendingPartyRequests = {}
	self.nameUnitMap = {}
	if G_RLF.DbAccessor:IsFeatureNeededByAnyFrame("partyLoot") then
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
	local plConfig = G_RLF.DbAccessor:AnyFeatureConfig("partyLoot") or {}
	if PartyLoot._partyLootAdapter.IsInRaid() and plConfig.onlyEpicAndAboveInRaid then
		onlyEpicPartyLoot = true
		return
	end

	if PartyLoot._partyLootAdapter.IsInInstance() and plConfig.onlyEpicAndAboveInInstance then
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
	local plFilterConfig = G_RLF.DbAccessor:AnyFeatureConfig("partyLoot") or {}
	-- nil quality filter entry = quality not enabled (treat same as false)
	if not (plFilterConfig.itemQualityFilter or {})[info.itemQuality] then
		return
	end
	-- Filter by ignored item IDs
	local ignoredIds = plFilterConfig.ignoreItemIds or {}
	if #ignoredIds > 0 then
		for _, id in ipairs(ignoredIds) do
			if tonumber(id) == tonumber(info.itemId) then
				LogDebug(
					info.itemName .. " ignored by item id in party loot",
					addonName,
					PartyLoot.moduleName,
					info.itemId,
					nil,
					amount
				)
				return
			end
		end
	end
	self.pendingPartyRequests[info.itemId] = nil

	local payload = PartyLoot:BuildPayload(info, amount, unit)
	if not payload then
		return
	end
	local e = LootElementBase:fromPayload(payload)
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
	if not G_RLF.DbAccessor:IsFeatureNeededByAnyFrame("partyLoot") then
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
