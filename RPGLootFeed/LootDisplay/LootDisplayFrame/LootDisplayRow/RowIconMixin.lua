---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_RowIconMixin
RLF_RowIconMixin = {}

function RLF_RowIconMixin:StyleIcon()
	local changed = false

	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	---@type RLF_ConfigStyling
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	local iconSize = sizingDb.iconSize
	local leftAlign = stylingDb.leftAlign

	if self.cachedIconSize ~= iconSize then
		self.cachedIconSize = iconSize
		changed = true
	end

	if self.cachedIconLeftAlign ~= leftAlign then
		self.cachedIconLeftAlign = leftAlign
		changed = true
	end

	if changed then
		self.Icon:ClearAllPoints()
		iconSize = G_RLF.PerfPixel.PScale(iconSize)
		self.Icon:SetSize(iconSize, iconSize)
		self.Icon.IconBorder:SetSize(iconSize, iconSize)
		local anchor, xOffset = "LEFT", iconSize / 4
		if not leftAlign then
			anchor, xOffset = "RIGHT", -xOffset
		end
		if G_RLF.Masque and G_RLF.iconGroup then
			G_RLF.iconGroup:AddButton(self.Icon)
		end
		self.Icon:SetPoint(anchor, xOffset, 0)
	end
	self.Icon:SetShown(self.icon ~= nil)
end

function RLF_RowIconMixin:UpdateIcon(key, icon, quality)
	self.icon = icon

	RunNextFrame(function()
		---@type RLF_ConfigSizing
		local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
		local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
		local iconSize = G_RLF.PerfPixel.PScale(sizingDb.iconSize)

		if not quality then
			self.Icon:SetItem(self.link)
		else
			self.Icon:SetItemButtonTexture(icon)
			self.Icon:SetItemButtonQuality(quality, self.link)
		end

		if self.Icon.IconOverlay then
			self.Icon.IconOverlay:SetSize(iconSize, iconSize)
		end
		if self.Icon.ProfessionQualityOverlay then
			self.Icon.ProfessionQualityOverlay:SetSize(iconSize, iconSize)
		end

		if stylingDb.enableTopLeftIconText and self.topLeftText and self.topLeftColor then
			self.Icon.topLeftText:SetText(self.topLeftText)
			if stylingDb.topLeftIconTextUseQualityColor then
				self.Icon.topLeftText:SetTextColor(unpack(self.topLeftColor))
			else
				self.Icon.topLeftText:SetTextColor(unpack(stylingDb.topLeftIconTextColor))
			end
			self.Icon.topLeftText:Show()
		else
			self.Icon.topLeftText:Hide()
		end

		self.Icon:ClearDisabledTexture()
		self.Icon:ClearNormalTexture()
		self.Icon:ClearPushedTexture()
		self.Icon:ClearHighlightTexture()

		-- Masque reskinning (may be costly, consider reducing frequency)
		if G_RLF.Masque and G_RLF.iconGroup then
			G_RLF.iconGroup:ReSkin(self.Icon)
		end
		if G_RLF.ElvSkins then
			G_RLF.ElvSkins:HandleItemButton(self.Icon, true)
			G_RLF.ElvSkins:HandleIconBorder(self.Icon.IconBorder)
		end
	end)
end

G_RLF.RLF_RowIconMixin = RLF_RowIconMixin
