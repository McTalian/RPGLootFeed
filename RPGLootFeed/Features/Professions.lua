---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's full
-- dependency surface on G_RLF / ns is visible in one place.  Tests pass a
-- minimal mock ns to loadfile("Professions.lua") to control these at
-- injection time without the full nsMocks framework.
-- NOTE: G_RLF.db is intentionally absent – AceDB populates it in
-- OnInitialize, so it must remain a runtime lookup inside function bodies.
local LootElementBase = G_RLF.LootElementBase
local DefaultIcons = G_RLF.DefaultIcons
local ItemQualEnum = G_RLF.ItemQualEnum
local FeatureBase = G_RLF.FeatureBase
local FeatureModule = G_RLF.FeatureModule
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
local CreatePatternSegments = function(pattern)
	return G_RLF:CreatePatternSegmentsForStringNumber(pattern)
end
local ExtractDynamicsFromPattern = function(message, segs)
	return G_RLF:ExtractDynamicsFromPattern(message, segs)
end

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- The shared adapter lives in WoWAPIAdapters.lua (G_RLF.WoWAPI.Professions).
-- Tests replace Professions._professionsAdapter with a mock after loadfile.

---@class RLF_Professions: RLF_Module, AceEvent-3.0
local Professions = FeatureBase:new(FeatureModule.Profession, "AceEvent-3.0")

Professions._professionsAdapter = G_RLF.WoWAPI.Professions

--- Builds a uniform payload for LootElementBase:fromPayload().
--- Replaces Professions.Element:new; event handlers call this then fromPayload → Show().
---@param key string Unique key for this profession (typically skillName)
---@param name string Profession name to display
---@param icon number|string Profession icon texture ID
---@param level number Current skill level
---@param quantity number Skill level delta (change amount this gain)
---@return RLF_ElementPayload
function Professions:BuildPayload(key, name, icon, level, quantity)
	local color = RGBAToHexFormat(unpack(G_RLF.db.global.prof.skillColor))

	---@type RLF_ElementPayload
	local payload = {
		-- Routing
		key = "PROF_" .. key,
		type = "Professions",

		-- Icon
		icon = (G_RLF.db.global.prof.enableIcon and not G_RLF.db.global.misc.hideAllIcons) and icon or nil,
		quality = ItemQualEnum.Rare,

		-- Primary line
		quantity = quantity,
		textFn = function()
			return color .. name .. " " .. level .. "|r"
		end,

		-- Secondary line
		secondaryTextFn = function()
			return ""
		end,

		-- Item count display (skill delta)
		itemCountFn = function()
			local profDb = G_RLF.db.global.prof
			if not profDb.showSkillChange then
				return nil
			end
			return quantity,
				{
					color = RGBAToHexFormat(unpack(profDb.skillColor)),
					wrapChar = profDb.skillTextWrapChar,
					showSign = true,
				}
		end,

		-- Lifecycle
		IsEnabled = function()
			return Professions:IsEnabled()
		end,
	}

	return payload
end

local segments
function Professions:OnInitialize()
	self.professions = {}
	self.profNameIconMap = {}
	self.profLocaleBaseNames = {}
	if G_RLF.db.global.prof.enabled then
		self:Enable()
	else
		self:Disable()
	end
	local pattern = Professions._professionsAdapter.GetSkillRankUpPattern()
	segments = CreatePatternSegments(pattern)
end

function Professions:OnDisable()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("CHAT_MSG_SKILL")
end

function Professions:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("CHAT_MSG_SKILL")
	LogDebug("OnEnable", addonName, self.moduleName)
end

function Professions:InitializeProfessions()
	local primaryId, secondaryId, archId, fishingId, cookingId = Professions._professionsAdapter.GetProfessions()
	local profs = { primaryId, secondaryId, archId, fishingId, cookingId }
	for i = 1, #profs do
		if profs[i] then
			local name, icon, skillLevel, maxSkillLevel, numAbilities, spellOffset, skillLine, skillModifier, specializationIndex, specializationOffset, a, b =
				Professions._professionsAdapter.GetProfessionInfo(profs[i])
			if name and icon then
				self.profNameIconMap[name] = icon
			end
		end
	end

	for k, v in pairs(self.profNameIconMap) do
		table.insert(self.profLocaleBaseNames, k)
	end
end

function Professions:PLAYER_ENTERING_WORLD()
	Professions:InitializeProfessions()
end

function Professions:CHAT_MSG_SKILL(event, message)
	if Professions._professionsAdapter.IssecretValue(message) then
		LogWarn("(" .. event .. ") Secret value detected, ignoring chat message", "WOWEVENT", self.moduleName, "")
		return
	end

	LogInfo(event, "WOWEVENT", self.moduleName, nil, message)

	local skillName, skillLevel = ExtractDynamicsFromPattern(message, segments)
	if skillName and skillLevel then
		if not self.professions[skillName] then
			self.professions[skillName] = {
				name = skillName,
				lastSkillLevel = skillLevel,
			}
		end
		local icon
		if self.profNameIconMap[skillName] then
			icon = self.profNameIconMap[skillName]
		else
			for i = 1, #self.profLocaleBaseNames do
				if skillName:find(self.profLocaleBaseNames[i]) then
					icon = self.profNameIconMap[self.profLocaleBaseNames[i]]
					self.profNameIconMap[skillName] = icon
					break
				end
			end
		end
		if not icon then
			icon = DefaultIcons.PROFESSION
		end
		local payload = self:BuildPayload(
			skillName,
			skillName,
			icon,
			skillLevel,
			skillLevel - self.professions[skillName].lastSkillLevel
		)
		LootElementBase:fromPayload(payload):Show()
		self.professions[skillName].lastSkillLevel = skillLevel
	end
end

return Professions
