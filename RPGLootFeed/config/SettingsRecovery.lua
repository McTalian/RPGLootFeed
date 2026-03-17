---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

--------------------------------------------------
-- Private helpers
--------------------------------------------------

--- Map a dotted diff path to a UI category name.
--- @param path string  e.g. "positioning.xOffset" or "features.itemLoot.enabled"
--- @return string  category label
local function categoryForPath(path)
	local section = path:match("^([^.]+)")
	if section == "positioning" then
		return G_RLF.L["Positioning"]
	elseif section == "sizing" then
		return G_RLF.L["Sizing"]
	elseif section == "styling" then
		return G_RLF.L["Styling"]
	elseif section == "animations" then
		return G_RLF.L["Animations"]
	elseif section == "features" then
		return G_RLF.L["Loot Feeds"]
	end
	return section
end

--- Get the list of diffs between the pending snapshot and current frames[1].
--- Caches the result in the recovery table so we don't recompute every UI refresh.
--- @return table  array of { path, old, new }
local function getDiffs()
	local recovery = G_RLF.db.global.pendingSettingsRecovery
	if not recovery or not recovery.snapshot then
		return {}
	end
	if recovery._cachedDiffs then
		return recovery._cachedDiffs
	end
	local currentFrame = G_RLF.db.global.frames and G_RLF.db.global.frames[1]
	local diffs = G_RLF:ComputeSnapshotDiff(recovery.snapshot, currentFrame or {})
	recovery._cachedDiffs = diffs
	return diffs
end

--- Build a per-category summary counting actual differences.
--- @return string
local function buildSummaryText()
	local diffs = getDiffs()
	if #diffs == 0 then
		return G_RLF.L["SettingsRecoveryNoChanges"]
	end

	-- Count diffs per category
	local categoryCounts = {}
	local categoryOrder = {}
	for _, d in ipairs(diffs) do
		local cat = categoryForPath(d.path)
		if not categoryCounts[cat] then
			categoryCounts[cat] = 0
			categoryOrder[#categoryOrder + 1] = cat
		end
		categoryCounts[cat] = categoryCounts[cat] + 1
	end

	local parts = {}
	for _, cat in ipairs(categoryOrder) do
		parts[#parts + 1] = "  " .. cat .. ": " .. categoryCounts[cat]
	end

	return G_RLF.L["SettingsRecoverySummaryHdr"] .. "\n" .. table.concat(parts, "\n")
end

--- Build a detailed per-setting diff showing old → new values.
--- @return string
local function buildDetailsText()
	local diffs = getDiffs()
	if #diffs == 0 then
		return G_RLF.L["SettingsRecoveryNoChanges"]
	end

	local lines = {}
	for _, d in ipairs(diffs) do
		local oldStr = tostring(d.old)
		local newStr = tostring(d.new)
		if d.old == nil then
			oldStr = "(nil)"
		end
		if d.new == nil then
			newStr = "(nil)"
		end
		lines[#lines + 1] = d.path .. ": " .. oldStr .. " → " .. newStr
	end
	table.sort(lines)

	return table.concat(lines, "\n")
end

--- Clear the old flat appearance keys from db.global.
--- Does NOT nil feature keys (g.item, g.currency, etc.) because feature
--- modules still read from those until Phase 5 of the multi-frame refactor.
local function cleanUpAppearanceFlatKeys()
	local g = G_RLF.db.global
	g.positioning = nil
	g.sizing = nil
	g.styling = nil
	g.animations = nil
end

--- Apply the recovery snapshot: write it to frames[1] and clean up.
local function applyRecovery()
	local recovery = G_RLF.db.global.pendingSettingsRecovery
	if not recovery then
		return
	end
	G_RLF.db.global.frames[1] = recovery.snapshot
	cleanUpAppearanceFlatKeys()
	G_RLF.db.global.pendingSettingsRecovery = nil
	G_RLF:NotifyChange(addonName)
	G_RLF.LootDisplay:InitFrame(G_RLF.Frames.MAIN)
	G_RLF.LootDisplay:RefreshSampleRowsIfShown()
end

--- Dismiss the recovery notice without applying it.
local function dismissRecovery()
	cleanUpAppearanceFlatKeys()
	G_RLF.db.global.pendingSettingsRecovery = nil
	G_RLF:NotifyChange(addonName)
end

--------------------------------------------------
-- AceConfig tab registration
--------------------------------------------------

G_RLF.options.args.global.args.settingsRecovery = {
	type = "group",
	name = G_RLF.L["Settings Recovery"],
	desc = function()
		local recovery = G_RLF.db.global.pendingSettingsRecovery or {}
		local prior = recovery.priorVersion or "?"
		return string.format(G_RLF.L["SettingsRecoveryDesc"], prior)
	end,
	order = 0,
	hidden = function()
		return G_RLF.db.global.pendingSettingsRecovery == nil
	end,
	args = {
		header = {
			type = "header",
			name = G_RLF.L["Settings Recovery"],
			order = 1,
		},
		body = {
			type = "description",
			name = function()
				local recovery = G_RLF.db.global.pendingSettingsRecovery or {}
				local prior = recovery.priorVersion or "?"
				local broken = recovery.brokenVersion or "?"
				return string.format(G_RLF.L["SettingsRecoveryBody"], prior, broken)
			end,
			order = 2,
			fontSize = "medium",
		},
		summary = {
			type = "description",
			name = function()
				return buildSummaryText()
			end,
			order = 3,
		},
		detailsLabel = {
			type = "description",
			name = G_RLF.L["SettingsRecoveryDetailsLabel"],
			order = 4,
		},
		detailsInput = {
			type = "input",
			name = "",
			multiline = 15,
			width = "full",
			order = 5,
			get = function()
				return buildDetailsText()
			end,
			set = function() end, -- read-only
		},
		restore = {
			type = "execute",
			name = G_RLF.L["RestoreOldSettings"],
			order = 10,
			func = function()
				applyRecovery()
			end,
		},
		dismiss = {
			type = "execute",
			name = G_RLF.L["DismissRecovery"],
			order = 11,
			func = function()
				dismissRecovery()
			end,
		},
	},
}
