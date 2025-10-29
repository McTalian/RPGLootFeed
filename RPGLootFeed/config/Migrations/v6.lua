---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local version = 6

local migration = {}

function migration:run()
	if not G_RLF:ShouldRunMigration(version) then
		return
	end

	if G_RLF.db.global.styling.enableRowBorder ~= nil and G_RLF.db.global.styling.enableRowBorder == true then
		G_RLF.db.global.styling.rowBorderTexture = "1 Pixel"
	end

	if G_RLF.db.global.partyLoot and G_RLF.db.global.partyLoot.styling then
		if
			G_RLF.db.global.partyLoot.styling.enableRowBorder ~= nil
			and G_RLF.db.global.partyLoot.styling.enableRowBorder == true
		then
			G_RLF.db.global.partyLoot.styling.rowBorderTexture = "1 Pixel"
		end
	end

	G_RLF.db.global.migrationVersion = version
end

G_RLF.migrations[version] = migration

return migration
