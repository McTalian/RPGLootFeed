---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_LootDisplayRow: BackdropTemplate, RLF_RowAnimationMixin, RLF_RowTooltipMixin, RLF_RowTextMixin, RLF_RowBackdropMixin, RLF_RowScriptedEffectsMixin, RLF_RowIconMixin, RLF_RowUnitPortraitMixin
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

function LootDisplayRowMixin:UpdateStyles()
	self:Styles()
	if self.icon and G_RLF.iconGroup then
		G_RLF.iconGroup:ReSkin(self.Icon)
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
	-- Allow the element to recompute color based on the net accumulated quantity
	if element.colorFn then
		r, g, b, a = element.colorFn(self.amount)
	end

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
