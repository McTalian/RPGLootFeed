---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_RowFontString: FontString
---@field elementFadeIn Alpha

---@class RLF_RowTextMixin
RLF_RowTextMixin = {}

local defaultColor = { 1, 1, 1, 1 }

--- Create the PrimaryLineLayout horizontal layout container that holds
--- PrimaryText and ItemCountText as layout children.
--- Must be called once during row frame initialisation (from Init()).
function RLF_RowTextMixin:CreatePrimaryLineLayout()
	-- Guard: the layout frame and its children persist on the pooled frame across
	-- Acquire/Release cycles, exactly like the XML-defined PrimaryText/ItemCountText.
	-- Only create once per physical frame object.
	if self.PrimaryLineLayout then
		return
	end

	local layout = CreateFrame("Frame", nil, self)
	-- Both mixins are required:
	--   LayoutMixin        → provides Layout(), GetLayoutChildren(), CalculateFrameSize()
	--   HorizontalLayoutMixin → provides LayoutChildren() (horizontal positioning)
	-- This mirrors the XML template: mixin="LayoutMixin, HorizontalLayoutMixin"
	Mixin(layout, LayoutMixin, HorizontalLayoutMixin)
	layout.spacing = 0 -- updated in StyleText() once iconSize is known

	-- PrimaryText is re-parented from the row into the layout container.
	self.PrimaryText:SetParent(layout)
	self.PrimaryText.layoutIndex = 1
	-- SetWordWrap(false) once here so the engine truncates with "..." rather than
	-- wrapping.  Not repeated in the hot-path LayoutPrimaryLine().
	self.PrimaryText:SetWordWrap(false)

	-- AmountText holds the quantity suffix (e.g. "x2") as a separate non-truncatable
	-- FontString at layoutIndex=2.  Hidden by default; shown by ShowAmountText().
	-- Inherits "GameFontNormal" so the engine never throws "Font not set" when
	-- SetText/Hide are called before StyleText() runs (e.g. in Reset()).
	local amountText = layout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	amountText.layoutIndex = 2
	amountText:SetWordWrap(false)
	amountText:Hide()
	self.AmountText = amountText

	-- ItemCountText shifts to layoutIndex=3 (bag count / skill delta / rep level).
	self.ItemCountText:SetParent(layout)
	self.ItemCountText.layoutIndex = 3

	self.PrimaryLineLayout = layout
end

--- Create the SecondaryLineLayout horizontal layout container that holds
--- SecondaryText (and future secondary-line children) as layout children.
--- Must be called once during row frame initialisation (from Init()).
function RLF_RowTextMixin:CreateSecondaryLineLayout()
	-- Guard: same pool-idempotency pattern as CreatePrimaryLineLayout().
	if self.SecondaryLineLayout then
		return
	end

	local layout = CreateFrame("Frame", nil, self)
	Mixin(layout, LayoutMixin, HorizontalLayoutMixin)
	layout.spacing = 0 -- updated in StyleText() once iconSize is known

	-- SecondaryText is re-parented from the row into the layout container.
	-- SetWordWrap(false) so the engine truncates with "..." rather than wrapping.
	self.SecondaryText:SetParent(layout)
	self.SecondaryText.layoutIndex = 1
	self.SecondaryText:SetWordWrap(false)

	layout:Hide()
	self.SecondaryLineLayout = layout
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
			self.AmountText:SetFontObject(font)
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
				self.AmountText,
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

	local textAlignment = stylingDb.textAlignment
	local iconOnLeft = textAlignment ~= G_RLF.TextAlignment.RIGHT
	local padding = sizingDb.padding
	local iconSize = sizingDb.iconSize
	local enabledSecondaryRowText = stylingDb.enabledSecondaryRowText

	-- Compute inter-child spacing before the cache block so the check can compare
	-- against the new value. 0 = auto (scales with icon size: iconSize/4).
	local rowTextSpacingCfg = stylingDb.rowTextSpacing or 0
	local spacing = (rowTextSpacingCfg == 0) and (iconSize / 4) or rowTextSpacingCfg

	if
		self.cachedRowTextAlignment ~= textAlignment
		or self.cachedRowTextXOffset ~= spacing
		or self.cachedRowTextIcon ~= self.icon
		or self.cachedEnabledSecondaryText ~= enabledSecondaryRowText
		or self.cachedSecondaryText ~= self.secondaryText
		or self.cachedUnitText ~= self.unit
		or self.cachedPaddingText ~= padding
	then
		self.cachedRowTextAlignment = textAlignment
		self.cachedRowTextXOffset = spacing
		self.cachedRowTextIcon = self.icon
		self.cachedEnabledSecondaryText = enabledSecondaryRowText
		self.cachedSecondaryText = self.secondaryText
		self.cachedUnitText = self.unit
		self.cachedPaddingText = padding

		local anchor = "LEFT"
		local iconAnchor = "RIGHT"
		local xOffset = spacing
		if not iconOnLeft then
			anchor = "RIGHT"
			iconAnchor = "LEFT"
			xOffset = xOffset * -1
		end
		-- PrimaryLineLayout owns the anchor to Icon; its children (PrimaryText,
		-- AmountText, ItemCountText) are positioned by Layout(). The spacing is
		-- user-configurable via rowTextSpacing (0 = auto = iconSize/4).
		-- childLayoutDirection reverses child order for right-align (icon on right)
		-- without changing layoutIndex values.
		self.PrimaryLineLayout.spacing = spacing
		self.SecondaryLineLayout.spacing = spacing
		if iconOnLeft then
			self.PrimaryLineLayout.childLayoutDirection = nil
		else
			self.PrimaryLineLayout.childLayoutDirection = "rightToLeft"
		end
		self.PrimaryLineLayout:ClearAllPoints()
		self.PrimaryText:SetJustifyH(anchor)
		if self.icon then
			if self.unit and G_RLF.db.global.partyLoot.enablePartyAvatar then
				self.PrimaryLineLayout:SetPoint(anchor, self.UnitPortrait, iconAnchor, xOffset, 0)
			else
				self.PrimaryLineLayout:SetPoint(anchor, self.Icon, iconAnchor, xOffset, 0)
			end
		else
			self.PrimaryLineLayout:SetPoint(anchor, self.Icon, anchor, 0, 0)
		end

		if enabledSecondaryRowText and self.secondaryText ~= nil and self.secondaryText ~= "" then
			self.SecondaryLineLayout:ClearAllPoints()
			self.SecondaryText:SetJustifyH(anchor)
			if self.icon then
				if self.unit then
					if G_RLF.db.global.partyLoot.enablePartyAvatar then
						self.SecondaryLineLayout:SetPoint(anchor, self.UnitPortrait, iconAnchor, xOffset, 0)
					else
						self.SecondaryLineLayout:SetPoint(anchor, self.Icon, iconAnchor, xOffset, 0)
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
					self.SecondaryLineLayout:SetPoint(anchor, self.Icon, iconAnchor, xOffset, 0)
				end
			else
				self.SecondaryLineLayout:SetPoint(anchor, self.Icon, anchor, 0, 0)
			end
			-- Vertical split: PrimaryLineLayout takes the top slot;
			-- SecondaryLineLayout takes the bottom slot.
			self.PrimaryLineLayout:SetPoint("BOTTOM", self, "CENTER", 0, padding)
			self.SecondaryLineLayout:SetPoint("TOP", self, "CENTER", 0, -padding)
			self.SecondaryLineLayout:SetShown(true)
		end
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
	-- Migrated modules provide itemCountFn on the payload
	if self.itemCountFn then
		RunNextFrame(function()
			local value, options = self.itemCountFn()
			if value then
				self:ShowItemCountText(value, options)
			end
		end)
		return
	end

	-- ── Legacy type-switch for non-migrated modules ──────────────────────────
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

--- Show or hide the AmountText (quantity suffix) FontString.
--- Calls LayoutPrimaryLine() at the end so the updated visibility is reflected
--- in PrimaryText's budget — mirrors ShowItemCountText's pattern exactly.
--- @param amountText string|nil  Formatted suffix e.g. "x2", or "" / nil to hide.
--- @param r number Red channel — matches PrimaryText color.
--- @param g number Green channel.
--- @param b number Blue channel.
--- @param a number Alpha channel.
function RLF_RowTextMixin:ShowAmountText(amountText, r, g, b, a)
	if amountText and amountText ~= "" then
		self.AmountText:SetText(amountText)
		self.AmountText:SetTextColor(r, g, b, a)
		self.AmountText:Show()
	else
		self.AmountText:Hide()
	end
	self:LayoutPrimaryLine()
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

	-- Second layout pass: now that the count string is set (or hidden), the
	-- accurate ItemCountText width is measured and PrimaryText is resized to
	-- fit within the remaining budget.
	self:LayoutPrimaryLine()
end

--- Compute the available text width, apply it to PrimaryText, and call Layout()
--- on PrimaryLineLayout.  Also sizes ClickableButton once Layout() has applied
--- engine truncation so GetStringWidth() reflects the visible display width.
--- Called from ShowText() for all rows, and again from ShowItemCountText() for
--- rows that display a count (Items, Currency, Reputation, XP, Professions).
function RLF_RowTextMixin:LayoutPrimaryLine()
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local iconSize = sizingDb.iconSize
	local feedWidth = sizingDb.feedWidth

	local portraitOffset = 0
	if self.unit and G_RLF.db.global.partyLoot.enablePartyAvatar then
		-- UnitPortrait is anchored at Icon.RIGHT + iconSize/4 (gap) with width portraitSize.
		-- PrimaryLineLayout is then anchored at UnitPortrait.RIGHT + iconSize/4 (gap).
		-- Extra width consumed beyond iconOffset: portraitSize + gap between icon and portrait.
		local portraitSize = iconSize * 0.8
		portraitOffset = portraitSize + (iconSize / 4)
	end

	-- Space occupied by the icon column:
	--   iconSize/4  (gap from row left edge to icon — icon is anchored at xOffset=iconSize/4)
	--   iconSize    (the icon itself)
	--   iconSize/4  (gap between icon right edge and the start of PrimaryLineLayout)
	-- This matches the original TruncateItemLink formula: feedWidth - (iconSize/4) - iconSize - (iconSize/4)
	local iconOffset = iconSize + 2 * (iconSize / 4)
	local availableWidth = feedWidth - iconOffset - portraitOffset

	-- When AmountText (quantity suffix) is visible its width (plus spacing) is
	-- subtracted from the budget first.
	local amountTextWidth = 0
	if self.AmountText:IsShown() then
		amountTextWidth = self.AmountText:GetUnboundedStringWidth() + self.PrimaryLineLayout.spacing
	end

	-- When ItemCountText is visible its width (plus the layout spacing gap) is
	-- subtracted from the budget so PrimaryText knows how much room it has.
	local itemCountWidth = 0
	if self.ItemCountText:IsShown() then
		itemCountWidth = self.ItemCountText:GetUnboundedStringWidth() + self.PrimaryLineLayout.spacing
	end

	-- PrimaryText takes only the space it naturally needs, truncating only when
	-- its intrinsic width would push AmountText or ItemCountText off-row.
	local maxPrimaryWidth = math.max(1, availableWidth - amountTextWidth - itemCountWidth)
	local naturalWidth = self.PrimaryText:GetUnboundedStringWidth()
	local primaryTextWidth = math.min(naturalWidth, maxPrimaryWidth)
	self.PrimaryText:SetWidth(primaryTextWidth)
	-- Re-set the stored raw text so GetText() always returns the full original
	-- string (engine truncation only affects display rendering, not GetText()).
	self.PrimaryText:SetText(self.rawPrimaryText)
	-- SetWordWrap(false) was already called once in CreatePrimaryLineLayout().

	self.PrimaryLineLayout.fixedWidth = availableWidth
	self.PrimaryLineLayout:Layout()

	-- ClickableButton geometry is owned exclusively here (not in ShowText or
	-- SetupTooltip) so it reflects the post-truncation display width.
	if self.link then
		self.ClickableButton:ClearAllPoints()
		self.ClickableButton:SetPoint("LEFT", self.PrimaryText, "LEFT")
		self.ClickableButton:SetSize(self.PrimaryText:GetStringWidth(), self.PrimaryText:GetStringHeight())
	end
end

--- Compute the available text width for SecondaryText, apply it, and call Layout()
--- on SecondaryLineLayout. Called from ShowText() whenever secondary text is shown.
function RLF_RowTextMixin:LayoutSecondaryLine()
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local iconSize = sizingDb.iconSize
	local feedWidth = sizingDb.feedWidth

	local portraitOffset = 0
	if self.unit and G_RLF.db.global.partyLoot.enablePartyAvatar then
		-- Mirrors the corrected portrait offset logic in LayoutPrimaryLine().
		local portraitSize = iconSize * 0.8
		portraitOffset = portraitSize + (iconSize / 4)
	end

	local iconOffset = iconSize + 2 * (iconSize / 4)
	local availableWidth = feedWidth - iconOffset - portraitOffset

	-- Constrain SecondaryText to availableWidth, then re-set its text so the
	-- engine renders the "." ellipsis against the original (untruncated) string.
	local naturalWidth = self.SecondaryText:GetUnboundedStringWidth()
	self.SecondaryText:SetWidth(math.max(1, math.min(naturalWidth, availableWidth)))
	self.SecondaryText:SetText(self.secondaryText or "")

	self.SecondaryLineLayout.fixedWidth = availableWidth
	self.SecondaryLineLayout:Layout()
end

function RLF_RowTextMixin:ShowText(rawText, r, g, b, a)
	if a == nil then
		a = 1
	end

	-- Store the raw (untruncated) text; LayoutPrimaryLine() will re-apply it
	-- after computing the correct width budget.
	self.rawPrimaryText = rawText
	self.PrimaryText:SetText(rawText)

	if r == nil or g == nil or b == nil then
		r, g, b, a = unpack(defaultColor)
	end

	self.PrimaryText:SetTextColor(r, g, b, a)

	---@type RLF_ConfigStyling
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	if stylingDb.enabledSecondaryRowText and self.secondaryText ~= nil and self.secondaryText ~= "" then
		self.SecondaryText:SetText(self.secondaryText)
		self.SecondaryText:Show()
		self.SecondaryLineLayout:Show()
		self:LayoutSecondaryLine()
	else
		self.SecondaryText:Hide()
		self.SecondaryLineLayout:Hide()
	end

	-- Initial layout pass with ItemCountText hidden (count text is set later via
	-- a deferred UpdateItemCount → ShowItemCountText call).  PrimaryText gets
	-- the full available width on this pass.
	self:LayoutPrimaryLine()
end

G_RLF.RLF_RowTextMixin = RLF_RowTextMixin
