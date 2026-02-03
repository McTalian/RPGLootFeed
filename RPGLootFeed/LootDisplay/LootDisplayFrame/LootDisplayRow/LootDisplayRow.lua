---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_RowItemButtonElementFadeIn
---@field icon Alpha
---@field IconBorder Alpha
---@field IconOverlay Alpha
---@field Stock Alpha
---@field Count Alpha
---@field TopLeftText Alpha

---@class RLF_RowFontString: FontString
---@field elementFadeIn Alpha

---@class RLF_RowItemButton: ItemButton
---@field elementFadeIn RLF_RowItemButtonElementFadeIn
---@field topLeftText RLF_RowFontString

---@class RLF_RowTexture: Texture
---@field elementFadeIn Alpha

---@class RLF_RowBorderTexture: Texture
---@field fadeIn Alpha
---@field fadeOut Alpha

---@class RLF_RowExitAnimationGroup: AnimationGroup
---@field noop Animation
---@field fadeOut Alpha

---@class RLF_RowEnterAnimationGroup: AnimationGroup
---@field noop Animation
---@field fadeIn Alpha
---@field slideIn Translation

---@class RLF_LootDisplayRow: BackdropTemplate
---@field key string
---@field frameType G_RLF.Frames
---@field amount number
---@field icon string
---@field link string
---@field secondaryText string
---@field unit string
---@field type string
---@field highlight boolean
---@field isHistoryMode boolean
---@field pendingElement table
---@field updatePending boolean
---@field waiting boolean
---@field _next RLF_LootDisplayRow
---@field _prev RLF_LootDisplayRow
---@field Background Texture
---@field HighlightBGOverlay Texture
---@field UnitPortrait RLF_RowTexture
---@field RLFUser RLF_RowTexture
---@field PrimaryText RLF_RowFontString
---@field SecondaryText RLF_RowFontString
---@field ItemCountText RLF_RowFontString
---@field TopBorder RLF_RowBorderTexture
---@field RightBorder RLF_RowBorderTexture
---@field BottomBorder RLF_RowBorderTexture
---@field LeftBorder RLF_RowBorderTexture
---@field ClickableButton Button
---@field Icon RLF_RowItemButton
---@field glowTexture table
---@field EnterAnimation RLF_RowEnterAnimationGroup
---@field ExitAnimation RLF_RowExitAnimationGroup
LootDisplayRowMixin = {}

local FALLBACK_BACKGROUND_TEXTURE = "Interface/Buttons/WHITE8X8"

local defaultColor = { 1, 1, 1, 1 }
function LootDisplayRowMixin:Init()
	self.waiting = false
	if self:IsStaggeredEnter() then
		self.waiting = true
	end
	self.updatePending = false
	self.pendingElement = nil
	self.quality = nil

	self.ClickableButton:Hide()
	---@type ScriptRegion[]
	local textures = {
		self.ClickableButton:GetRegions() --[[@as ScriptRegion[] ]],
	}
	for _, region in ipairs(textures) do
		if region:GetObjectType() == "Texture" then
			region:Hide()
		end
	end

	self.ClickableButton:SetScript("OnEnter", nil)
	self.ClickableButton:SetScript("OnLeave", nil)
	self.ClickableButton:SetScript("OnMouseUp", nil)
	self.ClickableButton:SetScript("OnEvent", nil)
	self.PrimaryText:SetTextColor(unpack(defaultColor))
	self.SecondaryText:SetTextColor(unpack(defaultColor))

	-- Sample rows should never fade out
	if self.isSampleRow then
		self.showForSeconds = math.pow(2, 19) -- Never fade out
	else
		self.showForSeconds = G_RLF.db.global.animations.exit.fadeOutDelay
	end

	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)

	self:SetSize(sizingDb.feedWidth, sizingDb.rowHeight)
	self.RLFUser:SetTexture("Interface/AddOns/RPGLootFeed/Icons/logo.blp")
	self.RLFUser:SetDrawLayer("OVERLAY")
	self.RLFUser:Hide()
	self:CreateTopLeftText()
	self.Icon.topLeftText:Hide()
	self.Icon.IconBorder:SetVertexColor(G_RLF.noQualColor.r, G_RLF.noQualColor.g, G_RLF.noQualColor.b, 1)
	self:StyleBackground()
	self:StyleRowBackdrop()
	self:StyleExitAnimation()
	self:StyleEnterAnimation()
	self:StyleElementFadeIn()
	self:StyleHighlightBorder()
	RunNextFrame(function()
		self:SetUpHoverEffect()
	end)
end

function LootDisplayRowMixin:StopAllAnimations()
	if self.glowAnimationGroup then
		self.glowAnimationGroup:Stop()
	end
	if self.EnterAnimation then
		self.EnterAnimation:Stop()
	end
	if self.ExitAnimation then
		self.ExitAnimation:Stop()
	end
	if self.HighlightFadeIn then
		self.HighlightFadeIn:Stop()
	end
	if self.HighlightFadeOut then
		self.HighlightFadeOut:Stop()
	end
	if self.HighlightAnimation then
		self.HighlightAnimation:Stop()
	end
	if self.ElementFadeInAnimation then
		self.ElementFadeInAnimation:Stop()
	end

	-- Stop scripted effects
	self:StopScriptedEffects()
end

function LootDisplayRowMixin:Reset()
	self:Hide()
	self:SetAlpha(1)
	self:ClearAllPoints()

	-- Reset row-specific data
	self.key = nil
	self.amount = nil
	self.quality = nil
	self.icon = nil
	self.link = nil
	self.secondaryText = nil
	self.unit = nil
	self.type = nil
	self.highlight = nil
	self.isHistoryMode = false
	self.isSampleRow = false -- Reset sample row flag
	self.pendingElement = nil
	self.updatePending = false
	self.waiting = false
	self.isCustomLink = false
	self.customBehavior = nil

	-- Reset UI elements that were part of the template
	self.TopBorder:SetAlpha(0)
	self.RightBorder:SetAlpha(0)
	self.BottomBorder:SetAlpha(0)
	self.LeftBorder:SetAlpha(0)

	self:CreateTopLeftText()
	self.Icon:Reset()
	self.Icon.IconBorder:SetVertexColor(G_RLF.noQualColor.r, G_RLF.noQualColor.g, G_RLF.noQualColor.b, 1)
	self.Icon.NormalTexture:SetTexture(nil)
	self.Icon.HighlightTexture:SetTexture(nil)
	self.Icon.PushedTexture:SetTexture(nil)
	self.Icon.topLeftText:Hide()
	self.Icon:SetScript("OnEnter", nil)
	self.Icon:SetScript("OnLeave", nil)
	self.Icon:SetScript("OnMouseUp", nil)
	self.Icon:SetScript("OnEvent", nil)

	self:StopAllAnimations()

	if self.glowTexture then
		self.glowTexture:Hide()
	end
	if self.HighlightBGOverlay then
		self.HighlightBGOverlay:SetAlpha(0)
	end
	if self.leftSideTexture then
		self.leftSideTexture:Hide()
	end
	if self.rightSideTexture then
		self.rightSideTexture:Hide()
	end

	self.UnitPortrait:SetTexture(nil)
	self.PrimaryText:SetText(nil)
	self.PrimaryText:SetTextColor(unpack(defaultColor))
	self.SecondaryText:SetText(nil)
	self.SecondaryText:SetTextColor(unpack(defaultColor))
	self.SecondaryText:Hide()
	self.ItemCountText:SetText(nil)
	self.ItemCountText:Hide()
	self.ClickableButton:Hide()
	---@type ScriptRegion[]
	local textures = {
		self.ClickableButton:GetRegions() --[[@as ScriptRegion[] ]],
	}
	for _, region in ipairs(textures) do
		if region:GetObjectType() == "Texture" then
			region:Hide()
		end
	end

	self.ClickableButton:SetScript("OnEnter", nil)
	self.ClickableButton:SetScript("OnLeave", nil)
	self.ClickableButton:SetScript("OnMouseUp", nil)
	self.ClickableButton:SetScript("OnEvent", nil)
end

function LootDisplayRowMixin:StyleElementFadeIn()
	-- Fade in all of the UI elements for the row
	-- Icon, PrimaryText, ItemCountText, SecondaryText, UnitPortrait
	local fadeInDuration = 0.2
	local fadeInSmoothing = "IN_OUT"

	if not self.ElementFadeInAnimation then
		self.ElementFadeInAnimation = self:CreateAnimationGroup()
		self.ElementFadeInAnimation:SetToFinalAlpha(true)
		self.ElementFadeInAnimation:SetScript("OnFinished", function()
			self:HighlightIcon()
			self:ResetFadeOut()
			if self.updatePending then
				self:UpdateQuantity(self.pendingElement)
			end
		end)
	end

	-- Icon
	if not self.Icon.elementFadeIn then
		self.Icon.elementFadeIn = {
			icon = self.ElementFadeInAnimation:CreateAnimation("Alpha"),
			IconBorder = self.ElementFadeInAnimation:CreateAnimation("Alpha"),
			IconOverlay = self.ElementFadeInAnimation:CreateAnimation("Alpha"),
			Stock = self.ElementFadeInAnimation:CreateAnimation("Alpha"),
			Count = self.ElementFadeInAnimation:CreateAnimation("Alpha"),
			TopLeftText = self.ElementFadeInAnimation:CreateAnimation("Alpha"),
		}
		self.Icon.elementFadeIn.icon:SetTarget(self.Icon.icon)
		self.Icon.elementFadeIn.icon:SetFromAlpha(0)
		self.Icon.elementFadeIn.icon:SetToAlpha(1)
		self.Icon.elementFadeIn.icon:SetSmoothing(fadeInSmoothing)
		self.Icon.elementFadeIn.IconBorder:SetTarget(self.Icon.IconBorder)
		self.Icon.elementFadeIn.IconBorder:SetFromAlpha(0)
		self.Icon.elementFadeIn.IconBorder:SetToAlpha(1)
		self.Icon.elementFadeIn.IconBorder:SetSmoothing(fadeInSmoothing)
		self.Icon.elementFadeIn.IconOverlay:SetTarget(self.Icon.IconOverlay)
		self.Icon.elementFadeIn.IconOverlay:SetFromAlpha(0)
		self.Icon.elementFadeIn.IconOverlay:SetToAlpha(1)
		self.Icon.elementFadeIn.IconOverlay:SetSmoothing(fadeInSmoothing)
		self.Icon.elementFadeIn.Stock:SetTarget(self.Icon.Stock)
		self.Icon.elementFadeIn.Stock:SetFromAlpha(0)
		self.Icon.elementFadeIn.Stock:SetToAlpha(1)
		self.Icon.elementFadeIn.Stock:SetSmoothing(fadeInSmoothing)
		self.Icon.elementFadeIn.Count:SetTarget(self.Icon.Count)
		self.Icon.elementFadeIn.Count:SetFromAlpha(0)
		self.Icon.elementFadeIn.Count:SetToAlpha(1)
		self.Icon.elementFadeIn.Count:SetSmoothing(fadeInSmoothing)
		self.Icon.elementFadeIn.TopLeftText:SetTarget(self.Icon.topLeftText)
		self.Icon.elementFadeIn.TopLeftText:SetFromAlpha(0)
		self.Icon.elementFadeIn.TopLeftText:SetToAlpha(1)
		self.Icon.elementFadeIn.TopLeftText:SetSmoothing(fadeInSmoothing)
	end
	self.Icon.elementFadeIn.icon:SetDuration(fadeInDuration)
	self.Icon.elementFadeIn.IconBorder:SetDuration(fadeInDuration)
	self.Icon.elementFadeIn.IconOverlay:SetDuration(fadeInDuration)
	self.Icon.elementFadeIn.Stock:SetDuration(fadeInDuration)
	self.Icon.elementFadeIn.Count:SetDuration(fadeInDuration)
	self.Icon.elementFadeIn.TopLeftText:SetDuration(fadeInDuration)

	-- PrimaryText
	if not self.PrimaryText.elementFadeIn then
		self.PrimaryText.elementFadeIn = self.ElementFadeInAnimation:CreateAnimation("Alpha")
		self.PrimaryText.elementFadeIn:SetTarget(self.PrimaryText)
		self.PrimaryText.elementFadeIn:SetFromAlpha(0)
		self.PrimaryText.elementFadeIn:SetToAlpha(1)
		self.PrimaryText.elementFadeIn:SetSmoothing(fadeInSmoothing)
	end
	self.PrimaryText.elementFadeIn:SetDuration(fadeInDuration)

	-- ItemCountText
	if not self.ItemCountText.elementFadeIn then
		self.ItemCountText.elementFadeIn = self.ElementFadeInAnimation:CreateAnimation("Alpha")
		self.ItemCountText.elementFadeIn:SetTarget(self.ItemCountText)
		self.ItemCountText.elementFadeIn:SetFromAlpha(0)
		self.ItemCountText.elementFadeIn:SetToAlpha(1)
		self.ItemCountText.elementFadeIn:SetSmoothing(fadeInSmoothing)
	end
	self.ItemCountText.elementFadeIn:SetDuration(fadeInDuration)

	-- SecondaryText
	if not self.SecondaryText.elementFadeIn then
		self.SecondaryText.elementFadeIn = self.ElementFadeInAnimation:CreateAnimation("Alpha")
		self.SecondaryText.elementFadeIn:SetTarget(self.SecondaryText)
		self.SecondaryText.elementFadeIn:SetFromAlpha(0)
		self.SecondaryText.elementFadeIn:SetToAlpha(1)
		self.SecondaryText.elementFadeIn:SetSmoothing(fadeInSmoothing)
	end
	self.SecondaryText.elementFadeIn:SetDuration(fadeInDuration)

	-- UnitPortrait
	if not self.UnitPortrait.elementFadeIn then
		self.UnitPortrait.elementFadeIn = self.ElementFadeInAnimation:CreateAnimation("Alpha")
		self.UnitPortrait.elementFadeIn:SetTarget(self.UnitPortrait)
		self.UnitPortrait.elementFadeIn:SetFromAlpha(0)
		self.UnitPortrait.elementFadeIn:SetToAlpha(1)
		self.UnitPortrait.elementFadeIn:SetSmoothing(fadeInSmoothing)
	end
	self.UnitPortrait.elementFadeIn:SetDuration(fadeInDuration)
end

function LootDisplayRowMixin:StyleBackground()
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)

	if stylingDb.rowBackgroundType ~= G_RLF.RowBackground.GRADIENT then
		self.Background:Hide()
		return
	else
		self.Background:Show()
	end

	local changed = false

	local insets = stylingDb.backdropInsets
	local topInset = insets.top or 0
	local rightInset = insets.right or 0
	local bottomInset = insets.bottom or 0
	local leftInset = insets.left or 0
	local gradientStart = stylingDb.rowBackgroundGradientStart
	local gradientEnd = stylingDb.rowBackgroundGradientEnd
	local leftAlign = stylingDb.leftAlign

	if
		self.cachedGradientStart ~= gradientStart
		or self.cachedGradientEnd ~= gradientEnd
		or self.cachedBackgoundLeftAlign ~= leftAlign
		or self.cachedTopInset ~= topInset
		or self.cachedRightInset ~= rightInset
		or self.cachedBottomInset ~= bottomInset
		or self.cachedLeftInset ~= leftInset
	then
		self.cachedGradientStart = gradientStart
		self.cachedGradientEnd = gradientEnd
		self.cachedBackgoundLeftAlign = leftAlign
		self.cachedTopInset = topInset
		self.cachedRightInset = rightInset
		self.cachedBottomInset = bottomInset
		self.cachedLeftInset = leftInset
		changed = true
	end

	if changed then
		local leftColor = CreateColor(unpack(gradientStart))
		local rightColor = CreateColor(unpack(gradientEnd))
		if not leftAlign then
			leftColor, rightColor = rightColor, leftColor
		end
		self.Background:SetGradient("HORIZONTAL", leftColor, rightColor)

		if topInset ~= 0 or rightInset ~= 0 or bottomInset ~= 0 or leftInset ~= 0 then
			self.Background:ClearAllPoints()
			self.Background:SetPoint("TOPLEFT", self, "TOPLEFT", leftInset, -topInset)
			self.Background:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -rightInset, bottomInset)
		end
	end
end

function LootDisplayRowMixin:StyleIcon()
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

function LootDisplayRowMixin:StyleUnitPortrait()
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
function LootDisplayRowMixin:StyleTopLeftText(stylingDb)
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

function LootDisplayRowMixin:StyleText()
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

function LootDisplayRowMixin:CreateTopLeftText()
	if not self.Icon.topLeftText then
		self.Icon.topLeftText = self.Icon:CreateFontString(nil, "OVERLAY") --[[@as RLF_RowFontString]]
		self.Icon.topLeftText:SetPoint("TOPLEFT", self.Icon, "TOPLEFT", 2, -2)
	end
	self:StyleTopLeftText()
	self.Icon.topLeftText:Hide()
end

function LootDisplayRowMixin:StyleRowBackdrop()
	---@type RLF_ConfigStyling
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	local enableRowBorder = stylingDb.enableRowBorder
	local enableTexturedBackground = stylingDb.rowBackgroundType == G_RLF.RowBackground.TEXTURED
	if
		(not enableRowBorder or stylingDb.rowBorderTexture == "None")
		and (not enableTexturedBackground or stylingDb.rowBackgroundTexture == "None")
	then
		self:ClearBackdrop()
		return
	end

	local borderSize = stylingDb.rowBorderSize
	local classColors = stylingDb.rowBorderClassColors
	local borderColor = stylingDb.rowBorderColor
	local borderTexture = enableRowBorder and stylingDb.rowBorderTexture or "None"
	local backdropTexture = enableTexturedBackground and stylingDb.rowBackgroundTexture or "None"
	local backdropColorR = stylingDb.rowBackgroundTextureColor[1]
	local backdropColorG = stylingDb.rowBackgroundTextureColor[2]
	local backdropColorB = stylingDb.rowBackgroundTextureColor[3]
	local backdropColorA = stylingDb.rowBackgroundTextureColor[4] or 1
	local topInset = stylingDb.backdropInsets.top or 0
	local rightInset = stylingDb.backdropInsets.right or 0
	local bottomInset = stylingDb.backdropInsets.bottom or 0
	local leftInset = stylingDb.backdropInsets.left or 0
	local needsUpdate = false

	if
		self.cachedBorderSize ~= borderSize
		or self.cacheBorderColor ~= borderColor
		or self.cacheClassColors ~= classColors
		or self.cachedBorderTexture ~= borderTexture
		or self.cachedBackdropTexture ~= backdropTexture
		or self.cachedBackdropColorR ~= backdropColorR
		or self.cachedBackdropColorG ~= backdropColorG
		or self.cachedBackdropColorB ~= backdropColorB
		or self.cachedBackdropColorA ~= backdropColorA
		or self.cachedBackdropTopInset ~= topInset
		or self.cachedBackdropRightInset ~= rightInset
		or self.cachedBackdropBottomInset ~= bottomInset
		or self.cachedBackdropLeftInset ~= leftInset
	then
		self.cachedBorderSize = borderSize
		self.cacheBorderColor = borderColor
		self.cacheClassColors = classColors
		self.cachedBorderTexture = borderTexture
		self.cachedBackdropTexture = backdropTexture
		self.cachedBackdropColorR = backdropColorR
		self.cachedBackdropColorG = backdropColorG
		self.cachedBackdropColorB = backdropColorB
		self.cachedBackdropColorA = backdropColorA
		self.cachedBackdropTopInset = topInset
		self.cachedBackdropRightInset = rightInset
		self.cachedBackdropBottomInset = bottomInset
		self.cachedBackdropLeftInset = leftInset
		borderSize = G_RLF.PerfPixel.PScale(borderSize)
		topInset = G_RLF.PerfPixel.PScale(topInset)
		rightInset = G_RLF.PerfPixel.PScale(rightInset)
		bottomInset = G_RLF.PerfPixel.PScale(bottomInset)
		leftInset = G_RLF.PerfPixel.PScale(leftInset)
		needsUpdate = true
	end

	if not needsUpdate then
		return
	end

	-- Use textured borders via backdrop
	local lsm = G_RLF.lsm

	---@type backdropInfo
	local backdrop = {}

	if borderTexture ~= "None" then
		local texturePath = lsm:Fetch(lsm.MediaType.BORDER, borderTexture)

		if texturePath == nil or texturePath == "" then
			G_RLF:LogWarn("Could not find a texture path in LSM for border texture: %s", borderTexture)
		else
			backdrop.edgeFile = texturePath
			backdrop.edgeSize = borderSize
		end
	end

	if backdropTexture ~= "None" then
		local texturePath = lsm:Fetch(lsm.MediaType.BACKGROUND, backdropTexture)

		if texturePath == nil or texturePath == "" then
			G_RLF:LogWarn("Could not find a texture path in LSM for backdrop texture: %s", backdropTexture)
		else
			backdrop.bgFile = texturePath
			backdrop.insets = {
				left = leftInset,
				right = rightInset,
				top = topInset,
				bottom = bottomInset,
			}
		end
	else
		backdrop.bgFile = FALLBACK_BACKGROUND_TEXTURE
	end

	self:SetBackdrop(backdrop)

	if backdropTexture ~= "None" then
		self:SetBackdropColor(backdropColorR or 0, backdropColorG or 0, backdropColorB or 0, backdropColorA or 1)
	else
		self:SetBackdropColor(0, 0, 0, 0) -- Transparent background
	end

	-- Apply coloring to textured border
	if classColors then
		local classColor
		local a = 1
		if GetExpansionLevel() >= G_RLF.Expansion.BFA then
			classColor = C_ClassColor.GetClassColor(select(2, UnitClass(self.unit or "player")))
		else
			classColor = RAID_CLASS_COLORS[select(2, UnitClass(self.unit or "player"))]
		end
		if classColor == nil then
			G_RLF:LogWarn("Could not find a class color for unit: %s", self.unit or "player")
			-- Fallback to transparent black
			classColor = { r = 0, g = 0, b = 0 }
			a = 0
		end
		self:SetBackdropBorderColor(classColor.r, classColor.g, classColor.b, a)
	else
		local r, g, b, a = unpack(borderColor)
		self:SetBackdropBorderColor(r, g, b, a or 1)
	end
end

function LootDisplayRowMixin:StyleHighlightBorder()
	if not self.HighlightAnimation then
		self.HighlightAnimation = self:CreateAnimationGroup()
		self.HighlightAnimation:SetToFinalAlpha(true)
	end

	---@type RLF_ConfigAnimations
	local animationsDb = G_RLF.db.global.animations

	if
		self.cachedUpdateDisableHighlight ~= animationsDb.update.disableHighlight
		or self.cachedUpdateDuration ~= animationsDb.update.duration
		or self.cachedUpdateLoop ~= animationsDb.update.loop
	then
		self.cachedUpdateDisableHighlight = animationsDb.update.disableHighlight
		self.cachedUpdateDuration = animationsDb.update.duration
		self.cachedUpdateLoop = animationsDb.update.loop

		local duration = animationsDb.update.duration
		local borderSize = G_RLF.PerfPixel.PScale(1)
		self.TopBorder:SetHeight(borderSize)
		self.RightBorder:SetWidth(borderSize)
		self.BottomBorder:SetHeight(borderSize)
		self.LeftBorder:SetWidth(borderSize)
		local borders = {
			self.TopBorder,
			self.RightBorder,
			self.BottomBorder,
			self.LeftBorder,
		}

		for _, b in ipairs(borders) do
			if not b.fadeIn then
				b.fadeIn = self.HighlightAnimation:CreateAnimation("Alpha")
				b.fadeIn:SetTarget(b)
				b.fadeIn:SetOrder(1)
				b.fadeIn:SetFromAlpha(0)
				b.fadeIn:SetToAlpha(1)
				b.fadeIn:SetSmoothing("IN_OUT")
			end
			b.fadeIn:SetDuration(duration)

			if not b.fadeOut then
				b.fadeOut = self.HighlightAnimation:CreateAnimation("Alpha")
				b.fadeOut:SetTarget(b)
				b.fadeOut:SetOrder(2)
				b.fadeOut:SetFromAlpha(1)
				b.fadeOut:SetToAlpha(0)
				b.fadeOut:SetStartDelay(0.1)
				b.fadeOut:SetSmoothing("IN_OUT")
			end
			b.fadeOut:SetDuration(duration)
		end

		if animationsDb.update.loop then
			self.HighlightAnimation:SetLooping("BOUNCE")
		else
			self.HighlightAnimation:SetLooping("NONE")
		end
	end
end

function LootDisplayRowMixin:StyleExitAnimation()
	local animationChanged = false
	if self.isSampleRow then
		-- Sample rows should never fade out
		self.showForSeconds = math.pow(2, 19) -- Never fade out
		self.bustCacheExitAnimation = true
	end

	---@type RLF_ConfigAnimations
	local animationsDb = G_RLF.db.global.animations
	local animationsExitDb = animationsDb.exit
	local disableExitAnimation = animationsExitDb.disable
	local exitAnimationType = animationsExitDb.type
	local exitDuration = animationsExitDb.duration
	local exitDelay = self.showForSeconds

	if
		self.cachedExitAnimationType ~= exitAnimationType
		or self.cachedExitAnimationDuration ~= exitDuration
		or self.cachedExitFadeOutDelay ~= exitDelay
		or self.cachedExitDisableAnimation ~= disableExitAnimation
		or self.bustCacheExitAnimation
	then
		self.cachedExitAnimationType = exitAnimationType
		self.cachedExitAnimationDuration = exitDuration
		self.cachedExitFadeOutDelay = exitDelay
		self.cachedExitDisableAnimation = disableExitAnimation
		self.bustCacheExitAnimation = false
		animationChanged = true
	end

	if animationChanged then
		if not self.ExitAnimation then
			self.ExitAnimation = self:CreateAnimationGroup() --[[@as RLF_RowExitAnimationGroup]]
			self.ExitAnimation:SetScript("OnFinished", function()
				self:Hide()
				local frame = self:GetParent() --[[@as RLF_LootDisplayFrame]]
				if not frame then
					return
				end
				frame:ReleaseRow(self)
			end)
		else
			self.ExitAnimation:Stop()
			self.ExitAnimation:RemoveAnimations()
		end

		if disableExitAnimation then
			exitDelay = math.pow(2, 19)
			exitAnimationType = G_RLF.ExitAnimationType.NONE
		end

		if exitAnimationType == G_RLF.ExitAnimationType.NONE then
			self.ExitAnimation:SetToFinalAlpha(false)
			self.ExitAnimation.noop = self.ExitAnimation:CreateAnimation()
			self.ExitAnimation.fadeOut = nil
			self.ExitAnimation.noop:SetStartDelay(exitDelay)
			self.ExitAnimation.noop:SetDuration(0)
			self:SetAlpha(1)
			return
		end

		if exitAnimationType ~= G_RLF.ExitAnimationType.NONE then
			self.ExitAnimation:SetToFinalAlpha(true)
			self.ExitAnimation.noop = nil
			self.ExitAnimation.fadeOut = self.ExitAnimation:CreateAnimation("Alpha")
			self.ExitAnimation.fadeOut:SetStartDelay(exitDelay)
			self.ExitAnimation.fadeOut:SetDuration(exitDuration)
			self.ExitAnimation.fadeOut:SetFromAlpha(1)
			self.ExitAnimation.fadeOut:SetToAlpha(0)
			self.ExitAnimation.fadeOut:SetScript("OnUpdate", function()
				if self.glowTexture and self.glowTexture:IsShown() then
					self.glowTexture:SetAlpha(0.75 * (1 - self.ExitAnimation.fadeOut:GetProgress()))
				end
			end)
		end
	else
		if self.ExitAnimation.fadeOut then
			self.ExitAnimation.fadeOut:SetStartDelay(exitDelay)
			self.ExitAnimation.fadeOut:SetDuration(exitDuration)
		end
		if self.ExitAnimation.noop then
			self.ExitAnimation.noop:SetStartDelay(exitDelay)
			self.ExitAnimation.noop:SetDuration(0)
		end
	end
end

function LootDisplayRowMixin:StyleEnterAnimation()
	local animationChanged = false

	---@type RLF_ConfigAnimations
	local animationsDb = G_RLF.db.global.animations
	local animationsEnterDb = animationsDb.enter
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local enterAnimationType = animationsEnterDb.type
	local slideDirection = animationsEnterDb.slide.direction
	local enterDuration = animationsEnterDb.duration
	local feedWidth = sizingDb.feedWidth
	local rowHeight = sizingDb.rowHeight

	if
		self.cachedEnterAnimationType ~= enterAnimationType
		or self.cachedEnterAnimationSlideDirection ~= slideDirection
		or self.cachedEnterAnimationDuration ~= enterDuration
		or self.cachedEnterAnimationFeedWidth ~= feedWidth
		or self.cachedEnterAnimationRowHeight ~= rowHeight
	then
		self.cachedEnterAnimationType = enterAnimationType
		self.cachedEnterAnimationSlideDirection = slideDirection
		self.cachedEnterAnimationDuration = enterDuration
		self.cachedEnterAnimationFeedWidth = feedWidth
		self.cachedEnterAnimationRowHeight = rowHeight
		animationChanged = true
	end

	if not self.EnterAnimation then
		self.EnterAnimation = self:CreateAnimationGroup() --[[@as RLF_RowEnterAnimationGroup]]
	end

	if animationChanged then
		self.EnterAnimation:Stop()
		self.EnterAnimation:RemoveAnimations()
		self.EnterAnimation:SetToFinalAlpha(true)
		self.EnterAnimation:SetScript("OnPlay", function()
			self.waiting = false
			self:ElementsVisible()
		end)
		self.EnterAnimation:SetScript("OnFinished", function()
			self:HighlightIcon()
			self:ResetFadeOut()
			if self.updatePending then
				self:UpdateQuantity(self.pendingElement)
			end
			if self:IsStaggeredEnter() then
				if self._next then
					self._next.waiting = false
					self._next:Enter()
				end
			end
		end)

		if enterAnimationType == G_RLF.EnterAnimationType.NONE then
			self.EnterAnimation.noop = self.EnterAnimation:CreateAnimation()
			self.EnterAnimation.fadeIn = nil
			self.EnterAnimation.slideIn = nil
			self:SetAlpha(1)
			return
		end

		-- Fade In unless explicitly disabled
		if enterAnimationType ~= G_RLF.EnterAnimationType.NONE then
			self.EnterAnimation.noop = nil
			self.EnterAnimation.slideIn = nil
			self.EnterAnimation.fadeIn = self.EnterAnimation:CreateAnimation("Alpha")
			self.EnterAnimation.fadeIn:SetFromAlpha(0)
			self.EnterAnimation.fadeIn:SetToAlpha(1)
			self.EnterAnimation.fadeIn:SetDuration(enterDuration)
			self.EnterAnimation.fadeIn:SetSmoothing("IN_OUT")
			self.EnterAnimation.fadeIn:SetScript("OnFinished", function()
				self:SetAlpha(1)
			end)
		end

		if enterAnimationType == G_RLF.EnterAnimationType.SLIDE then
			self.EnterAnimation:SetScript("OnPlay", function()
				self:ElementsInvisible()
			end)
			self.EnterAnimation:SetScript("OnFinished", function()
				self:FadeInElements()
				if self:IsStaggeredEnter() then
					if self._next then
						self._next.waiting = false
						self._next:Enter()
					end
				end
			end)

			self.EnterAnimation.slideIn = self.EnterAnimation:CreateAnimation("Translation")

			local initialOffsetX, initialOffsetY = 0, 0

			-- Determine the initial offset based on slide direction
			if slideDirection == G_RLF.SlideDirection.LEFT then
				initialOffsetX = feedWidth
			elseif slideDirection == G_RLF.SlideDirection.RIGHT then
				initialOffsetX = -feedWidth
			elseif slideDirection == G_RLF.SlideDirection.UP then
				initialOffsetY = -rowHeight
			elseif slideDirection == G_RLF.SlideDirection.DOWN then
				initialOffsetY = rowHeight
			end

			self.EnterAnimation.slideIn:SetOffset(-initialOffsetX, -initialOffsetY) -- Opposite of initial to slide to the final position
			self.EnterAnimation.slideIn:SetDuration(enterDuration)
			self.EnterAnimation.slideIn:SetSmoothing("OUT")

			-- Set the starting position before the animation begins
			self.EnterAnimation.slideIn:SetScript("OnPlay", function()
				if slideDirection == G_RLF.SlideDirection.LEFT or slideDirection == G_RLF.SlideDirection.RIGHT then
					self:SetPoint(slideDirection == G_RLF.SlideDirection.LEFT and "LEFT" or "RIGHT", initialOffsetX, 0)
				elseif slideDirection == G_RLF.SlideDirection.UP or slideDirection == G_RLF.SlideDirection.DOWN then
					if self.opposite then
						self:SetPoint(self.anchorPoint, self.anchorTo, self.opposite, 0, initialOffsetY)
					else
						self:SetPoint(self.anchorPoint, self.anchorTo, self.anchorPoint, 0, initialOffsetY)
					end
				end
			end)

			-- Reset the final position after the animation completes
			self.EnterAnimation.slideIn:SetScript("OnFinished", function()
				self:ClearAllPoints()
				local frame = self:GetParent() --[[@as RLF_LootDisplayFrame]]
				if not frame then
					return
				end
				self:UpdatePosition(frame)
				self.waiting = false
			end)
		end
	end
end

function LootDisplayRowMixin:StyleIconHighlight()
	if not self.glowTexture then
		-- Create the glow texture
		self.glowTexture = self.Icon:CreateTexture(nil, "OVERLAY")
		self.glowTexture:SetDrawLayer("OVERLAY", 7)
		self.glowTexture:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
		self.glowTexture:SetPoint("CENTER", self.Icon, "CENTER", 0, 0)
		self.glowTexture:SetBlendMode("ADD") -- "ADD" is often better for glow effects
		self.glowTexture:SetAlpha(0.75)
		self.glowTexture:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	end

	G_RLF.PerfPixel.PSize(self.glowTexture, self.Icon:GetWidth() * 1.75, self.Icon:GetHeight() * 1.75)
	self.glowTexture:Hide()

	-- Create the animation group if it doesn't exist
	if not self.glowAnimationGroup then
		self.glowAnimationGroup = self.glowTexture:CreateAnimationGroup()
		self.glowAnimationGroup:SetLooping("BOUNCE")
	end

	if not self.glowAnimationGroup.scaleUp then
		-- -- Scale up animation
		self.glowAnimationGroup.scaleUp = self.glowAnimationGroup:CreateAnimation("Scale")
		local factor = 1.1
		self.glowAnimationGroup.scaleUp:SetScaleFrom(1 / factor, 1 / factor)
		self.glowAnimationGroup.scaleUp:SetScaleTo(factor, factor)
		self.glowAnimationGroup.scaleUp:SetDuration(0.5)
		self.glowAnimationGroup.scaleUp:SetSmoothing("OUT")
	end

	-- Add scripted animation effects support
	self:CreateScriptedEffects()
end

function LootDisplayRowMixin:CreateScriptedEffects()
	if not G_RLF:IsRetail() then
		return
	end

	if not self.leftSideTexture then
		self.leftSideTexture = self:CreateTexture(nil, "ARTWORK")
	end

	if not self.rightSideTexture then
		self.rightSideTexture = self:CreateTexture(nil, "ARTWORK")
	end

	if not self.leftModelScene then
		self.leftModelScene = CreateFrame("ModelScene", nil, self, "ScriptAnimatedModelSceneTemplate")
	end

	if not self.rightModelScene then
		self.rightModelScene = CreateFrame("ModelScene", nil, self, "ScriptAnimatedModelSceneTemplate")
	end

	-- Initialize scripted animation effect timers
	if not self.scriptedEffectTimers then
		self.scriptedEffectTimers = {}
	end

	local changed = false

	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local feedWidth = sizingDb.feedWidth
	local rowHeight = sizingDb.rowHeight
	if self.cachedModelSceneFeedWidthRef ~= feedWidth or self.cachedModelSceneRowHeightRef ~= rowHeight then
		self.cachedModelSceneFeedWidthRef = feedWidth
		self.cachedModelSceneRowHeightRef = rowHeight
		changed = true
	end

	if changed then
		local scaledHeight = G_RLF.PerfPixel.PScale(7 / 6 * rowHeight)
		local scaledWidth = G_RLF.PerfPixel.PScale(0.03 * feedWidth)
		self.leftSideTexture:ClearAllPoints()
		self.leftSideTexture:SetTexture("Interface\\LootFrame\\CosmeticToast")
		self.leftSideTexture:SetTexCoord(0.03, 0.06, 0.05, 0.95)
		self.leftSideTexture:SetPoint("TOPLEFT", self, "TOPLEFT")
		self.leftSideTexture:SetSize(scaledWidth, scaledHeight)

		self.rightSideTexture:ClearAllPoints()
		self.rightSideTexture:SetTexture("Interface\\LootFrame\\CosmeticToast")
		self.rightSideTexture:SetTexCoord(0.535, 0.565, 0.05, 0.95)
		self.rightSideTexture:SetPoint("TOPRIGHT", self, "TOPRIGHT")
		self.rightSideTexture:SetSize(scaledWidth, scaledHeight)

		local modelSceneHeight = G_RLF.PerfPixel.PScale(0.7 * scaledHeight)
		local modelSceneWidth = G_RLF.PerfPixel.PScale(0.8 * scaledWidth)
		self.leftModelScene:SetPoint("TOPLEFT", self.leftSideTexture, "TOPLEFT")
		self.leftModelScene:SetSize(modelSceneWidth, modelSceneHeight)

		self.rightModelScene:SetPoint("TOPRIGHT", self.rightSideTexture, "TOPRIGHT")
		self.rightModelScene:SetSize(modelSceneWidth, modelSceneHeight)

		self.leftSideTexture:Hide()
		self.rightSideTexture:Hide()
	end
end

function LootDisplayRowMixin:PlayTransmogEffect()
	if not G_RLF:IsRetail() then
		return
	end

	if not self.leftModelScene or not self.rightModelScene or not self.scriptedEffectTimers then
		self:CreateScriptedEffects()
	end

	-- Clear any existing effects
	self:StopScriptedEffects()

	if G_RLF.db.global.transmog.enableBlizzardTransmogSound then
		PlaySound(SOUNDKIT.UI_COSMETIC_ITEM_TOAST_SHOW)
	end

	if not G_RLF.db.global.transmog.enableTransmogEffect then
		self.leftSideTexture:Hide()
		self.rightSideTexture:Hide()
		return
	end

	self.leftSideTexture:Show()
	self.rightSideTexture:Show()

	-- Effect IDs from the transmog system (these are the same ones used in the WoW source)
	local effectID1 = 135 -- Lightning effect
	local effectID2 = 136 -- Secondary lightning effect

	-- Create and play the effects with staggered timing
	self.leftModelScene:AddEffect(effectID1, self.leftModelScene)
	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.25, function()
			self.leftModelScene:AddEffect(effectID2, self.leftModelScene)
		end)
	)
	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.5, function()
			self.leftModelScene:AddEffect(effectID1, self.leftModelScene)
		end)
	)

	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.3, function()
			self.rightModelScene:AddEffect(effectID1, self.rightModelScene)
		end)
	)
	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.55, function()
			self.rightModelScene:AddEffect(effectID2, self.rightModelScene)
		end)
	)
	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.8, function()
			self.rightModelScene:AddEffect(effectID1, self.rightModelScene)
		end)
	)
end

function LootDisplayRowMixin:StopScriptedEffects()
	if not G_RLF:IsRetail() then
		return
	end

	if self.leftModelScene then
		self.leftModelScene:ClearEffects()
	end

	if self.rightModelScene then
		self.rightModelScene:ClearEffects()
	end

	if self.scriptedEffectTimers then
		for i, timer in ipairs(self.scriptedEffectTimers) do
			timer:Cancel()
		end
	end

	self.scriptedEffectTimers = {}
end

function LootDisplayRowMixin:Styles()
	self:StyleBackground()
	self:StyleRowBackdrop()
	self:StyleIcon()
	RunNextFrame(function()
		self:StyleIconHighlight()
	end)
	self:StyleUnitPortrait()
	self:StyleText()
	self:HandlerOnRightClick()
end

--- Bootstrap a row from an RLF_LootElement
--- @param element RLF_LootElement
function LootDisplayRowMixin:BootstrapFromElement(element)
	local key = element.key
	local textFn = element.textFn
	local secondaryTextFn = element.secondaryTextFn or function()
		return ""
	end
	local icon = element.icon
	local quantity = element.quantity
	local quality = element.quality
	local r, g, b, a = element.r, element.g, element.b, element.a
	self.logFn = element.logFn
	local isLink = element.isLink
	local unit = element.unit
	local highlight = element.highlight
	self.isSampleRow = element.isSampleRow or false
	self.itemCount = element.itemCount
	self.elementSecondaryText = element.secondaryText or nil
	---@type ColorMixin|nil
	self.elementSecondaryTextColor = element.secondaryTextColor or nil
	self.isCustomLink = element.isCustomLink or false
	self.customBehavior = element.customBehavior
	local text
	if element.isSampleRow or (element.showForSeconds ~= nil and element.showForSeconds ~= self.showForSeconds) then
		self.showForSeconds = element.showForSeconds
		self:StyleExitAnimation()
	end

	if unit then
		key = unit .. "_" .. key
		self.unit = unit
	end

	self.key = key
	self.amount = quantity
	self.type = element.type
	self.quality = quality
	self.topLeftText = element.topLeftText
	self.topLeftColor = element.topLeftColor

	if isLink then
		local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
		local iconSize = sizingDb.iconSize
		local extraWidthStr = ""
		if self.amount then
			extraWidthStr = " x" .. self.amount
		end
		local extraWidth = 0
		if type(self.itemCount) == "number" and self.itemCount > 0 then
			local wrapChar = nil
			if element.type == G_RLF.FeatureModule.ItemLoot then
				wrapChar = G_RLF.db.global.item.itemCountTextWrapChar
			elseif element.type == G_RLF.FeatureModule.Currency then
				wrapChar = G_RLF.db.global.currency.currencyTotalTextWrapChar
			end

			local leftChar, rightChar = G_RLF:GetWrapChars(wrapChar)

			extraWidth = (iconSize / 4)
				+ G_RLF:CalculateTextWidth(leftChar .. self.itemCount .. rightChar .. "  ", self.frameType)
		end
		extraWidth = extraWidth + G_RLF:CalculateTextWidth(extraWidthStr, self.frameType)
		if self.unit then
			local portraitSize = iconSize * 0.8
			extraWidth = extraWidth + portraitSize - (portraitSize / 2)
		end
		self.link = G_RLF:TruncateItemLink(textFn(), extraWidth)
		text = textFn(0, self.link)
		self:SetupTooltip()
	else
		text = textFn()
	end

	if icon then
		self:StyleText()
		self:UpdateIcon(key, icon, quality)
	end

	self:UpdateSecondaryText(secondaryTextFn)
	self:UpdateStyles()
	self:ShowText(text, r, g, b, a)
	self.highlight = highlight
	RunNextFrame(function()
		self:Enter()
		self:UpdateItemCount()
	end)
	self:LogRow(self.logFn, text, true)
end

function LootDisplayRowMixin:LogRow(logFn, text, new)
	if logFn then
		RunNextFrame(function()
			logFn(text, self.amount, new)
		end)
	end
end

function LootDisplayRowMixin:ElementsVisible()
	self.Icon:SetAlpha(1)
	self.PrimaryText:SetAlpha(1)
	self.ItemCountText:SetAlpha(1)
	self.SecondaryText:SetAlpha(1)
	self.UnitPortrait:SetAlpha(1)
end

function LootDisplayRowMixin:ElementsInvisible()
	self.Icon:SetAlpha(0)
	self.PrimaryText:SetAlpha(0)
	self.ItemCountText:SetAlpha(0)
	self.SecondaryText:SetAlpha(0)
	self.UnitPortrait:SetAlpha(0)
end

function LootDisplayRowMixin:FadeInElements()
	self.ElementFadeInAnimation:Play()
end

function LootDisplayRowMixin:IsStaggeredEnter()
	local enterAnimationType = G_RLF.db.global.animations.enter.type
	local slideDirection = G_RLF.db.global.animations.enter.slide.direction

	if
		enterAnimationType == G_RLF.EnterAnimationType.SLIDE
		and (slideDirection == G_RLF.SlideDirection.UP or slideDirection == G_RLF.SlideDirection.DOWN)
	then
		return true
	end
end

function LootDisplayRowMixin:IsPreviousRowEntering()
	if not self._prev then
		return false
	end

	if not self._prev.waiting then
		if not self._prev.EnterAnimation then
			return false
		end
		if not self._prev.EnterAnimation:IsPlaying() then
			return false
		end
	end

	return true
end

function LootDisplayRowMixin:Enter()
	self.EnterAnimation:Stop()
	self.ElementFadeInAnimation:Stop()
	self.ExitAnimation:Stop()
	if not self:IsStaggeredEnter() or not self.waiting then
		RunNextFrame(function()
			self:Show()
			self.EnterAnimation:Play()
		end)
		return
	end
	if self:IsPreviousRowEntering() then
		self:Hide()
		return
	end
	RunNextFrame(function()
		self:Show()
		self.EnterAnimation:Play()
	end)
end

function LootDisplayRowMixin:HandlerOnRightClick()
	self:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and not self.isHistoryMode then
			if not self.ExitAnimation then
				return
			end
			-- Stop any ongoing animation
			if self.ExitAnimation:IsPlaying() then
				self.ExitAnimation:Stop()
			end

			if self.ExitAnimation.noop then
				self.ExitAnimation.noop:SetStartDelay(0)
			elseif self.ExitAnimation.fadeOut then
				self.ExitAnimation.fadeOut:SetStartDelay(0)
			end
			self.bustCacheExitAnimation = true

			-- Start the fade-out animation
			self.ExitAnimation:Play()
		end
	end)
end

function LootDisplayRowMixin:UpdateStyles()
	self:Styles()
	if self.icon and G_RLF.iconGroup then
		G_RLF.iconGroup:ReSkin(self.Icon)
	end
end

function LootDisplayRowMixin:UpdateEnterAnimation()
	self:StyleEnterAnimation()
end

function LootDisplayRowMixin:UpdateFadeoutDelay()
	self:StyleExitAnimation()
end

function LootDisplayRowMixin:UpdateSecondaryText(secondaryTextFn)
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

function LootDisplayRowMixin:UpdateQuantity(element)
	self.updatePending = false
	if self.amount == nil then
		self.updatePending = true
	elseif self.PrimaryText:GetAlpha() < 1 then
		self.updatePending = true
	elseif self.EnterAnimation and self.EnterAnimation:IsPlaying() then
		self.updatePending = true
	elseif self.ElementFadeInAnimation and self.ElementFadeInAnimation:IsPlaying() then
		self.updatePending = true
	end
	if self.updatePending then
		self.pendingElement = element
		return
	end
	self.pendingElement = nil
	-- Update existing entry
	local text = element.textFn(self.amount, self.link)
	self.amount = self.amount + element.quantity
	self.itemCount = element.itemCount
	local r, g, b, a = element.r, element.g, element.b, element.a

	self:UpdateSecondaryText(element.secondaryTextFn)
	self:UpdateItemCount()
	self:ShowText(text, r, g, b, a)

	if not G_RLF.db.global.animations.update.disableHighlight then
		self.HighlightAnimation:Stop()
		self.HighlightAnimation:Play()
	end
	if self.ExitAnimation:IsPlaying() then
		self.ExitAnimation:Stop()
		self.ExitAnimation:Play()
	end

	self:LogRow(self.logFn, text, false)
end

--- Update the total item count for the row
function LootDisplayRowMixin:UpdateItemCount()
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

function LootDisplayRowMixin:UpdatePosition(frame)
	-- Position the new row at the bottom (or top if growing down)
	local vertDir, opposite, yOffset = frame.vertDir, frame.opposite, frame.yOffset
	self:ClearAllPoints()
	if self._prev then
		self:SetPoint(vertDir, self._prev, opposite, 0, yOffset)
		self.anchorPoint = vertDir
		self.opposite = opposite
		self.yOffset = yOffset
		self.anchorTo = self._prev
		self:SetFrameLevel(self._prev:GetFrameLevel() - 1)
	else
		self:SetPoint(vertDir, frame, vertDir)
		self.anchorPoint = vertDir
		self.opposite = nil
		self.yOffset = nil
		self.anchorTo = frame
		self:SetFrameLevel(500)
	end
end

function LootDisplayRowMixin:UpdateNeighborPositions(frame)
	local vertDir, opposite, yOffset = frame.vertDir, frame.opposite, frame.yOffset
	local _next = self._next
	local _prev = self._prev

	if _next then
		_next:ClearAllPoints()
		if _prev then
			_next:SetPoint(vertDir, _prev, opposite, 0, yOffset)
			_next.anchorPoint = vertDir
			_next.opposite = opposite
			_next.yOffset = yOffset
			_next.anchorTo = _prev
			_next:SetFrameLevel(_prev:GetFrameLevel() - 1)
		else
			_next:SetPoint(vertDir, frame, vertDir)
			_next.anchorPoint = vertDir
			_next.opposite = nil
			_next.yOffset = nil
			_next.anchorTo = frame
			_next:SetFrameLevel(500)
		end
	end
end

function LootDisplayRowMixin:SetupTooltip(isHistoryFrame)
	if not self.link then
		return
	end
	-- Dynamically size the button to match the PrimaryText width
	self.ClickableButton:ClearAllPoints()
	self.ClickableButton:SetPoint("LEFT", self.PrimaryText, "LEFT")
	self.ClickableButton:SetSize(self.PrimaryText:GetStringWidth(), self.PrimaryText:GetStringHeight())
	self.ClickableButton:Show()
	-- Add Tooltip
	-- Tooltip logic
	local function showTooltip()
		---@type RLF_ConfigTooltips
		local tooltipDb = G_RLF.db.global.tooltips
		if not tooltipDb.hover.enabled then
			return
		end
		if tooltipDb.hover.onShift and not IsShiftKeyDown() then
			return
		end
		local inCombat = UnitAffectingCombat("player")
		if inCombat then
			return
		end
		if not LinkUtil.IsLinkType(self.link, "item") then
			-- It doesn't look like we can get hover behavior for transmog links but
			-- they don't provide much information anyway
			return
		end
		GameTooltip:SetOwner(self.ClickableButton, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.link) -- Use the item's link to show the tooltip
		GameTooltip:Show()
	end

	local function hideTooltip()
		GameTooltip:Hide()
	end

	-- OnEnter: Show tooltip or listen for Shift changes
	self.ClickableButton:SetScript("OnEnter", function()
		if not isHistoryFrame then
			self.ExitAnimation:Stop()
			self.HighlightAnimation:Stop()
			self:ResetHighlightBorder()
		end
		showTooltip()

		-- Start listening for Shift key changes
		self.ClickableButton:RegisterEvent("MODIFIER_STATE_CHANGED")
	end)

	-- OnLeave: Hide tooltip and stop listening for Shift changes
	self.ClickableButton:SetScript("OnLeave", function()
		if not isHistoryFrame then
			self.ExitAnimation:Play()
		end
		hideTooltip()

		-- Stop listening for Shift key changes
		self.ClickableButton:UnregisterEvent("MODIFIER_STATE_CHANGED")
	end)

	-- Handle Shift key changes
	self.ClickableButton:SetScript("OnEvent", function(_, event, key, state)
		---@type RLF_ConfigTooltips
		local tooltipDb = G_RLF.db.global.tooltips
		if not tooltipDb.hover.onShift then
			return
		end

		if event == "MODIFIER_STATE_CHANGED" and key == "LSHIFT" then
			if state == 1 then
				showTooltip()
			else
				hideTooltip()
			end
		end
	end)

	local function handleClick(button)
		if button == "LeftButton" and not IsModifiedClick() then
			if not self.link then
				return
			end

			-- Check for custom behavior first
			if self.isCustomLink and self.customBehavior and type(self.customBehavior) == "function" then
				self.customBehavior()
				return
			end

			local s = self.link:find("transmogappearance:")
			if s then
				-- All this to check if the link is a transmog appearance link
				-- and get the ID to open the Transmog Collection
				-- If we just store the ID as well as the link, we can skip this
				local taS = self.link:find("transmogappearance:")
				if not taS then
					return
				end
				local shortened = self.link:sub(taS)
				local barS = shortened:find("|")
				if not barS then
					barS = #shortened + 1
				end
				shortened = shortened:sub(1, barS - 1)
				local _, id = strsplit(":", shortened)
				if id then
					TransmogUtil.OpenCollectionToItem(id)
				end
			elseif self.link then
				-- Open the ItemRefTooltip to mimic in-game chat behavior
				SetItemRef(self.link, self.link, button, self.ClickableButton)
			end
		elseif button == "LeftButton" and IsControlKeyDown() then
			DressUpItemLink(self.link)
		elseif button == "LeftButton" and IsShiftKeyDown() then
			-- Custom behavior for right click, if needed
			if ChatEdit_GetActiveWindow() then
				ChatEdit_InsertLink(self.link)
			else
				ChatFrame_OpenChat(self.link)
			end
		elseif button == "RightButton" and not self.isHistoryMode then
			-- Stop any ongoing animation
			if self.ExitAnimation:IsPlaying() then
				self.ExitAnimation:Stop()
			end

			-- Remove the delay for immediate fade-out
			if self.ExitAnimation.noop then
				self.ExitAnimation.noop:SetStartDelay(0)
			elseif self.ExitAnimation.fadeOut then
				self.ExitAnimation.fadeOut:SetStartDelay(0)
			end
			self.bustCacheExitAnimation = true

			-- Start the fade-out animation
			self.ExitAnimation:Play()
		end
	end

	-- Add Click Handling for ItemRefTooltip
	self.ClickableButton:SetScript("OnMouseUp", function(_, button)
		handleClick(button)
	end)

	if self.Icon then
		self.Icon:SetScript("OnEnter", function()
			if not isHistoryFrame then
				self.ExitAnimation:Stop()
				self.HighlightAnimation:Stop()
				self:ResetHighlightBorder()
			end
			showTooltip()
			self.Icon:RegisterEvent("MODIFIER_STATE_CHANGED")
		end)
		self.Icon:SetScript("OnLeave", function()
			if not isHistoryFrame then
				self.ExitAnimation:Play()
			end
			hideTooltip()
			self.Icon:UnregisterEvent("MODIFIER_STATE_CHANGED")
		end)
		self.Icon:SetScript("OnEvent", function(_, event, key, state)
			if event == "MODIFIER_STATE_CHANGED" and key == "LSHIFT" then
				if state == 1 then
					showTooltip()
				else
					hideTooltip()
				end
			end
		end)
		self.Icon:SetScript("OnMouseUp", function(_, button)
			handleClick(button)
		end)
	end
end

function LootDisplayRowMixin:IsFading()
	return self.ExitAnimation:IsPlaying() and not self.ExitAnimation.fadeOut:IsDelaying()
end

function LootDisplayRowMixin:Dump()
	local prevKey, nextKey
	if self._prev then
		prevKey = self._prev.key or "NONE"
	else
		prevKey = "prev nil"
	end

	if self._next then
		nextKey = self._next.key or "NONE"
	else
		nextKey = "next nil"
	end

	return format(
		"{name=%s, key=%s, amount=%s, PrimaryText=%s, _prev.key=%s, _next.key=%s}",
		self:GetDebugName(),
		self.key or "NONE",
		self.amount or "NONE",
		self.PrimaryText:GetText() or "NONE",
		prevKey,
		nextKey
	)
end

function LootDisplayRowMixin:ShowItemCountText(itemCount, options)
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

function LootDisplayRowMixin:ShowText(text, r, g, b, a)
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

function LootDisplayRowMixin:UpdateIcon(key, icon, quality)
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

-- Utility function to check if the mouse is over the parent or any of its children
local function isMouseOverSelfOrChildren(frame)
	if frame:IsMouseOver() then
		return true
	end

	for _, child in ipairs({ frame:GetChildren() }) do
		if child:IsMouseOver() then
			return true
		end
	end

	return false
end

function LootDisplayRowMixin:SetUpHoverEffect()
	---@type RLF_ConfigAnimations
	local animationsDb = G_RLF.db.global.animations
	local hoverDb = animationsDb.hover
	local highlightedAlpha = hoverDb.alpha
	local baseDuration = hoverDb.baseDuration

	-- Fade-in animation group
	if not self.HighlightFadeIn then
		self.HighlightFadeIn = self.HighlightBGOverlay:CreateAnimationGroup()

		local fadeIn = self.HighlightFadeIn:CreateAnimation("Alpha")
		local startingAlpha = self.HighlightBGOverlay:GetAlpha()
		fadeIn:SetFromAlpha(startingAlpha) -- Start from the current alpha
		fadeIn:SetToAlpha(highlightedAlpha) -- Target alpha for the highlight
		local duration = baseDuration * (highlightedAlpha - startingAlpha) / highlightedAlpha
		fadeIn:SetDuration(duration)
		fadeIn:SetSmoothing("OUT")

		-- Ensure alpha is held at target level after animation finishes
		self.HighlightFadeIn:SetScript("OnFinished", function()
			self.HighlightBGOverlay:SetAlpha(highlightedAlpha) -- Hold at target alpha
		end)
	end

	-- Fade-out animation group
	if not self.HighlightFadeOut then
		self.HighlightFadeOut = self.HighlightBGOverlay:CreateAnimationGroup()

		local fadeOut = self.HighlightFadeOut:CreateAnimation("Alpha")
		local startingAlpha = self.HighlightBGOverlay:GetAlpha()
		fadeOut:SetFromAlpha(startingAlpha) -- Start from the target alpha of the fade-in
		fadeOut:SetToAlpha(0) -- Return to original alpha
		local duration = baseDuration * startingAlpha / highlightedAlpha
		fadeOut:SetDuration(duration)
		fadeOut:SetSmoothing("IN")
		-- fadeOut:SetStartDelay(0.15) -- Delay before starting the fade-out

		-- Ensure alpha is fully reset after animation finishes
		self.HighlightFadeOut:SetScript("OnFinished", function()
			self.HighlightBGOverlay:SetAlpha(0) -- Reset to invisible
		end)
	end

	-- OnEnter: Play fade-in animation
	self:SetScript("OnEnter", function()
		---@type RLF_ConfigAnimations
		local animationsDb = G_RLF.db.global.animations
		if self.hasMouseOver or not animationsDb.hover.enabled then
			return
		end
		self.hasMouseOver = true
		-- Stop fade-out if it’s playing
		if self.HighlightFadeOut:IsPlaying() then
			self.HighlightFadeOut:Stop()
		end
		-- Play fade-in
		self.HighlightFadeIn:Play()
	end)

	-- OnLeave: Play fade-out animation
	self:SetScript("OnLeave", function()
		-- Prevent OnLeave from firing if the mouse is still over the row or any of its children
		if isMouseOverSelfOrChildren(self) or not self.hasMouseOver then
			return
		end
		self.hasMouseOver = false
		-- Stop fade-in if it’s playing
		if self.HighlightFadeIn:IsPlaying() then
			self.HighlightFadeIn:Stop()
		end
		-- Play fade-out
		self.HighlightFadeOut:Play()
	end)
end

function LootDisplayRowMixin:HighlightIcon()
	if self.highlight then
		RunNextFrame(function()
			if self.type == G_RLF.FeatureModule.Transmog and G_RLF:IsRetail() then
				self:PlayTransmogEffect()
			else
				-- Show the glow texture and play the animation
				self.glowTexture:SetAlpha(0.75)
				self.glowTexture:Show()
				self.glowAnimationGroup:Play()
			end
		end)
	end
end

function LootDisplayRowMixin:ResetFadeOut()
	RunNextFrame(function()
		if self.ExitAnimation then
			if self.ExitAnimation:IsPlaying() then
				self.ExitAnimation:Stop()
			end
			self.ExitAnimation:Play()
		end
	end)
end

function LootDisplayRowMixin:ResetHighlightBorder()
	self.TopBorder:SetAlpha(0)
	self.RightBorder:SetAlpha(0)
	self.BottomBorder:SetAlpha(0)
	self.LeftBorder:SetAlpha(0)
end

function LootDisplayRowMixin:UpdateWithHistoryData(data)
	self:Reset()
	self.isHistoryMode = true
	self.key = data.key
	self.amount = data.amount
	self.link = data.link
	self.quality = data.quality
	self.unit = data.unit
	self.PrimaryText:SetText(data.rowText)
	self.PrimaryText:SetTextColor(unpack(data.textColor))

	---@type RLF_ConfigStyling
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	if data.unit and data.secondaryText and stylingDb.enabledSecondaryRowText then
		self.secondaryText = data.secondaryText
		self.SecondaryText:SetText(data.secondaryText)
		self.SecondaryText:SetTextColor(unpack(data.secondaryTextColor))
	end
	self:StyleText()
	if data.icon then
		self:SetupTooltip(true)
		self:UpdateIcon(self.key, data.icon, self.quality)
	else
		self.icon = nil
	end
	self:UpdateStyles()
end
