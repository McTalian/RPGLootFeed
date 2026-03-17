---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local version = 8

-- Localize helpers extracted to MigrationHelpers.lua (loaded first via migrations.xml).
local _h = G_RLF._migHelpers
local copyPositioning = _h.copyPositioning
local copySizing = _h.copySizing
local copyStyling = _h.copyStyling
local copyAnimations = _h.copyAnimations
local copyStylingWithFallback = _h.copyStylingWithFallback
local buildFeatures = _h.buildFeatures

local migration = {}

--- Populate the new per-frame schema by copying existing DB values.
--- Old top-level keys (item, currency, money, etc.) are intentionally left in
--- place; feature modules still read from them until Phase 5 rewires them to
--- read from frames[id].features.*.
function migration:run()
	if not G_RLF:ShouldRunMigration(version) then
		return
	end

	local global = G_RLF.db.global

	-- Ensure the frames table exists.
	if global.frames == nil then
		global.frames = {}
	end

	local partyLoot = global.partyLoot
	local partyLootSeparate = partyLoot and partyLoot.separateFrame == true

	-- Build frame 1 (Main) from the current top-level settings.
	-- ShouldRunMigration(8) already prevents re-runs (migrationVersion >= 8),
	-- so we always write frames[1] here.
	---@type RLF_FrameConfig
	global.frames[1] = {
		name = "Main", -- nocheck
		positioning = copyPositioning(global.positioning),
		sizing = copySizing(global.sizing),
		styling = copyStyling(global.styling),
		animations = copyAnimations(global.animations),
		features = buildFeatures(global, partyLootSeparate and { partyLoot = false } or nil),
	}

	-- If the user previously had a separate Party frame, promote those
	-- appearance settings into a new frame 2 entry.
	-- Phase 4 removed the AceDB defaults for partyLoot.positioning/sizing/styling,
	-- so those sub-tables may exist but have nil for keys the user never explicitly
	-- changed.  We hardcode the old defaults here as the final fallback tier so
	-- every user migrating gets the correct party frame values regardless of what
	-- their main frame looks like.
	if partyLootSeparate then
		local f2 = global.frames[2]
		if f2 == nil or f2.name == "" then
			local plPos = partyLoot.positioning or {}
			local plSiz = partyLoot.sizing or {}
			local plSty = partyLoot.styling or {}

			-- Old party loot defaults (from main branch PartyLootConfig.lua) that
			-- were removed in Phase 4.  Used as final fallback for nil keys.
			local oldPartyDefaults = {
				positioning = {
					relativePoint = "UIParent",
					anchorPoint = "LEFT",
					xOffset = 0,
					yOffset = 375,
					frameStrata = "MEDIUM",
				},
				sizing = {
					feedWidth = 330,
					maxRows = 10,
					rowHeight = 22,
					padding = 2,
					iconSize = 18,
				},
			}
			local dpPos = oldPartyDefaults.positioning
			local dpSiz = oldPartyDefaults.sizing

			-- All features disabled except partyLoot.
			local partyFrameOverrides = {
				itemLoot = false,
				partyLoot = true,
				currency = false,
				money = false,
				experience = false,
				reputation = false,
				profession = false,
				travelPoints = false,
				transmog = false,
			}

			---@type RLF_FrameConfig
			global.frames[2] = {
				name = "Party", -- nocheck
				positioning = {
					relativePoint = plPos.relativePoint or dpPos.relativePoint,
					anchorPoint = plPos.anchorPoint or dpPos.anchorPoint,
					xOffset = plPos.xOffset or dpPos.xOffset,
					yOffset = plPos.yOffset or dpPos.yOffset,
					frameStrata = plPos.frameStrata or dpPos.frameStrata,
				},
				sizing = {
					feedWidth = plSiz.feedWidth or dpSiz.feedWidth,
					maxRows = plSiz.maxRows or dpSiz.maxRows,
					rowHeight = plSiz.rowHeight or dpSiz.rowHeight,
					padding = plSiz.padding or dpSiz.padding,
					iconSize = plSiz.iconSize or dpSiz.iconSize,
				},
				-- Styling old defaults matched the global styling defaults, so
				-- falling back to global.styling is correct here.
				styling = copyStylingWithFallback(plSty, global.styling),
				-- Party frame inherits the global animation settings as a baseline.
				animations = copyAnimations(global.animations),
				features = buildFeatures(global, partyFrameOverrides),
			}
		end
		global.nextFrameId = 3
	else
		global.nextFrameId = global.nextFrameId or 2
	end

	G_RLF.db.global.migrationVersion = version
end

G_RLF.migrations[version] = migration

return migration
