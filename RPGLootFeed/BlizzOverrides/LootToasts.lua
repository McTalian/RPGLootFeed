---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class LootToastOverride: RLF_Module, AceEvent-3.0, AceHook-3.0, AceTimer-3.0
local LootToastOverride =
	G_RLF.RLF:NewModule(G_RLF.BlizzModule.LootToasts, "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")

function LootToastOverride:OnInitialize()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "LootToastHook")
end

local lootAlertAttempts = 0
function LootToastOverride:LootToastHook()
	if self:IsHooked(LootAlertSystem, "AddAlert") then
		return
	end
	if LootAlertSystem and LootAlertSystem.AddAlert then
		self:RawHook(LootAlertSystem, "AddAlert", "InterceptAddAlert", true)
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	else
		-- "Use" the locale key so it doesn't get flagged as unused. We use it dynamically in the retryHook
		local _ = G_RLF.L["AddLootAlertUnavailable"]
		lootAlertAttempts = G_RLF.retryHook(self, lootAlertAttempts, "LootToastHook", "AddLootAlertUnavailable")
	end
end

function LootToastOverride:InterceptAddAlert(frame, ...)
	if G_RLF.db.global.blizzOverrides.disableBlizzLootToasts then
		return
	end
	-- Call the original AddAlert function if not blocked
	self.hooks[LootAlertSystem].AddAlert(frame, ...)
end

return LootToastOverride
