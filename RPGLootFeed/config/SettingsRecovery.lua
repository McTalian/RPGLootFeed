---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

--------------------------------------------------
-- Private helpers
--------------------------------------------------

-- Count non-table (scalar) leaf values in a table, recursively.
local function countLeaves(t)
	if type(t) ~= "table" then
		return 0
	end
	local count = 0
	for _, v in pairs(t) do
		if type(v) == "table" then
			count = count + countLeaves(v)
		else
			count = count + 1
		end
	end
	return count
end

-- Flatten a table into "prefix.key: value" lines, recursively.
local function flattenTable(t, prefix, lines)
	if type(t) ~= "table" then
		return
	end
	for k, v in pairs(t) do
		local fullKey = prefix ~= "" and (prefix .. "." .. tostring(k)) or tostring(k)
		if type(v) == "table" then
			flattenTable(v, fullKey, lines)
		else
			lines[#lines + 1] = fullKey .. ": " .. tostring(v)
		end
	end
end

--- Build a per-category summary of the pending recovery snapshot.
--- @return string
local function buildSummaryText()
	local recovery = G_RLF.db.global.pendingSettingsRecovery
	if not recovery or not recovery.snapshot then
		return G_RLF.L["SettingsRecoveryNoChanges"]
	end

	local s = recovery.snapshot
	local parts = {}

	local function addPart(label, t)
		local count = countLeaves(t)
		if count > 0 then
			parts[#parts + 1] = "  " .. label .. ": " .. count
		end
	end

	addPart(G_RLF.L["Positioning"], s.positioning)
	addPart(G_RLF.L["Sizing"], s.sizing)
	addPart(G_RLF.L["Styling"], s.styling)
	addPart(G_RLF.L["Animations"], s.animations)

	if type(s.features) == "table" then
		local featureCount = 0
		for _, featureCfg in pairs(s.features) do
			featureCount = featureCount + countLeaves(featureCfg)
		end
		if featureCount > 0 then
			parts[#parts + 1] = "  " .. G_RLF.L["Loot Feeds"] .. ": " .. featureCount
		end
	end

	if #parts == 0 then
		return G_RLF.L["SettingsRecoveryNoChanges"]
	end

	return G_RLF.L["SettingsRecoverySummaryHdr"] .. "\n" .. table.concat(parts, "\n")
end

--- Build a flat key: value diff of the pending recovery snapshot.
--- @return string
local function buildDetailsText()
	local recovery = G_RLF.db.global.pendingSettingsRecovery
	if not recovery or not recovery.snapshot then
		return G_RLF.L["SettingsRecoveryNoChanges"]
	end

	local lines = {}
	flattenTable(recovery.snapshot, "", lines)
	table.sort(lines)

	if #lines == 0 then
		return G_RLF.L["SettingsRecoveryNoChanges"]
	end

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
