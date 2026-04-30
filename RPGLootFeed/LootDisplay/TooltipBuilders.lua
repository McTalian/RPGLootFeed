---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── Tooltip augmentation builders ─────────────────────────────────────────────
-- Feature modules that need custom GameTooltip lines beyond the standard item /
-- currency hyperlink set a `customTooltipFn` on their payload.  The row mixin
-- calls that function (which delegates here) after GameTooltip:SetHyperlink so
-- the item info is already visible as the header.
--
-- Each builder receives the raw data captured at event time.  Do NOT store any
-- builder results on AceDB — this data lives only in memory for the current session.
G_RLF.TooltipBuilders = {}

-- ── LootRolls tooltip ─────────────────────────────────────────────────────────

-- Inline atlas markup for each EncounterLootDropRollState value.
-- Mirrors LootHistoryRollTooltipLineMixin in Blizzard_FrameXML/Mainline/LootHistory.lua.
local ROLL_ICON = {
	[0] = "|A:lootroll-icon-need:14:14|a", -- NeedMainSpec
	[1] = "|A:lootroll-icon-need:14:14|a", -- NeedOffSpec (suffix added below)
	[2] = "|A:lootroll-icon-transmog:14:14|a", -- Transmog
	[3] = "|A:lootroll-icon-greed:14:14|a", -- Greed
	[4] = "|A:lootroll-icon-pass:14:14|a", -- NoRoll → Pass icon
	[5] = "|A:lootroll-icon-pass:14:14|a", -- Pass
}

-- Off-spec rolls share the Need icon; the suffix disambiguates them.
local OFF_SPEC_SUFFIX = " (OS)"

-- A small checkmark atlas that Blizzard uses in the loot history frame.
local WINNER_ICON = "|A:lootroll-icon-checkmark:14:14|a "
local INDENT = "  "

-- EncounterLootDropRollState.NoRoll = 4 (player still deciding / hasn't rolled).
local ROLL_STATE_NO_ROLL = 4

--- Augments the already-opened GameTooltip with the full roll breakdown for a
--- loot drop in any state.  Called from RowTooltipMixin's showTooltip after
--- GameTooltip:SetHyperlink() has populated the item header.
---
---@param dropInfo table   EncounterLootDropInfo from C_LootHistory.GetSortedInfoForDrop
---@param encounterName string|nil  Encounter name from C_LootHistory.GetInfoForEncounter; nil = omitted
---@param state "pending"|"resolved"|"allPassed"|nil  Caller-computed state. Falls back to deriving from dropInfo.
function G_RLF.TooltipBuilders:LootRolls(dropInfo, encounterName, state)
	-- Derive state if the caller didn't supply one (back-compat for resolved-only callers).
	if not state then
		if dropInfo.allPassed then
			state = "allPassed"
		elseif dropInfo.winner then
			state = "resolved"
		else
			state = "pending"
		end
	end

	-- Blank separator between item tooltip header and our roll data.
	GameTooltip:AddLine(" ")

	-- Encounter name subheader (gold text).
	if encounterName and encounterName ~= "" then
		GameTooltip:AddLine(encounterName, 1, 0.82, 0)
	end

	if state == "allPassed" then
		-- No one needed / greeded — just say so.
		GameTooltip:AddLine(G_RLF.L["All Passed"], 0.6, 0.6, 0.6)
	else
		-- Filter and display individual rolls, mirroring Blizzard's own filtering
		-- in LootHistoryElementMixin:SetTooltip (see LootHistory.lua).
		local anyRollNumbers = false
		---@type string[]
		local waitingNames = {}

		for _, roll in ipairs(dropInfo.rollInfos or {}) do
			if roll.roll then
				anyRollNumbers = true
			end
			-- Collect names of players still deciding (NoRoll) for the pending
			-- "Waiting on:" footer.  Only relevant while the roll is unresolved.
			if state == "pending" and roll.state == ROLL_STATE_NO_ROLL and not roll.roll then
				local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[roll.playerClass]
				local name = classColor and classColor:WrapTextInColorCode(roll.playerName) or roll.playerName
				table.insert(waitingNames, name)
			end
		end

		for _, roll in ipairs(dropInfo.rollInfos or {}) do
			-- Skip NoRoll (4) entries unless it's us — consistent with Blizzard.
			if roll.state == ROLL_STATE_NO_ROLL and not roll.isSelf then
				-- skip
			else
				-- Skip rolls that lost due to win protection (same item, higher roll
				-- already won by someone else in a multi-drop scenario).
				local skip = dropInfo.winner
					and not roll.isWinner
					and roll.roll
					and dropInfo.winner.roll
					and roll.roll > dropInfo.winner.roll

				if not skip then
					local icon = ROLL_ICON[roll.state] or ""
					local suffix = (roll.state == 1) and OFF_SPEC_SUFFIX or ""

					-- Class-colored player name.
					local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[roll.playerClass]
					local name = classColor and classColor:WrapTextInColorCode(roll.playerName) or roll.playerName

					local prefix = roll.isWinner and WINNER_ICON or INDENT

					local line
					if anyRollNumbers and roll.roll then
						line = prefix .. icon .. " " .. name .. suffix .. "  " .. roll.roll
					else
						line = prefix .. icon .. " " .. name .. suffix
					end

					GameTooltip:AddLine(line, 1, 1, 1)
				end
			end
		end

		-- Pending state footer: who we're still waiting on.
		if state == "pending" and #waitingNames > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(
				G_RLF.L["LootRolls_WaitingOn"] .. " " .. table.concat(waitingNames, ", "),
				0.8,
				0.8,
				0.8,
				true -- wrap
			)
		end
	end

	GameTooltip:Show()
end

return G_RLF.TooltipBuilders
