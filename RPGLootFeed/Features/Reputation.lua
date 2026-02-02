---@diagnostic disable: inject-field
---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_Reputation: RLF_Module, AceEvent-3.0, AceTimer-3.0, AceBucket-3.0
local Rep = G_RLF.RLF:NewModule(G_RLF.FeatureModule.Reputation, "AceEvent-3.0", "AceTimer-3.0", "AceBucket-3.0")

Rep.Element = {}

---@enum RepType
local RepType = {
	MajorFaction = 1,
	Paragon = 2,
	BaseFaction = 3,
	DelveCompanion = 4,
	Friendship = 5,
}

local CURRENT_SEASON_DELVE_JOURNEY = 0

-- Precompute pattern segments to optimize runtime message parsing
local function precomputePatternSegments(patterns)
	local computedPatterns = {}
	for _, pattern in ipairs(patterns) do
		local segments = G_RLF:CreatePatternSegmentsForStringNumber(pattern)
		table.insert(computedPatterns, segments)
	end
	return computedPatterns
end

local locale
local function countMappedFactions()
	local count = 0
	for k, v in pairs(G_RLF.db.locale.factionMap) do
		if v then
			count = count + 1
		end
	end
	if G_RLF:IsRetail() then
		for k, v in pairs(G_RLF.db.locale.accountWideFactionMap) do
			if v then
				count = count + 1
			end
		end
	end

	return count
end

local function buildFactionLocaleMap(findName, isAccountWide)
	-- Classic:GetFactionInfo(factionIndex)
	local mappedFactions = countMappedFactions()
	local hasMoreFactions = false
	if G_RLF:IsRetail() then
		hasMoreFactions = C_Reputation.GetFactionDataByIndex(mappedFactions + 1) ~= nil
	-- So far up through MoP Classic, there is no C_Reputation.GetFactionDataByIndex
	else
		hasMoreFactions = GetFactionInfo(mappedFactions + 1) ~= nil
	end
	if not hasMoreFactions and not findName then
		return
	end
	local numFactions = mappedFactions + 5

	if not findName then
		local buckets = math.ceil(numFactions / 10) + 1
		local bucketSize = math.ceil(numFactions / buckets) + 1

		for bucket = 1, buckets do
			RunNextFrame(function()
				for i = 1 + (bucket - 1) * bucketSize, bucket * bucketSize do
					local factionData
					if G_RLF:IsRetail() then
						factionData = C_Reputation.GetFactionDataByIndex(i)
					-- So far up through MoP Classic, there is no C_Reputation.GetFactionDataByIndex
					else
						factionData = G_RLF.ClassicToRetail:ConvertFactionInfoByIndex(i)
					end
					if factionData and factionData.name then
						if G_RLF:IsRetail() and factionData.isAccountWide then
							G_RLF.db.locale.accountWideFactionMap[factionData.name] = factionData.factionID
						else
							G_RLF.db.locale.factionMap[factionData.name] = factionData.factionID
						end
					end
				end
			end)
		end

		return
	end

	for i = 1, numFactions do
		local factionData
		if G_RLF:IsRetail() then
			factionData = C_Reputation.GetFactionDataByIndex(i)
		-- So far up through MoP Classic, there is no C_Reputation.GetFactionDataByIndex
		else
			factionData = G_RLF.ClassicToRetail:ConvertFactionInfoByIndex(i)
		end

		if factionData then
			if factionData.isAccountWide then
				G_RLF.db.locale.accountWideFactionMap[factionData.name] = factionData.factionID
			else
				G_RLF.db.locale.factionMap[factionData.name] = factionData.factionID
			end
			if findName then
				if isAccountWide == factionData.isAccountWide and factionData.name == findName then
					break
				end
			end
		end
	end
end

--- Use C_MajorFactions.GetMajorFactionIDs(LE_EXPANSION_WAR_WITHIN) to get the major faction IDs
--- Use C_MajorFactions.GetMajorFactionData to get the textureKit (the key)
--- Search Wago Files for "interface/icons/ui_majorfactions_interface/icons/ui_majorfactions_" to find the icons
--- https://wago.tools/files?search=interface%2Ficons%2Fui_majorfaction
--- The format of the string could change from expansion to expansion (it was "ui_majorfaction_" in DF)
local majorFactionTextureKitIconMap = {
	["centaur"] = 4687627, -- Maruuk Centaur
	["expedition"] = 4687628, -- Dragonscale Expedition
	["tuskarr"] = 4687629, -- Iskaara Tuskarr
	["valdrakken"] = 4687630, -- Valdrakken Accord
	["niffen"] = 5140835, -- Loamm Niffen
	["dream"] = 5244643, -- Dream Wardens
	["storm"] = 5891369, -- Council of Dornogal
	["candle"] = 5891367, -- The Assembly of the Deeps
	["flame"] = 5891368, -- Hallowfall Arathi
	["web"] = 5891370, -- Severed Threads
	["rocket"] = 6252691, -- The Cartels of Undermine
	["stars"] = 6351805, -- Gallagio Loyalty Rewards Club
	["nightfall"] = 6694197, -- Flame's Radiance
	["karesh"] = 6937965, -- Manaforge Vandals
}

--- A bit of a grab bag
--- Search wago files for "interface/icons/ui_notoriety" and get the Azh-Kahet factions
--- Search wago files for "interface/icons reputationcurrencies" and you get the Goblin factions
local factionIdIconMap = {
	[2601] = 5862764, -- The Weaver
	[2605] = 5862762, -- The General
	[2607] = 5862763, -- The Vizier
	[2669] = 6439629, -- Darkfuse Solutions
	[2671] = 6439631, -- Venture Company
	[2673] = 6439627, -- Bilgewater Cartel
	[2675] = 6439628, -- Blackwater Cartel
	[2677] = 6439630, -- Steamwheedle Cartel
}

function Rep.Element:new(...)
	---@class Rep.Element: RLF_BaseLootElement
	---@field public repType RepType
	local element = {}
	G_RLF.InitializeLootDisplayProperties(element)

	element.type = "Reputation"
	element.IsEnabled = function()
		return Rep:IsEnabled()
	end

	local factionName, factionData, rL, gL, bL
	element.quantity, factionName, rL, gL, bL, element.factionId, factionData, element.repType = ...
	local rDef, gDef, bDef = unpack(G_RLF.db.global.rep.defaultRepColor)
	element.r, element.g, element.b = rL or rDef, gL or gDef, bL or bDef
	element.a = 1
	element.key = "REP_" .. factionName
	element.textFn = function(existingRep)
		local sign = "+"
		local rep = (existingRep or 0) + element.quantity
		if rep < 0 then
			sign = "-"
		end
		local factionDisplayName = factionName
		if factionDisplayName == _G["GUILD"] then
			-- Use the actual guild name
			factionDisplayName = factionData.name or _G["GUILD"]
		end
		return sign .. math.abs(rep) .. " " .. factionDisplayName
	end

	if factionData ~= nil and factionData.textureKit then
		local key = string.lower(factionData.textureKit)
		if majorFactionTextureKitIconMap and majorFactionTextureKitIconMap[key] then
			element.icon = majorFactionTextureKitIconMap[key]
		else
			element.icon = G_RLF.DefaultIcons.REPUTATION
		end
		element.quality = G_RLF.ItemQualEnum.Heirloom
	elseif factionIdIconMap[element.factionId] then
		element.icon = factionIdIconMap[element.factionId]
		element.quality = G_RLF.ItemQualEnum.Rare
	elseif element.repType == RepType.DelveCompanion then
		element.icon = 5315246 -- interface/icons/inv_cape_special_explorer_b_03
		element.quality = G_RLF.ItemQualEnum.Rare
	else
		element.icon = G_RLF.DefaultIcons.REPUTATION
		element.quality = G_RLF.ItemQualEnum.Rare
	end

	if not G_RLF.db.global.rep.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		element.icon = nil
	end

	element.itemCount = nil
	if factionData then
		if factionData.renownLevel then
			element.itemCount = factionData.renownLevel
		elseif element.repType == RepType.DelveCompanion then
			element.itemCount = factionData.currentLevel
		elseif element.repType == RepType.Friendship then
			element.itemCount = factionData.reaction
		elseif element.repType == RepType.BaseFaction and factionData.reaction then
			local gender = UnitSex("player")
			---@diagnostic disable-next-line: missing-parameter -- GetText only has one required parameter
			element.itemCount = GetText("FACTION_STANDING_LABEL" .. factionData.reaction, gender)
		end
	end

	element.secondaryTextFn = function()
		local str = ""

		if not element.factionId or not factionData then
			return str
		end

		local color = G_RLF:RGBAToHexFormat(element.r, element.g, element.b, G_RLF.db.global.rep.secondaryTextAlpha)

		if element.repType == RepType.DelveCompanion and factionData then
			if factionData.nextLevelAt > 0 then
				str = math.floor((factionData.currentXp / factionData.nextLevelAt) * 10000) / 100 .. "%"
				return "    " .. color .. str .. "|r"
			end
			return ""
		end

		if element.repType == RepType.MajorFaction then
			if
				factionData.renownReputationEarned ~= nil
				and factionData.renownLevelThreshold ~= nil
				and factionData.renownReputationEarned > 0
				and factionData.renownLevelThreshold > 0
			then
				str = str .. factionData.renownReputationEarned .. "/" .. factionData.renownLevelThreshold
			end
		elseif element.repType == RepType.Paragon then
			if factionData.hasRewardPending then
				local stylingDb = G_RLF.DbAccessor:Styling(G_RLF.Frames.MAIN)
				local atlasIcon = "ParagonReputation_Bag"
				local sizeCoeff = G_RLF.AtlasIconCoefficients[atlasIcon] or 1
				local atlasIconSize = stylingDb.fontSize * sizeCoeff
				str = str .. CreateAtlasMarkup(atlasIcon, atlasIconSize, atlasIconSize, 0, 0) .. "    "
			end
			if
				factionData.currentValue ~= nil
				and factionData.currentValue > 0
				and factionData.threshold ~= nil
				and factionData.threshold > 0
			then
				str = str .. (factionData.currentValue % factionData.threshold)
				str = str .. "/" .. factionData.threshold
			end
		elseif element.repType == RepType.Friendship then
			if factionData.repNumerator ~= nil and factionData.repNumerator > 0 then
				str = str .. factionData.repNumerator
				if factionData.repDenominator ~= nil and factionData.repDenominator > 0 then
					str = str .. "/" .. factionData.repDenominator
				end
			end
		else
			if
				(factionData.currentStanding ~= 0 or factionData.nextReactionThreshold ~= 0)
				-- currentReactionThreshold can be 0 (usually for neutral standing)
				-- but we want to make sure we don't get a division by zero
				and factionData.currentReactionThreshold ~= factionData.nextReactionThreshold
			then
				str = str
					.. (factionData.currentStanding - factionData.currentReactionThreshold)
					.. "/"
					.. (factionData.nextReactionThreshold - factionData.currentReactionThreshold)
			end
		end

		if str ~= "" then
			str = "    " .. color .. str .. "|r"
		end

		return str
	end

	return element
end

local increasePatterns, decreasePatterns, accountWideIncreasePatterns, accountWideDecreasePatterns
function Rep:OnInitialize()
	locale = GetLocale()

	local increase_consts = {
		FACTION_STANDING_INCREASED,
		FACTION_STANDING_INCREASED_ACH_BONUS,
		FACTION_STANDING_INCREASED_BONUS,
		FACTION_STANDING_INCREASED_DOUBLE_BONUS,
	}

	local decrease_consts = {
		FACTION_STANDING_DECREASED,
	}
	local account_wide_increase_consts = {}
	local account_wide_decrease_consts = {}

	if G_RLF:IsRetail() then
		table.insert(account_wide_increase_consts, FACTION_STANDING_INCREASED_ACCOUNT_WIDE)
		table.insert(account_wide_increase_consts, FACTION_STANDING_INCREASED_ACH_BONUS_ACCOUNT_WIDE)
		table.insert(account_wide_decrease_consts, FACTION_STANDING_DECREASED_ACCOUNT_WIDE)
	end

	increasePatterns = precomputePatternSegments(increase_consts)
	decreasePatterns = precomputePatternSegments(decrease_consts)
	if G_RLF:IsRetail() then
		accountWideIncreasePatterns = precomputePatternSegments(account_wide_increase_consts)
		accountWideDecreasePatterns = precomputePatternSegments(account_wide_decrease_consts)
	else
		accountWideIncreasePatterns = {}
		accountWideDecreasePatterns = {}
	end

	RunNextFrame(function()
		buildFactionLocaleMap()
	end)

	if G_RLF.db.global.rep.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

-- Function to extract faction and reputation change using precomputed patterns
local function extractFactionAndRep(message, patterns)
	for _, segments in ipairs(patterns) do
		local faction, rep = G_RLF:ExtractDynamicsFromPattern(message, segments)
		if faction and rep then
			return faction, rep
		end
	end
	return nil, nil
end

--- @return string?, number?
local function extractFactionAndRepForDelves(message, companionFactionName)
	if not companionFactionName then
		return nil, nil
	end

	local factionStart, factionEnd = string.find(message, companionFactionName, 1, true)
	if factionStart then
		local repStart, repEnd = string.find(message, "%d+", factionEnd + 1)
		if repStart then
			local rep = string.sub(message, repStart, repEnd)
			return companionFactionName, tonumber(rep)
		end
	end

	return nil, nil
end

function Rep:OnDisable()
	self:UnregisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if GetExpansionLevel() >= G_RLF.Expansion.TWW then
		self:UnregisterAllBuckets()
	end
end

function Rep:OnEnable()
	self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	if GetExpansionLevel() >= G_RLF.Expansion.TWW then
		--- @type FrameEvent[]
		local events = {
			"UPDATE_FACTION",
			"MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
		}
		---@diagnostic disable-next-line: param-type-mismatch
		self:RegisterBucketEvent(events, 0.5, "CheckForHiddenRenownFactions")
	end
	G_RLF:LogDebug("OnEnable", addonName, self.moduleName)
end

function Rep:ParseFactionChangeMessage(message)
	local isDelveCompanion = false
	local isAccountWide = false
	local faction, repChange
	if G_RLF:IsRetail() then
		faction, repChange = extractFactionAndRep(message, accountWideIncreasePatterns)
		if not faction then
			faction, repChange = extractFactionAndRep(message, accountWideDecreasePatterns)
			if repChange then
				repChange = -repChange
			end
		end

		if faction then
			isAccountWide = true
		end
	end

	if not faction then
		faction, repChange = extractFactionAndRep(message, increasePatterns)
	end
	if not faction then
		faction, repChange = extractFactionAndRep(message, decreasePatterns)
		if repChange then
			repChange = -repChange
		end
	end
	if not faction then
		G_RLF:LogDebug(
			"Checking for " .. self.companionFactionName .. " in message " .. message,
			addonName,
			self.moduleName
		)
		faction, repChange = extractFactionAndRepForDelves(message, self.companionFactionName)
		if faction then
			isDelveCompanion = true
			isAccountWide = true
		end
	end
	return faction, repChange, isDelveCompanion, isAccountWide
end

function Rep:PLAYER_ENTERING_WORLD(eventName, isLogin, isReload)
	if GetExpansionLevel() >= G_RLF.Expansion.TWW then
		if not self.companionFactionId or not self.companionFactionName then
			local companionId = C_DelvesUI.GetCompanionInfoForActivePlayer()
			self.companionFactionId = C_DelvesUI.GetFactionForCompanion(companionId)
			local factionData = C_Reputation.GetFactionDataByID(self.companionFactionId)
			if factionData then
				self.companionFactionName = factionData.name
			end
		end
		self.delversJourney = C_MajorFactions.GetMajorFactionRenownInfo(CURRENT_SEASON_DELVE_JOURNEY)
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

		--- @type number, number, number, ColorMixin
		local r, g, b, color
		local factionMapEntry
		if isAccountWide then
			factionMapEntry = G_RLF.db.locale.accountWideFactionMap[faction]
		else
			factionMapEntry = G_RLF.db.locale.factionMap[faction]
		end
		if factionMapEntry == nil then
			-- attempt to find the missing faction's ID
			G_RLF:LogDebug(faction .. " not cached for " .. locale, addonName, self.moduleName)
			buildFactionLocaleMap(faction, isAccountWide)
			if isAccountWide then
				factionMapEntry = G_RLF.db.locale.accountWideFactionMap[faction]
			else
				factionMapEntry = G_RLF.db.locale.factionMap[faction]
			end
		end

		local repType, fId, factionData
		if factionMapEntry then
			fId = factionMapEntry
			if G_RLF:IsRetail() and C_Reputation.IsMajorFaction(fId) then
				color = ACCOUNT_WIDE_FONT_COLOR
				repType = RepType.MajorFaction
				local renownInfo = C_MajorFactions.GetMajorFactionRenownInfo(fId)
				factionData = C_MajorFactions.GetMajorFactionData(fId)
				factionData.renownLevel = renownInfo and renownInfo.renownLevel or 0
				factionData.renownReputationEarned = renownInfo and renownInfo.renownReputationEarned or 0
				factionData.renownLevelThreshold = renownInfo and renownInfo.renownLevelThreshold or 0
			elseif G_RLF:IsRetail() and isDelveCompanion then
				factionData = C_Reputation.GetFactionDataByID(fId)
				if not factionData then
					G_RLF:LogWarn(
						faction .. " (supposed companion) faction data could not be retrieved by ID",
						addonName,
						self.moduleName
					)
					return
				end
				local ranks = C_GossipInfo.GetFriendshipReputationRanks(fId)
				local info = C_GossipInfo.GetFriendshipReputation(fId)
				if factionData.reaction then
					color = FACTION_BAR_COLORS[factionData.reaction]
				end
				factionData.currentLevel = ranks and ranks.currentLevel or 0
				factionData.maxLevel = ranks and ranks.maxLevel or 0
				factionData.currentXp = info.standing - info.reactionThreshold
				if info.nextThreshold and info.nextThreshold > 1 then
					factionData.nextLevelAt = info.nextThreshold - info.reactionThreshold
				else
					factionData.nextLevelAt = 0
				end
				repType = RepType.DelveCompanion
			else
				local friendInfo = C_GossipInfo.GetFriendshipReputation(fId)
				if GetExpansionLevel() >= G_RLF.Expansion.CATA and faction == _G["GUILD"] then
					factionData = C_Reputation.GetGuildFactionData()
				elseif G_RLF:IsRetail() then
					factionData = C_Reputation.GetFactionDataByID(fId)
				-- So far up through MoP Classic, there is no C_Reputation.GetFactionDataByID
				else
					factionData = G_RLF.ClassicToRetail:ConvertFactionInfoByID(fId)
				end
				if not factionData then
					G_RLF:LogWarn(faction .. " faction data could not be retrieved by ID", addonName, self.moduleName)
					return
				end
				if factionData.reaction then
					color = FACTION_BAR_COLORS[factionData.reaction]
				end
				if
					friendInfo
					and friendInfo.friendshipFactionID
					and friendInfo.friendshipFactionID > 0
					and friendInfo.nextThreshold
					and friendInfo.nextThreshold > 1
				then
					local ranks = C_GossipInfo.GetFriendshipReputationRanks(fId)
					factionData.currentLevel = ranks and ranks.currentLevel or 0
					factionData.maxLevel = ranks and ranks.maxLevel or 0
					factionData.repNumerator = friendInfo.standing - friendInfo.reactionThreshold
					factionData.repDenominator = friendInfo.nextThreshold - friendInfo.reactionThreshold
					repType = RepType.Friendship
				else
					repType = RepType.BaseFaction
				end
			end

			if GetExpansionLevel() >= G_RLF.Expansion.LEGION and C_Reputation.IsFactionParagon(fId) then
				color = color or FACTION_GREEN_COLOR
				repType = RepType.Paragon
				factionData = factionData or {}
				factionData.currentValue, factionData.threshold, factionData.rewardQuestId, factionData.hasRewardPending, factionData.tooLowLevelForParagon =
					C_Reputation.GetFactionParagonInfo(fId)
			end
		else
			G_RLF:LogWarn(faction .. " is STILL not cached for " .. locale, addonName, self.moduleName)
		end

		if color then
			r, g, b = color.r, color.g, color.b
		end

		local e = self.Element:new(repChange, faction, r, g, b, fId, factionData, repType)
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
---@param events table<UpdateFactionEventPayload | MajorFactionRenownLevelChangedEventPayload, number>
function Rep:CheckForHiddenRenownFactions(events)
	if CURRENT_SEASON_DELVE_JOURNEY == 0 and (G_RLF:IsRetail() or GetExpansionLevel() == G_RLF.Expansion.TWW) then
		CURRENT_SEASON_DELVE_JOURNEY = C_DelvesUI.GetDelvesFactionForSeason()
		factionIdIconMap[CURRENT_SEASON_DELVE_JOURNEY] = 4635200 -- Delver's Journey
	end
	local updated = C_MajorFactions.GetMajorFactionRenownInfo(CURRENT_SEASON_DELVE_JOURNEY)

	if not updated then
		G_RLF:LogDebug("No updated DJ info", addonName, self.moduleName)
		return
	end

	if not self.delversJourney then
		G_RLF:LogDebug("No cached DJ info, updating", addonName, self.moduleName)
		self.delversJourney = updated
		return
	end
	--- @type number
	local repChange

	if updated.renownLevel > self.delversJourney.renownLevel then
		G_RLF:LogDebug("DJ level up", addonName, self.moduleName)
		local knownRemainingToNextLevel = self.delversJourney.renownLevelThreshold
			- self.delversJourney.renownReputationEarned
		local currentLevelEarned = updated.renownReputationEarned
		repChange = currentLevelEarned + knownRemainingToNextLevel
	elseif updated.renownReputationEarned > self.delversJourney.renownReputationEarned then
		G_RLF:LogDebug("DJ rep change", addonName, self.moduleName)
		repChange = updated.renownReputationEarned - self.delversJourney.renownReputationEarned
	else
		G_RLF:LogDebug("DJ no change", addonName, self.moduleName)
		return
	end

	self.delversJourney = updated
	---@type string
	local localeGlobalString = _G["DELVES_REPUTATION_BAR_TITLE_NO_SEASON"]
	local trimIndex = localeGlobalString:find("%(")
	if not trimIndex then
		G_RLF:LogDebug("No trim index found for DJ locale string", addonName, self.moduleName)
		return
	end

	local faction = strtrim(localeGlobalString:sub(1, trimIndex - 1))
	local color = ACCOUNT_WIDE_FONT_COLOR
	local r, g, b = color.r, color.g, color.b

	if repChange and repChange > 0 then
		local e =
			self.Element:new(repChange, faction, r, g, b, CURRENT_SEASON_DELVE_JOURNEY, updated, RepType.MajorFaction)
		e:Show()
	end
end

return Rep
