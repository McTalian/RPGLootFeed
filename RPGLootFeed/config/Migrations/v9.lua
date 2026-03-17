---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local version = 9

local migration = {}

--- Detects users who skipped the v8 migration due to the AceDB default
--- guard bug introduced in v1.30.2.  Always builds a recovery snapshot
--- from old flat keys and compares it against the current frames[1].
--- Only stores pendingSettingsRecovery if the snapshot differs from what
--- frames[1] currently reports (indicating v8 was skipped or incomplete).
function migration:run()
	if not G_RLF:ShouldRunMigration(version) then
		return
	end

	local global = G_RLF.db.global
	local snapshot = G_RLF:BuildV8RecoverySnapshot(global)
	if snapshot then
		local currentFrame = global.frames and global.frames[1]
		if G_RLF:SnapshotDiffersFromFrame(snapshot, currentFrame) then
			global.pendingSettingsRecovery = {
				detectedVersion = version,
				priorVersion = "v1.30.0",
				brokenVersion = "v1.30.2",
				snapshot = snapshot,
			}
			G_RLF:LogDebug("Pending settings recovery snapshot stored.")
		end
	end

	global.migrationVersion = version
end

G_RLF.migrations[version] = migration

return migration
