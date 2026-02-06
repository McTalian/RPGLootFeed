---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_Transmog: RLF_Module, AceEvent-3.0
local Transmog = G_RLF.RLF:NewModule(G_RLF.FeatureModule.Transmog, "AceEvent-3.0")

Transmog.Element = {}

function Transmog.Element:new(transmogLink, icon)
	---@class Transmog.Element: RLF_BaseLootElement
	local element = {}
	G_RLF.InitializeLootDisplayProperties(element)

	element.type = Transmog.moduleName
	element.IsEnabled = function()
		return Transmog:IsEnabled()
	end

	element.isLink = true
	element.key = "TMOG_" .. transmogLink
	element.icon = icon or G_RLF.DefaultIcons.TRANSMOG
	if not G_RLF.db.global.transmog.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		element.icon = nil
	end
	element.quality = G_RLF.ItemQualEnum.Epic
	element.highlight = G_RLF:IsRetail()
	element.textFn = function(_, truncatedLink)
		if not truncatedLink or truncatedLink == "" then
			return transmogLink
		end

		return truncatedLink
	end

	element.secondaryTextFn = function(...)
		local str = string.format(_G["ERR_LEARN_TRANSMOG_S"], " "):trim()
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
	G_RLF:LogDebug("OnEnable", addonName, self.moduleName)
	self:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
end

function Transmog:OnDisable()
	self:UnregisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
end

function Transmog:TRANSMOG_COLLECTION_SOURCE_ADDED(eventName, itemModifiedAppearanceID)
	G_RLF:LogInfo(eventName, "WOWEVENT", self.moduleName, itemModifiedAppearanceID)

	local info = C_TransmogCollection.GetAppearanceSourceInfo(itemModifiedAppearanceID)

	if not info then
		G_RLF:LogWarn("Could not get appearance source info", addonName, self.moduleName)
		return
	end

	local itemLink = info.itemLink
	local transmogLink = info.transmoglink
	local icon = info.icon

	if not transmogLink or transmogLink == "" then
		G_RLF:LogWarn("Transmog link is empty for " .. itemModifiedAppearanceID, addonName, self.moduleName)
		if itemLink and itemLink ~= "" then
			local item = Item:CreateFromItemLink(itemLink)
			if item then
				item:ContinueOnItemLoad(function()
					info = C_TransmogCollection.GetAppearanceSourceInfo(itemModifiedAppearanceID)
					if not info then
						G_RLF:LogWarn("Could not get appearance source info on item load", addonName, self.moduleName)
						return
					end

					itemLink = info.itemLink
					transmogLink = info.transmoglink
					icon = info.icon

					if not transmogLink or transmogLink == "" then
						G_RLF:LogWarn(
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
						G_RLF:LogWarn("Could not create Transmog Element", addonName, self.moduleName)
					end
				end)
			end
		else
			G_RLF:LogWarn("Item link is also empty for " .. itemModifiedAppearanceID, addonName, self.moduleName)
		end
		return
	end

	local e = self.Element:new(transmogLink, icon)
	if e then
		e:Show()
	else
		G_RLF:LogWarn("Could not create Transmog Element", addonName, self.moduleName)
	end
end

return Transmog
