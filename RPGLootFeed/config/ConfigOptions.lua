---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

G_RLF.ConfigHandlers = {}

local ConfigOptions = {}

---@class CachedFactionDetails
---@field repType RepType
---@field rank integer|string|nil
---@field standing integer
---@field rankStandingMin integer?
---@field rankStandingMax integer?

---@class RLF_DB
G_RLF.defaults = {
	---@class RLF_DBProfile
	profile = {},
	---@class RLF_DBLocale
	locale = {
		factionMap = {},
		accountWideFactionMap = {},
	},
	---@class RLF_DBChar
	char = {
		migrationVersion = 0,
		repFactions = {
			count = 0,
			---@type table<number, CachedFactionDetails>
			cachedFactionDetailsById = {},
		},
	},
	---@class RLF_DBGlobal
	global = {
		lastVersionLoaded = "v1.0.0",
		logger = {},
		migrationVersion = 0,
		notifications = {},
		guid = nil,
		warbandFactions = {
			count = 0,
			---@type table<number, CachedFactionDetails>
			cachedFactionDetailsById = {},
		},
	},
}

---@type table<string, number>
G_RLF.level1OptionsOrder = {
	["testMode"] = 1,
	["clearRows"] = 2,
	["lootHistory"] = 3,
	["features"] = 4,
	["positioning"] = 5,
	["sizing"] = 6,
	["styling"] = 7,
	["animations"] = 8,
	["blizz"] = 9,
	["about"] = -1,
}

G_RLF.options = {
	name = addonName,
	handler = ConfigOptions,
	type = "group",
	args = {
		testMode = {
			type = "execute",
			name = G_RLF.L["Toggle Test Mode"],
			func = function()
				local TestMode = G_RLF.RLF:GetModule(G_RLF.SupportModule.TestMode) --[[@as RLF_TestMode]]
				TestMode:ToggleTestMode()
			end,
			order = G_RLF.level1OptionsOrder.testMode,
		},
		clearRows = {
			type = "execute",
			name = G_RLF.L["Clear rows"],
			func = function()
				G_RLF.LootDisplay:HideLoot()
			end,
			order = G_RLF.level1OptionsOrder.clearRows,
		},
		lootHistory = {
			type = "execute",
			name = G_RLF.L["Toggle Loot History"],
			func = function()
				G_RLF.HistoryService:ToggleHistoryFrame()
			end,
			order = G_RLF.level1OptionsOrder.lootHistory,
		},
	},
}
