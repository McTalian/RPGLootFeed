---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local version = 7

local migration = {}

--- Migrate leftAlign (boolean) → textAlignment (string enum).
--- leftAlign = true  → "LEFT"
--- leftAlign = false → "RIGHT"
function migration:run()
	if not G_RLF:ShouldRunMigration(version) then
		return
	end

	local function migrateLeftAlign(stylingPath)
		local styling = stylingPath
		if styling and styling.leftAlign ~= nil then
			if styling.leftAlign == true then
				styling.textAlignment = G_RLF.TextAlignment.LEFT
			else
				styling.textAlignment = G_RLF.TextAlignment.RIGHT
			end
			styling.leftAlign = nil
		end
	end

	migrateLeftAlign(G_RLF.db.global.styling)

	if G_RLF.db.global.partyLoot and G_RLF.db.global.partyLoot.styling then
		migrateLeftAlign(G_RLF.db.global.partyLoot.styling)
	end

	G_RLF.db.global.migrationVersion = version
end

G_RLF.migrations[version] = migration
