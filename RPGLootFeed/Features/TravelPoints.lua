---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's full
-- dependency surface on G_RLF / ns is visible in one place.  Tests pass a
-- minimal mock ns to loadfile("TravelPoints.lua") to control these at
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
local IsRetail = function()
	return G_RLF:IsRetail()
end
local RGBAToHexFormat = function(...)
	return G_RLF:RGBAToHexFormat(...)
end

-- ── WoW API / Global abstraction adapters ────────────────────────────────────
-- Each adapter wraps a surface of the WoW API or global state so the feature
-- code only deals with inputs and outputs.  These local tables are the
-- per-feature precursor to the planned top-level Abstractions/ folder; when
-- that consolidation happens, the adapter tables will simply be replaced with
-- references to the shared modules from that folder.

local PerksActivitiesAdapter = {
	GetPerksActivitiesInfo = function()
		return C_PerksActivities.GetPerksActivitiesInfo()
	end,
	GetPerksActivityInfo = function(activityID)
		return C_PerksActivities.GetPerksActivityInfo(activityID)
	end,
}

local GlobalStringsAdapter = {
	--- The locale string used as the label for Travel Points (e.g. "Traveler's Log").
	GetMonthlyActivitiesPointsLabel = function()
		return _G["MONTHLY_ACTIVITIES_POINTS"]
	end,
}

---@class RLF_TravelPoints: RLF_Module, AceEvent-3.0
local TravelPoints = FeatureBase:new(FeatureModule.TravelPoints, "AceEvent-3.0")
local currentTravelersJourney, maxTravelersJourney

TravelPoints._perksActivitiesAdapter = PerksActivitiesAdapter
TravelPoints._globalStringsAdapter = GlobalStringsAdapter

TravelPoints.Element = {}

function TravelPoints.Element:new(...)
	---@class TravelPoints.Element: RLF_BaseLootElement
	local element = LootElementBase:new()

	element.type = "TravelPoints"
	element.IsEnabled = function()
		return TravelPoints:IsEnabled()
	end

	element.key = "TRAVELPOINTS"
	element.quantity = ...
	element.r, element.g, element.b, element.a = unpack(G_RLF.db.global.travelPoints.textColor)
	element.textFn = function(existingAmount)
		return TravelPoints._globalStringsAdapter.GetMonthlyActivitiesPointsLabel()
			.. " + "
			.. ((existingAmount or 0) + element.quantity)
	end
	element.icon = DefaultIcons.TRAVELPOINTS
	if not G_RLF.db.global.travelPoints.enableIcon or G_RLF.db.global.misc.hideAllIcons then
		element.icon = nil
	end
	element.quality = ItemQualEnum.Common

	element.secondaryTextFn = function()
		if not currentTravelersJourney then
			return ""
		end
		if not maxTravelersJourney then
			return ""
		end

		local color = RGBAToHexFormat(element.r, element.g, element.b, element.a)

		return "    " .. color .. currentTravelersJourney .. "/" .. maxTravelersJourney .. "|r"
	end

	return element
end

--- Calculate the current and max values for the Travelers Journey
--- @param activityID? number
local function calcTravelersJourneyVal(activityID)
	local allInfo = TravelPoints._perksActivitiesAdapter.GetPerksActivitiesInfo()
	if allInfo == nil then
		LogWarn("Could not get all activity info", addonName, TravelPoints.moduleName)
		return
	end

	local progress = 0
	for i, v in ipairs(allInfo.activities) do
		if v.completed then
			progress = progress + v.thresholdContributionAmount
		elseif v.ID == activityID then
			progress = progress + v.thresholdContributionAmount
		end
	end

	local max = 0
	for i, v in ipairs(allInfo.thresholds) do
		max = math.max(max, v.requiredContributionAmount)
	end

	currentTravelersJourney = progress
	maxTravelersJourney = max
	LogDebug(
		"Current Travelers Journey " .. tostring(currentTravelersJourney) .. " / " .. tostring(maxTravelersJourney),
		addonName,
		TravelPoints.moduleName
	)
end

function TravelPoints:OnInitialize()
	if IsRetail() and G_RLF.db.global.travelPoints.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function TravelPoints:OnDisable()
	if not IsRetail() then
		return
	end
	self:UnregisterEvent("PERKS_ACTIVITY_COMPLETED")
end

function TravelPoints:OnEnable()
	if not IsRetail() then
		return
	end

	LogDebug("OnEnable", addonName, self.moduleName)
	self:RegisterEvent("PERKS_ACTIVITY_COMPLETED")
end

function TravelPoints:PERKS_ACTIVITY_COMPLETED(eventName, activityID)
	LogInfo(eventName, "WOWEVENT", self.moduleName, activityID)

	local info = TravelPoints._perksActivitiesAdapter.GetPerksActivityInfo(activityID)
	if info == nil then
		LogWarn("Could not get activity info", addonName, self.moduleName)
		return
	end
	local amount = info.thresholdContributionAmount
	calcTravelersJourneyVal(activityID)

	if amount > 0 then
		local e = self.Element:new(amount)
		e:Show()
	else
		LogWarn(eventName .. " fired but amount was not positive", addonName, self.moduleName)
	end
end

return TravelPoints
