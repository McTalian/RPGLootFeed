---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class GroupLootFrameOverride: RLF_Module, AceEvent-3.0, AceHook-3.0, AceTimer-3.0
local GroupLootFrameOverride =
	G_RLF.RLF:NewModule(G_RLF.BlizzModule.GroupLootFrame, "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")

-- Both Retail and Classic expose up to 4 simultaneous roll popup frames named
-- GroupLootFrame1–GroupLootFrame4.  Retail also has GroupLootContainer (a layout
-- manager), but the individual roll popups are always GroupLootFrame1–4.
local FRAME_COUNT = 4

function GroupLootFrameOverride:OnInitialize()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "GroupLootFrameHook")
	-- Also try to hook on first loot-roll event since the frames may not exist
	-- until the first roll of the session.
	self:RegisterEvent("LOOT_HISTORY_UPDATE_DROP", "AttemptLazyHook") -- Retail
	self:RegisterEvent("START_LOOT_ROLL", "AttemptLazyHook") -- Classic
end

function GroupLootFrameOverride:AttemptLazyHook()
	self:GroupLootFrameHook()
	-- Unregister once all four frames are hooked.
	local allHooked = true
	for i = 1, FRAME_COUNT do
		local frame = _G["GroupLootFrame" .. i]
		if frame and not self:IsHooked(frame, "Show") then
			allHooked = false
			break
		end
	end
	if allHooked then
		self:UnregisterEvent("LOOT_HISTORY_UPDATE_DROP")
		self:UnregisterEvent("START_LOOT_ROLL")
	end
end

local groupLootFrameAttempts = 0
function GroupLootFrameOverride:GroupLootFrameHook()
	-- GroupLootFrame1–4 may not exist until the first roll of the session,
	-- so hook whichever are present and retry until all are covered.
	local hookedAny = false
	for i = 1, FRAME_COUNT do
		local frame = _G["GroupLootFrame" .. i]
		if frame and not self:IsHooked(frame, "Show") then
			self:RawHook(frame, "Show", "InterceptGroupLootFrame", true)
			hookedAny = true
			G_RLF:LogDebug("GroupLootFrameOverride: hooked GroupLootFrame" .. i, addonName)
		end
	end
	if hookedAny then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	else
		-- "Use" the locale key so it doesn't get flagged as unused. We use it dynamically in the retryHook
		local _ = G_RLF.L["GroupLootFrameUnavailable"]
		groupLootFrameAttempts =
			G_RLF.retryHook(self, groupLootFrameAttempts, "GroupLootFrameHook", "GroupLootFrameUnavailable")
	end
end

function GroupLootFrameOverride:InterceptGroupLootFrame(frame)
	local lootRollsConfig = G_RLF.DbAccessor:AnyFeatureConfig("lootRolls") or {}
	if lootRollsConfig.disableLootRollFrame then
		-- Suppression enabled — hide the frame instead of showing it.
		frame:Hide()
	else
		-- Call through to the original Show method.
		self.hooks[frame].Show(frame)
	end
end

return GroupLootFrameOverride
