---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class LootHistoryFrameOverride: RLF_Module, AceEvent-3.0, AceHook-3.0, AceTimer-3.0
local LootHistoryFrameOverride =
	G_RLF.RLF:NewModule(G_RLF.BlizzModule.LootHistoryFrame, "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")

function LootHistoryFrameOverride:OnInitialize()
	-- GroupLootHistoryFrame is Retail-only; guard before hooking.
	if not G_RLF:IsRetail() then
		return
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "LootHistoryFrameHook")
	-- GroupLootHistoryFrame loads lazily; also try once loot rolls begin.
	self:RegisterEvent("LOOT_HISTORY_UPDATE_DROP", "LootHistoryFrameHook")
end

local lootHistoryFrameAttempts = 0
function LootHistoryFrameOverride:LootHistoryFrameHook()
	if self:IsHooked(GroupLootHistoryFrame, "Show") then
		self:UnregisterEvent("LOOT_HISTORY_UPDATE_DROP")
		return
	end
	if GroupLootHistoryFrame then
		self:RawHook(GroupLootHistoryFrame, "Show", "InterceptGroupLootHistoryFrame", true)
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		self:UnregisterEvent("LOOT_HISTORY_UPDATE_DROP")
		-- The frame may have already shown before we could hook it.
		-- If suppression is enabled, close it immediately.
		if G_RLF.db.global.blizzOverrides.disableGroupLootHistoryFrame then
			GroupLootHistoryFrame:Hide()
		end
	else
		-- "Use" the locale key so it doesn't get flagged as unused. We use it dynamically in the retryHook
		local _ = G_RLF.L["GroupLootHistoryFrameUnavailable"]
		lootHistoryFrameAttempts =
			G_RLF.retryHook(self, lootHistoryFrameAttempts, "LootHistoryFrameHook", "GroupLootHistoryFrameUnavailable")
	end
end

function LootHistoryFrameOverride:InterceptGroupLootHistoryFrame(frame)
	if G_RLF.db.global.blizzOverrides.disableGroupLootHistoryFrame then
		-- Suppression enabled — keep the frame hidden.
		frame:Hide()
	else
		-- Call through to the original Show method.
		self.hooks[GroupLootHistoryFrame].Show(frame)
	end
end

return LootHistoryFrameOverride
