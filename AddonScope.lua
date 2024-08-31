-- Define the global scope early so that the whole addon can use it
G_RLF = {}
local addonName = "RPGLootFeed"
local dbName = addonName .. "DB"
local localeName = addonName .. "Locale"
G_RLF.RLF = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")
G_RLF.RLF:SetDefaultModuleState(true)
G_RLF.addonName = addonName
G_RLF.dbName = dbName
G_RLF.localeName = localeName
G_RLF.addonVersion = "@project-version@-@project-revision@-@project-abbreviated-hash@"
G_RLF.DisableBossBanner = {
	ENABLED = 0,
	FULLY_DISABLE = 1,
	DISABLE_LOOT = 2,
	DISABLE_MY_LOOT = 3,
	DISABLE_GROUP_LOOT = 4,
}

function G_RLF:Print(...)
	G_RLF.RLF:Print(...)
end

local xpcall = xpcall

local function errorhandler(err)
	local suffix = "\n\n==== Addon Info " .. G_RLF.addonName .. " " .. G_RLF.addonVersion .. " ====\n\n"
	suffix = suffix .. G_RLF.L["Issues"] .. "\n\n"

	return geterrorhandler()(err .. suffix)
end

function G_RLF:fn(func, ...)
	-- Borrowed from AceAddon-3.0
	if type(func) == "function" then
		return xpcall(func, errorhandler, ...)
	end
end
