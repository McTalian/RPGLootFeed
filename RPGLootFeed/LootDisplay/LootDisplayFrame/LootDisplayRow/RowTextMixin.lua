---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_RowFontString: FontString
---@field elementFadeIn Alpha

---@class RLF_RowTextMixin
RLF_RowTextMixin = {}

local defaultColor = { 1, 1, 1, 1 }

local function ApplyFontStyle(
	fontString,
	fontPath,
	fontSize,
	fontFlagsString,
	fontShadowColor,
	fontShadowOffsetX,
	fontShadowOffsetY
)
	fontString:SetFont(fontPath, fontSize, fontFlagsString)
	fontString:SetShadowColor(unpack(fontShadowColor))
	fontString:SetShadowOffset(fontShadowOffsetX or 1, fontShadowOffsetY or -1)
end

--- Setup font styling for top left text
--- @param stylingDb? RLF_ConfigStyling
function RLF_RowTextMixin:StyleTopLeftText(stylingDb)
	---@type RLF_ConfigStyling
	local stylingDb = stylingDb or G_RLF.DbAccessor:Styling(self.frameType)
	local fontFace = stylingDb.fontFace
	local useFontObjects = stylingDb.useFontObjects
	local font = stylingDb.font
	local fontFlagsString = G_RLF:FontFlagsToString()
	local fontShadowColor = stylingDb.fontShadowColor
	local fontShadowOffsetX = stylingDb.fontShadowOffsetX
	local fontShadowOffsetY = stylingDb.fontShadowOffsetY
	local topLeftIconFontSize = stylingDb.topLeftIconFontSize

	if useFontObjects then
		self.Icon.topLeftText:SetFontObject(font)
	else
		local fontPath = G_RLF.lsm:Fetch(G_RLF.lsm.MediaType.FONT, fontFace)
		ApplyFontStyle(
			self.Icon.topLeftText,
			fontPath,
			topLeftIconFontSize,
			fontFlagsString,
			fontShadowColor,
			fontShadowOffsetX,
			fontShadowOffsetY
		)
	end
end

function RLF_RowTextMixin:StyleText()
	local fontChanged = false

	---@type RLF_ConfigStyling
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local fontFace = stylingDb.fontFace
	local useFontObjects = stylingDb.useFontObjects
	local font = stylingDb.font
	local fontSize = stylingDb.fontSize
	local fontFlagsString = G_RLF:FontFlagsToString()
	local fontShadowColor = stylingDb.fontShadowColor
	local fontShadowOffsetX = stylingDb.fontShadowOffsetX
	local fontShadowOffsetY = stylingDb.fontShadowOffsetY
	local secondaryFontSize = stylingDb.secondaryFontSize
	local topLeftIconFontSize = stylingDb.topLeftIconFontSize

	if
		self.cachedFontFace ~= fontFace
		or self.cachedFontSize ~= fontSize
		or self.cachedSecondaryFontSize ~= secondaryFontSize
		or self.cachedTopLeftIconFontSize ~= topLeftIconFontSize
		or self.cachedFontFlags ~= fontFlagsString
		or self.cachedUseFontObject ~= useFontObjects
		or self.cachedFontShadowColor ~= fontShadowColor
		or self.cachedFontShadowOffsetX ~= fontShadowOffsetX
		or self.cachedFontShadowOffsetY ~= fontShadowOffsetY
	then
		self.cachedUseFontObject = useFontObjects
		self.cachedFontFace = fontFace
		self.cachedFontSize = fontSize
		self.cachedSecondaryFontSize = secondaryFontSize
		self.cachedTopLeftIconFontSize = topLeftIconFontSize
		self.cachedFontFlags = fontFlagsString
		self.cachedFontShadowColor = fontShadowColor
		self.cachedFontShadowOffsetX = fontShadowOffsetX
		self.cachedFontShadowOffsetY = fontShadowOffsetY
		fontChanged = true
	end

	if fontChanged then
		if useFontObjects or not fontFace then
			self.PrimaryText:SetFontObject(font)
			self.ItemCountText:SetFontObject(font)
			self.SecondaryText:SetFontObject(font)
			self.Icon.topLeftText:SetFontObject(font)
		else
			local fontPath = G_RLF.lsm:Fetch(G_RLF.lsm.MediaType.FONT, fontFace)
			ApplyFontStyle(
				self.PrimaryText,
				fontPath,
				fontSize,
				fontFlagsString,
				fontShadowColor,
				fontShadowOffsetX,
				fontShadowOffsetY
			)
			ApplyFontStyle(
				self.ItemCountText,
				fontPath,
				fontSize,
				fontFlagsString,
				fontShadowColor,
				fontShadowOffsetX,
				fontShadowOffsetY
			)
			ApplyFontStyle(
				self.SecondaryText,
				fontPath,
				secondaryFontSize,
				fontFlagsString,
				fontShadowColor,
				fontShadowOffsetX,
				fontShadowOffsetY
			)
			self:CreateTopLeftText()
		end
	end

	local leftAlign = stylingDb.leftAlign
	local padding = sizingDb.padding
	local iconSize = sizingDb.iconSize
	local enabledSecondaryRowText = stylingDb.enabledSecondaryRowText

	if
		self.cachedRowTextLeftAlign ~= leftAlign
		or self.cachedRowTextXOffset ~= iconSize / 4
		or self.cachedRowTextIcon ~= self.icon
		or self.cachedEnabledSecondaryText ~= enabledSecondaryRowText
		or self.cachedSecondaryText ~= self.secondaryText
		or self.cachedUnitText ~= self.unit
		or self.cachedPaddingText ~= padding
	then
		self.cachedRowTextLeftAlign = leftAlign
		self.cachedRowTextXOffset = iconSize / 4
		self.cachedRowTextIcon = self.icon
		self.cachedEnabledSecondaryText = enabledSecondaryRowText
		self.cachedSecondaryText = self.secondaryText
		self.cachedUnitText = self.unit
		self.cachedPaddingText = padding

		local anchor = "LEFT"
		local iconAnchor = "RIGHT"
		local xOffset = iconSize / 4
		if not leftAlign then
			anchor = "RIGHT"
			iconAnchor = "LEFT"
			xOffset = xOffset * -1
		end
		self.PrimaryText:ClearAllPoints()
		self.ItemCountText:ClearAllPoints()
		self.PrimaryText:SetJustifyH(anchor)
		if self.icon then
			if self.unit and G_RLF.db.global.partyLoot.enablePartyAvatar then
				self.PrimaryText:SetPoint(anchor, self.UnitPortrait, iconAnchor, xOffset, 0)
			else
				self.PrimaryText:SetPoint(anchor, self.Icon, iconAnchor, xOffset, 0)
			end
		else
			self.PrimaryText:SetPoint(anchor, self.Icon, anchor, 0, 0)
		end

		if enabledSecondaryRowText and self.secondaryText ~= nil and self.secondaryText ~= "" then
			self.SecondaryText:ClearAllPoints()
			self.SecondaryText:SetJustifyH(anchor)
			if self.icon then
				if self.unit then
					if G_RLF.db.global.partyLoot.enablePartyAvatar then
						self.SecondaryText:SetPoint(anchor, self.UnitPortrait, iconAnchor, xOffset, 0)
					else
						self.SecondaryText:SetPoint(anchor, self.Icon, iconAnchor, xOffset, 0)
					end
					if self.elementSecondaryTextColor then
						self.SecondaryText:SetTextColor(
							self.elementSecondaryTextColor.r,
							self.elementSecondaryTextColor.g,
							self.elementSecondaryTextColor.b,
							1
						)
					end
				else
					self.SecondaryText:SetPoint(anchor, self.Icon, iconAnchor, xOffset, 0)
				end
			else
				self.SecondaryText:SetPoint(anchor, self.Icon, anchor, 0, 0)
			end
			self.PrimaryText:SetPoint("BOTTOM", self, "CENTER", 0, padding)
			self.SecondaryText:SetPoint("TOP", self, "CENTER", 0, -padding)
			self.SecondaryText:SetShown(true)
		end

		self.ItemCountText:SetPoint(anchor, self.PrimaryText, iconAnchor, xOffset, 0)
	end
end

function RLF_RowTextMixin:CreateTopLeftText()
	if not self.Icon.topLeftText then
		self.Icon.topLeftText = self.Icon:CreateFontString(nil, "OVERLAY") --[[@as RLF_RowFontString]]
		self.Icon.topLeftText:SetPoint("TOPLEFT", self.Icon, "TOPLEFT", 2, -2)
	end
	self:StyleTopLeftText()
	self.Icon.topLeftText:Hide()
end

function RLF_RowTextMixin:UpdateSecondaryText(secondaryTextFn)
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	if not stylingDb.enabledSecondaryRowText then
		self.secondaryText = nil
		return
	end

	if self.elementSecondaryText then
		self.secondaryText = self.elementSecondaryText
		return
	end

	if
		type(secondaryTextFn) == "function"
		and secondaryTextFn(self.amount) ~= ""
		and secondaryTextFn(self.amount) ~= nil
	then
		self.secondaryText = secondaryTextFn(self.amount)
	else
		self.secondaryText = nil
	end
end

--- Update the total item count for the row
function RLF_RowTextMixin:UpdateItemCount()
	if self.type == "Professions" then
		---@type RLF_ConfigProfession
		local profDb = G_RLF.db.global.prof
		if not profDb.showSkillChange then
			return
		end
		RunNextFrame(function()
			self:ShowItemCountText(self.amount, {
				color = G_RLF:RGBAToHexFormat(unpack(profDb.skillColor)),
				wrapChar = profDb.skillTextWrapChar,
				showSign = true,
			})
		end)
		return
	end

	if self.itemCount == nil then
		return
	end

	if self.type == "ItemLoot" and not self.unit then
		---@type RLF_ConfigItemLoot
		local itemDb = G_RLF.db.global.item
		if not itemDb.itemCountTextEnabled then
			return
		end
		if not self.link then
			G_RLF:LogDebug("Item link is nil")
			return
		end
		RunNextFrame(function()
			local itemInfo = self.link
			local success, name = pcall(function()
				return C_Item.GetItemInfo(itemInfo)
			end)
			if not success or not name then
				G_RLF:LogDebug("Failed to get item info for link: %s", itemInfo)
				return
			end
			local itemCount = C_Item.GetItemCount(itemInfo, true, false, true, true)
			self:ShowItemCountText(itemCount, {
				color = G_RLF:RGBAToHexFormat(unpack(itemDb.itemCountTextColor)),
				wrapChar = itemDb.itemCountTextWrapChar,
			})
		end)
		return
	end

	if self.type == "Currency" then
		---@type RLF_ConfigCurrency
		local currencyDb = G_RLF.db.global.currency
		if not currencyDb.currencyTotalTextEnabled then
			return
		end
		RunNextFrame(function()
			self:ShowItemCountText(self.itemCount, {
				color = G_RLF:RGBAToHexFormat(unpack(currencyDb.currencyTotalTextColor)),
				wrapChar = currencyDb.currencyTotalTextWrapChar,
			})
		end)
		return
	end

	if self.type == "Reputation" and self.itemCount then
		---@type RLF_ConfigReputation
		local repDb = G_RLF.db.global.rep
		if not repDb.enableRepLevel then
			return
		end
		RunNextFrame(function()
			self:ShowItemCountText(self.itemCount, {
				color = G_RLF:RGBAToHexFormat(unpack(repDb.repLevelColor)),
				wrapChar = repDb.repLevelTextWrapChar,
			})
		end)
		return
	end

	if self.type == "Experience" and self.itemCount then
		---@type RLF_ConfigExperience
		local xpDb = G_RLF.db.global.xp
		if not xpDb.showCurrentLevel then
			return
		end
		RunNextFrame(function()
			self:ShowItemCountText(self.itemCount, {
				color = G_RLF:RGBAToHexFormat(unpack(xpDb.currentLevelColor)),
				wrapChar = xpDb.currentLevelTextWrapChar,
			})
		end)
		return
	end
end

function RLF_RowTextMixin:ShowItemCountText(itemCount, options)
	local WrapChar = G_RLF.WrapCharEnum
	options = options or {}
	local color = options.color or G_RLF:RGBAToHexFormat(unpack({ 0.737, 0.737, 0.737, 1 }))
	local showSign = options.showSign or false
	local wrapChar = options.wrapChar

	local sChar, eChar = G_RLF:GetWrapChars(wrapChar)

	if itemCount then
		local itemCountType = type(itemCount)
		if itemCountType == "number" and (itemCount > 1 or (showSign and itemCount >= 1)) then
			local sign = ""
			if showSign then
				sign = "+"
			end
			self.ItemCountText:SetText(color .. sChar .. sign .. itemCount .. eChar .. "|r")
			self.ItemCountText:Show()
		elseif itemCountType == "string" and itemCount ~= "" then
			self.ItemCountText:SetText(color .. sChar .. itemCount .. eChar .. "|r")
			self.ItemCountText:Show()
		end
	else
		self.ItemCountText:Hide()
	end
end

function RLF_RowTextMixin:ShowText(text, r, g, b, a)
	if a == nil then
		a = 1
	end

	self.PrimaryText:SetText(text)

	if r == nil and g == nil and b == nil and self.amount ~= nil and self.amount < 0 then
		r, g, b, a = 1, 0, 0, 0.8
	elseif r == nil or g == nil or b == nil then
		r, g, b, a = unpack(defaultColor)
	end

	if self.link then
		self.ClickableButton:SetSize(self.PrimaryText:GetStringWidth(), self.PrimaryText:GetStringHeight())
	end

	self.PrimaryText:SetTextColor(r, g, b, a)

	---@type RLF_ConfigStyling
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	if stylingDb.enabledSecondaryRowText and self.secondaryText ~= nil and self.secondaryText ~= "" then
		self.SecondaryText:SetText(self.secondaryText)
		self.SecondaryText:Show()
	else
		self.SecondaryText:Hide()
	end
end

G_RLF.RLF_RowTextMixin = RLF_RowTextMixin
