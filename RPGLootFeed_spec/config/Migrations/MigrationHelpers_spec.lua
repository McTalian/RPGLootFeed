local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

--- Build a minimal namespace sufficient for MigrationHelpers.lua to load.
--- Uses an identity-metatable for L so L["Main"] -> "Main" without
--- needing a real locale file.
local function makeNs()
	local ns = {
		db = {
			global = {
				migrationVersion = 0,
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

describe("MigrationHelpers", function()
	describe("BuildV8RecoverySnapshot", function()
		local ns

		before_each(function()
			ns = makeNs()
			loadMigrationHelpers(ns)

			-- Minimal old flat tables representing a real v1-v7 upgrade
			ns.db.global.positioning = { anchorPoint = "TOPLEFT", xOffset = 100, yOffset = 200 }
			ns.db.global.sizing = { feedWidth = 400, maxRows = 8 }
			ns.db.global.styling = { growUp = false, fontSize = 12 }
			ns.db.global.animations = { enter = { type = "fade", duration = 0.3 } }
			ns.db.global.item = { enabled = true, enableIcon = true, itemCountTextEnabled = true }
			ns.db.global.partyLoot = { enabled = false }
			ns.db.global.currency = { enabled = true }
			ns.db.global.money = { enabled = true }
			ns.db.global.xp = { enabled = true }
			ns.db.global.rep = { enabled = true }
			ns.db.global.prof = { enabled = true }
			ns.db.global.travelPoints = { enabled = true }
			ns.db.global.transmog = { enabled = true }
		end)

		describe("when no old flat keys exist (fresh install)", function()
			it("returns nil when all flat keys are nil", function()
				ns.db.global.positioning = nil
				ns.db.global.sizing = nil
				ns.db.global.styling = nil
				ns.db.global.animations = nil
				ns.db.global.item = nil
				ns.db.global.partyLoot = nil
				ns.db.global.currency = nil
				ns.db.global.money = nil
				ns.db.global.xp = nil
				ns.db.global.rep = nil
				ns.db.global.prof = nil
				ns.db.global.travelPoints = nil
				ns.db.global.transmog = nil
				assert.is_nil(ns:BuildV8RecoverySnapshot(ns.db.global))
			end)
		end)

		describe("when old flat keys exist", function()
			it("returns a non-nil snapshot", function()
				assert.is_not_nil(ns:BuildV8RecoverySnapshot(ns.db.global))
			end)

			it("returns snapshot even when frames[1] exists as plain table", function()
				-- v8 ran correctly and wrote frames[1] — snapshot is still built
				-- (caller uses SnapshotDiffersFromFrame to decide if recovery is needed)
				ns.db.global.frames = { [1] = { name = "Main", positioning = { anchorPoint = "TOPLEFT" } } }
				assert.is_not_nil(ns:BuildV8RecoverySnapshot(ns.db.global))
			end)

			it("returns snapshot even when frames[1] is AceDB proxy", function()
				ns.db.global.frames = setmetatable({}, {
					__index = function(_, k)
						if k == 1 then
							return { name = "Main" }
						end
					end,
				})
				assert.is_not_nil(ns:BuildV8RecoverySnapshot(ns.db.global))
			end)

			it("snapshot name is 'Main'", function()
				local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
				assert.are.equal("Main", snapshot.name)
			end)

			it("snapshot positioning is copied from old flat keys", function()
				local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
				assert.are.equal("TOPLEFT", snapshot.positioning.anchorPoint)
				assert.are.equal(100, snapshot.positioning.xOffset)
				assert.are.equal(200, snapshot.positioning.yOffset)
			end)

			it("snapshot sizing is copied from old flat keys", function()
				local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
				assert.are.equal(400, snapshot.sizing.feedWidth)
				assert.are.equal(8, snapshot.sizing.maxRows)
			end)

			it("snapshot styling is copied from old flat keys", function()
				local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
				assert.is_false(snapshot.styling.growUp)
				assert.are.equal(12, snapshot.styling.fontSize)
			end)

			it("snapshot features include all feature keys", function()
				local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
				assert.is_not_nil(snapshot.features)
				assert.is_not_nil(snapshot.features.itemLoot)
				assert.is_not_nil(snapshot.features.partyLoot)
				assert.is_not_nil(snapshot.features.currency)
				assert.is_not_nil(snapshot.features.money)
				assert.is_not_nil(snapshot.features.experience)
				assert.is_not_nil(snapshot.features.reputation)
				assert.is_not_nil(snapshot.features.profession)
				assert.is_not_nil(snapshot.features.travelPoints)
				assert.is_not_nil(snapshot.features.transmog)
			end)

			it("snapshot features carry enabled flags from old tables", function()
				local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
				assert.is_true(snapshot.features.itemLoot.enabled)
				assert.is_false(snapshot.features.partyLoot.enabled)
				assert.is_true(snapshot.features.currency.enabled)
			end)

			it("snapshot is a deep copy — mutating source does not affect snapshot", function()
				local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
				ns.db.global.positioning.anchorPoint = "BOTTOMRIGHT"
				assert.are.equal("TOPLEFT", snapshot.positioning.anchorPoint)
			end)

			it("detects old data from feature keys even when positioning is nil", function()
				ns.db.global.positioning = nil
				ns.db.global.sizing = nil
				ns.db.global.styling = nil
				ns.db.global.animations = nil
				-- Only item flat key exists
				local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
				assert.is_not_nil(snapshot)
				assert.is_true(snapshot.features.itemLoot.enabled)
			end)
		end)

		describe("when global.frames is nil (schema not yet initialised)", function()
			it("returns a snapshot when old flat keys exist", function()
				ns.db.global.frames = nil
				local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
				assert.is_not_nil(snapshot)
				assert.are.equal("TOPLEFT", snapshot.positioning.anchorPoint)
			end)
		end)
	end)

	describe("SnapshotDiffersFromFrame", function()
		local ns

		before_each(function()
			ns = makeNs()
			loadMigrationHelpers(ns)
		end)

		it("returns true when snapshot is non-nil but currentFrame is nil", function()
			local snapshot = { positioning = {}, sizing = {}, styling = {}, features = {} }
			assert.is_true(ns:SnapshotDiffersFromFrame(snapshot, nil))
		end)

		it("returns false when both are nil", function()
			assert.is_false(ns:SnapshotDiffersFromFrame(nil, nil))
		end)

		it("returns false when positioning, sizing, styling, and features match", function()
			local snapshot = {
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
			}
			-- currentFrame has the same values
			local currentFrame = {
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
			}
			assert.is_false(ns:SnapshotDiffersFromFrame(snapshot, currentFrame))
		end)

		it("detects positioning anchorPoint difference", function()
			local snapshot = {
				positioning = {
					anchorPoint = "TOPRIGHT",
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
			}
			local currentFrame = {
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
			}
			assert.is_true(ns:SnapshotDiffersFromFrame(snapshot, currentFrame))
		end)

		it("detects sizing feedWidth difference", function()
			local snapshot = {
				positioning = {
					anchorPoint = "BOTTOMLEFT",
					xOffset = 720,
					yOffset = 375,
					relativePoint = "UIParent",
					frameStrata = "MEDIUM",
				},
				sizing = { feedWidth = 400, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 },
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
			}
			local currentFrame = {
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
			}
			assert.is_true(ns:SnapshotDiffersFromFrame(snapshot, currentFrame))
		end)

		it("detects feature enabled flag difference", function()
			local base = {
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
			}
			local snapshot = {
				positioning = base.positioning,
				sizing = base.sizing,
				styling = base.styling,
				features = { itemLoot = { enabled = true }, currency = { enabled = false } },
			}
			local currentFrame = {
				positioning = base.positioning,
				sizing = base.sizing,
				styling = base.styling,
				features = { itemLoot = { enabled = true }, currency = { enabled = true } },
			}
			assert.is_true(ns:SnapshotDiffersFromFrame(snapshot, currentFrame))
		end)

		it("detects styling difference", function()
			local base = {
				positioning = {
					anchorPoint = "BOTTOMLEFT",
					xOffset = 720,
					yOffset = 375,
					relativePoint = "UIParent",
					frameStrata = "MEDIUM",
				},
				sizing = { feedWidth = 330, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 },
			}
			local snapshot = {
				positioning = base.positioning,
				sizing = base.sizing,
				styling = {
					growUp = false,
					fontSize = 10,
					fontFace = "Friz Quadrata TT",
					textAlignment = "LEFT",
					enabledSecondaryRowText = false,
					enableRowBorder = false,
					rowBackgroundType = 1,
				},
				features = { itemLoot = { enabled = true } },
			}
			local currentFrame = {
				positioning = base.positioning,
				sizing = base.sizing,
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
			}
			assert.is_true(ns:SnapshotDiffersFromFrame(snapshot, currentFrame))
		end)

		it("detects deeply nested styling differences (e.g. fontShadowColor)", function()
			local base = {
				positioning = {
					anchorPoint = "BOTTOMLEFT",
					xOffset = 720,
					yOffset = 375,
					relativePoint = "UIParent",
					frameStrata = "MEDIUM",
				},
				sizing = { feedWidth = 330, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 },
			}
			local snapshot = {
				positioning = base.positioning,
				sizing = base.sizing,
				styling = {
					growUp = true,
					fontSize = 10,
					fontShadowColor = { 1, 0, 0, 1 },
				},
				features = { itemLoot = { enabled = true } },
			}
			local currentFrame = {
				positioning = base.positioning,
				sizing = base.sizing,
				styling = {
					growUp = true,
					fontSize = 10,
					fontShadowColor = { 0, 0, 0, 1 },
				},
				features = { itemLoot = { enabled = true } },
			}
			assert.is_true(ns:SnapshotDiffersFromFrame(snapshot, currentFrame))
		end)

		it("detects animation differences", function()
			local base = {
				positioning = {
					anchorPoint = "BOTTOMLEFT",
					xOffset = 720,
					yOffset = 375,
					relativePoint = "UIParent",
					frameStrata = "MEDIUM",
				},
				sizing = { feedWidth = 330, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 },
				styling = { growUp = true },
				features = { itemLoot = { enabled = true } },
			}
			local snapshot = {
				positioning = base.positioning,
				sizing = base.sizing,
				styling = base.styling,
				animations = { exit = { fadeOutDelay = 10 } },
				features = base.features,
			}
			local currentFrame = {
				positioning = base.positioning,
				sizing = base.sizing,
				styling = base.styling,
				animations = { exit = { fadeOutDelay = 5 } },
				features = base.features,
			}
			assert.is_true(ns:SnapshotDiffersFromFrame(snapshot, currentFrame))
		end)

		it("detects per-feature config differences beyond enabled flag", function()
			local base = {
				positioning = {
					anchorPoint = "BOTTOMLEFT",
					xOffset = 720,
					yOffset = 375,
					relativePoint = "UIParent",
					frameStrata = "MEDIUM",
				},
				sizing = { feedWidth = 330, maxRows = 10, rowHeight = 22, padding = 2, iconSize = 18 },
				styling = { growUp = true },
			}
			local snapshot = {
				positioning = base.positioning,
				sizing = base.sizing,
				styling = base.styling,
				features = { itemLoot = { enabled = true, enableIcon = false } },
			}
			local currentFrame = {
				positioning = base.positioning,
				sizing = base.sizing,
				styling = base.styling,
				features = { itemLoot = { enabled = true, enableIcon = true } },
			}
			assert.is_true(ns:SnapshotDiffersFromFrame(snapshot, currentFrame))
		end)
	end)

	describe("ComputeSnapshotDiff", function()
		local ns

		before_each(function()
			ns = makeNs()
			loadMigrationHelpers(ns)
		end)

		it("returns empty table when both are nil", function()
			local diffs = ns:ComputeSnapshotDiff(nil, nil)
			assert.are.equal(0, #diffs)
		end)

		it("returns empty table when snapshot and frame match", function()
			local data = {
				positioning = { anchorPoint = "BOTTOMLEFT", xOffset = 720 },
				sizing = { feedWidth = 330 },
				styling = { growUp = true },
				features = { itemLoot = { enabled = true } },
			}
			local diffs = ns:ComputeSnapshotDiff(data, data)
			assert.are.equal(0, #diffs)
		end)

		it("returns diff entries for differing scalar values", function()
			local snapshot = {
				positioning = { anchorPoint = "TOPRIGHT", xOffset = 400 },
				sizing = { feedWidth = 500 },
			}
			local current = {
				positioning = { anchorPoint = "BOTTOMLEFT", xOffset = 720 },
				sizing = { feedWidth = 330 },
			}
			local diffs = ns:ComputeSnapshotDiff(snapshot, current)
			assert.is_true(#diffs >= 3)
			-- Check that diff entries have the expected structure
			local found = {}
			for _, d in ipairs(diffs) do
				found[d.path] = { old = d.old, new = d.new }
			end
			assert.are.equal("TOPRIGHT", found["positioning.anchorPoint"].old)
			assert.are.equal("BOTTOMLEFT", found["positioning.anchorPoint"].new)
			assert.are.equal(500, found["sizing.feedWidth"].old)
			assert.are.equal(330, found["sizing.feedWidth"].new)
		end)

		it("returns diff entries for nested feature differences", function()
			local snapshot = {
				features = { itemLoot = { enabled = true, enableIcon = false } },
			}
			local current = {
				features = { itemLoot = { enabled = true, enableIcon = true } },
			}
			local diffs = ns:ComputeSnapshotDiff(snapshot, current)
			assert.are.equal(1, #diffs)
			assert.are.equal("features.itemLoot.enableIcon", diffs[1].path)
			assert.is_false(diffs[1].old)
			assert.is_true(diffs[1].new)
		end)

		it("includes keys present only in snapshot", function()
			local snapshot = {
				styling = { growUp = true, rowTextSpacing = 5 },
			}
			local current = {
				styling = { growUp = true },
			}
			local diffs = ns:ComputeSnapshotDiff(snapshot, current)
			assert.are.equal(1, #diffs)
			assert.are.equal("styling.rowTextSpacing", diffs[1].path)
			assert.are.equal(5, diffs[1].old)
			assert.is_nil(diffs[1].new)
		end)

		it("includes keys present only in current frame", function()
			local snapshot = {
				styling = { growUp = true },
			}
			local current = {
				styling = { growUp = true, rowTextSpacing = 5 },
			}
			local diffs = ns:ComputeSnapshotDiff(snapshot, current)
			assert.are.equal(1, #diffs)
			assert.are.equal("styling.rowTextSpacing", diffs[1].path)
			assert.is_nil(diffs[1].old)
			assert.are.equal(5, diffs[1].new)
		end)
	end)

	describe("BuildV8RecoverySnapshot partyLoot detection", function()
		local ns

		before_each(function()
			ns = makeNs()
			loadMigrationHelpers(ns)
		end)

		it("detects partyLoot with non-nil table even when enabled is nil", function()
			-- User customized partyLoot settings but never toggled enabled
			ns.db.global.partyLoot = { hideServerNames = true, onlyEpicAndAboveInRaid = false }
			local snapshot = ns:BuildV8RecoverySnapshot(ns.db.global)
			assert.is_not_nil(snapshot)
			assert.is_not_nil(snapshot.features.partyLoot)
		end)
	end)
end)
