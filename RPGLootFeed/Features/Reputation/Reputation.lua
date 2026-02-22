---@diagnostic disable: inject-field
---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's
-- full dependency surface on G_RLF / ns is visible in one place.  Tests
-- pass a minimal mock ns to loadfile("Reputation.lua") to control these at
-- injection time without the full nsMocks framework.
-- NOTE: G_RLF.db is intentionally absent – AceDB populates it in
-- OnInitialize, so it must remain a runtime lookup inside function bodies.
local LootElementBase = G_RLF.LootElementBase
local ItemQualEnum = G_RLF.ItemQualEnum
local FeatureBase = G_RLF.FeatureBase
local FeatureModule = G_RLF.FeatureModule
local RepUtils = G_RLF.RepUtils
local RepType = RepUtils.RepType
local LegRep = G_RLF.LegacyRepParsing
local Expansion = G_RLF.Expansion
local LogDebug = function(...)
	G_RLF:LogDebug(...)
end
local LogInfo = function(...)
	G_RLF:LogInfo(...)
end
local LogWarn = function(...)
	G_RLF:LogWarn(...)
end
local LogError = function(...)
	G_RLF:LogError(...)
end
local RGBAToHexFormat = function(...)
	return G_RLF:RGBAToHexFormat(...)
end
local IsRetail = function()
	return G_RLF:IsRetail()
end

local CURRENT_SEASON_DELVE_JOURNEY = 0
local DELVER_JOURNEY_LABEL = nil

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- Wraps all C_ APIs and bare WoW globals used by Reputation.lua so tests
-- can inject mocks without patching _G directly.
local RepAdapter = {
	GetExpansionLevel = function()
		return GetExpansionLevel()
	end,
	RunNextFrame = function(fn)
		return RunNextFrame(fn)
	end,
	IssecretValue = function(msg)
		return issecretvalue and issecretvalue(msg)
	end,
	IsEventValid = function(event)
		return C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid(event)
	end,
	GetFactionForCompanion = function()
		return C_DelvesUI.GetFactionForCompanion()
	end,
	GetFactionDataByID = function(id)
		return C_Reputation.GetFactionDataByID(id)
	end,
	GetDelvesFactionForSeason = function()
		return C_DelvesUI and C_DelvesUI.GetDelvesFactionForSeason and C_DelvesUI.GetDelvesFactionForSeason() or 0
	end,
	GetMajorFactionRenownInfo = function(id)
		return C_MajorFactions.GetMajorFactionRenownInfo(id)
	end,
	GetNumFactions = function()
		return C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetNumFactions() or nil
	end,
	GetFactionDataByIndex = function(i)
		return C_Reputation and C_Reputation.GetFactionDataByIndex and C_Reputation.GetFactionDataByIndex(i) or nil
	end,
	HasRetailReputationAPIAvailable = function()
		return C_Reputation ~= nil and C_Reputation.GetNumFactions ~= nil and C_Reputation.GetFactionDataByIndex ~= nil
	end,
	GetAccountWideFontColor = function()
		return ACCOUNT_WIDE_FONT_COLOR
	end,
	GetDelveReputationBarTitle = function()
		return _G["DELVES_REPUTATION_BAR_TITLE_NO_SEASON"]
	end,
	Strtrim = function(str)
		return strtrim(str)
	end,
}

---@class RLF_Reputation: RLF_Module, AceEvent-3.0, AceTimer-3.0, AceBucket-3.0
local Rep = FeatureBase:new(FeatureModule.Reputation, "AceEvent-3.0", "AceTimer-3.0", "AceBucket-3.0")

Rep._repAdapter = RepAdapter

Rep.Element = {}

local function buildCachedFactionDetails()
	-- This should only be called from Retail, but just in case
	if not Rep._repAdapter.HasRetailReputationAPIAvailable() then
		return
	end

	local numCachedFactions = RepUtils.GetCount()
	local numFactions = Rep._repAdapter.GetNumFactions()
	local hasMoreFactions = numFactions > numCachedFactions
	if not hasMoreFactions then
		return
	end

	for i = 1, numFactions do
		local factionData = Rep._repAdapter.GetFactionDataByIndex(i)
		if factionData and factionData.name then
			local repType = RepUtils.DetermineRepType(factionData.factionID)
			local detailedFactionData = RepUtils.GetFactionData(factionData.factionID, repType)
			if detailedFactionData then
				---@type CachedFactionDetails
				local cachedDetails = {
					repType = repType,
					rank = detailedFactionData.rank,
					standing = detailedFactionData.standing,
					rankStandingMin = detailedFactionData.rankStandingMin,
					rankStandingMax = detailedFactionData.rankStandingMax,
				}
				RepUtils.UpdateCacheEntry(factionData.factionID, cachedDetails, repType)
			end
		end
	end
end

function Rep.Element:new(...)
	---@class Rep.Element: RLF_BaseLootElement
	---@field public repType RepType
	local element = LootElementBase:new()

	element.type = "Reputation"
	element.IsEnabled = function()
		return Rep:IsEnabled()
	end

	---@type UnifiedFactionData
	local unifiedFactionData = ...
	if unifiedFactionData.color and unifiedFactionData.color.GetRGBA then
		element.r, element.g, element.b, element.a = unifiedFactionData.color:GetRGBA()
	else
		element.r, element.g, element.b = unpack(G_RLF.db.global.rep.defaultRepColor)
		element.a = 1
	end
	element.key = "REP_" .. unifiedFactionData.factionId
	element.factionId = unifiedFactionData.factionId
	element.quantity = unifiedFactionData.delta
	element.textFn = function(existingRep)
		local sign = "+"
		local rep = (existingRep or 0) + element.quantity
		if rep < 0 then
			sign = "-"
		end
		return sign .. math.abs(rep) .. " " .. unifiedFactionData.name
	end

	element.icon = unifiedFactionData.icon
	element.quality = unifiedFactionData.quality
	element.itemCount = unifiedFactionData.rank

	element.secondaryTextFn = function()
		local str = ""

		if not element.factionId then
			return str
		end

		local color = RGBAToHexFormat(element.r, element.g, element.b, G_RLF.db.global.rep.secondaryTextAlpha)

		if unifiedFactionData.contextInfo then
			str = "    " .. color .. unifiedFactionData.contextInfo .. "|r"
		end

		return str
	end

	if not G_RLF.db.global.rep.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		element.icon = nil
	end

	return element
end

function Rep:OnInitialize()
	if not IsRetail() then
		LegRep.InitializeLegacyReputationChatParsing()
	end

	if G_RLF.db.global.rep.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function Rep:OnDisable()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if Rep._repAdapter.GetExpansionLevel() >= Expansion.TWW then
		self:UnregisterAllBuckets()
	end
	if Rep._repAdapter.IsEventValid("FACTION_STANDING_CHANGED") then
		self:UnregisterAllBuckets()
	else
		self:UnregisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
	end
end

function Rep:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	if Rep._repAdapter.IsEventValid("FACTION_STANDING_CHANGED") then
		self:RegisterBucketEvent("FACTION_STANDING_CHANGED", 0.2)
	else
		self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
	end
	if Rep._repAdapter.GetExpansionLevel() >= Expansion.TWW then
		--- @type FrameEvent[]
		local delversJourneyPollEvents = {
			"UPDATE_FACTION",
			"MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
		}
		---@diagnostic disable-next-line: param-type-mismatch
		self:RegisterBucketEvent(delversJourneyPollEvents, 0.5, "CheckForHiddenRenownFactions")
	end
	LogDebug("OnEnable", addonName, self.moduleName)
end

function Rep:ParseFactionChangeMessage(message)
	return LegRep.ParseFactionChangeMessage(message, self.companionFactionName)
end

function Rep:PLAYER_ENTERING_WORLD(eventName, isLogin, isReload)
	if Rep._repAdapter.GetExpansionLevel() >= Expansion.TWW then
		if not self.companionFactionId or not self.companionFactionName then
			self.companionFactionId = Rep._repAdapter.GetFactionForCompanion()
			local factionData = Rep._repAdapter.GetFactionDataByID(self.companionFactionId)
			if factionData then
				self.companionFactionName = factionData.name
			end
		end
		self.delversJourney = Rep._repAdapter.GetMajorFactionRenownInfo(CURRENT_SEASON_DELVE_JOURNEY)
		Rep._repAdapter.RunNextFrame(function()
			buildCachedFactionDetails()
		end)
	end
end

function Rep:FACTION_STANDING_CHANGED(factionEvents)
	for factionId, cnt in pairs(factionEvents) do
		LogInfo(cnt .. "x FACTION_STANDING_CHANGED for factionID " .. tostring(factionId), addonName, self.moduleName)
		self:UpdateReputationForFaction(factionId)
	end
end

function Rep:UpdateReputationForFaction(factionID)
	local repType = RepUtils.DetermineRepType(factionID)
	local factionData = RepUtils.GetFactionData(factionID, repType)
	if not factionData then
		LogWarn(
			"Could not retrieve faction data for ID " .. tostring(factionID) .. " repType:" .. tostring(repType),
			addonName,
			self.moduleName
		)
		return
	end

	local repChange = RepUtils.GetDeltaAndUpdateCache(factionID, factionData.standing)

	factionData.delta = repChange

	if repChange and repChange ~= 0 then
		local e = self.Element:new(factionData)
		if e then
			e:Show()
		end
	end
end

function Rep:CHAT_MSG_COMBAT_FACTION_CHANGE(eventName, message)
	if Rep._repAdapter.IssecretValue(message) then
		LogWarn("(" .. eventName .. ") Secret value detected, ignoring chat message", "WOWEVENT", self.moduleName, "")
		return
	end

	LogInfo(eventName .. " " .. message, "WOWEVENT", self.moduleName)

	local faction, repChange, isDelveCompanion, isAccountWide = self:ParseFactionChangeMessage(message)

	if not faction or not repChange then
		LogError(
			"Could not determine faction and/or rep change from message",
			addonName,
			self.moduleName,
			faction,
			nil,
			repChange
		)
		return
	end

	local factionMapEntry = LegRep.GetLocaleFactionMapData(faction, isAccountWide)
	local repType, fId, factionData
	if factionMapEntry then
		fId = factionMapEntry
		repType = RepUtils.DetermineRepType(fId)
		factionData = RepUtils.GetFactionData(fId, repType)
		if not factionData then
			LogWarn(
				"Could not retrieve faction data for ID " .. tostring(fId) .. " repType:" .. tostring(repType),
				addonName,
				self.moduleName
			)
			return
		end
		if factionData.name ~= faction then
			-- In case there's a mismatch for some reason when parsing chat messages,
			-- prefer the parsed name
			factionData.name = faction
		end
		factionData.delta = repChange
	end

	if factionData == nil then
		LogWarn(faction .. " faction data could not be retrieved by ID", addonName, self.moduleName)
		return
	end

	local e = self.Element:new(factionData)
	e:Show()
end

--- @class UpdateFactionEventPayload
--- @field eventName string

--- @class MajorFactionRenownLevelChangedEventPayload
--- @field eventName string
--- @field majorFactionID number
--- @field newRenownLevel number
--- @field oldRenownLevel number

--- Checks for updates to known hidden renown factions
---@param events table<number | nil, number>
function Rep:CheckForHiddenRenownFactions(events)
	for k, v in pairs(events) do
		if k then
			LogDebug(
				"Processing MAJOR_FACTION_RENOWN_LEVEL_CHANGED event for factionID " .. tostring(k),
				addonName,
				self.moduleName
			)
		end
	end
	if CURRENT_SEASON_DELVE_JOURNEY == 0 and (IsRetail() or Rep._repAdapter.GetExpansionLevel() >= Expansion.TWW) then
		CURRENT_SEASON_DELVE_JOURNEY = Rep._repAdapter.GetDelvesFactionForSeason()
	end

	if CURRENT_SEASON_DELVE_JOURNEY == 0 then
		LogDebug("No current season delve journey faction", addonName, self.moduleName)
		return
	end

	if not DELVER_JOURNEY_LABEL then
		---@type string
		local localeGlobalString = Rep._repAdapter.GetDelveReputationBarTitle()
		if not localeGlobalString or type(localeGlobalString) ~= "string" then
			LogDebug("No DJ locale string found", addonName, self.moduleName)
			return
		end
		local trimIndex = localeGlobalString:find("%(")
		if not trimIndex then
			LogDebug("No trim index found for DJ locale string", addonName, self.moduleName)
			return
		end
		DELVER_JOURNEY_LABEL = Rep._repAdapter.Strtrim(localeGlobalString:sub(1, trimIndex - 1))
		if not DELVER_JOURNEY_LABEL or DELVER_JOURNEY_LABEL == "" then
			LogDebug("No DJ label after trim", addonName, self.moduleName)
			return
		end
	end

	local faction = DELVER_JOURNEY_LABEL

	---@type UnifiedFactionData
	local factionData = {
		factionId = CURRENT_SEASON_DELVE_JOURNEY,
		name = faction,
		standing = 0,
		icon = 4635200, -- Delver's Journey
		quality = ItemQualEnum.Rare,
		color = Rep._repAdapter.GetAccountWideFontColor(),
		contextInfo = "",
	}

	local updated = Rep._repAdapter.GetMajorFactionRenownInfo(CURRENT_SEASON_DELVE_JOURNEY)

	if not updated then
		LogDebug("No updated DJ info", addonName, self.moduleName)
		return
	end

	--- Convert MajorFactionRenownInfo to CachedFactionDetails
	--- @param renownInfo MajorFactionRenownInfo
	--- @return CachedFactionDetails
	local function MajorFactionRenownInfoToCachedDetails(renownInfo)
		return {
			repType = bit.bor(RepType.Warband, RepType.MajorFaction),
			rank = renownInfo.renownLevel,
			standing = renownInfo.renownReputationEarned,
			rankStandingMin = 0,
			rankStandingMax = renownInfo.renownLevelThreshold,
		}
	end

	local cacheDetails = RepUtils.GetCachedFactionDetails(CURRENT_SEASON_DELVE_JOURNEY, RepType.Warband)
	if not cacheDetails then
		LogDebug("No cached DJ info, updating", addonName, self.moduleName)
		cacheDetails = MajorFactionRenownInfoToCachedDetails(updated)
		RepUtils.InsertNewCacheEntry(CURRENT_SEASON_DELVE_JOURNEY, cacheDetails, RepType.Warband)
		return
	end

	local newFactionDetails = MajorFactionRenownInfoToCachedDetails(updated)
	--- @type number
	local repChange = RepUtils.GetDeltaAndUpdateCache(CURRENT_SEASON_DELVE_JOURNEY, newFactionDetails.standing)

	factionData.rank = newFactionDetails.rank
	if newFactionDetails.standing then
		factionData.contextInfo = tostring(newFactionDetails.standing)
		if newFactionDetails.rankStandingMax then
			factionData.contextInfo = factionData.contextInfo .. " / " .. tostring(newFactionDetails.rankStandingMax)
		end
	end

	if repChange and repChange > 0 then
		factionData.delta = repChange
		local e = self.Element:new(factionData)
		e:Show()
	end
end

return Rep
