local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

--- Build a minimal namespace with all helpers v9 depends on.
local function makeNs(migrationVersion)
	local ns = {
		db = {
			global = {
				migrationVersion = migrationVersion or 0,
			},
		},
		migrations = {},
		L = setmetatable({}, {
			__index = function(_, k)
				return k
			end,
		}),
	}

	function ns:ShouldRunMigration(version)
		return ns.db.global.migrationVersion < version
	end

	function ns:LogDebug(msg) end

	return ns
end

local function loadMigrationHelpers(ns)
	return assert(loadfile("RPGLootFeed/config/Migrations/MigrationHelpers.lua"))("TestAddon", ns)
end

local function loadV9(ns)
	loadMigrationHelpers(ns)
	return assert(loadfile("RPGLootFeed/config/Migrations/v9.lua"))("TestAddon", ns)
end

--- Reproduce the state left by the v1.30.2 bug:
--- AceDB injects a default frames[1] with default values,
--- while the old flat appearance/feature tables (with the user's
--- actual customized settings) are still present.
local function setupSkippedV8State(ns)
	-- frames[1] serves AceDB defaults (not the user's real settings)
	ns.db.global.frames = {
		[1] = {
			name = "Main",
			positioning = {
				anchorPoint = "BOTTOMLEFT",
				xOffset = 720,
				yOffset = 375,
				relativePoint = "UIParent",
				frameStrata = "MEDIUM",
			},
			sizing = { feedWidth = 330, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 },
			styling = {
				growUp = true,
				fontSize = 10,
				fontFace = "Friz Quadrata TT",
				textAlignment = "LEFT",
				enabledSecondaryRowText = false,
				enableRowBorder = false,
				rowBackgroundType = 1,
			},
			animations = { enter = { type = "fade", duration = 0.3 } },
			features = {
				itemLoot = { enabled = true },
				partyLoot = { enabled = false },
				currency = { enabled = true },
				money = { enabled = true },
				experience = { enabled = true },
				reputation = { enabled = true },
				profession = { enabled = true },
				travelPoints = { enabled = true },
				transmog = { enabled = true },
			},
		},
	}
	-- User's REAL settings in old flat keys (customized: different anchor, feed width)
	ns.db.global.positioning = { anchorPoint = "TOPRIGHT", xOffset = 400, yOffset = 375 }
	ns.db.global.sizing = { feedWidth = 500, maxRows = 10 }
	ns.db.global.styling = { growUp = true, fontSize = 10 }
	ns.db.global.animations = { enter = { type = "fade", duration = 0.3 } }
	ns.db.global.item = { enabled = true, enableIcon = true }
	ns.db.global.partyLoot = { enabled = false }
	ns.db.global.currency = { enabled = true }
	ns.db.global.money = { enabled = true }
	ns.db.global.xp = { enabled = true }
	ns.db.global.rep = { enabled = true }
	ns.db.global.prof = { enabled = true }
	ns.db.global.travelPoints = { enabled = true }
	ns.db.global.transmog = { enabled = true }
end

describe("Migration v9", function()
	describe("when migrationVersion < 9 and v8 was skipped (v1.30.2 bug)", function()
		local ns

		before_each(function()
			ns = makeNs(8)
			setupSkippedV8State(ns)
			loadV9(ns)
		end)

		it("stores pendingSettingsRecovery", function()
			ns.migrations[9]:run()
			assert.is_not_nil(ns.db.global.pendingSettingsRecovery)
		end)

		it("stores detectedVersion = 9", function()
			ns.migrations[9]:run()
			assert.are.equal(9, ns.db.global.pendingSettingsRecovery.detectedVersion)
		end)

		it("stores priorVersion and brokenVersion strings", function()
			ns.migrations[9]:run()
			assert.are.equal("v1.30.0", ns.db.global.pendingSettingsRecovery.priorVersion)
			assert.are.equal("v1.30.2", ns.db.global.pendingSettingsRecovery.brokenVersion)
		end)

		it("stores a non-nil snapshot", function()
			ns.migrations[9]:run()
			assert.is_not_nil(ns.db.global.pendingSettingsRecovery.snapshot)
		end)

		it("snapshot positioning comes from old flat keys", function()
			ns.migrations[9]:run()
			local snapshot = ns.db.global.pendingSettingsRecovery.snapshot
			assert.are.equal("TOPRIGHT", snapshot.positioning.anchorPoint)
			assert.are.equal(400, snapshot.positioning.xOffset)
		end)

		it("snapshot features come from old flat keys", function()
			ns.migrations[9]:run()
			local features = ns.db.global.pendingSettingsRecovery.snapshot.features
			assert.is_true(features.itemLoot.enabled)
			assert.is_false(features.partyLoot.enabled)
		end)

		it("sets migrationVersion to 9", function()
			ns.migrations[9]:run()
			assert.are.equal(9, ns.db.global.migrationVersion)
		end)
	end)

	describe("when migrationVersion < 9 but v8 ran correctly (snapshot matches frames[1])", function()
		it("does not store pendingSettingsRecovery when values match", function()
			local ns = makeNs(8)
			-- Old flat keys and frames[1] have the SAME custom values (v8 copied correctly)
			ns.db.global.positioning = {
				anchorPoint = "TOPRIGHT",
				xOffset = 400,
				yOffset = 375,
				relativePoint = "UIParent",
				frameStrata = "MEDIUM",
			}
			ns.db.global.sizing = { feedWidth = 500, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 }
			ns.db.global.styling = {
				growUp = false,
				fontSize = 12,
				fontFace = "Friz Quadrata TT",
				textAlignment = "LEFT",
				enabledSecondaryRowText = false,
				enableRowBorder = false,
				rowBackgroundType = 1,
			}
			ns.db.global.animations = { enter = { type = "fade", duration = 0.3 } }
			ns.db.global.item = { enabled = true }
			ns.db.global.partyLoot = { enabled = false }
			ns.db.global.currency = { enabled = true }
			ns.db.global.money = { enabled = true }
			ns.db.global.xp = { enabled = true }
			ns.db.global.rep = { enabled = true }
			ns.db.global.prof = { enabled = true }
			ns.db.global.travelPoints = { enabled = true }
			ns.db.global.transmog = { enabled = true }
			-- frames[1] was correctly written by v8 with the same values
			ns.db.global.frames = {
				[1] = {
					name = "Main",
					positioning = {
						anchorPoint = "TOPRIGHT",
						xOffset = 400,
						yOffset = 375,
						relativePoint = "UIParent",
						frameStrata = "MEDIUM",
					},
					sizing = { feedWidth = 500, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 },
					styling = {
						growUp = false,
						fontSize = 12,
						fontFace = "Friz Quadrata TT",
						textAlignment = "LEFT",
						enabledSecondaryRowText = false,
						enableRowBorder = false,
						rowBackgroundType = 1,
					},
					features = {
						itemLoot = { enabled = true },
						partyLoot = { enabled = false },
						currency = { enabled = true },
						money = { enabled = true },
						experience = { enabled = true },
						reputation = { enabled = true },
						profession = { enabled = true },
						travelPoints = { enabled = true },
						transmog = { enabled = true },
					},
				},
			}
			loadV9(ns)
			ns.migrations[9]:run()
			assert.is_nil(ns.db.global.pendingSettingsRecovery)
		end)

		it("still sets migrationVersion to 9", function()
			local ns = makeNs(8)
			ns.db.global.positioning = {
				anchorPoint = "BOTTOMLEFT",
				xOffset = 720,
				yOffset = 375,
				relativePoint = "UIParent",
				frameStrata = "MEDIUM",
			}
			ns.db.global.sizing = { feedWidth = 330, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 }
			ns.db.global.styling = {
				growUp = true,
				fontSize = 10,
				fontFace = "Friz Quadrata TT",
				textAlignment = "LEFT",
				enabledSecondaryRowText = false,
				enableRowBorder = false,
				rowBackgroundType = 1,
			}
			ns.db.global.item = { enabled = true }
			ns.db.global.frames = {
				[1] = {
					name = "Main",
					positioning = {
						anchorPoint = "BOTTOMLEFT",
						xOffset = 720,
						yOffset = 375,
						relativePoint = "UIParent",
						frameStrata = "MEDIUM",
					},
					sizing = { feedWidth = 330, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 },
					styling = {
						growUp = true,
						fontSize = 10,
						fontFace = "Friz Quadrata TT",
						textAlignment = "LEFT",
						enabledSecondaryRowText = false,
						enableRowBorder = false,
						rowBackgroundType = 1,
					},
					features = { itemLoot = { enabled = true } },
				},
			}
			loadV9(ns)
			ns.migrations[9]:run()
			assert.are.equal(9, ns.db.global.migrationVersion)
		end)
	end)

	describe("when migrationVersion < 9 and fresh install (no old flat keys)", function()
		it("does not store pendingSettingsRecovery", function()
			local ns = makeNs(8)
			ns.db.global.frames = { [1] = { name = "Main" } }
			-- No old flat keys — fresh install
			ns.db.global.positioning = nil
			loadV9(ns)
			ns.migrations[9]:run()
			assert.is_nil(ns.db.global.pendingSettingsRecovery)
		end)
	end)

	describe("when migrationVersion >= 9", function()
		it("is a no-op — does not set pendingSettingsRecovery", function()
			local ns = makeNs(9)
			setupSkippedV8State(ns)
			loadV9(ns)
			ns.migrations[9]:run()
			assert.is_nil(ns.db.global.pendingSettingsRecovery)
		end)

		it("does not change migrationVersion", function()
			local ns = makeNs(9)
			loadV9(ns)
			ns.migrations[9]:run()
			assert.are.equal(9, ns.db.global.migrationVersion)
		end)
	end)
end)
