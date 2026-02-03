---@class G_RLF
local G_RLF = select(2, ...)

local version = 7

local migration = {}

--- TODO: May not need this
function migration:run()
	local repUtils = G_RLF.RepUtils
	if G_RLF:ShouldRunMigrationForChar(version) then
		for _, factionId in pairs(G_RLF.db.locale.factionMap) do
			local repType = repUtils.DetermineRepType(factionId)
			local factionData = repUtils.GetFactionData(factionId, repType)
			if factionData then
				---@type CachedFactionDetails
				local cachedDetails = {
					rank = factionData.rank,
					standing = factionData.standing,
					rankStandingMin = factionData.rankStandingMin,
					rankStandingMax = factionData.rankStandingMax,
				}
				G_RLF.db.char.repFactions.cachedFactionDetailsById[factionId] = cachedDetails
				G_RLF.db.char.repFactions.count = G_RLF.db.char.repFactions.count + 1
			end
		end

		G_RLF.db.char.migrationVersion = version
	end

	if not G_RLF:ShouldRunMigration(version) then
		return
	end

	for _, factionId in pairs(G_RLF.db.locale.accountWideFactionMap) do
		local repType = repUtils.DetermineRepType(factionId)
		local factionData = repUtils.GetFactionData(factionId, repType)
		if factionData then
			---@type CachedFactionDetails
			local cachedDetails = {
				rank = factionData.rank,
				standing = factionData.standing,
				rankStandingMin = factionData.rankStandingMin,
				rankStandingMax = factionData.rankStandingMax,
			}
			G_RLF.db.global.warbandFactions.cachedFactionDetailsById[factionId] = cachedDetails
			G_RLF.db.global.warbandFactions.count = G_RLF.db.global.warbandFactions.count + 1
		end
	end

	G_RLF.db.global.migrationVersion = version
end

G_RLF.migrations[version] = migration

return migration
