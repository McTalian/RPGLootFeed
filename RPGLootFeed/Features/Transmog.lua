---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's full
-- dependency surface on G_RLF / ns is visible in one place.  Tests pass a
-- minimal mock ns to loadfile("Transmog.lua") to control these at
-- injection time without the full nsMocks framework.
-- NOTE: G_RLF.db is intentionally absent – AceDB populates it in
-- OnInitialize, so it must remain a runtime lookup inside function bodies.
local LootElementBase = G_RLF.LootElementBase
local DefaultIcons = G_RLF.DefaultIcons
local ItemQualEnum = G_RLF.ItemQualEnum
local FeatureBase = G_RLF.FeatureBase
local FeatureModule = G_RLF.FeatureModule
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

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- Each adapter wraps a surface of the WoW API or global state so the feature
-- code only deals with inputs and outputs.  These local tables are the
-- per-feature precursor to the planned top-level Abstractions/ folder; when
-- that consolidation happens, the adapter tables will simply be replaced with
-- references to the shared modules from that folder.

local TransmogCollectionAdapter = {
	GetAppearanceSourceInfo = function(itemModifiedAppearanceID)
		return C_TransmogCollection.GetAppearanceSourceInfo(itemModifiedAppearanceID)
	end,
	CreateItemFromItemLink = function(itemLink)
		return Item:CreateFromItemLink(itemLink)
	end,
}

local GlobalStringsAdapter = {
	--- The locale string used as the label for learning a transmog appearance.
	GetErrLearnTransmogS = function()
		return _G["ERR_LEARN_TRANSMOG_S"]
	end,
}

---@class RLF_Transmog: RLF_Module, AceEvent-3.0
local Transmog = FeatureBase:new(FeatureModule.Transmog, "AceEvent-3.0")

Transmog._transmogCollectionAdapter = TransmogCollectionAdapter
Transmog._globalStringsAdapter = GlobalStringsAdapter

Transmog.Element = {}

function Transmog.Element:new(transmogLink, icon)
	---@class Transmog.Element: RLF_BaseLootElement
	local element = LootElementBase:new()

	element.type = Transmog.moduleName
	element.IsEnabled = function()
		return Transmog:IsEnabled()
	end

	element.isLink = true
	element.key = "TMOG_" .. transmogLink
	element.icon = icon or DefaultIcons.TRANSMOG
	if not G_RLF.db.global.transmog.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		element.icon = nil
	end
	element.quality = ItemQualEnum.Epic
	element.highlight = IsRetail()
	element.textFn = function(_, truncatedLink)
		if not truncatedLink or truncatedLink == "" then
			return transmogLink
		end

		return truncatedLink
	end

	element.secondaryTextFn = function(...)
		local str = string.format(Transmog._globalStringsAdapter.GetErrLearnTransmogS(), " "):trim()
		-- Some locales have the string placeholder in the middle of the string, so we should replace any triple spaces
		str = str:gsub("   ", " ")
		-- Let's remove the trailing period if it exists
		str = str:gsub("%.$", "")
		return str
	end

	return element
end

function Transmog:OnInitialize()
	if G_RLF.db.global.transmog.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function Transmog:OnEnable()
	LogDebug("OnEnable", addonName, self.moduleName)
	self:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
end

function Transmog:OnDisable()
	self:UnregisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
end

function Transmog:TRANSMOG_COLLECTION_SOURCE_ADDED(eventName, itemModifiedAppearanceID)
	LogInfo(eventName, "WOWEVENT", self.moduleName, itemModifiedAppearanceID)

	local info = Transmog._transmogCollectionAdapter.GetAppearanceSourceInfo(itemModifiedAppearanceID)

	if not info then
		LogWarn("Could not get appearance source info", addonName, self.moduleName)
		return
	end

	local itemLink = info.itemLink
	local transmogLink = info.transmoglink
	local icon = info.icon

	if not transmogLink or transmogLink == "" then
		LogWarn("Transmog link is empty for " .. itemModifiedAppearanceID, addonName, self.moduleName)
		if itemLink and itemLink ~= "" then
			local item = Transmog._transmogCollectionAdapter.CreateItemFromItemLink(itemLink)
			if item then
				item:ContinueOnItemLoad(function()
					info = Transmog._transmogCollectionAdapter.GetAppearanceSourceInfo(itemModifiedAppearanceID)
					if not info then
						LogWarn("Could not get appearance source info on item load", addonName, self.moduleName)
						return
					end

					itemLink = info.itemLink
					transmogLink = info.transmoglink
					icon = info.icon

					if not transmogLink or transmogLink == "" then
						LogWarn(
							"Transmog link is still empty for " .. itemModifiedAppearanceID,
							addonName,
							self.moduleName
						)
						transmogLink = itemLink
					end

					local e = self.Element:new(transmogLink, icon)
					if e then
						e:Show()
					else
						LogWarn("Could not create Transmog Element", addonName, self.moduleName)
					end
				end)
			end
		else
			LogWarn("Item link is also empty for " .. itemModifiedAppearanceID, addonName, self.moduleName)
		end
		return
	end

	local e = self.Element:new(transmogLink, icon)
	if e then
		e:Show()
	else
		LogWarn("Could not create Transmog Element", addonName, self.moduleName)
	end
end

return Transmog
