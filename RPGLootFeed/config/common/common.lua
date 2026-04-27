---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_ConfigCommon
---@field StylingBase RLF_StylingBase
---@field DbUtils RLF_DbUtils
local ConfigCommon = {}

---@alias methodname string

---@class AceConfigBase
---@field type "execute" | "input" | "toggle" | "range" | "select" | "multiselect" | "color" | "keybinding" | "header" | "description" | "group"
---@field name string | fun(): string
---@field desc? string | fun(): string
---@field validate? methodname | function | false
---@field confirm? methodname | function | boolean
---@field order? number | methodname | fun(): string
---@field disabled? methodname | function | boolean
---@field hidden? methodname | function | boolean
---@field guiHidden? boolean
---@field dialogHidden? boolean
---@field dropdownHidden? boolean
---@field cmdHidden? boolean
---@field icon? string | fun(): string
---@field iconCoords? table | methodname | fun(): table
---@field handler? table
---@field width? "normal" | "double" | "full" | "half" | number
---@field dialogControl? string
---descStyle would technically be here but it's only supported on Toggle

---@param base AceConfigBase
local function createBase(base, type)
	local validTypes = {
		execute = true,
		input = true,
		toggle = true,
		range = true,
		select = true,
		multiselect = true,
		color = true,
		keybinding = true,
		header = true,
		description = true,
		group = true,
	}

	if not validTypes[type] then
		error("Invalid config type: " .. tostring(type), 2)
	end

	return {
		type = type,
		name = base.name,
		desc = base.desc,
		validate = base.validate,
		confirm = base.confirm,
		order = base.order,
		disabled = base.disabled,
		hidden = base.hidden,
		guiHidden = base.guiHidden,
		dialogHidden = base.dialogHidden,
		dropdownHidden = base.dropdownHidden,
		cmdHidden = base.cmdHidden,
		icon = base.icon,
		iconCoords = base.iconCoords,
		handler = base.handler,
		width = base.width,
		dialogControl = base.dialogControl,
	}
end

---@class AceConfigData : AceConfigBase
---@field get methodname | function
---@field set methodname | function

---@param data AceConfigData
---@param type string
local function createData(data, type)
	if data.get == nil or data.set == nil then
		error("Data config must provide both get and set methods", 2)
	end
	local out = createBase(data, type)
	out.get = data.get
	out.set = data.set

	return out
end

---@class AceConfigExecute : AceConfigBase
---@field func methodname | function
---@field image? string | fun(): string | fun(): string, number, number
---@field imageCoords? table | methodname | fun(): table
---@field imageWidth? number
---@field imageHeight? number

---@param exec table
---@return AceConfigExecute
function ConfigCommon.CreateExecute(exec)
	if exec.func == nil then
		error("Execute function must be provided", 2)
	end
	---@type AceConfigExecute
	local out = createBase(exec, "execute")
	out.func = exec.func
	out.image = exec.image
	out.imageCoords = exec.imageCoords
	out.imageWidth = exec.imageWidth
	out.imageHeight = exec.imageHeight

	return out
end

---@class AceConfigInput : AceConfigData
---@field multiline? boolean | integer
---@field pattern? string
---@field usage? string

---@param input table
---@return AceConfigInput
function ConfigCommon.CreateInput(input)
	---@type AceConfigInput
	local out = createData(input, "input")
	out.multiline = input.multiline
	out.pattern = input.pattern
	out.usage = input.usage

	return out
end

---@class AceConfigToggle : AceConfigData
---@field descStyle? "inline"
---@field tristate? boolean

---@param toggle table
---@return AceConfigToggle
function ConfigCommon.CreateToggle(toggle)
	---@type AceConfigToggle
	local out = createData(toggle, "toggle")
	out.descStyle = toggle.descStyle
	out.tristate = toggle.tristate

	return out
end

---@class AceConfigRange : AceConfigData
---@field min? number
---@field max? number
---@field softMin? number
---@field softMax? number
---@field step? number
---@field bigStep? number
---@field isPercent? boolean

---@param range table
---@return AceConfigRange
function ConfigCommon.CreateRange(range)
	---@type AceConfigRange
	local out = createData(range, "range")
	out.min = range.min
	out.max = range.max
	out.softMin = range.softMin
	out.softMax = range.softMax
	out.step = range.step
	out.bigStep = range.bigStep
	out.isPercent = range.isPercent

	return out
end

---@class AceConfigSelect : AceConfigData
---@field values table<any, string> | fun(): table<any, string>
---@field sorting? any[] | fun(): any[]
---@field style? "dropdown" | "radio"

---@param select table
---@return AceConfigSelect
function ConfigCommon.CreateSelect(select)
	if select.values == nil then
		error("Select values must be provided", 2)
	end
	---@type AceConfigSelect
	local out = createData(select, "select")
	out.values = select.values
	out.sorting = select.sorting
	out.style = select.style

	return out
end

---@class AceConfigMultiSelect : AceConfigToggle
---@field values table<any, string> | fun(): table<any, string>

---@param multiselect table
---@return AceConfigMultiSelect
function ConfigCommon.CreateMultiSelect(multiselect)
	if multiselect.values == nil then
		error("MultiSelect values must be provided", 2)
	end
	---@type AceConfigMultiSelect
	---@diagnostic disable-next-line: assign-type-mismatch
	local out = createData(multiselect, "multiselect")
	out.values = multiselect.values
	out.descStyle = multiselect.descStyle
	out.tristate = multiselect.tristate

	return out
end

---@class AceConfigColor : AceConfigData
---@field hasAlpha? boolean

---@param color table
---@return AceConfigColor
function ConfigCommon.CreateColor(color)
	---@type AceConfigColor
	local out = createData(color, "color")
	out.hasAlpha = color.hasAlpha

	return out
end

---@class AceConfigKeybinding : AceConfigData

---@param keybinding table
---@return AceConfigKeybinding
function ConfigCommon.CreateKeybinding(keybinding)
	---@type AceConfigKeybinding
	local out = createData(keybinding, "keybinding")

	return out
end

---@class AceConfigHeader : AceConfigBase

---@param header table
---@return AceConfigHeader
function ConfigCommon.CreateHeader(header)
	---@type AceConfigHeader
	local out = createBase(header, "header")

	return out
end

---@class AceConfigDescription : AceConfigBase
---@field fontSize? "small" | "medium" | "large"
---@field image? string | fun(): string | fun(): string, number, number
---@field imageCoords? table | methodname | fun(): table
---@field imageWidth? number
---@field imageHeight? number

---@param desc table
---@return AceConfigDescription
function ConfigCommon.CreateDescription(desc)
	---@type AceConfigDescription
	local out = createBase(desc, "description")
	out.fontSize = desc.fontSize
	out.image = desc.image
	out.imageCoords = desc.imageCoords
	out.imageWidth = desc.imageWidth
	out.imageHeight = desc.imageHeight

	return out
end

---@class AceConfigGroup : AceConfigBase
---@field args table<string, AceConfigBase>
---@field plugins? table<string, table>
---@field childGroups? "select" | "tab" | "tree"
---@field inline? boolean
---@field cmdInline? boolean
---@field guiInline? boolean
---@field dropdownInline? boolean
---@field dialogInline? boolean

---@param group table
---@return AceConfigGroup
function ConfigCommon.CreateGroup(group)
	---@type AceConfigGroup
	local out = createBase(group, "group")
	out.args = group.args or {}
	out.plugins = group.plugins
	out.childGroups = group.childGroups
	out.inline = group.inline
	out.cmdInline = group.cmdInline
	out.guiInline = group.guiInline
	out.dropdownInline = group.dropdownInline
	out.dialogInline = group.dialogInline

	return out
end

---@class RLF_FeatureBackgroundOverrideOptions
---@field frameId integer
---@field featureKey string
---@field order number
---@field isFeatureEnabled fun(): boolean

--- Build a reusable per-feature background override options group.
--- The override colors apply to rows produced by the feature when enabled.
---@param opts RLF_FeatureBackgroundOverrideOptions
---@return AceConfigGroup
function ConfigCommon.CreateFeatureBackgroundOverrideGroup(opts)
	if not opts or not opts.frameId or not opts.featureKey or not opts.isFeatureEnabled then
		error("CreateFeatureBackgroundOverrideGroup requires frameId, featureKey, and isFeatureEnabled", 2)
	end

	local function featureDisabled()
		return not opts.isFeatureEnabled()
	end

	local function backgroundOverrideDb()
		local featureConfig = G_RLF.DbAccessor:Feature(opts.frameId, opts.featureKey)
		if not featureConfig then
			return nil
		end
		return featureConfig.backgroundOverride
	end

	local function usingGradientBackground()
		return G_RLF.DbAccessor:Styling(opts.frameId).rowBackgroundType == G_RLF.RowBackground.GRADIENT
	end

	local function usingTexturedBackground()
		return G_RLF.DbAccessor:Styling(opts.frameId).rowBackgroundType == G_RLF.RowBackground.TEXTURED
	end

	local function refreshRows()
		G_RLF.LootDisplay:UpdateRowStyles(opts.frameId)
		G_RLF.LootDisplay:RefreshSampleRowsIfShown()
	end

	return ConfigCommon.CreateGroup({
		name = G_RLF.L["Background Override"],
		desc = G_RLF.L["BackgroundOverrideDesc"],
		inline = true,
		order = opts.order,
		disabled = featureDisabled,
		args = {
			enabled = ConfigCommon.CreateToggle({
				name = G_RLF.L["Enable Background Color Override"],
				desc = G_RLF.L["EnableBackgroundColorOverrideDesc"],
				width = "double",
				order = 1,
				get = function()
					local db = backgroundOverrideDb()
					return db and db.enabled or false
				end,
				set = function(_, value)
					local db = backgroundOverrideDb()
					if not db then
						return
					end
					db.enabled = value
					refreshRows()
				end,
			}),
			gradientStart = ConfigCommon.CreateColor({
				name = G_RLF.L["Background Gradient Start"],
				desc = G_RLF.L["GradientStartDesc"],
				hasAlpha = true,
				width = "double",
				order = 2,
				hidden = function()
					return not usingGradientBackground()
				end,
				disabled = function()
					local db = backgroundOverrideDb()
					return featureDisabled() or not db or not db.enabled
				end,
				get = function()
					local db = backgroundOverrideDb()
					local color = db and db.gradientStart
					if not color then
						color = G_RLF.DbAccessor:Styling(opts.frameId).rowBackgroundGradientStart
					end
					return unpack(color)
				end,
				set = function(_, r, g, b, a)
					local db = backgroundOverrideDb()
					if not db then
						return
					end
					db.gradientStart = { r, g, b, a }
					refreshRows()
				end,
			}),
			gradientEnd = ConfigCommon.CreateColor({
				name = G_RLF.L["Background Gradient End"],
				desc = G_RLF.L["GradientEndDesc"],
				hasAlpha = true,
				order = 3,
				hidden = function()
					return not usingGradientBackground()
				end,
				disabled = function()
					local db = backgroundOverrideDb()
					return featureDisabled() or not db or not db.enabled
				end,
				get = function()
					local db = backgroundOverrideDb()
					local color = db and db.gradientEnd
					if not color then
						color = G_RLF.DbAccessor:Styling(opts.frameId).rowBackgroundGradientEnd
					end
					return unpack(color)
				end,
				set = function(_, r, g, b, a)
					local db = backgroundOverrideDb()
					if not db then
						return
					end
					db.gradientEnd = { r, g, b, a }
					refreshRows()
				end,
			}),
			textureColor = ConfigCommon.CreateColor({
				name = G_RLF.L["Background Texture Color"],
				desc = G_RLF.L["BackgroundTextureColorDesc"],
				hasAlpha = true,
				width = "double",
				order = 4,
				hidden = function()
					return not usingTexturedBackground()
				end,
				disabled = function()
					local db = backgroundOverrideDb()
					return featureDisabled() or not db or not db.enabled
				end,
				get = function()
					local db = backgroundOverrideDb()
					local color = db and db.textureColor
					if not color then
						color = G_RLF.DbAccessor:Styling(opts.frameId).rowBackgroundTextureColor
					end
					return unpack(color)
				end,
				set = function(_, r, g, b, a)
					local db = backgroundOverrideDb()
					if not db then
						return
					end
					db.textureColor = { r, g, b, a }
					refreshRows()
				end,
			}),
		},
	})
end

G_RLF.ConfigCommon = ConfigCommon

return ConfigCommon
