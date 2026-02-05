---@diagnostic disable: inject-field
---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_Reputation: RLF_Module, AceEvent-3.0, AceTimer-3.0, AceBucket-3.0
local Rep = G_RLF.RLF:NewModule(G_RLF.FeatureModule.Reputation, "AceEvent-3.0", "AceTimer-3.0", "AceBucket-3.0")

Rep.Element = {}

local RepUtils = G_RLF.RepUtils
local RepType = RepUtils.RepType
local LegRep = G_RLF.LegacyRepParsing

local CURRENT_SEASON_DELVE_JOURNEY = 0
local DELVER_JOURNEY_LABEL = nil

local function buildCachedFactionDetails()
	local numCachedFactions = RepUtils.GetCount()
	local numFactions = C_Reputation.GetNumFactions()
	local hasMoreFactions = numFactions > numCachedFactions
	if not hasMoreFactions then
		return
	end

	for i = 1, numFactions do
		local factionData = C_Reputation.GetFactionDataByIndex(i)
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
	local element = {}
	G_RLF.InitializeLootDisplayProperties(element)

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

		local color = G_RLF:RGBAToHexFormat(element.r, element.g, element.b, G_RLF.db.global.rep.secondaryTextAlpha)

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
	if not G_RLF:IsRetail() then
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
	if GetExpansionLevel() >= G_RLF.Expansion.TWW then
		self:UnregisterAllBuckets()
	end
	if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("FACTION_STANDING_CHANGED") then
		self:UnregisterAllBuckets()
	else
		self:UnregisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
	end
end

function Rep:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("FACTION_STANDING_CHANGED") then
		self:RegisterBucketEvent("FACTION_STANDING_CHANGED", 0.2)
	else
		self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
	end
	if GetExpansionLevel() >= G_RLF.Expansion.TWW then
		--- @type FrameEvent[]
		local delversJourneyPollEvents = {
			"UPDATE_FACTION",
			"MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
		}
		---@diagnostic disable-next-line: param-type-mismatch
		self:RegisterBucketEvent(delversJourneyPollEvents, 0.5, "CheckForHiddenRenownFactions")
	end
	G_RLF:LogDebug("OnEnable", addonName, self.moduleName)
end

function Rep:ParseFactionChangeMessage(message)
	return G_RLF.LegacyRepParsing.ParseFactionChangeMessage(message, self.companionFactionName)
end

function Rep:PLAYER_ENTERING_WORLD(eventName, isLogin, isReload)
	if GetExpansionLevel() >= G_RLF.Expansion.TWW then
		if not self.companionFactionId or not self.companionFactionName then
			self.companionFactionId = C_DelvesUI.GetFactionForCompanion()
			local factionData = C_Reputation.GetFactionDataByID(self.companionFactionId)
			if factionData then
				self.companionFactionName = factionData.name
			end
		end
		self.delversJourney = C_MajorFactions.GetMajorFactionRenownInfo(CURRENT_SEASON_DELVE_JOURNEY)
		RunNextFrame(function()
			buildCachedFactionDetails()
		end)
	end
end

function Rep:FACTION_STANDING_CHANGED(factionEvents)
	for factionId, cnt in pairs(factionEvents) do
		G_RLF:LogInfo(
			cnt .. "x FACTION_STANDING_CHANGED for factionID " .. tostring(factionId),
			addonName,
			self.moduleName
		)
		self:UpdateReputationForFaction(factionId)
	end
end

function Rep:UpdateReputationForFaction(factionID)
	local repType = RepUtils.DetermineRepType(factionID)
	local factionData = RepUtils.GetFactionData(factionID, repType)
	if not factionData then
		G_RLF:LogWarn(
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
	if issecretvalue and issecretvalue(message) then
		G_RLF:LogWarn(
			"(" .. eventName .. ") Secret value detected, ignoring chat message",
			"WOWEVENT",
			self.moduleName,
			""
		)
		return
	end

	G_RLF:LogInfo(eventName .. " " .. message, "WOWEVENT", self.moduleName)

	return self:fn(function()
		local faction, repChange, isDelveCompanion, isAccountWide = self:ParseFactionChangeMessage(message)

		if not faction or not repChange then
			G_RLF:LogError(
				"Could not determine faction and/or rep change from message",
				addonName,
				self.moduleName,
				faction,
				nil,
				repChange
			)
			return
		end

		local factionMapEntry = G_RLF.LegacyRepParsing.GetLocaleFactionMapData(faction, isAccountWide)
		local repType, fId, factionData
		if factionMapEntry then
			fId = factionMapEntry
			repType = RepUtils.DetermineRepType(fId)
			factionData = RepUtils.GetFactionData(fId, repType)
			if not factionData then
				G_RLF:LogWarn(
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
			G_RLF:LogWarn(faction .. " faction data could not be retrieved by ID", addonName, self.moduleName)
			return
		end

		local e = self.Element:new(factionData)
		e:Show()
	end)
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
			G_RLF:LogDebug(
				"Processing MAJOR_FACTION_RENOWN_LEVEL_CHANGED event for factionID " .. tostring(k),
				addonName,
				self.moduleName
			)
		end
	end
	if CURRENT_SEASON_DELVE_JOURNEY == 0 and (G_RLF:IsRetail() or GetExpansionLevel() >= G_RLF.Expansion.TWW) then
		CURRENT_SEASON_DELVE_JOURNEY = C_DelvesUI.GetDelvesFactionForSeason()
	end

	if CURRENT_SEASON_DELVE_JOURNEY == 0 then
		G_RLF:LogDebug("No current season delve journey faction", addonName, self.moduleName)
		return
	end

	if not DELVER_JOURNEY_LABEL then
		---@type string
		local localeGlobalString = _G["DELVES_REPUTATION_BAR_TITLE_NO_SEASON"]
		if not localeGlobalString or type(localeGlobalString) ~= "string" then
			G_RLF:LogDebug("No DJ locale string found", addonName, self.moduleName)
			return
		end
		local trimIndex = localeGlobalString:find("%(")
		if not trimIndex then
			G_RLF:LogDebug("No trim index found for DJ locale string", addonName, self.moduleName)
			return
		end
		DELVER_JOURNEY_LABEL = strtrim(localeGlobalString:sub(1, trimIndex - 1))
		if not DELVER_JOURNEY_LABEL or DELVER_JOURNEY_LABEL == "" then
			G_RLF:LogDebug("No DJ label after trim", addonName, self.moduleName)
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
		quality = G_RLF.ItemQualEnum.Rare,
		color = ACCOUNT_WIDE_FONT_COLOR,
		contextInfo = "",
	}

	local updated = C_MajorFactions.GetMajorFactionRenownInfo(CURRENT_SEASON_DELVE_JOURNEY)

	if not updated then
		G_RLF:LogDebug("No updated DJ info", addonName, self.moduleName)
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
		G_RLF:LogDebug("No cached DJ info, updating", addonName, self.moduleName)
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
