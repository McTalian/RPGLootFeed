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

-- Button validity cache keyed by "encounterID_lootListID".
LootRolls._buttonValidityCache = {}

-- Staging cache keyed by rollID alone (populated from START_LOOT_ROLL before
-- encounterID is known; absorbed into _buttonValidityCache on LOOT_HISTORY_UPDATE_DROP).
LootRolls._rollValidityStaging = {}

-- Action row state cache keyed by rollID (Retail + Classic).
-- Each entry: { state = "pending"|"submitted", buttonValidity = {...},
--               itemLink = "...", startTime = n, rollTime = n }
-- Independent from _dropStates — action rows live on rollID, not encounterID_lootListID.
-- Entries are created on START_LOOT_ROLL and cleared when the roll concludes.
LootRolls._actionRowStates = {}
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

--- Builds a payload for a Retail action row, keyed by rollID.
--- Action rows are independent from result rows (no encounterID/lootListID).
--- Returns nil when the module is disabled.
---@param rollID number
---@param rollTime number  seconds until roll auto-closes (from START_LOOT_ROLL)
---@param itemLink string|nil
---@param buttonValidity table  { canNeed, canGreed, canTransmog, canPass }
---@param state "pending"|"submitted"
---@return RLF_ElementPayload?
function LootRolls:BuildActionRowPayload(rollID, rollTime, itemLink, buttonValidity, state)
	if not LootRolls:IsEnabled() then
		return nil
	end

	local lootRollsActionsConfig = G_RLF.DbAccessor:AnyFeatureConfig("lootRollActions") or {}
	local payload = {}

	-- Action row key uses "LAR_" prefix to distinguish from result rows ("LR_").
	payload.key = "LAR_" .. rollID
	payload.type = FeatureModule.LootRolls
	payload.isLink = true
	-- quantity = 0 — rows are state machines, not stacking counts.
	payload.quantity = 0

	-- Icon from item link cache; fall back to default LOOTROLLS icon.
	if lootRollsActionsConfig.enableIcon and not G_RLF.db.global.misc.hideAllIcons then
		if itemLink and itemLink ~= "" then
			payload.icon = LootRolls._lootRollsAdapter.GetItemInfoIcon(itemLink) or DefaultIcons.LOOTROLLS
		else
			payload.icon = DefaultIcons.LOOTROLLS
		end
	end

	-- Quality from item link cache; default to Uncommon when unavailable.
	if itemLink and itemLink ~= "" then
		payload.quality = LootRolls._lootRollsAdapter.GetItemInfoQuality(itemLink) or ItemQualEnum.Uncommon
	else
		payload.quality = ItemQualEnum.Uncommon
	end

	-- Primary text: item hyperlink (clickable link) or fallback.
	local link = itemLink or ""
	payload.textFn = function(_, truncatedLink)
		if not truncatedLink or truncatedLink == "" then
			return link
		end
		return truncatedLink
	end

	-- Secondary text: pending state shows waiting message; submitted shows selection.
	local actionRowEntry = LootRolls._actionRowStates[rollID]
	if state == "submitted" and actionRowEntry and actionRowEntry.playerSelection then
		local selectionLabel = G_RLF.L["LootRolls_YouSelected_" .. actionRowEntry.playerSelection]
			or actionRowEntry.playerSelection
		payload.secondaryText = selectionLabel
	else
		payload.secondaryText = G_RLF.L["LootRolls_WaitingForRolls"]
	end

	-- Exit timer anchored to rollTime so the row drains in sync with the roll window.
	if rollTime and rollTime > 0 then
		payload.showForSeconds = rollTime + PENDING_EXIT_BUFFER
	end

	-- Tooltip: minimal for action rows (no encounter context).
	payload.customTooltipFn = function()
		-- Action rows don't have encounter context; skip detailed tooltip.
	end

	-- Button validity for the row's button mixin.
	if buttonValidity then
		payload.buttonValidity = {
			canNeed = buttonValidity.canNeed or false,
			canGreed = buttonValidity.canGreed or false,
			canTransmog = buttonValidity.canTransmog or false,
			canDisenchant = buttonValidity.canDisenchant or false,
			canPass = buttonValidity.canPass ~= false, -- default true
		}
	end

	-- Player selection from action row state.
	if actionRowEntry and actionRowEntry.playerSelection then
		payload.playerSelection = actionRowEntry.playerSelection
	end

	-- Store rollID so buttons can call SubmitActionRoll directly.
	payload.rollID = rollID
	payload.rollState = state
	payload.isActionRow = true
	-- Pass self so mixin can call SubmitActionRoll without a global lookup.
	payload.lootRollsFeature = LootRolls

	payload.IsEnabled = function()
		return LootRolls:IsEnabled()
	end

	return payload
end

--- Pushes an action row payload onto the message bus.
---@param rollID number
---@param rollTime number
---@param itemLink string|nil
---@param buttonValidity table
---@param state "pending"|"submitted"
function LootRolls:DispatchActionRowPayload(rollID, rollTime, itemLink, buttonValidity, state)
	local payload = self:BuildActionRowPayload(rollID, rollTime, itemLink, buttonValidity, state)
	if not payload then
		return
	end
	LogDebug("DispatchActionRowPayload", addonName, self.moduleName, rollID, state)
	local element = LootElementBase:fromPayload(payload)
	element:Show()
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
	local lootRollsResultsConfig = G_RLF.DbAccessor:AnyFeatureConfig("lootRollResults") or {}

	-- Result row feature gate: checked at dispatch time (second gate).
	if lootRollsResultsConfig.enabled == false then
		LogDebug(
			"lootRollResults disabled — skipping result row",
			addonName,
			self.moduleName,
			encounterID,
			lootListID
		)
		return nil
	end

	local payload = {}

	payload.key = key
	payload.type = FeatureModule.LootRolls
	payload.isLink = true
	payload.isActionRow = false
	-- quantity = 0 — LootRolls rows are state machines, not stacking counts.
	-- A non-nil amount lets UpdateQuantity proceed without deferring forever.
	payload.quantity = 0

	-- Icon: try to resolve from item info cache.  The item is usually cached by
	-- the time roll results arrive; if not, the row renders without an icon.
	if lootRollsResultsConfig.enableIcon and not G_RLF.db.global.misc.hideAllIcons then
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

	-- Button validity from cache.
	local dropKey = encounterID .. "_" .. lootListID
	local cached = LootRolls._buttonValidityCache[dropKey]
	if cached then
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

	-- Store encounterID/lootListID/rollState so buttons can call Submit* methods.
	payload.encounterID = encounterID
	payload.lootListID = lootListID
	payload.rollState = state
	-- Pass self so the mixin can call SubmitNeed/SubmitGreed etc. directly
	-- without a global G_RLF.LootRolls lookup (LootRolls is a module-local).
	payload.lootRollsFeature = LootRolls

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
	if
		G_RLF.DbAccessor:IsFeatureNeededByAnyFrame("lootRollActions")
		or G_RLF.DbAccessor:IsFeatureNeededByAnyFrame("lootRollResults")
	then
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
		self:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
		-- START_LOOT_ROLL fires on Retail too — use it to cache button validity
		-- at the exact moment GetLootRollItemInfo(rollID) is guaranteed valid.
		self:RegisterEvent("START_LOOT_ROLL")
		-- Action row lifecycle: hide rows when the roll concludes.
		self:RegisterEvent("MAIN_SPEC_NEED_ROLL")
		self:RegisterEvent("CANCEL_LOOT_ROLL")
		self:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
		LogDebug(
			"Registered LOOT_HISTORY_UPDATE_DROP + START_LOOT_ROLL + outcome events (Retail)",
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
		LogDebug("Registered START_LOOT_ROLL + LOOT_ROLLS_COMPLETE (Classic)", addonName, self.moduleName)
	end
end

function LootRolls:OnDisable()
	self:UnregisterAllEvents()
	-- Reset state so re-enabling presents fresh data.
	LootRolls._dropStates = {}
	LootRolls._buttonValidityCache = {}
	LootRolls._rollValidityStaging = {}
	LootRolls._actionRowStates = {}
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

	-- Result row feature gate: checked at state population time (first gate).
	local lootRollsResultsConfig = G_RLF.DbAccessor:AnyFeatureConfig("lootRollResults") or {}
	if lootRollsResultsConfig.enabled == false then
		LogDebug(
			"lootRollResults disabled — skipping LOOT_HISTORY_UPDATE_DROP",
			addonName,
			self.moduleName,
			encounterID,
			lootListID
		)
		return
	end

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

	-- Absorb staged validity (set by START_LOOT_ROLL before encounterID was known).
	if newState == "pending" and not LootRolls._buttonValidityCache[dropKey] then
		local staged = LootRolls._rollValidityStaging[lootListID]
		if staged then
			LootRolls._buttonValidityCache[dropKey] = staged
			LootRolls._rollValidityStaging[lootListID] = nil
			LogDebug(
				"Absorbed staged validity for",
				addonName,
				self.moduleName,
				dropKey,
				staged.canNeed,
				staged.canGreed,
				staged.canTransmog
			)
		else
			-- Fallback: try calling directly (may return nil if roll already closed).
			if LootRolls._lootRollsAdapter.GetRollButtonValidity then
				local validity = LootRolls._lootRollsAdapter.GetRollButtonValidity(lootListID)
				if validity then
					LootRolls._buttonValidityCache[dropKey] = validity
				end
			end
		end
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

--- Fired on Classic when a new group loot roll begins.
function LootRolls:START_LOOT_ROLL(eventName, rollID, rollTime)
	LogInfo(eventName, "WOWEVENT", self.moduleName, rollID, rollTime)

	if IsRetail() then
		-- On Retail, START_LOOT_ROLL fires when a GroupLootFrame roll opens.
		-- Cache button validity now — GetLootRollItemInfo(rollID) is valid here.
		-- 1. Stage validity for LOOT_HISTORY_UPDATE_DROP (result row path).
		-- 2. Cache in _actionRowStates and dispatch action row immediately.
		if LootRolls._lootRollsAdapter.GetRollButtonValidity then
			local validity = LootRolls._lootRollsAdapter.GetRollButtonValidity(rollID)
			if validity then
				-- Stage for result row absorption.
				LootRolls._rollValidityStaging[rollID] = validity
				LogDebug(
					"Staged Retail button validity",
					addonName,
					self.moduleName,
					rollID,
					validity.canNeed,
					validity.canGreed,
					validity.canTransmog
				)

				-- Cache in _actionRowStates for the independent action row path.
				local existing = LootRolls._actionRowStates[rollID]
				if not existing then
					-- Fetch item link for the action row display.
					local itemLink = LootRolls._lootRollsAdapter.GetRollItemLink
							and LootRolls._lootRollsAdapter.GetRollItemLink(rollID)
						or nil

					LootRolls._actionRowStates[rollID] = {
						state = "pending",
						buttonValidity = validity,
						itemLink = itemLink,
						startTime = GetTime(),
						rollTime = rollTime,
					}
					LogInfo(
						"START_LOOT_ROLL action row cached",
						addonName,
						self.moduleName,
						rollID,
						"canNeed=" .. tostring(validity.canNeed),
						"canGreed=" .. tostring(validity.canGreed),
						"canTransmog=" .. tostring(validity.canTransmog),
						"rollTime=" .. tostring(rollTime)
					)

					-- Dispatch action row to the feed immediately.
					self:DispatchActionRowPayload(rollID, rollTime, itemLink, validity, "pending")
				else
					LogDebug("Action row already cached for rollID", addonName, self.moduleName, rollID)
				end
			else
				LogWarn("GetRollButtonValidity returned nil for rollID", addonName, self.moduleName, rollID)
			end
		end
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
		entry = { state = "pending", _isClassic = true, _rollID = rollID }
		LootRolls._dropStates[dropKey] = entry
	else
		entry.state = "pending"
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
	self:DispatchClassicPayload(rollID, dropInfo, "pending", itemInfo)
end

--- Fired on Classic when all rolls for a loot item have concluded.
function LootRolls:LOOT_ROLLS_COMPLETE(eventName, lootHandle)
	LogInfo(eventName, "WOWEVENT", self.moduleName, lootHandle)

	for dropKey, entry in pairs(LootRolls._dropStates) do
		if entry.state == "pending" and entry._isClassic then
			entry.state = "allPassed"
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
	local lootRollsResultsConfig = G_RLF.DbAccessor:AnyFeatureConfig("lootRollResults") or {}

	local payload = {}

	payload.key = "LR_" .. rollID .. "_" .. rollID
	payload.type = FeatureModule.LootRolls
	payload.isLink = true
	payload.isActionRow = false
	payload.quantity = 0

	if lootRollsResultsConfig.enableIcon and not G_RLF.db.global.misc.hideAllIcons then
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

	if state == "allPassed" or state == "resolved" then
		payload.secondaryText = G_RLF.L["All Passed"]
	else
		payload.secondaryText = G_RLF.L["LootRolls_WaitingForRolls"]
		local remaining = GetRemainingPendingSeconds(dropInfo)
		if remaining then
			payload.showForSeconds = remaining
		end
	end

	payload.customTooltipFn = function()
		if G_RLF.TooltipBuilders and G_RLF.TooltipBuilders.LootRolls then
			G_RLF.TooltipBuilders:LootRolls(dropInfo, nil, state)
		end
	end

	local cached = LootRolls._buttonValidityCache[dropKey]
	if cached then
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

	payload.IsEnabled = function()
		return LootRolls:IsEnabled()
	end

	return payload
end

--- Submit a Classic roll action via ClassicRollOnLoot.
---@param rollID number
---@param rollTypeName string  "NEED"|"GREED"|"DISENCHANT"|"PASS"
function LootRolls:SubmitClassicRoll(rollID, rollTypeName)
	local dropKey = rollID .. "_" .. rollID

	local classicMap = { NEED = 1, GREED = 2, DISENCHANT = 3, PASS = 0 }
	local rollType = classicMap[rollTypeName]
	if rollType == nil then
		LogWarn("SubmitClassicRoll: invalid rollTypeName", addonName, self.moduleName, rollTypeName)
		return
	end

	LogDebug("SubmitClassicRoll", addonName, self.moduleName, rollID, rollTypeName, rollType)
	local ok, err = LootRolls._lootRollsAdapter.ClassicRollOnLoot(rollID, rollType)
	if not ok then
		LogWarn("ClassicRollOnLoot failed", addonName, self.moduleName, rollTypeName, err)
		return
	end

	local entry = LootRolls._dropStates[dropKey]
	if entry then
		entry.playerSelection = rollTypeName
		LogDebug("Classic player selection recorded", addonName, self.moduleName, dropKey, rollTypeName)

		local cachedDropInfo = entry._dropInfo
		if cachedDropInfo then
			self:DispatchClassicPayload(rollID, cachedDropInfo, entry.state or "pending", nil)
		end
	end
end

-- ── Roll submit actions (Retail + Classic routing) ────────────────────────────

--- Routes a roll action to Classic or Retail path based on drop state.
local function submitRollAction(encounterID, lootListID, rollTypeName)
	local dropKey = encounterID .. "_" .. lootListID
	local entry = LootRolls._dropStates[dropKey]

	if entry and entry._isClassic then
		local classicTypeName = rollTypeName == "TRANSMOG" and "DISENCHANT" or rollTypeName
		LootRolls:SubmitClassicRoll(lootListID, classicTypeName)
		return
	end

	-- Retail path.
	if not LootRolls._lootRollsAdapter.DecodeRollType then
		LogWarn("DecodeRollType not available", addonName, LootRolls.moduleName)
		return
	end
	local rollType, decodeErr = LootRolls._lootRollsAdapter.DecodeRollType(rollTypeName)
	if not rollType then
		LogWarn("submitRollAction: invalid rollType", addonName, LootRolls.moduleName, rollTypeName, decodeErr)
		return
	end

	if not LootRolls._lootRollsAdapter.SubmitLootRoll then
		LogWarn("SubmitLootRoll not available", addonName, LootRolls.moduleName)
		return
	end
	local ok, submitErr = LootRolls._lootRollsAdapter.SubmitLootRoll(lootListID, rollType)
	if not ok then
		LogWarn("SubmitLootRoll failed", addonName, LootRolls.moduleName, rollTypeName, submitErr)
		return
	end

	if entry then
		entry.playerSelection = rollTypeName
		LogDebug("Player selection recorded", addonName, LootRolls.moduleName, dropKey, rollTypeName)
		local currentDropInfo = LootRolls._lootRollsAdapter.GetSortedInfoForDrop(encounterID, lootListID)
		if currentDropInfo then
			LootRolls:DispatchPayload(encounterID, lootListID, currentDropInfo, entry.state or "pending")
		end
	end
end

--- Submits a Retail action-row roll via rollID (independent of encounterID/lootListID).
---@param rollID number  The rollID from START_LOOT_ROLL
---@param rollTypeName string  "NEED"|"GREED"|"TRANSMOG"|"PASS"
function LootRolls:SubmitActionRoll(rollID, rollTypeName)
	if not rollID then
		LogWarn("SubmitActionRoll: rollID is nil", addonName, self.moduleName)
		return
	end

	if not LootRolls._lootRollsAdapter.DecodeRollType then
		LogWarn("DecodeRollType not available", addonName, self.moduleName)
		return
	end
	local rollType, decodeErr = LootRolls._lootRollsAdapter.DecodeRollType(rollTypeName)
	if not rollType then
		LogWarn("SubmitActionRoll: invalid rollType", addonName, self.moduleName, rollTypeName, decodeErr)
		return
	end

	if not LootRolls._lootRollsAdapter.SubmitLootRoll then
		LogWarn("SubmitLootRoll not available", addonName, self.moduleName)
		return
	end

	LogInfo("SubmitActionRoll", "ACTION", self.moduleName, rollID, rollTypeName)
	local ok, submitErr = LootRolls._lootRollsAdapter.SubmitLootRoll(rollID, rollType)
	if not ok then
		LogWarn("SubmitActionRoll failed", addonName, self.moduleName, rollTypeName, submitErr)
		return
	end

	-- Record player selection and re-dispatch as submitted.
	local entry = LootRolls._actionRowStates[rollID]
	if entry then
		entry.playerSelection = rollTypeName
		LogDebug("Action row player selection recorded", addonName, self.moduleName, rollID, rollTypeName)
		self:DispatchActionRowPayload(rollID, entry.rollTime or 0, entry.itemLink, entry.buttonValidity, "submitted")
	end
end

-- ── Action row lifecycle: hide on outcome events ──────────────────────────────

--- Hides a pending action row by dispatching a "resolved" payload and clearing
--- the state entry.  Called from outcome-event handlers to ensure no orphaned
--- action rows remain after the roll window closes.
---@param rollID number
local function hideActionRow(rollID)
	local entry = LootRolls._actionRowStates[rollID]
	if not entry then
		LogDebug("hideActionRow: no entry for rollID (already gone)", addonName, LootRolls.moduleName, rollID)
		return
	end
	LogInfo("Action row hide", "ACTION", LootRolls.moduleName, rollID, "state=" .. tostring(entry.state))
	-- Dispatch as "resolved" so the row's exit animation fires.
	LootRolls:DispatchActionRowPayload(rollID, 0, entry.itemLink, entry.buttonValidity, "resolved")
	-- Clear state — no orphaned entries.
	LootRolls._actionRowStates[rollID] = nil
	LogDebug("Action row state cleared for rollID", addonName, LootRolls.moduleName, rollID)
end

--- MAIN_SPEC_NEED_ROLL fires on Retail when the player (or another player) wins
--- the roll via a GroupLootFrame Need button.  rollID uniquely identifies which
--- roll concluded so we can target the correct action row.
---@param eventName string
---@param rollID number
function LootRolls:MAIN_SPEC_NEED_ROLL(eventName, rollID)
	LogInfo(eventName, "WOWEVENT", self.moduleName, rollID)
	hideActionRow(rollID)
end

--- CANCEL_LOOT_ROLL fires on Retail when a specific roll is cancelled (e.g.
--- timeout, player disconnects, or item no longer available for the roll).
---@param eventName string
---@param rollID number
function LootRolls:CANCEL_LOOT_ROLL(eventName, rollID)
	LogInfo(eventName, "WOWEVENT", self.moduleName, rollID)
	hideActionRow(rollID)
end

--- CANCEL_ALL_LOOT_ROLLS fires on Retail when all pending rolls are cancelled
--- simultaneously (e.g. zone transition, encounter ends prematurely).
--- Hides every action row that is still pending.
---@param eventName string
function LootRolls:CANCEL_ALL_LOOT_ROLLS(eventName)
	LogInfo(eventName, "WOWEVENT", self.moduleName)
	-- Collect rollIDs first to avoid mutating the table while iterating.
	local pending = {}
	for rollID, _ in pairs(LootRolls._actionRowStates) do
		table.insert(pending, rollID)
	end
	LogDebug("CANCEL_ALL_LOOT_ROLLS hiding", addonName, self.moduleName, #pending, "action rows")
	for _, rollID in ipairs(pending) do
		hideActionRow(rollID)
	end
end

function LootRolls:SubmitNeed(encounterID, lootListID)
	submitRollAction(encounterID, lootListID, "NEED")
end

function LootRolls:SubmitGreed(encounterID, lootListID)
	submitRollAction(encounterID, lootListID, "GREED")
end

function LootRolls:SubmitTransmog(encounterID, lootListID)
	submitRollAction(encounterID, lootListID, "TRANSMOG")
end

function LootRolls:SubmitPass(encounterID, lootListID)
	submitRollAction(encounterID, lootListID, "PASS")
end

function LootRolls:SubmitDisenchant(encounterID, lootListID)
	submitRollAction(encounterID, lootListID, "DISENCHANT")
end

return LootRolls
