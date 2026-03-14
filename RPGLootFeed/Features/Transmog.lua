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

-- ── WoW API / Global abstraction adapter ─────────────────────────────────────
-- The shared adapter lives in WoWAPIAdapters.lua (G_RLF.WoWAPI.Transmog).
-- Captured here at module-load time so tests can override _transmogAdapter
-- per-test without patching _G.

---@class RLF_Transmog: RLF_Module, AceEvent-3.0
local Transmog = FeatureBase:new(FeatureModule.Transmog, "AceEvent-3.0")

Transmog._transmogAdapter = G_RLF.WoWAPI.Transmog

--- Builds a uniform payload table for a transmog collection event.
--- Returns nil when the module is disabled.
---@param transmogLink string
---@param icon string?
---@return RLF_ElementPayload?
function Transmog:BuildPayload(transmogLink, icon)
	if not Transmog:IsEnabled() then
		return nil
	end

	local payload = {}

	payload.key = "TMOG_" .. transmogLink
	payload.type = FeatureModule.Transmog
	payload.isLink = true

	payload.icon = icon or DefaultIcons.TRANSMOG
	local transmogConfig = G_RLF.DbAccessor:AnyFeatureConfig("transmog") or {}
	if not transmogConfig.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		payload.icon = nil
	end

	payload.quality = ItemQualEnum.Epic
	payload.highlight = IsRetail()

	local link = transmogLink
	payload.textFn = function(_, truncatedLink)
		if not truncatedLink or truncatedLink == "" then
			return link
		end
		return truncatedLink
	end

	payload.secondaryTextFn = function()
		local str = string.format(Transmog._transmogAdapter.GetErrLearnTransmogS(), " "):trim()
		-- Some locales have the string placeholder in the middle of the string
		str = str:gsub("   ", " ")
		-- Remove the trailing period if it exists
		str = str:gsub("%.$", "")
		return str
	end

	payload.IsEnabled = function()
		return Transmog:IsEnabled()
	end

	return payload
end

function Transmog:OnInitialize()
	if G_RLF.DbAccessor:IsFeatureNeededByAnyFrame("transmog") then
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

	local info = Transmog._transmogAdapter.GetAppearanceSourceInfo(itemModifiedAppearanceID)

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
			local item = Transmog._transmogAdapter.CreateItemFromItemLink(itemLink)
			if item then
				item:ContinueOnItemLoad(function()
					info = Transmog._transmogAdapter.GetAppearanceSourceInfo(itemModifiedAppearanceID)
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

					local payload = self:BuildPayload(transmogLink, icon)
					if payload then
						local e = LootElementBase:fromPayload(payload)
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

	local payload = self:BuildPayload(transmogLink, icon)
	if payload then
		local e = LootElementBase:fromPayload(payload)
		e:Show()
	else
		LogWarn("Could not create Transmog Element", addonName, self.moduleName)
	end
end

return Transmog
