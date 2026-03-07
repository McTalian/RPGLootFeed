---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's full
-- dependency surface on G_RLF / ns is visible in one place.  Tests pass a
-- minimal mock ns to loadfile("Experience.lua") to control these at
-- injection time without the full nsMocks framework.
-- NOTE: G_RLF.db is intentionally absent – AceDB populates it in
-- OnInitialize, so it must remain a runtime lookup inside function bodies.
local LootElementBase = G_RLF.LootElementBase
local DefaultIcons = G_RLF.DefaultIcons
local ItemQualEnum = G_RLF.ItemQualEnum
local FeatureBase = G_RLF.FeatureBase
local FeatureModule = G_RLF.FeatureModule
local TextTemplateEngine = G_RLF.TextTemplateEngine
local LogDebug = function(...)
	G_RLF:LogDebug(...)
end
local LogInfo = function(...)
	G_RLF:LogInfo(...)
end
local LogWarn = function(...)
	G_RLF:LogWarn(...)
end
local RGBAToHexFormat = function(...)
	return G_RLF:RGBAToHexFormat(...)
end

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- Shared adapter from G_RLF.WoWAPI; tests override Xp._xpAdapter after load.
local UnitXpAdapter = G_RLF.WoWAPI.Experience

---@class RLF_Experience: RLF_Module, AceEvent-3.0
local Xp = FeatureBase:new(FeatureModule.Experience, "AceEvent-3.0")
local currentXP, currentMaxXP, currentLevel

Xp._xpAdapter = UnitXpAdapter

-- Context provider function to be registered when module is enabled
local function createExperienceContextProvider()
	return function(context, data)
		-- Basic XP display
		context.xpLabel = G_RLF.L["XP"]

		-- Current XP percentage for secondary text
		if currentXP and currentMaxXP and currentMaxXP > 0 then
			local percentage = currentXP / currentMaxXP * 100
			context.currentXPPercentage = string.format("%.2f", percentage) .. "%%" -- need to escape % since it's being used in a gsub later
		else
			-- When XP data is not available, provide empty percentage
			context.currentXPPercentage = ""
		end
	end
end

--- Build a uniform payload from an XP delta.
--- This is the service layer: it transforms the XP gain into the generic
--- RLF_ElementPayload contract that LootElementBase:fromPayload() consumes.
---@param quantity number The XP delta gained
---@return RLF_ElementPayload|nil payload nil if quantity is missing or zero
function Xp:BuildPayload(quantity)
	if not quantity or quantity == 0 then
		return nil
	end

	-- Generate text elements using the data-driven approach
	local textElements = self:GenerateTextElements(quantity)

	local xpConfig = G_RLF.DbAccessor:AnyFeatureConfig("experience") or {}

	---@type RLF_LootElementData
	local elementData = {
		key = "EXPERIENCE",
		type = "Experience",
		textElements = textElements,
		quantity = quantity,
		icon = (xpConfig.enableIcon and not G_RLF.db.global.misc.hideAllIcons) and DefaultIcons.XP or nil,
		quality = ItemQualEnum.Epic,
	}

	---@type RLF_ElementPayload
	local payload = {
		-- Routing
		key = "EXPERIENCE",
		type = "Experience",

		-- Icon
		icon = elementData.icon,
		quality = ItemQualEnum.Epic,

		-- Primary line
		quantity = quantity,
		textFn = function(existingXP)
			return TextTemplateEngine:ProcessRowElements(1, elementData, existingXP)
		end,

		-- Secondary line
		secondaryTextFn = function(existingXP)
			return TextTemplateEngine:ProcessRowElements(2, elementData, existingXP)
		end,

		-- Item count display (current level)
		itemCountFn = function()
			local xpCfg = G_RLF.DbAccessor:AnyFeatureConfig("experience") or {}
			if not xpCfg.showCurrentLevel then
				return nil
			end
			return currentLevel,
				{
					color = RGBAToHexFormat(unpack(xpCfg.currentLevelColor or { 0.749, 0.737, 0.012, 1 })),
					wrapChar = xpCfg.currentLevelTextWrapChar,
				}
		end,

		-- Lifecycle
		IsEnabled = function()
			return Xp:IsEnabled()
		end,
	}

	return payload
end

--- Generate text elements for Experience type using the new data-driven approach
---@param quantity number The experience amount
---@return table<number, table<string, RLF_TextElement>> textElements Row-indexed elements: [row][elementKey] = element
function Xp:GenerateTextElements(quantity)
	local elements = {}

	local xpTextColor = (G_RLF.DbAccessor:AnyFeatureConfig("experience") or {}).experienceTextColor or { 1, 0, 1, 0.8 }

	-- Row 1: Primary experience display
	elements[1] = {}
	elements[1].primary = {
		type = "primary",
		template = "{sign}{total} {xpLabel}",
		order = 1,
		color = xpTextColor,
	}

	-- Row 2: Context text element (XP percentage)
	elements[2] = {}
	elements[2].contextSpacer = {
		type = "spacer",
		spacerCount = 4, -- "    " spacing
		order = 1,
	}

	elements[2].context = {
		type = "context",
		template = "{currentXPPercentage}",
		order = 2,
		color = xpTextColor,
	}

	return elements
end

local function initXpValues()
	currentXP = Xp._xpAdapter.UnitXP("player")
	currentMaxXP = Xp._xpAdapter.UnitXPMax("player")
	currentLevel = Xp._xpAdapter.UnitLevel("player")
end

function Xp:OnInitialize()
	if G_RLF.DbAccessor:IsFeatureNeededByAnyFrame("experience") then
		self:Enable()
	else
		self:Disable()
	end
end

function Xp:OnDisable()
	-- Unregister our context provider
	TextTemplateEngine.contextProviders["Experience"] = nil

	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("PLAYER_XP_UPDATE")
end

function Xp:OnEnable()
	LogDebug("OnEnable", addonName, self.moduleName)

	-- Register our context provider with the TextTemplateEngine
	TextTemplateEngine:RegisterContextProvider("Experience", createExperienceContextProvider())

	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_XP_UPDATE")
	if currentXP == nil then
		initXpValues()
	end
end

function Xp:PLAYER_ENTERING_WORLD(eventName)
	LogInfo(eventName, "WOWEVENT", self.moduleName)
	initXpValues()
end

function Xp:PLAYER_XP_UPDATE(eventName, unitTarget)
	LogInfo(eventName, "WOWEVENT", self.moduleName, unitTarget)
	if unitTarget ~= "player" then
		return
	end

	local oldLevel = currentLevel
	local oldCurrentXP = currentXP
	local oldMaxXP = currentMaxXP
	local newLevel = Xp._xpAdapter.UnitLevel(unitTarget)
	if newLevel == nil then
		LogWarn("Could not get player level", addonName, self.moduleName)
		return
	end
	currentLevel = newLevel
	currentXP = Xp._xpAdapter.UnitXP(unitTarget)
	currentMaxXP = Xp._xpAdapter.UnitXPMax(unitTarget)
	local delta = 0
	if newLevel > oldLevel then
		delta = (oldMaxXP - oldCurrentXP) + currentXP
	else
		delta = currentXP - oldCurrentXP
	end

	if delta > 0 then
		local payload = self:BuildPayload(delta)
		if payload then
			local e = LootElementBase:fromPayload(payload)
			e:Show()
		end
	else
		LogWarn(eventName .. " fired but delta was not positive", addonName, self.moduleName)
	end
end

return Xp
