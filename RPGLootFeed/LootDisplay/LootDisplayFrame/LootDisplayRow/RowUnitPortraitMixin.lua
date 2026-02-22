---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_RowUnitPortraitMixin
RLF_RowUnitPortraitMixin = {}

function RLF_RowUnitPortraitMixin:StyleUnitPortrait()
	local sizeChanged = false

	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	---@type RLF_ConfigStyling
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	local iconSize = sizingDb.iconSize
	local leftAlign = stylingDb.leftAlign

	if self.cachedUnitIconSize ~= iconSize or self.cachedUnitLeftAlign ~= leftAlign then
		self.cachedUnitIconSize = iconSize
		self.cachedUnitLeftAlign = leftAlign
		sizeChanged = true
	end

	if sizeChanged then
		local portraitSize = G_RLF.PerfPixel.PScale(iconSize * 0.8)
		self.UnitPortrait:SetSize(portraitSize, portraitSize)
		self.UnitPortrait:ClearAllPoints()
		local rlfIconSize = G_RLF.PerfPixel.PScale(portraitSize * 0.6)
		self.RLFUser:SetSize(rlfIconSize, rlfIconSize)
		self.RLFUser:ClearAllPoints()

		local anchor, iconAnchor, xOffset = "LEFT", "RIGHT", iconSize / 4
		if not leftAlign then
			anchor, iconAnchor, xOffset = "RIGHT", "LEFT", -xOffset
		end

		self.UnitPortrait:SetPoint(anchor, self.Icon, iconAnchor, xOffset, 0)
		self.RLFUser:SetPoint("BOTTOMRIGHT", self.UnitPortrait, "BOTTOMRIGHT", rlfIconSize / 2, 0)
	end

	if self.unit then
		RunNextFrame(function()
			if self.unit then
				SetPortraitTexture(self.UnitPortrait, self.unit)
			end
		end)
		if G_RLF.db.global.partyLoot.enablePartyAvatar then
			self.UnitPortrait:Show()
		else
			self.UnitPortrait:Hide()
		end
		if false then -- TODO: Coming soon
			self.RLFUser:Show()
		end
	else
		self.UnitPortrait:Hide()
		self.RLFUser:Hide()
	end
end

G_RLF.RLF_RowUnitPortraitMixin = RLF_RowUnitPortraitMixin
