---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

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

return G_RLF.WoWAPI.Reputation
