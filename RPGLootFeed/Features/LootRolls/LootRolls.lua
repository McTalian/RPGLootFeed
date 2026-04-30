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
local RollStates = G_RLF.RollStates
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
-- Each entry: {
--   state = "pending"|"resolved"|"allPassed"  (roll/loot outcome state),
--   phase = "pending"|"result"|"resolved"|"cancelled"  (row display lifecycle phase),
-- }
-- `state` tracks the roll outcome; `phase` tracks the row display lifecycle
-- used by S04 dismiss gating (dismiss disabled while phase is "pending" or "result").
-- Phase transitions: pending → result (on LOOT_HISTORY_UPDATE_DROP arrival)
--                   result  → resolved (on winner/allPassed detection)
--                   any     → cancelled (on CANCEL_LOOT_ROLL)
LootRolls._dropStates = {}

-- Button validity cache keyed by "encounterID_lootListID".
LootRolls._buttonValidityCache = {}

-- Pending action queue: keyed by rollID, value = { itemLink, rollType, rollValue, timestamp }.
-- Populated by START_LOOT_ROLL and MAIN_SPEC_NEED_ROLL when the player submits an
-- action through the RPGLootFeed buttons. Consumed (and removed) by the matching
-- logic in MatchActionToResult when a LOOT_HISTORY_UPDATE_DROP arrives.
-- Entries are keyed by rollID (number) for O(1) enqueue/dequeue.
LootRolls._pendingActions = {}

-- Retail staging: keyed by rollID, value = { validity = table, itemLink = string }.
-- Populated by START_LOOT_ROLL (which fires before LOOT_HISTORY_UPDATE_DROP).
-- Absorbed into _buttonValidityCache once LOOT_HISTORY_UPDATE_DROP fires for
-- the matching item — matched by itemHyperlink since there is no API to
-- cross-reference rollID → (encounterID, lootListID) directly.
LootRolls._stagedRollValidity = {}

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

-- Fallback duration (seconds) for the action phase when rollTime is unavailable.
local ACTION_PHASE_FALLBACK_SECONDS = 121.0 -- 120s + 1s buffer

--- Returns the configured fade-out delay for resolved rows.
--- Falls back to PENDING_EXIT_BUFFER when the config is not yet populated.
---@return number  seconds to display a resolved row before fade-out
local function GetFadeOutDelay()
	local anim = G_RLF.db and G_RLF.db.global and G_RLF.db.global.animations
	if anim and anim.exit and anim.exit.fadeOutDelay and anim.exit.fadeOutDelay > 0 then
		return anim.exit.fadeOutDelay
	end
	return 5.0 -- Safe default if db not yet initialised
end

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
---@return G_RLF.RollStates
local function ComputeState(dropInfo)
	if dropInfo.allPassed then
		return RollStates.ALL_PASSED
	end
	if dropInfo.winner then
		return RollStates.RESOLVED
	end
	return RollStates.PENDING
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

--- Advances a _dropStates entry to the next row lifecycle phase, with logging.
--- Transitions are one-directional and guarded — resolved/cancelled are terminal.
---@param entry table  _dropStates entry (must be non-nil)
---@param newPhase string  target phase: "pending"|"result"|"resolved"|"cancelled"
---@param dropKey string  for logging
local function AdvancePhase(entry, newPhase, dropKey)
	local oldPhase = entry.phase or "pending"
	if oldPhase == newPhase then
		return -- no-op: re-fire protection
	end
	-- Terminal phases cannot regress (cancelled is a hard override from CANCEL_LOOT_ROLL).
	if oldPhase == "resolved" or oldPhase == "cancelled" then
		LogDebug(
			"Row phase transition skipped (terminal): %s -> %s (%s)",
			addonName,
			"LootRolls",
			oldPhase,
			newPhase,
			dropKey
		)
		return
	end
	entry.phase = newPhase
	LogDebug("Row phase transition: %s -> %s (%s)", addonName, "LootRolls", oldPhase, newPhase, dropKey)
end

--- Returns the current row lifecycle phase for a given dropKey, or "pending" if unknown.
--- Used by dismiss gating (S04/T02) and tests.
---@param dropKey string  the "_dropStates" key (e.g. "1001_2")
---@return string  "pending"|"result"|"resolved"|"cancelled"
function LootRolls:GetRowPhase(dropKey)
	local entry = LootRolls._dropStates[dropKey]
	return entry and entry.phase or "pending"
end

--- Builds a uniform payload table for a loot roll drop in any state.
--- Returns nil when the module is disabled.
---
--- The payload always sets `quantity = 0` so re-fires on the same key flow
--- through the row's UpdateQuantity path without changing the displayed amount.
---@param encounterID number
---@param lootListID number
---@param dropInfo table  EncounterLootDropInfo as returned by C_LootHistory.GetSortedInfoForDrop
---@param state G_RLF.RollStates
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

	-- ── Phase-aware timer: showForSeconds ────────────────────────────────────
	-- Each row lifecycle phase uses a distinct display duration:
	--   pending / result → remaining roll-window time (from dropInfo.startTime + duration)
	--                       or full dropInfo.duration when startTime is absent
	--   resolved / allPassed → exit.fadeOutDelay from config (reader time)
	-- We compute and log the timer here so it appears in every BuildPayload call,
	-- regardless of which branch sets secondaryText.
	local rowPhaseForTimer = (LootRolls._dropStates[encounterID .. "_" .. lootListID] or {}).phase or "pending"
	if state == RollStates.RESOLVED or state == RollStates.ALL_PASSED then
		-- Final phase: use the configured fade-out delay.
		local delay = GetFadeOutDelay()
		payload.showForSeconds = delay
		LogDebug(
			"Row %s timer update: phase=%s, duration=%.1fs",
			addonName,
			"LootRolls",
			"LR_" .. encounterID .. "_" .. lootListID,
			rowPhaseForTimer,
			delay
		)
	else
		-- Pending / result phase: anchor to Blizzard's roll-window expiry.
		local remaining = GetRemainingPendingSeconds(dropInfo)
		if remaining then
			payload.showForSeconds = remaining
			LogDebug(
				"Row %s timer update: phase=%s, duration=%.1fs",
				addonName,
				"LootRolls",
				"LR_" .. encounterID .. "_" .. lootListID,
				rowPhaseForTimer,
				remaining
			)
		elseif not dropInfo.startTime and dropInfo.duration and dropInfo.duration > 0 then
			-- startTime absent (backfilled mid-roll) — use full duration.
			local dur = dropInfo.duration + PENDING_EXIT_BUFFER
			payload.showForSeconds = dur
			LogDebug(
				"Row %s timer update: phase=%s, duration=%.1fs (no startTime, full duration)",
				addonName,
				"LootRolls",
				"LR_" .. encounterID .. "_" .. lootListID,
				rowPhaseForTimer,
				dur
			)
		end
		-- If neither remaining nor duration is available the row will fall back
		-- to the global fadeOutDelay set by BootstrapFromElement.
	end

	-- Secondary text: state-aware summary.
	if state == RollStates.ALL_PASSED then
		payload.secondaryText = G_RLF.L["All Passed"]
	elseif state == RollStates.RESOLVED then
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
		local dropEntry2 = LootRolls._dropStates[encounterID .. "_" .. lootListID]
		local playerSelection = dropEntry2 and dropEntry2.playerSelection
		if selfRoll and not selfRoll.isWinner and selfRoll.roll and selfRoll.state ~= ROLL_STATE_NO_ROLL then
			if playerSelection then
				local selectionLabel = G_RLF.L["LootRolls_YouSelected_" .. playerSelection] or playerSelection
				payload.secondaryText = string.format(
					G_RLF.L["LootRolls_WinnerWithSelfAndSelectionFmt"],
					winnerText,
					selectionLabel,
					selfRoll.roll
				)
			else
				payload.secondaryText = string.format(G_RLF.L["LootRolls_WinnerWithSelfFmt"], winnerText, selfRoll.roll)
			end
		else
			payload.secondaryText = winnerText
		end
	else
		-- Pending state: secondary text depends on whether the local player has
		-- already submitted a button click (actionPhase == "waiting").
		local dropKey2 = encounterID .. "_" .. lootListID
		local dropEntry2a = LootRolls._dropStates[dropKey2]
		if dropEntry2a and dropEntry2a.actionPhase == "waiting" then
			-- Player clicked a button — show selection + "Waiting for results" overlay.
			-- buttons are suppressed by clearing buttonValidity below.
			local selLabel = dropEntry2a.playerSelection
					and (G_RLF.L["LootRolls_YouSelected_" .. dropEntry2a.playerSelection] or dropEntry2a.playerSelection)
				or nil
			if selLabel then
				payload.secondaryText = selLabel .. "  |  " .. G_RLF.L["LootRolls_WaitingForResults"]
			else
				payload.secondaryText = G_RLF.L["LootRolls_WaitingForResults"]
			end
		elseif dropInfo.isTied and dropInfo.currentLeader and dropInfo.currentLeader.roll then
			payload.secondaryText = string.format(G_RLF.L["LootRolls_TiedFmt"], dropInfo.currentLeader.roll)
		elseif dropInfo.currentLeader and dropInfo.currentLeader.roll then
			local coloredName = GetColoredName(dropInfo.currentLeader.playerName, dropInfo.currentLeader.playerClass)
			payload.secondaryText =
				string.format(G_RLF.L["LootRolls_CurrentLeaderFmt"], coloredName, dropInfo.currentLeader.roll)
		else
			payload.secondaryText = G_RLF.L["LootRolls_WaitingForRolls"]
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

	-- Button validity from cache.
	-- When actionPhase=="waiting" (player already clicked a button) suppress
	-- buttons so the row shows the "Waiting for results" overlay instead.
	local dropKey = encounterID .. "_" .. lootListID
	local dropEntryForButtons = LootRolls._dropStates[dropKey]
	local cached = LootRolls._buttonValidityCache[dropKey]
	if cached and not (dropEntryForButtons and dropEntryForButtons.actionPhase == "waiting") then
		payload.buttonValidity = {
			canNeed = cached.canNeed,
			canGreed = cached.canGreed,
			canTransmog = cached.canTransmog,
			canDisenchant = cached.canDisenchant,
			canPass = cached.canPass,
		}
	end

	-- Player selection from drop state.
	local dropEntry = LootRolls._dropStates[dropKey]
	if dropEntry and dropEntry.playerSelection then
		payload.playerSelection = dropEntry.playerSelection
	end

	-- rollID from the START_LOOT_ROLL event — required by RollOnLoot() for
	-- button clicks.  Only set on Retail (Classic uses lootListID as a stand-in).
	if dropEntry and dropEntry.rollID then
		payload.rollID = dropEntry.rollID
	end

	payload.encounterID = encounterID
	payload.lootListID = lootListID
	payload.rollState = state

	-- Expose row lifecycle phase for dismiss gating (S04/T02).
	-- phase: "pending"|"result" = dismiss locked; "resolved"|"cancelled" = dismiss enabled.
	local dropEntryForPhase = LootRolls._dropStates[dropKey]
	payload.rowPhase = dropEntryForPhase and dropEntryForPhase.phase or "pending"

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

	if IsRetail() then
		-- Retail path: C_LootHistory drives the state machine.
		if not LootRolls._lootRollsAdapter.HasLootHistory() then
			LogWarn("C_LootHistory not available; LootRolls disabled", addonName, self.moduleName)
			return
		end
		-- START_LOOT_ROLL fires first (with rollID + GetLootRollItemLink available),
		-- giving us the button validity and item link before LOOT_HISTORY_UPDATE_DROP
		-- arrives with the encounterID/lootListID we need for the cache key.
		self:RegisterEvent("START_LOOT_ROLL")
		self:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
		-- MAIN_SPEC_NEED_ROLL fires after the server confirms a Need roll for
		-- the local player, carrying the actual numeric roll value.  We update
		-- the pending action's rollValue so multi-drop matching can use it.
		self:RegisterEvent("MAIN_SPEC_NEED_ROLL")
		-- CANCEL_LOOT_ROLL fires when the roll window closes for a specific rollID.
		-- CANCEL_ALL_LOOT_ROLLS fires when all active roll windows are closed at once.
		-- Both events are Retail-side signals we use to purge stale pending slots.
		self:RegisterEvent("CANCEL_LOOT_ROLL")
		self:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
		LogDebug(
			"Registered START_LOOT_ROLL + LOOT_HISTORY_UPDATE_DROP + MAIN_SPEC_NEED_ROLL"
				.. " + CANCEL_LOOT_ROLL + CANCEL_ALL_LOOT_ROLLS (Retail)",
			addonName,
			self.moduleName
		)
	else
		-- Classic path: START_LOOT_ROLL / LOOT_ROLLS_COMPLETE drive the state machine.
		if
			not LootRolls._lootRollsAdapter.HasStartLootRollEvent
			or not LootRolls._lootRollsAdapter.HasStartLootRollEvent()
		then
			LogWarn("START_LOOT_ROLL not available; LootRolls disabled on Classic", addonName, self.moduleName)
			return
		end
		self:RegisterEvent("START_LOOT_ROLL")
		self:RegisterEvent("LOOT_ROLLS_COMPLETE")
		-- Cancel events are available on Classic as well; register them so stale
		-- pending slots are cleaned up regardless of client flavour.
		self:RegisterEvent("CANCEL_LOOT_ROLL")
		self:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
		LogDebug(
			"Registered START_LOOT_ROLL + LOOT_ROLLS_COMPLETE"
				.. " + CANCEL_LOOT_ROLL + CANCEL_ALL_LOOT_ROLLS (Classic)",
			addonName,
			self.moduleName
		)
	end

	-- Hook RollOnLoot (Retail + Classic) so every button click — whether from
	-- RPGLootFeed buttons or the built-in Blizzard loot frame — updates the
	-- pending queue entry for this rollID with the confirmed rollType.
	-- hooksecurefunc fires AFTER the secure call so the actual RollOnLoot()
	-- goes through unimpeded; we just record the intent.
	if hooksecurefunc then
		hooksecurefunc("RollOnLoot", function(rollID, numericType)
			LootRolls:OnRollButtonClick(rollID, numericType)
		end)
		LogDebug("OnEnable: hooked RollOnLoot via hooksecurefunc", addonName, self.moduleName)
	end
end

function LootRolls:OnDisable()
	self:UnregisterAllEvents()
	-- Reset state so re-enabling presents fresh data.
	LootRolls._dropStates = {}
	LootRolls._buttonValidityCache = {}
	LootRolls._stagedRollValidity = {}
	LootRolls._pendingActions = {}
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

	local dropInfo = self._lootRollsAdapter.GetSortedInfoForDrop(encounterID, lootListID)
	if not dropInfo then
		LogWarn("GetSortedInfoForDrop returned nil", addonName, self.moduleName, encounterID, lootListID)
		return
	end

	local dropKey = encounterID .. "_" .. lootListID
	local newState = ComputeState(dropInfo)
	local entry = self._dropStates[dropKey]

	-- Already in a terminal state — ignore further events for this drop.
	if entry and (entry.state == "resolved" or entry.state == "allPassed") then
		LogDebug("Drop already terminal, skipping", addonName, self.moduleName, encounterID, lootListID)
		return
	end

	-- Track or update state.
	if not entry then
		entry = { state = newState, phase = "pending" }
		self._dropStates[dropKey] = entry
		LogDebug("Row phase transition: (new) -> pending (%s)", addonName, "LootRolls", dropKey)
	else
		entry.state = newState
	end

	-- Advance row lifecycle phase based on the new roll state.
	if newState == RollStates.RESOLVED or newState == RollStates.ALL_PASSED then
		AdvancePhase(entry, "resolved", dropKey)
	else
		-- Data arrived but roll still in progress — transition to "result" phase.
		AdvancePhase(entry, "result", dropKey)
	end

	-- Absorb staged validity from START_LOOT_ROLL (Retail).
	-- START_LOOT_ROLL fires first and stages { validity, itemLink } keyed by rollID.
	-- We match on itemHyperlink because there is no API to map rollID → lootListID.
	if newState == "pending" and not self._buttonValidityCache[dropKey] then
		local itemLink = dropInfo.itemHyperlink
		if itemLink and itemLink ~= "" then
			-- Scan staging for the rollID whose item link matches this drop.
			local matchedRollID = nil
			for rollID, staged in pairs(self._stagedRollValidity) do
				if staged.itemLink == itemLink then
					matchedRollID = rollID
					break
				end
			end
			if matchedRollID then
				self._buttonValidityCache[dropKey] = self._stagedRollValidity[matchedRollID].validity
				self._stagedRollValidity[matchedRollID] = nil
				entry.rollID = matchedRollID
				LogDebug(
					"Absorbed staged validity via item link match",
					addonName,
					self.moduleName,
					dropKey,
					matchedRollID
				)
			else
				LogDebug(
					"No staged validity found for drop; buttons may be hidden",
					addonName,
					self.moduleName,
					dropKey,
					itemLink
				)
			end
		end
	end

	-- Diagnostic sweep: log any pending actions that have been waiting >10s.
	-- This surfaces entries where the player used the built-in Blizzard UI or
	-- a network delay caused the result to arrive before the action was enqueued.
	self:ScanUnmatchedPendingActions()

	-- ── S03: Match incoming drop result against pending player action ─────────
	-- Attempt to pair this drop event with an action the player submitted via
	-- the RPGLootFeed buttons (or the built-in Blizzard loot frame via the hook).
	-- • On match: the pending action is removed from the queue and the log entry
	--   confirms the action-result pairing (verifiable in S06 live-raid validation).
	-- • On no-match (terminal drop): player rolled via a different path or used
	--   the built-in Blizzard UI; logged at WARN for S06 diagnostics.
	-- • On no-match (still pending): normal — result not yet resolved; no warning.
	local matchedRollID, matchedAction = self:MatchActionToResult(encounterID, lootListID, dropInfo)
	if matchedRollID then
		-- ── State transition: waiting → resolved ──────────────────────────────
		-- Clear actionPhase so _dropStates accurately reflects action was confirmed.
		-- Record playerSelection from the matched action (preserve any pre-set value
		-- from OnRollButtonClick, fall back to matchedAction.rollType when nil).
		-- The or-idiom ensures OnRollButtonClick-set values are never overwritten.
		entry.actionPhase = nil
		if matchedAction and matchedAction.rollType ~= nil then
			entry.playerSelection = entry.playerSelection or matchedAction.rollType
		end
		LogDebug(
			"LOOT_HISTORY_UPDATE_DROP: playerSelection recorded",
			addonName,
			self.moduleName,
			"playerSelection=" .. tostring(entry.playerSelection),
			"source=" .. (entry.playerSelection and "matchedAction" or "nil")
		)
		LogDebug(
			"LOOT_HISTORY_UPDATE_DROP: matched action consumed — state transition waiting → resolved",
			addonName,
			self.moduleName,
			"encounterID=" .. tostring(encounterID),
			"lootListID=" .. tostring(lootListID),
			"rollID=" .. tostring(matchedRollID),
			"itemLink=" .. tostring(matchedAction and matchedAction.itemLink),
			"rollType=" .. tostring(matchedAction and matchedAction.rollType),
			"age="
				.. (
					matchedAction
						and string.format("%.2f", self:CurrentTimestamp() - matchedAction.timestamp) .. "s"
					or "?"
				)
		)
	elseif newState == RollStates.RESOLVED or newState == RollStates.ALL_PASSED then
		-- Terminal result arrived with no matching pending action.
		-- This is expected when the player rolled via the built-in Blizzard UI,
		-- but also fires when the player used the RPGLootFeed buttons but the
		-- action arrived outside the match window or was already consumed.
		-- Logged at WARN so S06 live-raid validation can surface mismatches.
		LogWarn(
			"LOOT_HISTORY_UPDATE_DROP: unmatched terminal drop (no pending action found)",
			addonName,
			self.moduleName,
			"encounterID=" .. tostring(encounterID),
			"lootListID=" .. tostring(lootListID),
			"itemLink=" .. tostring(dropInfo.itemHyperlink),
			"state=" .. tostring(newState)
		)
	end

	-- Dispatch the current snapshot to the feed.
	self:DispatchPayload(encounterID, lootListID, dropInfo, newState)
end

-- ── Classic roll state machine ────────────────────────────────────────────────

--- Builds a simplified dropInfo table from Classic GetClassicRollItemInfo data.
---@param rollID number
---@param rollTime number  seconds until roll auto-closes
---@param itemInfo table  result from GetClassicRollItemInfo
---@return table
local function BuildClassicDropInfo(rollID, rollTime, itemInfo)
	return {
		itemHyperlink = itemInfo.itemLink or "",
		winner = nil,
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		startTime = GetTime(),
		duration = rollTime,
		_classicRollID = rollID,
	}
end

--- Fired when a group loot roll window opens.
--- On Retail: fires before LOOT_HISTORY_UPDATE_DROP; we stage validity + item
---   link keyed by rollID so the history handler can absorb it by item link.
---   Also pre-enqueues a pending action entry (rollType=nil) so the queue slot
---   is ready for MAIN_SPEC_NEED_ROLL or button-click updates (S02).
--- On Classic: drives the full state machine directly.
function LootRolls:START_LOOT_ROLL(eventName, rollID, rollTime)
	LogInfo(eventName, "WOWEVENT", self.moduleName, rollID, rollTime)

	if IsRetail() then
		-- Retail: GetLootRollItemLink + GetRollButtonValidity are valid right now.
		-- Stage both so LOOT_HISTORY_UPDATE_DROP can absorb by item link.
		local itemLink = LootRolls._lootRollsAdapter.GetRetailRollItemLink(rollID)
		if not itemLink then
			LogDebug(
				"START_LOOT_ROLL (Retail): GetRetailRollItemLink returned nil — no staging",
				addonName,
				self.moduleName,
				rollID
			)
			return
		end
		local validity = LootRolls._lootRollsAdapter.GetRollButtonValidity(rollID)
		if validity then
			LootRolls._stagedRollValidity[rollID] = { validity = validity, itemLink = itemLink }
			LogDebug(
				"START_LOOT_ROLL (Retail): staged validity for rollID",
				addonName,
				self.moduleName,
				rollID,
				itemLink,
				validity.canNeed,
				validity.canGreed,
				validity.canTransmog
			)
		else
			LogDebug(
				"START_LOOT_ROLL (Retail): GetRollButtonValidity returned nil — no staging",
				addonName,
				self.moduleName,
				rollID
			)
		end
		-- Pre-enqueue a pending action slot (rollType=nil; updated by
		-- MAIN_SPEC_NEED_ROLL or S02 button-click hook).  This ensures the
		-- queue entry exists as soon as the roll window opens so that
		-- MAIN_SPEC_NEED_ROLL can update it atomically.
		self:EnqueueAction(rollID, itemLink, nil, nil)
		LogDebug("START_LOOT_ROLL (Retail): pre-enqueued pending action", addonName, self.moduleName, rollID, itemLink)
		return
	end

	local itemInfo = LootRolls._lootRollsAdapter.GetClassicRollItemInfo(rollID)
	if not itemInfo or not itemInfo.itemLink then
		LogDebug("GetClassicRollItemInfo returned nil or no itemLink — skipping", addonName, self.moduleName, rollID)
		return
	end

	local dropKey = rollID .. "_" .. rollID
	local entry = LootRolls._dropStates[dropKey]

	if entry and (entry.state == "resolved" or entry.state == "allPassed") then
		LogDebug("Classic drop already terminal, skipping", addonName, self.moduleName, rollID)
		return
	end

	if not entry then
		entry = { state = "pending", phase = "pending", _isClassic = true, _rollID = rollID }
		LootRolls._dropStates[dropKey] = entry
		LogDebug("Row phase transition: (new) -> pending (%s)", addonName, "LootRolls", dropKey)
	else
		entry.state = "pending"
		AdvancePhase(entry, "pending", dropKey)
	end
	LogDebug("Classic drop state → pending", addonName, self.moduleName, rollID)

	if not LootRolls._buttonValidityCache[dropKey] then
		local validity = {
			canNeed = itemInfo.canNeed,
			canGreed = itemInfo.canGreed,
			canTransmog = false,
			canDisenchant = itemInfo.canDisenchant,
			canPass = true,
			isCached = true,
		}
		LootRolls._buttonValidityCache[dropKey] = validity
		LogDebug(
			"Cached Classic button validity",
			addonName,
			self.moduleName,
			dropKey,
			validity.canNeed,
			validity.canGreed,
			validity.canDisenchant
		)
	end

	local dropInfo = BuildClassicDropInfo(rollID, rollTime, itemInfo)
	entry._dropInfo = dropInfo
	-- Pre-enqueue a pending action slot for Classic (rollType=nil; S02 button-
	-- click hook will update with the actual rollType when the player clicks).
	self:EnqueueAction(rollID, itemInfo.itemLink, nil, nil)
	LogDebug(
		"START_LOOT_ROLL (Classic): pre-enqueued pending action",
		addonName,
		self.moduleName,
		rollID,
		itemInfo.itemLink
	)
	self:DispatchClassicPayload(rollID, dropInfo, "pending", itemInfo)
end

--- Fired on Classic when all rolls for a loot item have concluded.
function LootRolls:LOOT_ROLLS_COMPLETE(eventName, lootHandle)
	LogInfo(eventName, "WOWEVENT", self.moduleName, lootHandle)

	for dropKey, entry in pairs(LootRolls._dropStates) do
		if entry.state == "pending" and entry._isClassic then
			entry.state = "allPassed"
			AdvancePhase(entry, "resolved", dropKey)
			LogDebug("Classic drop state → allPassed via LOOT_ROLLS_COMPLETE", addonName, self.moduleName, dropKey)

			LootRolls._buttonValidityCache[dropKey] = nil

			local cachedDropInfo = entry._dropInfo
			if cachedDropInfo then
				cachedDropInfo.allPassed = true
				self:DispatchClassicPayload(entry._rollID, cachedDropInfo, "allPassed", nil)
			end
		end
	end
end

--- Fired by the server (Retail only) when the local player's main-spec Need
--- roll has been registered.  Carries the actual numeric roll value (rollValue).
---
--- This handler updates the pending action entry for this rollID (pre-populated
--- by START_LOOT_ROLL) to set rollType="NEED" and the confirmed rollValue.
--- If no pending entry exists (e.g. player used the Blizzard UI instead of the
--- RPGLootFeed buttons), the call is a no-op.
---
--- Event signature (Retail): MAIN_SPEC_NEED_ROLL(eventName, rollID, rollValue)
---   rollID    – same rollID from START_LOOT_ROLL
---   rollValue – the numeric result of the Need roll (1–100)
function LootRolls:MAIN_SPEC_NEED_ROLL(eventName, rollID, rollValue)
	LogInfo(eventName, "WOWEVENT", self.moduleName, rollID, rollValue)

	local entry = self._pendingActions[rollID]
	if not entry then
		LogDebug(
			"MAIN_SPEC_NEED_ROLL: no pending action for rollID — player may have used Blizzard UI",
			addonName,
			self.moduleName,
			rollID,
			rollValue
		)
		return
	end

	-- Update the pending slot with confirmed Need roll data.
	entry.rollType = "NEED"
	entry.rollValue = rollValue
	LogDebug(
		"MAIN_SPEC_NEED_ROLL: updated pending action",
		addonName,
		self.moduleName,
		"rollID=" .. tostring(rollID),
		"rollValue=" .. tostring(rollValue),
		"itemLink=" .. tostring(entry.itemLink)
	)
end

--- Fired when a pending roll is cancelled (e.g. item distributed directly by ML,
--- or the roll window closes without resolution).
--- Advances the matching drop's phase to 'cancelled' so dismiss gating releases.
--- Releases the dismiss lock on any active row whose key matches dropKey.
--- Called after a phase transition to "cancelled" or "resolved" so the row
--- becomes right-click-dismissible immediately, without waiting for the next
--- LOOT_HISTORY_UPDATE_DROP re-fire.
---@param dropKey string
local function ReleaseDismissLock(dropKey)
	-- Row key in LootDisplay is prefixed with "LR_" (from BuildPayload's
	-- key = "LR_" .. encounterID .. "_" .. lootListID).  Classic keys are
	-- stored as rollID_rollID in _dropStates but dispatched under
	-- "LR_" .. rollID .. "_" .. rollID (from BuildClassicPayload).
	local rowKey = "LR_" .. dropKey
	local LootDisplay = G_RLF.LootDisplay
	if not LootDisplay then
		return
	end
	for _, frame in LootDisplay:GetAllFrames() do
		if frame then
			local row = frame:GetRow(rowKey)
			if row and row.SetClickThrough then
				row:SetClickThrough(false)
				LogDebug("Row %s dismiss lock released (phase=cancelled/resolved)", addonName, "LootRolls", rowKey)
			end
		end
	end
end

function LootRolls:CANCEL_LOOT_ROLL(eventName, rollID)
	LogInfo(eventName, "WOWEVENT", self.moduleName, rollID)

	-- Clear any staged validity for this rollID.
	if LootRolls._stagedRollValidity and LootRolls._stagedRollValidity[rollID] then
		LogDebug("CANCEL_LOOT_ROLL: clearing staged validity for rollID=%s", addonName, self.moduleName, rollID)
		LootRolls._stagedRollValidity[rollID] = nil
	end

	-- Clear any pending action slot for this rollID.
	local pendingEntry = self._pendingActions[rollID]
	if pendingEntry then
		self._pendingActions[rollID] = nil
		LogDebug(
			"CANCEL_LOOT_ROLL: removed pending action",
			addonName,
			self.moduleName,
			"rollID=" .. tostring(rollID),
			"rollType=" .. tostring(pendingEntry.rollType),
			"itemLink=" .. tostring(pendingEntry.itemLink),
			"reason=explicit_cancel"
		)
	else
		LogDebug(
			"CANCEL_LOOT_ROLL: no pending action for rollID — already matched or built-in UI used",
			addonName,
			self.moduleName,
			rollID
		)
	end

	-- Attempt to find the _dropStates entry whose rollID matches and advance phase.
	for dropKey, entry in pairs(LootRolls._dropStates) do
		if entry.rollID == rollID or (entry._isClassic and entry._rollID == rollID) then
			if entry.phase ~= "resolved" and entry.phase ~= "cancelled" then
				AdvancePhase(entry, "cancelled", dropKey)
				LogDebug(
					"CANCEL_LOOT_ROLL: phase → cancelled (%s) rollID=%s",
					addonName,
					self.moduleName,
					dropKey,
					rollID
				)
				ReleaseDismissLock(dropKey)
			end
			return
		end
	end

	-- Also handle Classic dropKey pattern (rollID_rollID).
	local classicKey = tostring(rollID) .. "_" .. tostring(rollID)
	local classicEntry = LootRolls._dropStates[classicKey]
	if classicEntry and classicEntry.phase ~= "resolved" and classicEntry.phase ~= "cancelled" then
		AdvancePhase(classicEntry, "cancelled", classicKey)
		LogDebug(
			"CANCEL_LOOT_ROLL: Classic phase → cancelled (%s) rollID=%s",
			addonName,
			self.moduleName,
			classicKey,
			rollID
		)
		ReleaseDismissLock(classicKey)
	end
end

--- Dispatches a Classic roll payload onto the feed.
function LootRolls:DispatchClassicPayload(rollID, dropInfo, state, itemInfo)
	local payload = self:BuildClassicPayload(rollID, dropInfo, state, itemInfo)
	if not payload then
		return
	end
	local element = LootElementBase:fromPayload(payload)
	element:Show()
end

--- Builds a payload for a Classic loot roll.
---@return RLF_ElementPayload?
function LootRolls:BuildClassicPayload(rollID, dropInfo, state, itemInfo)
	if not LootRolls:IsEnabled() then
		return nil
	end

	local dropKey = rollID .. "_" .. rollID
	local lootRollsConfig = G_RLF.DbAccessor:AnyFeatureConfig("lootRolls") or {}

	local payload = {}

	payload.key = "LR_" .. rollID .. "_" .. rollID
	payload.type = FeatureModule.LootRolls
	payload.isLink = true
	payload.quantity = 0

	if lootRollsConfig.enableIcon and not G_RLF.db.global.misc.hideAllIcons then
		if itemInfo and itemInfo.texture then
			payload.icon = itemInfo.texture
		elseif dropInfo.itemHyperlink and dropInfo.itemHyperlink ~= "" then
			payload.icon = LootRolls._lootRollsAdapter.GetItemInfoIcon(dropInfo.itemHyperlink) or DefaultIcons.LOOTROLLS
		else
			payload.icon = DefaultIcons.LOOTROLLS
		end
	end

	if itemInfo and itemInfo.quality then
		payload.quality = itemInfo.quality
	else
		payload.quality = (dropInfo.itemHyperlink and dropInfo.itemHyperlink ~= "")
				and LootRolls._lootRollsAdapter.GetItemInfoQuality(dropInfo.itemHyperlink)
			or ItemQualEnum.Uncommon
	end

	local link = dropInfo.itemHyperlink
	payload.textFn = function(_, truncatedLink)
		if not truncatedLink or truncatedLink == "" then
			return link
		end
		return truncatedLink
	end

	-- ── Phase-aware timer: showForSeconds (Classic) ──────────────────────────
	-- Same phase contract as BuildPayload:
	--   pending / result → remaining or full duration from dropInfo
	--   allPassed / resolved → exit.fadeOutDelay from config
	local classicPhaseForTimer = (LootRolls._dropStates[dropKey] or {}).phase or "pending"
	if state == "allPassed" or state == "resolved" then
		local delay = GetFadeOutDelay()
		payload.showForSeconds = delay
		LogDebug(
			"Row %s timer update: phase=%s, duration=%.1fs",
			addonName,
			"LootRolls",
			"LR_" .. rollID .. "_" .. rollID,
			classicPhaseForTimer,
			delay
		)
	else
		local remaining = GetRemainingPendingSeconds(dropInfo)
		if remaining then
			payload.showForSeconds = remaining
			LogDebug(
				"Row %s timer update: phase=%s, duration=%.1fs",
				addonName,
				"LootRolls",
				"LR_" .. rollID .. "_" .. rollID,
				classicPhaseForTimer,
				remaining
			)
		elseif not dropInfo.startTime and dropInfo.duration and dropInfo.duration > 0 then
			local dur = dropInfo.duration + PENDING_EXIT_BUFFER
			payload.showForSeconds = dur
			LogDebug(
				"Row %s timer update: phase=%s, duration=%.1fs (no startTime, action fallback)",
				addonName,
				"LootRolls",
				"LR_" .. rollID .. "_" .. rollID,
				classicPhaseForTimer,
				dur
			)
		end
	end

	if state == "allPassed" or state == "resolved" then
		payload.secondaryText = G_RLF.L["All Passed"]
	else
		-- When the player has already clicked a button (actionPhase=="waiting"),
		-- show their selection + "Waiting for results" instead of roll progress.
		local classicDropEntry = LootRolls._dropStates[dropKey]
		if classicDropEntry and classicDropEntry.actionPhase == "waiting" then
			local selLabel = classicDropEntry.playerSelection
					and (G_RLF.L["LootRolls_YouSelected_" .. classicDropEntry.playerSelection] or classicDropEntry.playerSelection)
				or nil
			if selLabel then
				payload.secondaryText = selLabel .. "  |  " .. G_RLF.L["LootRolls_WaitingForResults"]
			else
				payload.secondaryText = G_RLF.L["LootRolls_WaitingForResults"]
			end
		else
			payload.secondaryText = G_RLF.L["LootRolls_WaitingForRolls"]
		end
	end

	payload.customTooltipFn = function()
		if G_RLF.TooltipBuilders and G_RLF.TooltipBuilders.LootRolls then
			G_RLF.TooltipBuilders:LootRolls(dropInfo, nil, state)
		end
	end

	local cached = LootRolls._buttonValidityCache[dropKey]
	local classicDropEntryForButtons = LootRolls._dropStates[dropKey]
	if cached and not (classicDropEntryForButtons and classicDropEntryForButtons.actionPhase == "waiting") then
		payload.buttonValidity = {
			canNeed = cached.canNeed,
			canGreed = cached.canGreed,
			canTransmog = cached.canTransmog,
			canDisenchant = cached.canDisenchant,
			canPass = cached.canPass,
		}
	end

	local dropEntry = LootRolls._dropStates[dropKey]
	if dropEntry and dropEntry.playerSelection then
		payload.playerSelection = dropEntry.playerSelection
	end

	payload.encounterID = rollID
	payload.lootListID = rollID
	payload.rollState = state

	-- Expose row lifecycle phase for dismiss gating (S04/T02).
	local classicDropEntryForPhase = LootRolls._dropStates[dropKey]
	payload.rowPhase = classicDropEntryForPhase and classicDropEntryForPhase.phase or "pending"

	payload.IsEnabled = function()
		return LootRolls:IsEnabled()
	end

	return payload
end

-- ── Pending action queue API ──────────────────────────────────────────────────
-- These four functions provide the public interface for the pending queue.
-- S02 calls EnqueueAction() when the player clicks a roll button.
-- S03 calls ScanPendingActions() on LOOT_HISTORY_UPDATE_DROP.
-- S01/T03 registers CANCEL_LOOT_ROLL / CANCEL_ALL_LOOT_ROLLS which call
-- DequeueAction() / ClearAllPendingActions().

--- Returns the current monotonic timestamp (GetTime() equivalent).
--- Abstracted so tests can inject a deterministic clock without touching _G.
---@return number
function LootRolls:CurrentTimestamp()
	return GetTime()
end

--- Returns the elapsed seconds since a stored timestamp.
---@param timestamp number  result of a prior CurrentTimestamp() call
---@return number  elapsed seconds (>= 0)
function LootRolls:TimestampDelta(timestamp)
	return self:CurrentTimestamp() - timestamp
end

--- Enqueues a player action awaiting result-row matching.
--- Safe to call concurrently from START_LOOT_ROLL and MAIN_SPEC_NEED_ROLL;
--- each rollID is independent so there are no cross-entry ordering concerns.
---@param rollID     number  WoW roll identifier
---@param itemLink   string  item hyperlink from the loot roll window
---@param rollType   string  "NEED" | "GREED" | "TRANSMOG" | "PASS" | "DISENCHANT"
---@param rollValue  number|nil  numeric roll result (only available for NEED after MAIN_SPEC_NEED_ROLL)
function LootRolls:EnqueueAction(rollID, itemLink, rollType, rollValue)
	local ts = self:CurrentTimestamp()
	self._pendingActions[rollID] = {
		itemLink = itemLink,
		rollType = rollType,
		rollValue = rollValue,
		timestamp = ts,
	}
	LogDebug(
		"EnqueueAction",
		addonName,
		self.moduleName,
		"rollID=" .. tostring(rollID),
		"rollType=" .. tostring(rollType),
		"rollValue=" .. tostring(rollValue),
		"itemLink=" .. tostring(itemLink),
		"ts=" .. tostring(ts)
	)
end

--- Removes and returns a pending action by rollID.
--- Returns nil when no matching entry exists (e.g. user rolled via Blizzard UI).
---@param rollID number
---@return table|nil  the removed action entry, or nil
function LootRolls:DequeueAction(rollID)
	local entry = self._pendingActions[rollID]
	if entry then
		self._pendingActions[rollID] = nil
		local delta = self:TimestampDelta(entry.timestamp)
		LogDebug(
			"DequeueAction",
			addonName,
			self.moduleName,
			"rollID=" .. tostring(rollID),
			"rollType=" .. tostring(entry.rollType),
			"itemLink=" .. tostring(entry.itemLink),
			"age=" .. string.format("%.2f", delta) .. "s"
		)
	else
		LogDebug("DequeueAction: no entry for rollID", addonName, self.moduleName, tostring(rollID))
	end
	return entry
end

--- Scans all pending actions and calls matchFn(rollID, action) for each one.
--- matchFn should return true to signal a match; ScanPendingActions returns the
--- first matching {rollID, action} pair, or nil when no entry matches.
--- The matched entry is removed from the queue automatically.
---
--- Iteration is performed over a snapshot of keys so matchFn may safely call
--- DequeueAction() on other rollIDs without corrupting the loop.
---@param matchFn fun(rollID: number, action: table): boolean
---@return number|nil, table|nil  matchedRollID, matchedAction
function LootRolls:ScanPendingActions(matchFn)
	-- Collect keys first to prevent mid-iteration mutation.
	local keys = {}
	for rollID in pairs(self._pendingActions) do
		keys[#keys + 1] = rollID
	end

	LogDebug("ScanPendingActions: scanning", addonName, self.moduleName, tostring(#keys) .. " entries")

	for _, rollID in ipairs(keys) do
		local action = self._pendingActions[rollID]
		-- Entry may have been removed by a prior matchFn call; guard before invoking.
		if action and matchFn(rollID, action) then
			self._pendingActions[rollID] = nil
			local delta = self:TimestampDelta(action.timestamp)
			LogDebug(
				"ScanPendingActions: matched",
				addonName,
				self.moduleName,
				"rollID=" .. tostring(rollID),
				"rollType=" .. tostring(action.rollType),
				"itemLink=" .. tostring(action.itemLink),
				"age=" .. string.format("%.2f", delta) .. "s"
			)
			return rollID, action
		end
	end

	LogDebug("ScanPendingActions: no match found", addonName, self.moduleName)
	return nil, nil
end

--- Fired when all active loot-roll windows are closed simultaneously (e.g.
--- raid ends, zone change, GM command).  Clears all pending action slots using
--- the key-snapshot pattern (MEM051/MEM073) to prevent Lua table iteration
--- corruption.
---
--- Event signature: CANCEL_ALL_LOOT_ROLLS(eventName)
function LootRolls:CANCEL_ALL_LOOT_ROLLS(eventName)
	LogInfo(eventName, "WOWEVENT", self.moduleName)
	self:ClearAllPendingActions()
	LogDebug("CANCEL_ALL_LOOT_ROLLS: pending queue cleared", addonName, self.moduleName, "reason=all_cancel")
end

-- ── Button click handler ─────────────────────────────────────────────────────
-- Maps WoW's numeric RollOnLoot type argument to the canonical rollType string
-- used by the pending queue.  Called via hooksecurefunc("RollOnLoot", ...) so
-- the Blizzard secure call proceeds unblocked while we update the pending slot.

--- WoW RollOnLoot numeric rollType → pending queue rollType string.
--- 0 = Pass, 1 = Need (main spec), 2 = Greed, 4 = Transmog.
--- Returns nil for any unrecognised value so the queue entry is not
--- corrupted with a bogus string.
---@param numericType number  second argument to RollOnLoot()
---@return string|nil  "NEED" | "GREED" | "TRANSMOG" | "PASS" | nil
local function NumericRollTypeToString(numericType)
	if numericType == 0 then
		return "PASS"
	elseif numericType == 1 then
		return "NEED"
	elseif numericType == 2 then
		return "GREED"
	elseif numericType == 4 then
		return "TRANSMOG"
	end
	return nil
end

--- Called (via hooksecurefunc) immediately after the player's RollOnLoot()
--- secure call fires.  Updates the pending queue entry for this rollID
--- with the confirmed rollType so MatchActionToResult can use it.
---
--- Design notes:
---   • START_LOOT_ROLL pre-enqueues an entry with rollType=nil.  This handler
---     fills in the rollType once the player actually clicks a button.
---   • For NEED rolls MAIN_SPEC_NEED_ROLL will fire shortly after and fill in
---     the numeric rollValue; we leave rollValue nil here.
---   • If no pending entry exists (player re-rolled or queue was cleared) we
---     log a warning but do not crash — the call already went through.
---
---@param rollID      number  WoW roll identifier (first arg to RollOnLoot)
---@param numericType number  WoW roll type integer (second arg to RollOnLoot)
function LootRolls:OnRollButtonClick(rollID, numericType)
	local rollType = NumericRollTypeToString(numericType)
	local ts = self:CurrentTimestamp()

	LogDebug(
		"OnRollButtonClick",
		addonName,
		self.moduleName,
		"rollID=" .. tostring(rollID),
		"numericType=" .. tostring(numericType),
		"rollType=" .. tostring(rollType),
		"ts=" .. tostring(ts)
	)

	if rollType == nil then
		LogWarn(
			"OnRollButtonClick: unrecognised numericType — pending entry not updated",
			addonName,
			self.moduleName,
			"rollID=" .. tostring(rollID),
			"numericType=" .. tostring(numericType)
		)
		return
	end

	local entry = self._pendingActions[rollID]
	if not entry then
		LogWarn(
			"OnRollButtonClick: no pending entry for rollID — EnqueueAction was not called yet or entry was removed",
			addonName,
			self.moduleName,
			"rollID=" .. tostring(rollID),
			"rollType=" .. tostring(rollType)
		)
		-- Fallback: create a new entry so the click is not silently dropped.
		-- itemLink is unknown at this point; leave it nil and let MatchActionToResult
		-- filter it out via the itemLink gate.
		self:EnqueueAction(rollID, nil, rollType, nil)
		return
	end

	-- Update the existing pending slot with the confirmed rollType.
	entry.rollType = rollType
	entry.timestamp = ts
	LogDebug(
		"OnRollButtonClick: updated pending entry",
		addonName,
		self.moduleName,
		"rollID=" .. tostring(rollID),
		"rollType=" .. tostring(rollType),
		"itemLink=" .. tostring(entry.itemLink)
	)

	-- ── State transition: pending → waiting ───────────────────────────────
	-- Scan _dropStates for the entry associated with this rollID and mark it
	-- as "waiting" (player submitted; result pending from server).
	-- Also set playerSelection so payload builders can render "You: Need | Waiting..."
	-- For Classic: dropKey == rollID.."_"..rollID; for Retail: entry.rollID is stored.
	local dropKeyForRollID = nil
	for dk, ds in pairs(self._dropStates) do
		if
			ds._rollID == rollID
			or ds.rollID == rollID
			or (ds._isClassic and dk == tostring(rollID) .. "_" .. tostring(rollID))
		then
			dropKeyForRollID = dk
			break
		end
	end

	if dropKeyForRollID then
		local dsEntry = self._dropStates[dropKeyForRollID]
		dsEntry.actionPhase = "waiting"
		dsEntry.playerSelection = rollType
		LogDebug(
			"OnRollButtonClick: state → waiting",
			addonName,
			self.moduleName,
			"rollID=" .. tostring(rollID),
			"dropKey=" .. tostring(dropKeyForRollID),
			"rollType=" .. tostring(rollType),
			"ts=" .. tostring(ts)
		)

		-- Re-dispatch the row so the UI immediately reflects the "waiting" state
		-- (buttons disabled, secondaryText shows selection + "Waiting for results").
		if dsEntry._isClassic then
			-- Classic: use cached dropInfo + itemInfo from _dropStates entry.
			local cachedDropInfo = dsEntry._dropInfo
			if cachedDropInfo then
				self:DispatchClassicPayload(rollID, cachedDropInfo, "pending", nil)
			end
		else
			-- Retail: look up fresh dropInfo via encounterID + lootListID embedded in dropKey.
			local encID, llID = dropKeyForRollID:match("^(%d+)_(%d+)$")
			if encID and llID then
				local freshDropInfo = self._lootRollsAdapter.GetSortedInfoForDrop(tonumber(encID), tonumber(llID))
				if freshDropInfo then
					self:DispatchPayload(tonumber(encID), tonumber(llID), freshDropInfo, "pending")
				else
					LogWarn(
						"OnRollButtonClick: GetSortedInfoForDrop returned nil for re-dispatch",
						addonName,
						self.moduleName,
						"dropKey=" .. tostring(dropKeyForRollID)
					)
				end
			end
		end
	else
		LogWarn(
			"OnRollButtonClick: no _dropStates entry found for rollID — state not transitioned to waiting",
			addonName,
			self.moduleName,
			"rollID=" .. tostring(rollID),
			"rollType=" .. tostring(rollType)
		)
	end
end

-- ── Multi-drop matching ────────────────────────────────────────────────────
-- MATCH_WINDOW_SECONDS defines the maximum age of a pending action that is
-- still eligible for matching.  Actions older than this are considered stale
-- and are logged as unmatched for S06 live-raid diagnostics.
local MATCH_WINDOW_SECONDS = 12

-- STALE_PENDING_LOG_SECONDS: pending actions older than this are surfaced by
-- ScanUnmatchedPendingActions() as diagnostic warnings.  Set lower than
-- MATCH_WINDOW_SECONDS so we log the warning before the action becomes
-- completely ineligible for matching.
local STALE_PENDING_LOG_SECONDS = 10

--- Maps a rollInfo.state integer to the canonical rollType string used by the
--- pending queue.  Returns nil for unrecognised / no-roll states.
---@param rollInfoState number  EncounterLootDropRollState enum value
---@return string|nil  "NEED" | "GREED" | "TRANSMOG" | "PASS" | nil
local function RollInfoStateToRollType(rollInfoState)
	-- EncounterLootDropRollState:
	--   0 = NeedMainSpec  → NEED
	--   1 = NeedOffSpec   → NEED (same button, same queue type)
	--   2 = Transmog      → TRANSMOG
	--   3 = Greed         → GREED
	--   4 = NoRoll        → nil  (player has not yet decided; not matchable)
	--   5 = Pass          → PASS
	if rollInfoState == 0 or rollInfoState == 1 then
		return "NEED"
	elseif rollInfoState == 2 then
		return "TRANSMOG"
	elseif rollInfoState == 3 then
		return "GREED"
	elseif rollInfoState == 5 then
		return "PASS"
	end
	return nil
end

--- Attempts to match a LOOT_HISTORY_UPDATE_DROP result row against a pending
--- player action from the queue.
---
--- Matching rules (all must pass):
---   1. Temporal window: pending action must be ≤ MATCH_WINDOW_SECONDS old.
---   2. itemLink equality: action.itemLink == dropInfo.itemHyperlink.
---   3. For NEED rolls: action.rollValue == selfRoll.roll (numeric result).
---      For all other types: action.rollType == derived rollType.
---
--- When a match is found the entry is removed from the queue and returned.
--- Returns nil, nil when no match is found.
---
---@param encounterID number  passed through for logging only
---@param lootListID  number  passed through for logging only
---@param dropInfo    table   EncounterLootDropInfo from C_LootHistory
---@return number|nil, table|nil  matchedRollID, matchedPendingAction
function LootRolls:MatchActionToResult(encounterID, lootListID, dropInfo)
	local dropItemLink = dropInfo and dropInfo.itemHyperlink
	if not dropItemLink or dropItemLink == "" then
		LogWarn(
			"MatchActionToResult: dropInfo.itemHyperlink is nil/empty — cannot match",
			addonName,
			self.moduleName,
			"encounterID=" .. tostring(encounterID),
			"lootListID=" .. tostring(lootListID)
		)
		return nil, nil
	end

	-- Determine the player's own roll state from the drop result.
	local selfRoll = GetSelfRoll(dropInfo)
	local selfRollType = selfRoll and RollInfoStateToRollType(selfRoll.state) or nil
	local selfRollValue = selfRoll and selfRoll.roll or nil

	LogDebug(
		"MatchActionToResult: begin scan",
		addonName,
		self.moduleName,
		"encounterID=" .. tostring(encounterID),
		"lootListID=" .. tostring(lootListID),
		"dropItemLink=" .. tostring(dropItemLink),
		"selfRollType=" .. tostring(selfRollType),
		"selfRollValue=" .. tostring(selfRollValue)
	)

	local now = self:CurrentTimestamp()

	local matchedRollID, matchedAction = self:ScanPendingActions(function(rollID, action)
		local age = now - action.timestamp
		local itemMatch = action.itemLink == dropItemLink

		-- ── Temporal gate ───────────────────────────────────────────────────
		if age > MATCH_WINDOW_SECONDS then
			LogDebug(
				"MatchActionToResult: SKIP (out-of-window)",
				addonName,
				self.moduleName,
				"rollID=" .. tostring(rollID),
				"age=" .. string.format("%.2f", age) .. "s",
				"window=" .. tostring(MATCH_WINDOW_SECONDS) .. "s",
				"itemLink=" .. tostring(action.itemLink)
			)
			return false
		end

		-- ── Item link gate ──────────────────────────────────────────────────
		if not itemMatch then
			LogDebug(
				"MatchActionToResult: SKIP (itemLink mismatch)",
				addonName,
				self.moduleName,
				"rollID=" .. tostring(rollID),
				"actionItemLink=" .. tostring(action.itemLink),
				"dropItemLink=" .. tostring(dropItemLink),
				"age=" .. string.format("%.2f", age) .. "s"
			)
			return false
		end

		-- ── Roll type / value gate ──────────────────────────────────────────
		-- For NEED rolls: match on the numeric rollValue (unique per player per
		-- drop, so two concurrent NEEDs on the same item are distinguishable).
		-- For all other types: match on rollType string equality.
		--
		-- Guard: a nil rollType means the player has not yet clicked a button
		-- (the slot was pre-enqueued by START_LOOT_ROLL but MAIN_SPEC_NEED_ROLL
		-- and OnRollButtonClick have not yet fired).  Such an entry is not
		-- matchable — skip it so it is not consumed prematurely.
		if action.rollType == nil then
			LogDebug(
				"MatchActionToResult: SKIP (rollType nil — button not yet clicked)",
				addonName,
				self.moduleName,
				"rollID=" .. tostring(rollID),
				"age=" .. string.format("%.2f", age) .. "s"
			)
			return false
		end
		if action.rollType == "NEED" then
			-- Require both sides to be NEED with the same numeric result.
			if selfRollType ~= "NEED" then
				LogDebug(
					"MatchActionToResult: SKIP (pending=NEED but drop selfRollType mismatch)",
					addonName,
					self.moduleName,
					"rollID=" .. tostring(rollID),
					"selfRollType=" .. tostring(selfRollType),
					"age=" .. string.format("%.2f", age) .. "s"
				)
				return false
			end
			if action.rollValue ~= selfRollValue then
				LogDebug(
					"MatchActionToResult: SKIP (NEED rollValue mismatch)",
					addonName,
					self.moduleName,
					"rollID=" .. tostring(rollID),
					"actionRollValue=" .. tostring(action.rollValue),
					"selfRollValue=" .. tostring(selfRollValue),
					"age=" .. string.format("%.2f", age) .. "s"
				)
				return false
			end
		else
			-- Non-NEED: match on rollType string equality.
			if action.rollType ~= selfRollType then
				LogDebug(
					"MatchActionToResult: SKIP (rollType mismatch)",
					addonName,
					self.moduleName,
					"rollID=" .. tostring(rollID),
					"actionRollType=" .. tostring(action.rollType),
					"selfRollType=" .. tostring(selfRollType),
					"age=" .. string.format("%.2f", age) .. "s"
				)
				return false
			end
		end

		-- All gates passed.
		local delta = now - action.timestamp
		LogDebug(
			"MatchActionToResult: MATCH",
			addonName,
			self.moduleName,
			"rollID=" .. tostring(rollID),
			"rollType=" .. tostring(action.rollType),
			"rollValue=" .. tostring(action.rollValue),
			"itemLink=" .. tostring(action.itemLink),
			"temporalDelta=" .. string.format("%.2f", delta) .. "s"
		)
		return true
	end)

	if matchedRollID then
		LogInfo(
			"MatchActionToResult: matched rollID=" .. tostring(matchedRollID),
			addonName,
			self.moduleName,
			"encounterID=" .. tostring(encounterID),
			"lootListID=" .. tostring(lootListID),
			"rollType=" .. tostring(matchedAction and matchedAction.rollType),
			"temporalDelta=" .. tostring(matchedAction and string.format("%.2f", now - matchedAction.timestamp) .. "s")
		)
	else
		LogDebug(
			"MatchActionToResult: no match",
			addonName,
			self.moduleName,
			"encounterID=" .. tostring(encounterID),
			"lootListID=" .. tostring(lootListID),
			"dropItemLink=" .. tostring(dropItemLink),
			"selfRollType=" .. tostring(selfRollType)
		)
	end

	return matchedRollID, matchedAction
end

--- Used by CANCEL_ALL_LOOT_ROLLS and OnDisable.
--- Iterates over a snapshot of rollIDs to prevent Lua table iteration corruption
--- (MEM051 pattern: collect keys → iterate snapshot → delete).
function LootRolls:ClearAllPendingActions()
	-- Snapshot the keys first.
	local toRemove = {}
	for rollID in pairs(self._pendingActions) do
		toRemove[#toRemove + 1] = rollID
	end

	LogDebug("ClearAllPendingActions", addonName, self.moduleName, "clearing " .. tostring(#toRemove) .. " entries")

	for _, rollID in ipairs(toRemove) do
		local action = self._pendingActions[rollID]
		if action then
			local delta = self:TimestampDelta(action.timestamp)
			LogDebug(
				"ClearAllPendingActions: removing",
				addonName,
				self.moduleName,
				"rollID=" .. tostring(rollID),
				"rollType=" .. tostring(action.rollType),
				"itemLink=" .. tostring(action.itemLink),
				"age=" .. string.format("%.2f", delta) .. "s"
			)
			self._pendingActions[rollID] = nil
		end
	end
end

--- Scans _pendingActions for entries older than STALE_PENDING_LOG_SECONDS and
--- logs a diagnostic warning for each one.  Does NOT remove stale entries —
--- a network-delayed LOOT_HISTORY_UPDATE_DROP may still match them.
---
--- Called from LOOT_HISTORY_UPDATE_DROP so every incoming drop event triggers
--- a queue health sweep.  The summary line ("X pending; Y unmatched >10s") is
--- emitted at DEBUG level and is consumable by S06 live-raid validation.
---
--- Possible causes for a stale entry (noted in each log line):
---   - Player used the built-in Blizzard loot window instead of RPGLootFeed buttons.
---   - Network delay between action submission and server acknowledgment.
---   - Roll cancelled before result arrived (CANCEL_LOOT_ROLL not yet processed).
function LootRolls:ScanUnmatchedPendingActions()
	local now = self:CurrentTimestamp()
	local total = 0
	local staleCount = 0

	-- Snapshot keys (MEM051: collect → iterate snapshot → never delete mid-scan).
	local keys = {}
	for rollID in pairs(self._pendingActions) do
		keys[#keys + 1] = rollID
		total = total + 1
	end

	for _, rollID in ipairs(keys) do
		local action = self._pendingActions[rollID]
		if action then
			local age = now - action.timestamp
			if age > STALE_PENDING_LOG_SECONDS then
				staleCount = staleCount + 1
				LogDebug(
					"ScanUnmatchedPendingActions: STALE entry",
					addonName,
					self.moduleName,
					"rollID=" .. tostring(rollID),
					"itemLink=" .. tostring(action.itemLink),
					"rollType=" .. tostring(action.rollType),
					"rollValue=" .. tostring(action.rollValue),
					"age=" .. string.format("%.2f", age) .. "s",
					"cause=player_used_builtin_ui_or_network_delay"
				)
			end
		end
	end

	-- Summary line visible at debug level for S06 diagnostics.
	LogDebug(
		"ScanUnmatchedPendingActions: summary",
		addonName,
		self.moduleName,
		tostring(total) .. " pending actions;",
		tostring(staleCount) .. " unmatched (>" .. tostring(STALE_PENDING_LOG_SECONDS) .. "s old);",
		tostring(total - staleCount) .. " within window"
	)
end

return LootRolls
