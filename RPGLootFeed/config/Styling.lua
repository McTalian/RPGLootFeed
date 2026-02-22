---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class Styling : RLF_StylingConfigHandlerBase
local Styling = {}

---@class RLF_DBGlobal
G_RLF.defaults.global = G_RLF.defaults.global or {}

G_RLF.ConfigCommon.StylingBase.CloneDefaultDb("global.styling")
---@class RLF_ConfigStyling
G_RLF.defaults.global.styling = G_RLF.defaults.global.styling or {}

function Styling:GetTextAlignment()
	return G_RLF.db.global.styling.textAlignment
end

function Styling:SetTextAlignment(_, value)
	G_RLF.db.global.styling.textAlignment = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:GetGrowUp()
	return G_RLF.db.global.styling.growUp
end

function Styling:SetGrowUp(_, value)
	G_RLF.db.global.styling.growUp = value
	G_RLF.LootDisplay:UpdateRowPositions()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:GetBackgroundType()
	return G_RLF.db.global.styling.rowBackgroundType
end

function Styling:SetBackgroundType(_, value)
	G_RLF.db.global.styling.rowBackgroundType = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:IsGradientHidden()
	return G_RLF.db.global.styling.rowBackgroundType ~= G_RLF.RowBackground.GRADIENT
end

function Styling:GetGradientStartColor()
	local r, g, b, a = unpack(G_RLF.db.global.styling.rowBackgroundGradientStart)
	return r, g, b, a
end

function Styling:SetGradientStartColor(_, r, g, b, a)
	G_RLF.db.global.styling.rowBackgroundGradientStart = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetGradientEndColor()
	local r, g, b, a = unpack(G_RLF.db.global.styling.rowBackgroundGradientEnd)
	return r, g, b, a
end

function Styling:SetGradientEndColor(_, r, g, b, a)
	G_RLF.db.global.styling.rowBackgroundGradientEnd = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:IsBackgroundTextureHidden()
	return G_RLF.db.global.styling.rowBackgroundType ~= G_RLF.RowBackground.TEXTURED
end

function Styling:GetBackgroundTexture()
	return G_RLF.db.global.styling.rowBackgroundTexture
end

function Styling:SetBackgroundTexture(_, value)
	G_RLF.db.global.styling.rowBackgroundTexture = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetBackgroundTextureColor()
	local r, g, b, a = unpack(G_RLF.db.global.styling.rowBackgroundTextureColor)
	return r, g, b, a
end

function Styling:SetBackgroundTextureColor(_, r, g, b, a)
	G_RLF.db.global.styling.rowBackgroundTextureColor = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetTopInset()
	return G_RLF.db.global.styling.backdropInsets.top
end

function Styling:SetTopInset(_, value)
	G_RLF.db.global.styling.backdropInsets.top = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetRightInset()
	return G_RLF.db.global.styling.backdropInsets.right
end

function Styling:SetRightInset(_, value)
	G_RLF.db.global.styling.backdropInsets.right = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetBottomInset()
	return G_RLF.db.global.styling.backdropInsets.bottom
end

function Styling:SetBottomInset(_, value)
	G_RLF.db.global.styling.backdropInsets.bottom = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetLeftInset()
	return G_RLF.db.global.styling.backdropInsets.left
end

function Styling:SetLeftInset(_, value)
	G_RLF.db.global.styling.backdropInsets.left = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetRowBordersEnabled()
	return G_RLF.db.global.styling.enableRowBorder
end

function Styling:SetRowBordersEnabled(_, value)
	G_RLF.db.global.styling.enableRowBorder = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:IsRowBorderDisabled()
	return not G_RLF.db.global.styling.enableRowBorder
end

function Styling:GetRowBorderTexture()
	return G_RLF.db.global.styling.rowBorderTexture
end

function Styling:SetRowBorderTexture(_, value)
	G_RLF.db.global.styling.rowBorderTexture = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetRowBorderThickness()
	return G_RLF.db.global.styling.rowBorderSize
end

function Styling:SetRowBorderThickness(_, value)
	G_RLF.db.global.styling.rowBorderSize = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetRowBorderColor()
	local r, g, b, a = unpack(G_RLF.db.global.styling.rowBorderColor)
	return r, g, b, a
end

function Styling:SetRowBorderColor(_, r, g, b, a)
	G_RLF.db.global.styling.rowBorderColor = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetRowBorderClassColors()
	return G_RLF.db.global.styling.rowBorderClassColors
end

function Styling:SetRowBorderClassColors(_, value)
	G_RLF.db.global.styling.rowBorderClassColors = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetEnabledSecondaryRowText()
	return G_RLF.db.global.styling.enabledSecondaryRowText
end

function Styling:SetEnabledSecondaryRowText(_, value)
	G_RLF.db.global.styling.enabledSecondaryRowText = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetEnableTopLeftIconText()
	return G_RLF.db.global.styling.enableTopLeftIconText
end

function Styling:SetEnableTopLeftIconText(_, value)
	G_RLF.db.global.styling.enableTopLeftIconText = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:IsTopLeftIconTextDisabled()
	return not G_RLF.db.global.styling.enableTopLeftIconText
end

function Styling:GetTopLeftIconFontSize()
	return G_RLF.db.global.styling.topLeftIconFontSize
end

function Styling:SetTopLeftIconFontSize(_, value)
	G_RLF.db.global.styling.topLeftIconFontSize = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetTopLeftIconTextUseQualityColor()
	return G_RLF.db.global.styling.topLeftIconTextUseQualityColor
end

function Styling:SetTopLeftIconTextUseQualityColor(_, value)
	G_RLF.db.global.styling.topLeftIconTextUseQualityColor = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetTopLeftIconTextColor()
	local r, g, b, a = unpack(G_RLF.db.global.styling.topLeftIconTextColor)
	return r, g, b, a
end

function Styling:SetTopLeftIconTextColor(_, r, g, b, a)
	G_RLF.db.global.styling.topLeftIconTextColor = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function Styling:GetUseFontObjects()
	return G_RLF.db.global.styling.useFontObjects
end

function Styling:SetUseFontObjects(_, value)
	G_RLF.db.global.styling.useFontObjects = value
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:IsFontObjectsDisabled()
	return not G_RLF.db.global.styling.useFontObjects
end

function Styling:GetFontObject()
	return G_RLF.db.global.styling.font
end

function Styling:SetFontObject(_, value)
	G_RLF.db.global.styling.font = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:IsCustomFontsDisabled()
	return G_RLF.db.global.styling.useFontObjects == true
end

function Styling:GetFontFace()
	return G_RLF.db.global.styling.fontFace
end

function Styling:SetFontFace(_, value)
	G_RLF.db.global.styling.fontFace = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:GetFontSize()
	return G_RLF.db.global.styling.fontSize
end

function Styling:SetFontSize(_, value)
	G_RLF.db.global.styling.fontSize = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:IsSecondaryFontSizeDisabled()
	return not G_RLF.db.global.styling.enabledSecondaryRowText or (G_RLF.db.global.styling.useFontObjects == true)
end

function Styling:GetSecondaryFontSize()
	return G_RLF.db.global.styling.secondaryFontSize
end

function Styling:SetSecondaryFontSize(_, value)
	G_RLF.db.global.styling.secondaryFontSize = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:GetFontFlags(_, key)
	return G_RLF.db.global.styling.fontFlags[key]
end

function Styling:SetFontFlags(_, key, value)
	G_RLF.db.global.styling.fontFlags[key] = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:GetShadowColor()
	local r, g, b, a = unpack(G_RLF.db.global.styling.fontShadowColor)
	return r, g, b, a
end

function Styling:SetShadowColor(_, r, g, b, a)
	G_RLF.db.global.styling.fontShadowColor = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:GetShadowOffsetX()
	return G_RLF.db.global.styling.fontShadowOffsetX
end

function Styling:SetShadowOffsetX(_, value)
	G_RLF.db.global.styling.fontShadowOffsetX = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:GetShadowOffsetY()
	return G_RLF.db.global.styling.fontShadowOffsetY
end

function Styling:SetShadowOffsetY(_, value)
	G_RLF.db.global.styling.fontShadowOffsetY = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function Styling:GetRowTextSpacing()
	return G_RLF.db.global.styling.rowTextSpacing
end

function Styling:SetRowTextSpacing(_, value)
	G_RLF.db.global.styling.rowTextSpacing = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

G_RLF.options.args.styles = G_RLF.ConfigCommon.StylingBase.CreateStylingGroup(Styling, G_RLF.level1OptionsOrder.styling)
G_RLF.options.args.styles.args.partyLootFrame = G_RLF.ConfigHandlers.PartyLootConfig:GetStylingOptions(10)
