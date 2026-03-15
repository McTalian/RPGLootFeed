---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local version = 4

local migration = {}

function migration:run()
	if not G_RLF:ShouldRunMigration(version) then
		return
	end

	---@diagnostic disable-next-line: undefined-field
	if G_RLF.db.global.item ~= nil and G_RLF.db.global.item.itemQualityFilter ~= nil then
		---@diagnostic disable-next-line: undefined-field
		for i, v in ipairs(G_RLF.db.global.item.itemQualityFilter) do
			G_RLF.DbMigrations:Migrate(
				G_RLF.db,
				"global.item.itemQualityFilter" .. i,
				"global.item.itemQualitySettings." .. i .. ".enabled"
			)
		end
	end

	G_RLF.db.global.migrationVersion = version
end

G_RLF.migrations[version] = migration

return migration
