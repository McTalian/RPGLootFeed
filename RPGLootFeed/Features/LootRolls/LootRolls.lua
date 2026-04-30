---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
-- Every reference to the addon namespace is captured here so the module's full
-- dependency surface on G_RLF / ns is visible in one place.  Tests pass a
-- minimal mock ns to loadfile("LootRolls.lua") to control these at
-- injection time without the full nsMocks framework.
-- NOTE: G_RLF.db is intentionally absent – AceDB populates it in
-- OnInitialize, so it must remain a runtime lookup inside function bodies.
local LootElementBase = G_RLF.LootElementBase
local ItemQualEnum = G_RLF.ItemQualEnum
local DefaultIcons = G_RLF.DefaultIcons
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

-- ── WoW API / Global abstraction adapter ─────────────────────────────────────
-- The shared adapter lives in WoWAPIAdapters.lua (G_RLF.WoWAPI.LootRolls).
-- Captured here at module-load time so tests can override _lootRollsAdapter
-- per-test without patching _G.

---@class RLF_LootRolls: RLF_Module, AceEvent-3.0
local LootRolls = FeatureBase:new(FeatureModule.LootRolls, "AceEvent-3.0")

LootRolls._lootRollsAdapter = G_RLF.WoWAPI.LootRolls

-- Per-drop state tracker keyed by "encounterID_lootListID".
-- Each entry: { state = "pending"|"resolved"|"allPassed" }
-- Used to short-circuit further events once a drop reaches a terminal state
-- and to detect state transitions across LOOT_HISTORY_UPDATE_DROP fires.
LootRolls._dropStates = {}

-- Inline atlas markup for roll-state icons (matches Blizzard's LootHistory icons).
-- Width/height of 14 keeps the icon visually balanced with adjacent text.
-- Maps EncounterLootDropRollState numeric values → atlas markup.
local ROLL_STATE_ICONS = {
	[0] = "|A:lootroll-icon-need:14:14|a", -- NeedMainSpec
	[1] = "|A:lootroll-icon-need:14:14|a", -- NeedOffSpec (suffixed in label)
	[2] = "|A:lootroll-icon-transmog:14:14|a", -- Transmog
	[3] = "|A:lootroll-icon-greed:14:14|a", -- Greed
	[4] = "|A:lootroll-icon-pass:14:14|a", -- NoRoll (treated as Pass)
	[5] = "|A:lootroll-icon-pass:14:14|a", -- Pass
}

-- Short suffix for off-spec rolls; the icon is the same as Need so we need a
-- text marker to distinguish the intent.
local OFF_SPEC_SUFFIX = " (OS)"

-- EncounterLootDropRollState.NoRoll = 4 (player still deciding / hasn't rolled).
local ROLL_STATE_NO_ROLL = 4

-- Buffer (seconds) added to the pending row's exit timer so the row doesn't
-- fade out the instant Blizzard's roll window closes — gives the resolved
-- event a moment to arrive and update the row.
local PENDING_EXIT_BUFFER = 1.0

-- Returns the inline atlas + (optional) "(OS)" suffix for a roll state.
---@param state number  EncounterLootDropRollState value
---@return string  Atlas markup, optionally followed by " (OS)" for NeedOffSpec
local function GetRollIconLabel(state)
	local icon = ROLL_STATE_ICONS[state] or ""
	if state == 1 then
		return icon .. OFF_SPEC_SUFFIX
	end
	return icon
end

--- Returns a class-colored player name string, or the plain name as a fallback.
---@param playerName string
---@param playerClass string  Class token, e.g. "WARRIOR"
---@return string
local function GetColoredName(playerName, playerClass)
	local classColor = LootRolls._lootRollsAdapter.GetRaidClassColor(playerClass)
	if classColor then
		return classColor:WrapTextInColorCode(playerName)
	end
	return playerName
end

--- Returns the canonical state name for a dropInfo snapshot.
---@param dropInfo table
---@return "pending"|"resolved"|"allPassed"
local function ComputeState(dropInfo)
	if dropInfo.allPassed then
		return "allPassed"
	end
	if dropInfo.winner then
		return "resolved"
	end
	return "pending"
end

--- Computes how many seconds remain on a pending roll's auto-pass window.
--- Falls back to nil when startTime/duration are absent so the caller can use
--- the configured default.
---@param dropInfo table
---@return number|nil  seconds remaining (>= 1), or nil if unknown / already expired
local function GetRemainingPendingSeconds(dropInfo)
	if not dropInfo.startTime or not dropInfo.duration then
		return nil
	end
	-- startTime/duration from C_LootHistory are in seconds (GetTime() basis).
	local remaining = (dropInfo.startTime + dropInfo.duration) - GetTime()
	if remaining <= 0 then
		return nil
	end
	return remaining + PENDING_EXIT_BUFFER
end

--- Looks up the player's own roll in dropInfo.rollInfos (matched on isSelf=true).
---@param dropInfo table
---@return table|nil  rollInfo entry for the local player, or nil if absent
local function GetSelfRoll(dropInfo)
	if not dropInfo.rollInfos then
		return nil
	end
	for _, roll in ipairs(dropInfo.rollInfos) do
		if roll.isSelf then
			return roll
		end
	end
	return nil
end

--- Builds a uniform payload table for a loot roll drop in any state.
--- Returns nil when the module is disabled.
---
--- The payload always sets `quantity = 0` so re-fires on the same key flow
--- through the row's UpdateQuantity path without changing the displayed amount.
---@param encounterID number
---@param lootListID number
---@param dropInfo table  EncounterLootDropInfo as returned by C_LootHistory.GetSortedInfoForDrop
---@param state "pending"|"resolved"|"allPassed"
---@return RLF_ElementPayload?
function LootRolls:BuildPayload(encounterID, lootListID, dropInfo, state)
	if not LootRolls:IsEnabled() then
		return nil
	end

	local itemHyperlink = dropInfo.itemHyperlink
	local key = "LR_" .. encounterID .. "_" .. lootListID
	local lootRollsConfig = G_RLF.DbAccessor:AnyFeatureConfig("lootRolls") or {}

	local payload = {}

	payload.key = key
	payload.type = FeatureModule.LootRolls
	payload.isLink = true
	-- quantity = 0 — LootRolls rows are state machines, not stacking counts.
	-- A non-nil amount lets UpdateQuantity proceed without deferring forever.
	payload.quantity = 0

	-- Icon: try to resolve from item info cache.  The item is usually cached by
	-- the time roll results arrive; if not, the row renders without an icon.
	if lootRollsConfig.enableIcon and not G_RLF.db.global.misc.hideAllIcons then
		payload.icon = LootRolls._lootRollsAdapter.GetItemInfoIcon(itemHyperlink) or DefaultIcons.LOOTROLLS
	end

	-- Quality: resolve from item info cache; default to Uncommon if unavailable.
	payload.quality = LootRolls._lootRollsAdapter.GetItemInfoQuality(itemHyperlink) or ItemQualEnum.Uncommon

	-- Primary text: the item hyperlink (rendered as a clickable link).
	local link = itemHyperlink
	payload.textFn = function(_, truncatedLink)
		if not truncatedLink or truncatedLink == "" then
			return link
		end
		return truncatedLink
	end

	-- Secondary text: state-aware summary.
	if state == "allPassed" then
		payload.secondaryText = G_RLF.L["All Passed"]
	elseif state == "resolved" then
		local winner = dropInfo.winner
		local coloredName = GetColoredName(winner.playerName, winner.playerClass)
		local rollIcon = GetRollIconLabel(winner.state)
		local winnerText
		if winner.roll then
			winnerText = string.format(G_RLF.L["LootRolls_WonByFmt"], coloredName, rollIcon, winner.roll)
		else
			winnerText = string.format(G_RLF.L["LootRolls_WonByNoRollFmt"], coloredName)
		end
		-- Append personal roll context when the local player rolled and didn't win.
		local selfRoll = GetSelfRoll(dropInfo)
		if selfRoll and not selfRoll.isWinner and selfRoll.roll and selfRoll.state ~= ROLL_STATE_NO_ROLL then
			payload.secondaryText = string.format(G_RLF.L["LootRolls_WinnerWithSelfFmt"], winnerText, selfRoll.roll)
		else
			payload.secondaryText = winnerText
		end
	else
		-- Pending state: secondary text is static between events; the row's exit
		-- timer bar visualizes how long until rolls auto-pass (configured below
		-- via payload.showForSeconds).
		if dropInfo.isTied and dropInfo.currentLeader and dropInfo.currentLeader.roll then
			payload.secondaryText = string.format(G_RLF.L["LootRolls_TiedFmt"], dropInfo.currentLeader.roll)
		elseif dropInfo.currentLeader and dropInfo.currentLeader.roll then
			local coloredName = GetColoredName(dropInfo.currentLeader.playerName, dropInfo.currentLeader.playerClass)
			payload.secondaryText =
				string.format(G_RLF.L["LootRolls_CurrentLeaderFmt"], coloredName, dropInfo.currentLeader.roll)
		else
			payload.secondaryText = G_RLF.L["LootRolls_WaitingForRolls"]
		end

		-- Anchor the row's fade-out to Blizzard's actual roll-window expiry so
		-- the timer bar drains in lockstep with how long players have left to
		-- decide.  Falls back to the configured default when startTime/duration
		-- are unavailable (e.g. backfilled mid-roll without metadata).
		local remaining = GetRemainingPendingSeconds(dropInfo)
		if remaining then
			payload.showForSeconds = remaining
		end
	end

	-- Tooltip: hand off to TooltipBuilders with full dropInfo + encounter context.
	-- Re-query encounter info each time so tooltip stays current across renders.
	payload.customTooltipFn = function()
		local encounterInfo = LootRolls._lootRollsAdapter.GetInfoForEncounter
			and LootRolls._lootRollsAdapter.GetInfoForEncounter(encounterID)
		local encounterName = encounterInfo and encounterInfo.encounterName or nil
		local fresh = LootRolls._lootRollsAdapter.GetSortedInfoForDrop(encounterID, lootListID) or dropInfo
		if G_RLF.TooltipBuilders and G_RLF.TooltipBuilders.LootRolls then
			G_RLF.TooltipBuilders:LootRolls(fresh, encounterName, ComputeState(fresh))
		end
	end

	payload.IsEnabled = function()
		return LootRolls:IsEnabled()
	end

	return payload
end

--- Pushes a payload onto the message bus for the given drop snapshot.
---@param encounterID number
---@param lootListID number
---@param dropInfo table
---@param state "pending"|"resolved"|"allPassed"
function LootRolls:DispatchPayload(encounterID, lootListID, dropInfo, state)
	local payload = self:BuildPayload(encounterID, lootListID, dropInfo, state)
	if not payload then
		return
	end
	local element = LootElementBase:fromPayload(payload)
	element:Show()
end

function LootRolls:OnInitialize()
	if G_RLF.DbAccessor:IsFeatureNeededByAnyFrame("lootRolls") then
		self:Enable()
	else
		self:Disable()
	end
end

function LootRolls:OnEnable()
	LogDebug("OnEnable", addonName, self.moduleName)

	-- LOOT_HISTORY_UPDATE_DROP is Retail-only; guard before registering.
	if not IsRetail() then
		LogDebug("Skipping LootRolls registration — not Retail", addonName, self.moduleName)
		return
	end
	if not LootRolls._lootRollsAdapter.HasLootHistory() then
		LogWarn("C_LootHistory not available; LootRolls disabled", addonName, self.moduleName)
		return
	end

	self:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
end

function LootRolls:OnDisable()
	self:UnregisterAllEvents()
	-- Reset state so re-enabling presents fresh data.
	LootRolls._dropStates = {}
end

--- Fired whenever a specific drop entry changes — new roll cast, winner decided,
--- or all players passed.  We display the row at every state and let the
--- LootDisplay row pipeline merge updates onto the existing key.
---
--- The pending row's exit timer is set from dropInfo.startTime + duration so
--- the row's own fade-out countdown mirrors Blizzard's roll window — no
--- per-second ticker required.  Subsequent events from new rolls naturally
--- refresh the secondary text and reset the timer.
function LootRolls:LOOT_HISTORY_UPDATE_DROP(eventName, encounterID, lootListID)
	LogInfo(eventName, "WOWEVENT", self.moduleName, encounterID, lootListID)

	local dropInfo = LootRolls._lootRollsAdapter.GetSortedInfoForDrop(encounterID, lootListID)
	if not dropInfo then
		LogWarn("GetSortedInfoForDrop returned nil", addonName, self.moduleName, encounterID, lootListID)
		return
	end

	local dropKey = encounterID .. "_" .. lootListID
	local newState = ComputeState(dropInfo)
	local entry = LootRolls._dropStates[dropKey]

	-- Already in a terminal state — ignore further events for this drop.
	if entry and (entry.state == "resolved" or entry.state == "allPassed") then
		LogDebug("Drop already terminal, skipping", addonName, self.moduleName, encounterID, lootListID)
		return
	end

	-- Track or update state.
	if not entry then
		entry = { state = newState }
		LootRolls._dropStates[dropKey] = entry
	else
		entry.state = newState
	end

	-- Dispatch the current snapshot to the feed.
	self:DispatchPayload(encounterID, lootListID, dropInfo, newState)
end
