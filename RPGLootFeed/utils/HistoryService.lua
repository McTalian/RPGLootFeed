---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class HistoryService
G_RLF.HistoryService = {
	---@type boolean
	historyShown = false,
}

function G_RLF.HistoryService:ToggleHistoryFrame()
	if not G_RLF.db.global.lootHistory.enabled then
		return
	end

	local show = not self.historyShown
	self.historyShown = show

	local LootDisplay = G_RLF.LootDisplay
	for _, frame in LootDisplay:GetAllFrames() do
		if frame then
			if show then
				frame:ShowHistoryFrame()
			else
				frame:HideHistoryFrame()
			end
		end
	end
end

function G_RLF.HistoryService:HideHistoryFrame()
	if self.historyShown then
		self.historyShown = false
		local LootDisplay = G_RLF.LootDisplay
		for _, frame in LootDisplay:GetAllFrames() do
			if frame then
				frame:HideHistoryFrame()
			end
		end
	end
end
