---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class PartyLootConfig : RLF_StylingConfigHandlerBase
local PartyLootConfig = {}

function PartyLootConfig:GetTextAlignment()
	return G_RLF.db.global.partyLoot.styling.textAlignment
end

function PartyLootConfig:SetTextAlignment(_, value)
	G_RLF.db.global.partyLoot.styling.textAlignment = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:GetGrowUp()
	return G_RLF.db.global.partyLoot.styling.growUp
end

function PartyLootConfig:SetGrowUp(_, value)
	G_RLF.db.global.partyLoot.styling.growUp = value
	G_RLF.LootDisplay:UpdateRowPositions()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:GetBackgroundType()
	return G_RLF.db.global.partyLoot.styling.rowBackgroundType
end

function PartyLootConfig:SetBackgroundType(_, value)
	G_RLF.db.global.partyLoot.styling.rowBackgroundType = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:IsGradientHidden()
	return G_RLF.db.global.partyLoot.styling.rowBackgroundType ~= G_RLF.RowBackground.GRADIENT
end

function PartyLootConfig:GetGradientStartColor()
	local r, g, b, a = unpack(G_RLF.db.global.partyLoot.styling.rowBackgroundGradientStart)
	return r, g, b, a
end

function PartyLootConfig:SetGradientStartColor(_, r, g, b, a)
	G_RLF.db.global.partyLoot.styling.rowBackgroundGradientStart = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetGradientEndColor()
	local r, g, b, a = unpack(G_RLF.db.global.partyLoot.styling.rowBackgroundGradientEnd)
	return r, g, b, a
end

function PartyLootConfig:SetGradientEndColor(_, r, g, b, a)
	G_RLF.db.global.partyLoot.styling.rowBackgroundGradientEnd = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:IsBackgroundTextureHidden()
	return G_RLF.db.global.partyLoot.styling.rowBackgroundType ~= G_RLF.RowBackground.TEXTURED
end

function PartyLootConfig:GetBackgroundTexture()
	return G_RLF.db.global.partyLoot.styling.rowBackgroundTexture
end

function PartyLootConfig:SetBackgroundTexture(_, value)
	G_RLF.db.global.partyLoot.styling.rowBackgroundTexture = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetBackgroundTextureColor()
	local r, g, b, a = unpack(G_RLF.db.global.partyLoot.styling.rowBackgroundTextureColor)
	return r, g, b, a
end

function PartyLootConfig:SetBackgroundTextureColor(_, r, g, b, a)
	G_RLF.db.global.partyLoot.styling.rowBackgroundTextureColor = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetTopInset()
	return G_RLF.db.global.partyLoot.styling.backdropInsets.top
end

function PartyLootConfig:SetTopInset(_, value)
	G_RLF.db.global.partyLoot.styling.backdropInsets.top = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetRightInset()
	return G_RLF.db.global.partyLoot.styling.backdropInsets.right
end

function PartyLootConfig:SetRightInset(_, value)
	G_RLF.db.global.partyLoot.styling.backdropInsets.right = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetBottomInset()
	return G_RLF.db.global.partyLoot.styling.backdropInsets.bottom
end

function PartyLootConfig:SetBottomInset(_, value)
	G_RLF.db.global.partyLoot.styling.backdropInsets.bottom = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetLeftInset()
	return G_RLF.db.global.partyLoot.styling.backdropInsets.left
end

function PartyLootConfig:SetLeftInset(_, value)
	G_RLF.db.global.partyLoot.styling.backdropInsets.left = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetRowBordersEnabled()
	return G_RLF.db.global.partyLoot.styling.enableRowBorder
end

function PartyLootConfig:SetRowBordersEnabled(_, value)
	G_RLF.db.global.partyLoot.styling.enableRowBorder = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:IsRowBorderDisabled()
	return not G_RLF.db.global.partyLoot.styling.enableRowBorder
end

function PartyLootConfig:GetRowBorderTexture()
	return G_RLF.db.global.partyLoot.styling.rowBorderTexture
end

function PartyLootConfig:SetRowBorderTexture(_, value)
	G_RLF.db.global.partyLoot.styling.rowBorderTexture = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetRowBorderThickness()
	return G_RLF.db.global.partyLoot.styling.rowBorderSize
end

function PartyLootConfig:SetRowBorderThickness(_, value)
	G_RLF.db.global.partyLoot.styling.rowBorderSize = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetRowBorderColor()
	local r, g, b, a = unpack(G_RLF.db.global.partyLoot.styling.rowBorderColor)
	return r, g, b, a
end

function PartyLootConfig:SetRowBorderColor(_, r, g, b, a)
	G_RLF.db.global.partyLoot.styling.rowBorderColor = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetRowBorderClassColors()
	return G_RLF.db.global.partyLoot.styling.rowBorderClassColors
end

function PartyLootConfig:SetRowBorderClassColors(_, value)
	G_RLF.db.global.partyLoot.styling.rowBorderClassColors = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetEnabledSecondaryRowText()
	return G_RLF.db.global.partyLoot.styling.enabledSecondaryRowText
end

function PartyLootConfig:SetEnabledSecondaryRowText(_, value)
	G_RLF.db.global.partyLoot.styling.enabledSecondaryRowText = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetEnableTopLeftIconText()
	return G_RLF.db.global.partyLoot.styling.enableTopLeftIconText
end

function PartyLootConfig:SetEnableTopLeftIconText(_, value)
	G_RLF.db.global.partyLoot.styling.enableTopLeftIconText = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:IsTopLeftIconTextDisabled()
	return not G_RLF.db.global.partyLoot.styling.enableTopLeftIconText
end

function PartyLootConfig:GetTopLeftIconFontSize()
	return G_RLF.db.global.partyLoot.styling.topLeftIconFontSize
end

function PartyLootConfig:SetTopLeftIconFontSize(_, value)
	G_RLF.db.global.partyLoot.styling.topLeftIconFontSize = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetTopLeftIconTextUseQualityColor()
	return G_RLF.db.global.partyLoot.styling.topLeftIconTextUseQualityColor
end

function PartyLootConfig:SetTopLeftIconTextUseQualityColor(_, value)
	G_RLF.db.global.partyLoot.styling.topLeftIconTextUseQualityColor = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetTopLeftIconTextColor()
	local r, g, b, a = unpack(G_RLF.db.global.partyLoot.styling.topLeftIconTextColor)
	return r, g, b, a
end

function PartyLootConfig:SetTopLeftIconTextColor(_, r, g, b, a)
	G_RLF.db.global.partyLoot.styling.topLeftIconTextColor = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetUseFontObjects()
	return G_RLF.db.global.partyLoot.styling.useFontObjects
end

function PartyLootConfig:SetUseFontObjects(_, value)
	G_RLF.db.global.partyLoot.styling.useFontObjects = value
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:IsFontObjectsDisabled()
	return not G_RLF.db.global.partyLoot.styling.useFontObjects
end

function PartyLootConfig:GetFontObject()
	return G_RLF.db.global.partyLoot.styling.font
end

function PartyLootConfig:SetFontObject(_, value)
	G_RLF.db.global.partyLoot.styling.font = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:IsCustomFontsDisabled()
	return G_RLF.db.global.partyLoot.styling.useFontObjects == true
end

function PartyLootConfig:GetFontFace()
	return G_RLF.db.global.partyLoot.styling.fontFace
end

function PartyLootConfig:SetFontFace(_, value)
	G_RLF.db.global.partyLoot.styling.fontFace = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:GetFontSize()
	return G_RLF.db.global.partyLoot.styling.fontSize
end

function PartyLootConfig:SetFontSize(_, value)
	G_RLF.db.global.partyLoot.styling.fontSize = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:IsSecondaryFontSizeDisabled()
	return not G_RLF.db.global.partyLoot.styling.enabledSecondaryRowText
		or (G_RLF.db.global.partyLoot.styling.useFontObjects == true)
end

function PartyLootConfig:GetSecondaryFontSize()
	return G_RLF.db.global.partyLoot.styling.secondaryFontSize
end

function PartyLootConfig:SetSecondaryFontSize(_, value)
	G_RLF.db.global.partyLoot.styling.secondaryFontSize = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:GetRowTextSpacing()
	return G_RLF.db.global.partyLoot.styling.rowTextSpacing
end

function PartyLootConfig:SetRowTextSpacing(_, value)
	G_RLF.db.global.partyLoot.styling.rowTextSpacing = value
	G_RLF.LootDisplay:UpdateRowStyles()
end

function PartyLootConfig:GetFontFlags(_, key)
	return G_RLF.db.global.partyLoot.styling.fontFlags[key]
end

function PartyLootConfig:SetFontFlags(_, key, value)
	G_RLF.db.global.partyLoot.styling.fontFlags[key] = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:GetShadowColor()
	local r, g, b, a = unpack(G_RLF.db.global.partyLoot.styling.fontShadowColor)
	return r, g, b, a
end

function PartyLootConfig:SetShadowColor(_, r, g, b, a)
	G_RLF.db.global.partyLoot.styling.fontShadowColor = { r, g, b, a }
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:GetShadowOffsetX()
	return G_RLF.db.global.partyLoot.styling.fontShadowOffsetX
end

function PartyLootConfig:SetShadowOffsetX(_, value)
	G_RLF.db.global.partyLoot.styling.fontShadowOffsetX = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:GetShadowOffsetY()
	return G_RLF.db.global.partyLoot.styling.fontShadowOffsetY
end

function PartyLootConfig:SetShadowOffsetY(_, value)
	G_RLF.db.global.partyLoot.styling.fontShadowOffsetY = value
	G_RLF.LootDisplay:UpdateRowStyles()
	G_RLF.LootDisplay:ReInitQueueLabel()
end

function PartyLootConfig:IsStylingDisabled()
	return not G_RLF.db.global.partyLoot.separateFrame
end

function PartyLootConfig:CopyStylingFromMainFrame()
	local stylingDb = G_RLF.DbAccessor:Styling(G_RLF.Frames.MAIN)
	for k, v in pairs(stylingDb) do
		G_RLF.db.global.partyLoot.styling[k] = v
	end
	G_RLF.LootDisplay:UpdateRowStyles(G_RLF.Frames.PARTY)
	G_RLF.LootDisplay:ReInitQueueLabel(G_RLF.Frames.PARTY)
end

function PartyLootConfig:GetPositioningOptions(order)
	order = order or 9.1
	return {
		type = "group",
		inline = true,
		name = G_RLF.L["Party Loot Frame Positioning"],
		desc = G_RLF.L["PartyLootFrameDesc"],
		hidden = function()
			return not G_RLF.db.global.partyLoot.separateFrame
		end,
		order = order,
		args = {
			relativePoint = {
				type = "select",
				name = G_RLF.L["Anchor Relative To"],
				desc = G_RLF.L["RelativeToDesc"],
				values = {
					["UIParent"] = G_RLF.L["UIParent"],
					["PlayerFrame"] = G_RLF.L["PlayerFrame"],
					["Minimap"] = G_RLF.L["Minimap"],
					["MainMenuBarBackpackButton"] = G_RLF.L["BagBar"],
				},
				get = function()
					return G_RLF.db.global.partyLoot.positioning.relativePoint
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.positioning.relativePoint = value
					G_RLF.LootDisplay:UpdatePosition(G_RLF.Frames.PARTY)
				end,
				order = 1,
			},
			anchorPoint = {
				type = "select",
				name = G_RLF.L["Anchor Point"],
				desc = G_RLF.L["AnchorPointDesc"],
				values = {
					["TOPLEFT"] = G_RLF.L["Top Left"],
					["TOPRIGHT"] = G_RLF.L["Top Right"],
					["BOTTOMLEFT"] = G_RLF.L["Bottom Left"],
					["BOTTOMRIGHT"] = G_RLF.L["Bottom Right"],
					["TOP"] = G_RLF.L["Top"],
					["BOTTOM"] = G_RLF.L["Bottom"],
					["LEFT"] = G_RLF.L["Left"],
					["RIGHT"] = G_RLF.L["Right"],
					["CENTER"] = G_RLF.L["Center"],
				},
				get = function()
					return G_RLF.db.global.partyLoot.positioning.anchorPoint
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.positioning.anchorPoint = value
					G_RLF.LootDisplay:UpdatePosition(G_RLF.Frames.PARTY)
				end,
				order = 2,
			},
			xOffset = {
				type = "range",
				name = G_RLF.L["X Offset"],
				desc = G_RLF.L["XOffsetDesc"],
				min = -1000,
				max = 1000,
				step = 1,
				get = function()
					return G_RLF.db.global.partyLoot.positioning.xOffset
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.positioning.xOffset = value
					G_RLF.LootDisplay:UpdatePosition(G_RLF.Frames.PARTY)
				end,
				order = 3,
			},
			yOffset = {
				type = "range",
				name = G_RLF.L["Y Offset"],
				desc = G_RLF.L["YOffsetDesc"],
				min = -1000,
				max = 1000,
				step = 1,
				get = function()
					return G_RLF.db.global.partyLoot.positioning.yOffset
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.positioning.yOffset = value
					G_RLF.LootDisplay:UpdatePosition(G_RLF.Frames.PARTY)
				end,
				order = 4,
			},
			frameStrata = {
				type = "select",
				name = G_RLF.L["Frame Strata"],
				desc = G_RLF.L["FrameStrataDesc"],
				values = {
					["BACKGROUND"] = G_RLF.L["Background"],
					["LOW"] = G_RLF.L["Low"],
					["MEDIUM"] = G_RLF.L["Medium"],
					["HIGH"] = G_RLF.L["High"],
					["DIALOG"] = G_RLF.L["Dialog"],
					["TOOLTIP"] = G_RLF.L["Tooltip"],
				},
				sorting = {
					"BACKGROUND",
					"LOW",
					"MEDIUM",
					"HIGH",
					"DIALOG",
					"TOOLTIP",
				},
				get = function()
					return G_RLF.db.global.partyLoot.positioning.frameStrata
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.positioning.frameStrata = value
					G_RLF.LootDisplay:UpdateStrata(G_RLF.Frames.PARTY)
				end,
				order = 5,
			},
		},
	}
end

function PartyLootConfig:GetSizingOptions(order)
	order = order or 9.2
	return {
		type = "group",
		inline = true,
		hidden = function()
			return not G_RLF.db.global.partyLoot.separateFrame
		end,
		name = G_RLF.L["Party Loot Frame Sizing"],
		desc = G_RLF.L["PartyLootFrameSizeDesc"],
		order = order,
		args = {
			copySizingFromMainFrame = {
				type = "execute",
				name = G_RLF.L["Copy Sizing from Main Frame"],
				desc = G_RLF.L["CopySizingFromMainFrameDesc"],
				func = function()
					local sizingDb = G_RLF.db.global.sizing
					for k, v in pairs(sizingDb) do
						G_RLF.db.global.partyLoot.sizing[k] = v
					end
					G_RLF.LootDisplay:UpdateSize(G_RLF.Frames.PARTY)
				end,
				order = 0.5,
				width = "full",
			},
			feedWidth = {
				type = "range",
				name = G_RLF.L["Feed Width"],
				desc = G_RLF.L["FeedWidthDesc"],
				min = 100,
				max = 1000,
				step = 1,
				get = function()
					return G_RLF.db.global.partyLoot.sizing.feedWidth
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.sizing.feedWidth = value
					G_RLF.LootDisplay:UpdateSize(G_RLF.Frames.PARTY)
				end,
				order = 1,
			},
			maxRows = {
				type = "range",
				name = G_RLF.L["Maximum Rows to Display"],
				desc = G_RLF.L["MaxRowsDesc"],
				min = 1,
				max = 100,
				step = 1,
				get = function()
					return G_RLF.db.global.partyLoot.sizing.maxRows
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.sizing.maxRows = value
					G_RLF.LootDisplay:UpdateSize(G_RLF.Frames.PARTY)
				end,
				order = 2,
			},
			rowHeight = {
				type = "range",
				name = G_RLF.L["Loot Item Height"],
				desc = G_RLF.L["RowHeightDesc"],
				min = 5,
				max = 100,
				step = 1,
				get = function()
					return G_RLF.db.global.partyLoot.sizing.rowHeight
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.sizing.rowHeight = value
					G_RLF.LootDisplay:UpdateSize(G_RLF.Frames.PARTY)
				end,
				order = 3,
			},
			iconSize = {
				type = "range",
				name = G_RLF.L["Loot Item Icon Size"],
				desc = G_RLF.L["IconSizeDesc"],
				min = 5,
				max = 100,
				step = 1,
				get = function()
					return G_RLF.db.global.partyLoot.sizing.iconSize
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.sizing.iconSize = value
					G_RLF.LootDisplay:UpdateRowStyles(G_RLF.Frames.PARTY)
				end,
				order = 4,
			},
			padding = {
				type = "range",
				name = G_RLF.L["Loot Item Padding"],
				desc = G_RLF.L["RowPaddingDesc"],
				min = 0,
				max = 10,
				step = 1,
				get = function()
					return G_RLF.db.global.partyLoot.sizing.padding
				end,
				set = function(_, value)
					G_RLF.db.global.partyLoot.sizing.padding = value
					G_RLF.LootDisplay:UpdateSize(G_RLF.Frames.PARTY)
				end,
				order = 5,
			},
		},
	}
end

function PartyLootConfig:GetStylingOptions(order)
	order = order or 9.3
	local stylingGroup = G_RLF.ConfigCommon.StylingBase.CreateStylingGroup(G_RLF.ConfigHandlers.PartyLootConfig, order)
	stylingGroup.name = G_RLF.L["Party Loot Frame Styling"]
	stylingGroup.desc = G_RLF.L["PartyLootFrameStyleDesc"]
	stylingGroup.inline = true
	stylingGroup.hidden = "IsStylingDisabled"
	stylingGroup.args.copyStylingFromMainFrame = G_RLF.ConfigCommon.CreateExecute({
		name = G_RLF.L["Copy Styling from Main Frame"],
		desc = G_RLF.L["CopyStylingFromMainFrameDesc"],
		func = "CopyStylingFromMainFrame",
		order = 0.5,
		width = "full",
	})
	-- Top-left Icon Text is not supported for Party Loot right now
	stylingGroup.args.topLeftIconTextOptions = nil
	return stylingGroup
end

G_RLF.ConfigHandlers.PartyLootConfig = PartyLootConfig

---@class RLF_DBGlobal
---@field partyLoot RLF_ConfigPartyLoot
G_RLF.defaults.global = G_RLF.defaults.global or {}

---@class RLF_ConfigPartyLoot
G_RLF.defaults.global.partyLoot = {
	enabled = false,
	separateFrame = false,
	itemQualityFilter = {
		[G_RLF.ItemQualEnum.Poor] = true,
		[G_RLF.ItemQualEnum.Common] = true,
		[G_RLF.ItemQualEnum.Uncommon] = true,
		[G_RLF.ItemQualEnum.Rare] = true,
		[G_RLF.ItemQualEnum.Epic] = true,
		[G_RLF.ItemQualEnum.Legendary] = true,
		[G_RLF.ItemQualEnum.Artifact] = true,
		[G_RLF.ItemQualEnum.Heirloom] = true,
	},
	hideServerNames = false,
	onlyEpicAndAboveInRaid = true,
	onlyEpicAndAboveInInstance = true,
	---@type RLF_ConfigPositioning
	positioning = {
		---@type string | ScriptRegion
		relativePoint = "UIParent",
		anchorPoint = "LEFT",
		xOffset = 0,
		yOffset = 375,
		frameStrata = "MEDIUM",
	},
	---@type RLF_ConfigSizing
	sizing = {
		feedWidth = 330,
		maxRows = 10,
		rowHeight = 22,
		padding = 2,
		iconSize = 18,
	},
	---@type RLF_ConfigStyling
	styling = {},
	---@type number[]
	ignoreItemIds = {},
	enableIcon = true,
	enablePartyAvatar = true,
}
G_RLF.ConfigCommon.StylingBase.CloneDefaultDb("global.partyLoot.styling")

G_RLF.options.args.features.args.partyLootConfig = {
	type = "group",
	handler = PartyLootConfig,
	name = G_RLF.L["Party Loot Config"],
	order = G_RLF.mainFeatureOrder.PartyLoot,
	args = {
		enablePartyLoot = {
			type = "toggle",
			name = G_RLF.L["Enable Party Loot in Feed"],
			desc = G_RLF.L["EnablePartyLootDesc"],
			width = "double",
			get = function()
				return G_RLF.db.global.partyLoot.enabled
			end,
			set = function(_, value)
				G_RLF.db.global.partyLoot.enabled = value
			end,
			order = 1,
		},
		partyLootOptions = {
			type = "group",
			inline = true,
			name = G_RLF.L["Party Loot Options"],
			disabled = function()
				return not G_RLF.db.global.partyLoot.enabled
			end,
			order = 2,
			args = {
				showIcon = {
					type = "toggle",
					name = G_RLF.L["Show Item Icon"],
					desc = G_RLF.L["ShowItemIconDesc"],
					width = "double",
					disabled = function()
						return G_RLF.db.global.misc.hideAllIcons
					end,
					get = function()
						return G_RLF.db.global.partyLoot.enableIcon
					end,
					set = function(_, value)
						G_RLF.db.global.partyLoot.enableIcon = value
					end,
					order = 0.5,
				},
				showPartyAvatar = {
					type = "toggle",
					name = G_RLF.L["Show Party Avatar"],
					desc = G_RLF.L["ShowPartyAvatarDesc"],
					width = "double",
					get = function()
						return G_RLF.db.global.partyLoot.enablePartyAvatar
					end,
					set = function(_, value)
						G_RLF.db.global.partyLoot.enablePartyAvatar = value
					end,
					order = 1,
				},
				hideServerNames = {
					type = "toggle",
					name = G_RLF.L["Hide Server Names"],
					desc = G_RLF.L["HideServerNamesDesc"],
					width = "double",
					get = function()
						return G_RLF.db.global.partyLoot.hideServerNames
					end,
					set = function(_, value)
						G_RLF.db.global.partyLoot.hideServerNames = value
					end,
					order = 1.5,
				},
				itemQualityFilter = {
					type = "multiselect",
					name = G_RLF.L["Party Item Quality Filter"],
					desc = G_RLF.L["PartyItemQualityFilterDesc"],
					values = {
						[G_RLF.ItemQualEnum.Poor] = G_RLF.L["Poor"],
						[G_RLF.ItemQualEnum.Common] = G_RLF.L["Common"],
						[G_RLF.ItemQualEnum.Uncommon] = G_RLF.L["Uncommon"],
						[G_RLF.ItemQualEnum.Rare] = G_RLF.L["Rare"],
						[G_RLF.ItemQualEnum.Epic] = G_RLF.L["Epic"],
						[G_RLF.ItemQualEnum.Legendary] = G_RLF.L["Legendary"],
						[G_RLF.ItemQualEnum.Artifact] = G_RLF.L["Artifact"],
						[G_RLF.ItemQualEnum.Heirloom] = G_RLF.L["Heirloom"],
					},
					get = function(_, key)
						return G_RLF.db.global.partyLoot.itemQualityFilter[key]
					end,
					set = function(_, key, value)
						G_RLF.db.global.partyLoot.itemQualityFilter[key] = value
					end,
					order = 2,
				},
				onlyEpicAndAboveInRaid = {
					type = "toggle",
					name = G_RLF.L["Only Epic and Above in Raid"],
					desc = G_RLF.L["OnlyEpicAndAboveInRaidDesc"],
					width = "double",
					get = function()
						return G_RLF.db.global.partyLoot.onlyEpicAndAboveInRaid
					end,
					set = function(_, value)
						G_RLF.db.global.partyLoot.onlyEpicAndAboveInRaid = value
						local partyLoot = G_RLF.RLF:GetModule(G_RLF.FeatureModule.PartyLoot) --[[@as RLF_PartyLoot]]
						partyLoot:SetPartyLootFilters()
					end,
					order = 3,
				},
				onlyEpicAndAboveInInstance = {
					type = "toggle",
					name = G_RLF.L["Only Epic and Above in Instance"],
					desc = G_RLF.L["OnlyEpicAndAboveInInstanceDesc"],
					width = "double",
					get = function()
						return G_RLF.db.global.partyLoot.onlyEpicAndAboveInInstance
					end,
					set = function(_, value)
						G_RLF.db.global.partyLoot.onlyEpicAndAboveInInstance = value
						local partyLoot = G_RLF.RLF:GetModule(G_RLF.FeatureModule.PartyLoot) --[[@as RLF_PartyLoot]]
						partyLoot:SetPartyLootFilters()
					end,
					order = 4,
				},
				ignoreItemIds = {
					type = "input",
					name = G_RLF.L["Ignore Item IDs"],
					desc = G_RLF.L["IgnoreItemIDsDesc"],
					multiline = true,
					width = "double",
					get = function()
						return table.concat(G_RLF.db.global.partyLoot.ignoreItemIds, ", ")
					end,
					set = function(_, value)
						local ids = {}
						for id in value:gmatch("%d+") do
							table.insert(ids, tonumber(id))
						end
						G_RLF.db.global.partyLoot.ignoreItemIds = ids
					end,
					order = 5,
				},
				separateFrame = {
					type = "toggle",
					name = G_RLF.L["Separate Frame"],
					desc = G_RLF.L["SeparateFrameDesc"],
					width = "double",
					get = function()
						return G_RLF.db.global.partyLoot.separateFrame
					end,
					set = function(_, value)
						G_RLF.db.global.partyLoot.separateFrame = value
						if value then
							G_RLF.LootDisplay:CreatePartyFrame()
						else
							G_RLF.LootDisplay:DestroyPartyFrame()
						end
					end,
					order = 9,
				},
				positioning = PartyLootConfig:GetPositioningOptions(),
				sizing = PartyLootConfig:GetSizingOptions(),
				styling = PartyLootConfig:GetStylingOptions(),
			},
		},
	},
}
