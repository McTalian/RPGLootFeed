---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local C = LibStub("C_Everywhere")

-- ── Shared WoW API Adapters ──────────────────────────────────────────────────
-- Central namespace for WoW API wrappers used across feature modules.
-- Each adapter is a plain table of functions that wrap a single C_ namespace
-- or family of related globals. Tests mock at this boundary.
if not G_RLF.WoWAPI then
	G_RLF.WoWAPI = {}
end

-- ── Reputation API Adapter ───────────────────────────────────────────────────
-- Wraps C_Reputation, C_MajorFactions, C_DelvesUI, C_EventUtils, and
-- related globals used by the Reputation feature module and RepUtils.
---@class RLF_WoWAPI_Reputation
G_RLF.WoWAPI.Reputation = {
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

-- ── Experience API Adapter ────────────────────────────────────────────────────
-- Wraps UnitXP, UnitXPMax, and UnitLevel globals used by the Experience
-- feature module.
---@class RLF_WoWAPI_Experience
G_RLF.WoWAPI.Experience = {
	UnitXP = function(unit)
		return UnitXP(unit)
	end,
	UnitXPMax = function(unit)
		return UnitXPMax(unit)
	end,
	UnitLevel = function(unit)
		return UnitLevel(unit)
	end,
}

-- ── Money API Adapter ─────────────────────────────────────────────────────────
-- Wraps C_CurrencyInfo, GetMoney, and PlaySoundFile so tests can inject mocks
-- without patching _G directly.
---@class RLF_WoWAPI_Money
G_RLF.WoWAPI.Money = {
	GetCoinTextureString = function(amount)
		return C_CurrencyInfo.GetCoinTextureString(amount)
	end,
	GetMoney = function()
		return GetMoney()
	end,
	PlaySoundFile = function(sound)
		return PlaySoundFile(sound)
	end,
}

-- ── TravelPoints API Adapter ──────────────────────────────────────────────────
-- Wraps C_PerksActivities and the MONTHLY_ACTIVITIES_POINTS global string used
-- by the TravelPoints feature module.
---@class RLF_WoWAPI_TravelPoints
G_RLF.WoWAPI.TravelPoints = {
	GetPerksActivitiesInfo = function()
		return C_PerksActivities.GetPerksActivitiesInfo()
	end,
	GetPerksActivityInfo = function(activityID)
		return C_PerksActivities.GetPerksActivityInfo(activityID)
	end,
	GetMonthlyActivitiesPointsLabel = function()
		return _G["MONTHLY_ACTIVITIES_POINTS"]
	end,
}

-- ── Currency API Adapter ──────────────────────────────────────────────────────
-- Wraps GetExpansionLevel, currency info APIs (C_Everywhere + direct), honor
-- tracking, locale patterns, Constants, and Ethereal-Strands UI behind
-- testable functions so tests can inject mocks without patching _G.
---@class RLF_WoWAPI_Currency
G_RLF.WoWAPI.Currency = {
	GetExpansionLevel = function()
		return GetExpansionLevel()
	end,
	IssecretValue = function(msg)
		return issecretvalue and issecretvalue(msg)
	end,
	-- C_Everywhere unified queries used in Process (CURRENCY_DISPLAY_UPDATE path)
	GetCurrencyInfo = function(currencyType)
		return C.CurrencyInfo.GetCurrencyInfo(currencyType)
	end,
	GetBasicCurrencyInfo = function(currencyType, amount)
		return C.CurrencyInfo.GetBasicCurrencyInfo(currencyType, amount)
	end,
	GetCurrencyLinkFromLib = function(currencyType)
		return C.CurrencyInfo.GetCurrencyLink(currencyType)
	end,
	-- Predicate: does the modern C_CurrencyInfo.GetCurrencyLink API exist?
	HasGetCurrencyLinkAPI = function()
		return C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink ~= nil
	end,
	-- Classic fallback (bare global) for GetCurrencyLink
	GetCurrencyLinkFromGlobal = function(currencyId, quantity)
		return GetCurrencyLink(currencyId, quantity)
	end,
	-- Honor tracking for the Account-Wide Honor currency element
	GetUnitHonorLevel = function(unit)
		return UnitHonorLevel(unit)
	end,
	GetUnitHonorMax = function(unit)
		return UnitHonorMax(unit)
	end,
	GetUnitHonor = function(unit)
		return UnitHonor(unit)
	end,
	-- WoW Constants tables
	GetAccountWideHonorCurrencyID = function()
		return Constants and Constants.CurrencyConsts and Constants.CurrencyConsts.ACCOUNT_WIDE_HONOR_CURRENCY_ID
	end,
	GetPerksProgramCurrencyID = function()
		return Constants
			and Constants.CurrencyConsts
			and Constants.CurrencyConsts.CURRENCY_ID_PERKS_PROGRAM_DISPLAY_INFO
	end,
	-- Classic locale patterns used in OnInitialize to build classicCurrencyPatterns
	GetCurrencyGainedMultiplePattern = function()
		return CURRENCY_GAINED_MULTIPLE
	end,
	GetCurrencyGainedMultipleBonusPattern = function()
		return CURRENCY_GAINED_MULTIPLE_BONUS
	end,
	-- Ethereal Strands UI (3278) custom link handler
	GenericTraitToggle = function()
		GenericTraitUI_LoadUI()
		GenericTraitFrame:SetSystemID(29)
		GenericTraitFrame:SetTreeID(1115)
		ToggleFrame(GenericTraitFrame)
	end,
}

-- ── Professions API Adapter ──────────────────────────────────────────────────
-- Wraps GetProfessions, GetProfessionInfo, issecretvalue, and SKILL_RANK_UP
-- for the Professions feature module.
---@class RLF_WoWAPI_Professions
G_RLF.WoWAPI.Professions = {
	GetProfessions = function()
		return GetProfessions()
	end,
	GetProfessionInfo = function(id)
		return GetProfessionInfo(id)
	end,
	IssecretValue = function(msg)
		return issecretvalue and issecretvalue(msg)
	end,
	GetSkillRankUpPattern = function()
		return _G.SKILL_RANK_UP
	end,
}

-- ── Transmog API Adapter ──────────────────────────────────────────────────────
-- Wraps C_TransmogCollection.GetAppearanceSourceInfo, Item:CreateFromItemLink,
-- and the ERR_LEARN_TRANSMOG_S locale string for the Transmog feature module.
---@class RLF_WoWAPI_Transmog
G_RLF.WoWAPI.Transmog = {
	GetAppearanceSourceInfo = function(itemModifiedAppearanceID)
		return C_TransmogCollection.GetAppearanceSourceInfo(itemModifiedAppearanceID)
	end,
	CreateItemFromItemLink = function(itemLink)
		return Item:CreateFromItemLink(itemLink)
	end,
	GetErrLearnTransmogS = function()
		return _G["ERR_LEARN_TRANSMOG_S"]
	end,
}

-- ── ItemLoot API Adapter ──────────────────────────────────────────────────────
-- Wraps WoW API calls used by the ItemLoot feature module: unit queries,
-- C_Item stat/count/info lookups, GetCoinTextureString, CreateAtlasMarkup,
-- PlaySoundFile, and the AuctionIntegrations price hook.
---@class RLF_WoWAPI_ItemLoot
G_RLF.WoWAPI.ItemLoot = {
	GetExpansionLevel = function()
		return GetExpansionLevel()
	end,
	UnitName = function(unit)
		return UnitName(unit)
	end,
	UnitClass = function(unit)
		return UnitClass(unit)
	end,
	UnitLevel = function(unit)
		return UnitLevel(unit)
	end,
	IssecretValue = function(msg)
		return issecretvalue and issecretvalue(msg)
	end,
	GetPlayerGuid = function()
		return GetPlayerGuid()
	end,
	GetInventoryItemLink = function(unit, slot)
		return GetInventoryItemLink(unit, slot)
	end,
	GetItemQualityColor = function(quality)
		return C_Item.GetItemQualityColor(quality)
	end,
	GetCoinTextureString = function(price)
		return C_CurrencyInfo.GetCoinTextureString(price)
	end,
	CreateAtlasMarkup = function(icon, w, h, x, y)
		return CreateAtlasMarkup(icon, w, h, x, y)
	end,
	PlaySoundFile = function(sound)
		return PlaySoundFile(sound)
	end,
	GetAHPrice = function(itemLink)
		local ai = G_RLF.AuctionIntegrations
		if ai and ai.activeIntegration then
			return ai.activeIntegration:GetAHPrice(itemLink)
		end
		return nil
	end,
	GetItemInfo = function(link)
		return C.Item.GetItemInfo(link)
	end,
	GetItemIDForItemInfo = function(link)
		return C.Item.GetItemIDForItemInfo(link)
	end,
	GetItemCount = function(link, ...)
		return C.Item.GetItemCount(link, ...)
	end,
	GetItemStatDelta = function(link1, link2)
		return C.Item.GetItemStatDelta(link1, link2)
	end,
}

-- ── PartyLoot API Adapter ─────────────────────────────────────────────────────
-- Wraps UnitName, UnitClass, IsInRaid, IsInInstance, GetNumGroupMembers,
-- GetExpansionLevel, GetPlayerGuid, C_ClassColor, RAID_CLASS_COLORS,
-- issecretvalue, and the C_Everywhere item query for the PartyLoot feature module.
---@class RLF_WoWAPI_PartyLoot
G_RLF.WoWAPI.PartyLoot = {
	UnitName = function(unit)
		return UnitName(unit)
	end,
	UnitClass = function(unit)
		return UnitClass(unit)
	end,
	IssecretValue = function(msg)
		return issecretvalue and issecretvalue(msg)
	end,
	GetNumGroupMembers = function()
		return GetNumGroupMembers()
	end,
	IsInRaid = function()
		return IsInRaid()
	end,
	IsInInstance = function()
		return IsInInstance()
	end,
	GetExpansionLevel = function()
		return GetExpansionLevel()
	end,
	GetPlayerGuid = function()
		return GetPlayerGuid()
	end,
	GetClassColor = function(className)
		return C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(className)
	end,
	GetRaidClassColor = function(className)
		return RAID_CLASS_COLORS and RAID_CLASS_COLORS[className]
	end,
	GetItemInfo = function(itemLink)
		return C.Item.GetItemInfo(itemLink)
	end,
}

-- ── LootRolls API Adapter ─────────────────────────────────────────────────────
-- Wraps C_LootHistory (Retail only), RAID_CLASS_COLORS, and Item:CreateFromItemLink
-- for the LootRolls feature module.  HasLootHistory() guards all callers so the
-- module degrades gracefully on Classic clients where this API is absent.
---@class RLF_WoWAPI_LootRolls
G_RLF.WoWAPI.LootRolls = {
	HasLootHistory = function()
		return C_LootHistory ~= nil
	end,
	GetSortedInfoForDrop = function(encounterID, lootListID)
		return C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
	end,
	GetInfoForEncounter = function(encounterID)
		-- Returns EncounterLootInfo (encounterName, encounterID, startTime, duration) or nil.
		if C_LootHistory and C_LootHistory.GetInfoForEncounter then
			return C_LootHistory.GetInfoForEncounter(encounterID)
		end
		return nil
	end,
	GetRaidClassColor = function(className)
		return RAID_CLASS_COLORS and RAID_CLASS_COLORS[className]
	end,
	GetItemInfoIcon = function(itemLink)
		-- Returns the icon FileDataID (10th return value) or nil if not cached.
		return select(10, C.Item.GetItemInfo(itemLink))
	end,
	GetItemInfoQuality = function(itemLink)
		-- Returns the item quality (3rd return value) or nil if not cached.
		return select(3, C.Item.GetItemInfo(itemLink))
	end,
	CreateItemFromItemLink = function(itemLink)
		return Item:CreateFromItemLink(itemLink)
	end,

	-- ── Classic-only methods ──────────────────────────────────────────────────

	--- Returns true when the START_LOOT_ROLL event is available (Classic clients).
	--- Used by OnEnable to decide which event path to register.
	HasStartLootRollEvent = function()
		if G_RLF:IsRetail() then
			return false
		end
		-- START_LOOT_ROLL exists on all Classic flavors (Vanilla, TBC, Wrath, Cata).
		-- We detect it by checking for GetLootRollItemInfo which is always present
		-- alongside START_LOOT_ROLL on Classic clients.
		return GetLootRollItemInfo ~= nil
	end,

	--- Wraps GetLootRollItemInfo (Classic) per-item roll data.
	--- Returns table { texture, name, count, quality, canNeed, canGreed,
	--- canDisenchant, itemLink } or nil when rollID is invalid/expired.
	---@param rollID number
	---@return table|nil
	GetClassicRollItemInfo = function(rollID)
		if G_RLF:IsRetail() then
			return nil
		end
		if not GetLootRollItemInfo then
			return nil
		end
		local texture, name, count, quality, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
		if not texture then
			return nil
		end
		local itemLink = GetLootRollItemLink and GetLootRollItemLink(rollID) or nil
		return {
			texture = texture,
			name = name,
			count = count or 1,
			quality = quality,
			canNeed = canNeed,
			canGreed = canGreed,
			canDisenchant = canDisenchant,
			itemLink = itemLink,
		}
	end,

	--- Wraps RollOnLoot (Classic) to submit a roll choice.
	---@param rollID number
	---@param rollType number  0=Pass, 1=Need, 2=Greed, 3=Disenchant
	---@return boolean, string|nil
	ClassicRollOnLoot = function(rollID, rollType)
		if G_RLF:IsRetail() then
			return false, "ClassicRollOnLoot not available on Retail"
		end
		if not RollOnLoot then
			return false, "RollOnLoot not available"
		end
		if type(rollType) ~= "number" then
			return false, "invalid rollType: expected number, got " .. type(rollType)
		end
		RollOnLoot(rollID, rollType)
		return true
	end,

	--- Decodes Classic roll type number to human-readable label string.
	---@param rollType number
	---@return string|nil, string|nil
	DecodeClassicRollType = function(rollType)
		if type(rollType) ~= "number" then
			return nil, "invalid rollType: expected number, got " .. type(rollType)
		end
		-- On Retail: type 3 is TRANSMOG
		-- On Classic: type 3 is DISENCHANT
		local isRetail = G_RLF:IsRetail()
		local labels
		if isRetail then
			labels = { [0] = "PASS", [1] = "NEED", [2] = "GREED", [3] = "TRANSMOG" }
		else
			labels = { [0] = "PASS", [1] = "NEED", [2] = "GREED", [3] = "DISENCHANT" }
		end
		local label = labels[rollType]
		if label == nil then
			return nil, "unknown roll type: " .. tostring(rollType)
		end
		return label
	end,
	--- Gets button validity state for a loot roll.
	---@param rollID number
	---@return table { canNeed, canGreed, canTransmog, canPass, itemLink }
	GetRollButtonValidity = function(rollID)
		if not C_LootHistory then
			-- Classic path — handled by GetClassicRollItemInfo instead.
			return nil
		end
		-- Retail: GetLootRollItemInfo signature (13 values):
		-- texture, name, count, quality, bindOnPickUp,
		-- canNeed, canGreed, canDisenchant,
		-- reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired,
		-- canTransmog
		local _texture, _name, _count, _quality, _bindOnPickUp, canNeed, canGreed, _canDisenchant, _reasonNeed, _reasonGreed, _reasonDisenchant, _deSkillRequired, canTransmog =
			GetLootRollItemInfo(rollID)

		-- If the API returned nothing the roll frame may not be active yet.
		-- Return nil so the caller can decide to skip caching rather than
		-- storing a table of all-false values.
		if canNeed == nil and canGreed == nil and canTransmog == nil then
			return nil
		end

		return {
			canNeed = canNeed or false,
			canGreed = canGreed or false,
			canTransmog = canTransmog or false,
			canPass = true,
		}
	end,

	--- Wraps RollOnLoot to submit a roll choice.
	---@param rollID number
	---@param rollType number  0=Pass, 1=Need, 2=Greed, 3=Transmog
	---@return boolean, string|nil
	SubmitLootRoll = function(rollID, rollType)
		if not C_LootHistory then
			return false, "C_LootHistory not available (Classic client?)"
		end
		if type(rollType) ~= "number" then
			return false, "invalid rollType: expected number, got " .. type(rollType)
		end
		RollOnLoot(rollID, rollType)
		return true
	end,

	--- Decodes roll type name string to numeric roll type.
	---@param rollTypeName string  "NEED"|"GREED"|"TRANSMOG"|"PASS"
	---@return number|nil, string|nil
	DecodeRollType = function(rollTypeName)
		local typeMap = {
			NEED = 1,
			GREED = 2,
			PASS = 0,
			TRANSMOG = 4, -- TransmogButton id="4" in GroupLootFrame.xml
		}
		local rollType = typeMap[rollTypeName]
		if rollType == nil then
			return nil, "unknown roll type: " .. tostring(rollTypeName)
		end
		return rollType
	end,
}

return G_RLF.WoWAPI
