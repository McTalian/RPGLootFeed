---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class MoneyAlertOverride: RLF_Module, AceEvent-3.0, AceHook-3.0, AceTimer-3.0
local MoneyAlertOverride =
	G_RLF.RLF:NewModule(G_RLF.BlizzModule.MoneyAlerts, "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")

function MoneyAlertOverride:OnInitialize()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "MoneyAlertHook")
end

local moneyAlertAttempts = 0
function MoneyAlertOverride:MoneyAlertHook()
	if self:IsHooked(MoneyWonAlertSystem, "AddAlert") then
		return
	end
	if MoneyWonAlertSystem and MoneyWonAlertSystem.AddAlert then
		self:RawHook(MoneyWonAlertSystem, "AddAlert", "InterceptMoneyAddAlert", true)
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	else
		-- "Use" the locale key so it doesn't get flagged as unused. We use it dynamically in the retryHook
		local _ = G_RLF.L["AddMoneyAlertUnavailable"]
		moneyAlertAttempts = G_RLF.retryHook(self, moneyAlertAttempts, "MoneyAlertHook", "AddMoneyAlertUnavailable")
	end
end

function MoneyAlertOverride:InterceptMoneyAddAlert(frame, ...)
	if G_RLF.db.global.blizzOverrides.disableBlizzMoneyAlerts then
		return
	end
	-- Call the original AddAlert function if not blocked
	self.hooks[MoneyWonAlertSystem].AddAlert(frame, ...)
end

return MoneyAlertOverride
