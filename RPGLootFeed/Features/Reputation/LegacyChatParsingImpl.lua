local addonName = select(1, ...)
---@class G_RLF
local G_RLF = select(2, ...)

---@class LegacyRepParsing
local LegacyRepParsing = {}

-- ── External dependency locals ────────────────────────────────────────────────
-- Captures G_RLF methods so the full dependency surface is visible in one
-- place and tests can inject a minimal ns without the full nsMocks framework.
local IsRetail = function()
	return G_RLF:IsRetail()
end
local LogDebug = function(...)
	G_RLF:LogDebug(...)
end
local LogWarn = function(...)
	G_RLF:LogWarn(...)
end
local CreatePatternSegments = function(pattern)
	return G_RLF:CreatePatternSegmentsForStringNumber(pattern)
end
local ExtractDynamics = function(msg, segs)
	return G_RLF:ExtractDynamicsFromPattern(msg, segs)
end

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- Wraps all bare WoW globals and C_ APIs used by LegacyChatParsingImpl so
-- tests can inject mock implementations without patching _G directly.
local LegacyRepParsingAdapter = {
	GetLocale = function()
		return GetLocale()
	end,
	RunNextFrame = function(fn)
		return RunNextFrame(fn)
	end,
	-- Returns factionData if C_Reputation.GetFactionDataByIndex exists (Retail/MoP+), nil on Classic.
	GetFactionDataByIndex = function(i)
		if C_Reputation and C_Reputation.GetFactionDataByIndex then
			return C_Reputation.GetFactionDataByIndex(i)
		end
		return nil
	end,
	-- Classic-only: bare GetFactionInfo global (pre-MoP / no C_Reputation).
	GetFactionInfoByIndex = function(i)
		return GetFactionInfo(i)
	end,
	-- Classic-only: convert bare GetFactionInfo tuple to a retail-like table.
	ConvertFactionInfoByIndex = function(i)
		return G_RLF.ClassicToRetail:ConvertFactionInfoByIndex(i)
	end,
	-- Returns true when C_Reputation.GetFactionDataByIndex is available.
	HasRetailFactionDataAPI = function()
		return C_Reputation ~= nil and C_Reputation.GetFactionDataByIndex ~= nil
	end,
	-- WoW locale globals for reputation standing change patterns.
	GetFactionStandingIncreasePatterns = function()
		return {
			FACTION_STANDING_INCREASED,
			FACTION_STANDING_INCREASED_ACH_BONUS,
			FACTION_STANDING_INCREASED_BONUS,
			FACTION_STANDING_INCREASED_DOUBLE_BONUS,
		}
	end,
	GetFactionStandingDecreasePatterns = function()
		return { FACTION_STANDING_DECREASED }
	end,
}
LegacyRepParsing._legacyAdapter = LegacyRepParsingAdapter

-- Precompute pattern segments to optimize runtime message parsing
local function precomputePatternSegments(patterns)
	local computedPatterns = {}
	for _, pattern in ipairs(patterns) do
		local segments = CreatePatternSegments(pattern)
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
	if IsRetail() then
		for k, v in pairs(G_RLF.db.locale.accountWideFactionMap) do
			if v then
				count = count + 1
			end
		end
	end

	return count
end

function LegacyRepParsing.buildFactionLocaleMap(findName, isAccountWide)
	-- Classic:GetFactionInfo(factionIndex)
	local mappedFactions = countMappedFactions()
	local hasMoreFactions = false
	if LegacyRepParsing._legacyAdapter.HasRetailFactionDataAPI() then
		hasMoreFactions = LegacyRepParsing._legacyAdapter.GetFactionDataByIndex(mappedFactions + 1) ~= nil
	-- So far up through MoP Classic, there is no C_Reputation.GetFactionDataByIndex
	else
		hasMoreFactions = LegacyRepParsing._legacyAdapter.GetFactionInfoByIndex(mappedFactions + 1) ~= nil
	end
	if not hasMoreFactions and not findName then
		return
	end
	local numFactions = mappedFactions + 5

	if not findName then
		local buckets = math.ceil(numFactions / 10) + 1
		local bucketSize = math.ceil(numFactions / buckets) + 1

		for bucket = 1, buckets do
			LegacyRepParsing._legacyAdapter.RunNextFrame(function()
				for i = 1 + (bucket - 1) * bucketSize, bucket * bucketSize do
					local factionData
					if LegacyRepParsing._legacyAdapter.HasRetailFactionDataAPI() then
						factionData = LegacyRepParsing._legacyAdapter.GetFactionDataByIndex(i)
					-- So far up through MoP Classic, there is no C_Reputation.GetFactionDataByIndex
					else
						factionData = LegacyRepParsing._legacyAdapter.ConvertFactionInfoByIndex(i)
					end
					if factionData and factionData.name then
						if IsRetail() and factionData.isAccountWide then
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
		if IsRetail() then
			factionData = LegacyRepParsing._legacyAdapter.GetFactionDataByIndex(i)
		-- So far up through MoP Classic, there is no C_Reputation.GetFactionDataByIndex
		else
			factionData = LegacyRepParsing._legacyAdapter.ConvertFactionInfoByIndex(i)
		end

		if factionData then
			if factionData.isAccountWide then
				G_RLF.db.locale.accountWideFactionMap[factionData.name] = factionData.factionID
			else
				G_RLF.db.locale.factionMap[factionData.name] = factionData.factionID
			end
			if findName then
				if
					(isAccountWide == nil or isAccountWide == factionData.isAccountWide)
					and factionData.name == findName
				then
					break
				end
			end
		end
	end
end

-- Function to extract faction and reputation change using precomputed patterns
local function extractFactionAndRep(message, patterns)
	if not patterns then
		return nil, nil
	end

	for _, segments in ipairs(patterns) do
		local faction, rep = ExtractDynamics(message, segments)
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

local increasePatterns, decreasePatterns, accountWideIncreasePatterns, accountWideDecreasePatterns

function LegacyRepParsing.InitializeLegacyReputationChatParsing()
	locale = LegacyRepParsing._legacyAdapter.GetLocale()

	local increase_consts = LegacyRepParsing._legacyAdapter.GetFactionStandingIncreasePatterns()
	local decrease_consts = LegacyRepParsing._legacyAdapter.GetFactionStandingDecreasePatterns()

	increasePatterns = precomputePatternSegments(increase_consts)
	decreasePatterns = precomputePatternSegments(decrease_consts)
	accountWideIncreasePatterns = {}
	accountWideDecreasePatterns = {}

	LegacyRepParsing._legacyAdapter.RunNextFrame(function()
		LegacyRepParsing.buildFactionLocaleMap()
	end)
end

function LegacyRepParsing.ParseFactionChangeMessage(message, companionFactionName)
	local isDelveCompanion = false
	local isAccountWide = false
	local faction, repChange
	-- Account-wide factions only exist in Retail, currently. And now we're getting faction
	-- rep changes from a different event instead of CHAT_MSG events. As such, this code
	-- will likely never be hit again, but leaving it here for posterity.
	if IsRetail() and accountWideIncreasePatterns then
		faction, repChange = extractFactionAndRep(message, accountWideIncreasePatterns)
		if not faction and accountWideDecreasePatterns then
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
		LogDebug(
			"Checking for " .. tostring(companionFactionName) .. " in message " .. message,
			addonName,
			"Reputation.LegacyChatParsing"
		)
		faction, repChange = extractFactionAndRepForDelves(message, companionFactionName)
		if faction then
			isDelveCompanion = true
			isAccountWide = true
		end
	end
	return faction, repChange, isDelveCompanion, isAccountWide
end

function LegacyRepParsing.GetLocaleFactionMapData(faction, isAccountWide)
	local factionMapEntry
	if isAccountWide then
		factionMapEntry = G_RLF.db.locale.accountWideFactionMap[faction]
	else
		factionMapEntry = G_RLF.db.locale.factionMap[faction]
	end
	if factionMapEntry == nil then
		-- attempt to find the missing faction's ID
		LogDebug(faction .. " not cached for " .. locale, addonName, "Reputation.LegacyChatParsing")
		LegacyRepParsing.buildFactionLocaleMap(faction, isAccountWide)
		if isAccountWide then
			factionMapEntry = G_RLF.db.locale.accountWideFactionMap[faction]
		else
			factionMapEntry = G_RLF.db.locale.factionMap[faction]
		end
	end

	if factionMapEntry then
		return factionMapEntry
	else
		LogWarn(faction .. " is STILL not cached for " .. locale, addonName, "Reputation.LegacyChatParsing")
		return nil
	end
end

G_RLF.LegacyRepParsing = LegacyRepParsing
