local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

--- Build a minimal namespace with the helpers that v8 depends on.
local function makeNs(migrationVersion)
	local ns = {
		db = {
			global = {
				migrationVersion = migrationVersion or 0,
			},
		},
		migrations = {},
	}

	function ns:ShouldRunMigration(version)
		if ns.db.global.migrationVersion >= version then
			return false
		end
		return true
	end

	function ns:LogDebug(msg) end

	return ns
end

local function loadV8(ns)
	return assert(loadfile("RPGLootFeed/config/Migrations/v8.lua"))("TestAddon", ns)
end

describe("Migration v8", function()
	describe("when migrationVersion < 8", function()
		local ns

		before_each(function()
			ns = makeNs(7)
			ns.db.global.positioning = { anchorPoint = "BOTTOMLEFT", xOffset = 720, yOffset = 375 }
			ns.db.global.sizing = { feedWidth = 330, maxRows = 10 }
			ns.db.global.styling = { growUp = true, fontSize = 10 }
			ns.db.global.animations = {
				enter = { type = "fade", duration = 0.3 },
				exit = { duration = 1, fadeOutDelay = 5 },
			}
			-- Feature source tables (old top-level DB paths)
			ns.db.global.item = { enabled = true, enableIcon = true, itemCountTextEnabled = true }
			ns.db.global.partyLoot = { enabled = false }
			ns.db.global.currency = { enabled = true, enableIcon = true }
			ns.db.global.money = { enabled = true, enableIcon = true }
			ns.db.global.xp = { enabled = true, enableIcon = true }
			ns.db.global.rep = { enabled = true, enableIcon = true }
			ns.db.global.prof = { enabled = true, enableIcon = true }
			ns.db.global.travelPoints = { enabled = true, enableIcon = true }
			ns.db.global.transmog = { enabled = true, enableIcon = true }
		end)

		describe("frame 1 (Main)", function()
			it("creates frames[1] populated from existing global tables", function()
				loadV8(ns)
				ns.migrations[8]:run()

				local f1 = ns.db.global.frames[1]
				assert.is_not_nil(f1, "frames[1] should exist")
				assert.are.equal("Main", f1.name)
				assert.are.equal("BOTTOMLEFT", f1.positioning.anchorPoint)
				assert.are.equal(330, f1.sizing.feedWidth)
				assert.is_true(f1.styling.growUp)
				assert.are.equal("fade", f1.animations.enter.type)
			end)

			it("is a deep copy — mutating original does not change frame 1", function()
				loadV8(ns)
				ns.migrations[8]:run()

				ns.db.global.positioning.anchorPoint = "TOPRIGHT"
				assert.are.equal("BOTTOMLEFT", ns.db.global.frames[1].positioning.anchorPoint)

				-- Feature deep copy
				ns.db.global.item.enabled = false
				assert.is_true(ns.db.global.frames[1].features.itemLoot.enabled)
			end)

			it("copies feature configs from old top-level tables", function()
				loadV8(ns)
				ns.migrations[8]:run()

				local f = ns.db.global.frames[1].features
				assert.is_not_nil(f, "features table should exist")
				assert.is_not_nil(f.itemLoot)
				assert.is_not_nil(f.partyLoot)
				assert.is_not_nil(f.currency)
				assert.is_not_nil(f.money)
				assert.is_not_nil(f.experience)
				assert.is_not_nil(f.reputation)
				assert.is_not_nil(f.profession)
				assert.is_not_nil(f.travelPoints)
				assert.is_not_nil(f.transmog)
			end)

			it("sets the correct feature enabled flags", function()
				loadV8(ns)
				ns.migrations[8]:run()

				local f = ns.db.global.frames[1].features
				assert.is_true(f.itemLoot.enabled)
				-- partyLoot.enabled comes from db.global.partyLoot.enabled (false)
				assert.is_false(f.partyLoot.enabled)
				assert.is_true(f.currency.enabled)
				assert.is_true(f.money.enabled)
				assert.is_true(f.experience.enabled)
				assert.is_true(f.reputation.enabled)
				assert.is_true(f.profession.enabled)
				assert.is_true(f.travelPoints.enabled)
				assert.is_true(f.transmog.enabled)
			end)

			it("copies feature-specific settings from old tables", function()
				loadV8(ns)
				ns.migrations[8]:run()

				local f = ns.db.global.frames[1].features
				assert.is_true(f.itemLoot.enableIcon)
				assert.is_true(f.itemLoot.itemCountTextEnabled)
				assert.is_true(f.currency.enableIcon)
				assert.is_true(f.money.enableIcon)
			end)

			it("sets nextFrameId to 2 when no separate party frame", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.are.equal(2, ns.db.global.nextFrameId)
			end)
		end)

		describe("old global keys are preserved (copy-only migration)", function()
			it("does not remove global.positioning", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_not_nil(ns.db.global.positioning)
			end)

			it("does not remove global.sizing", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_not_nil(ns.db.global.sizing)
			end)

			it("does not remove global.styling", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_not_nil(ns.db.global.styling)
			end)

			it("does not remove global.animations", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_not_nil(ns.db.global.animations)
			end)

			it("does not remove old feature keys", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_not_nil(ns.db.global.item)
				assert.is_not_nil(ns.db.global.partyLoot)
				assert.is_not_nil(ns.db.global.currency)
				assert.is_not_nil(ns.db.global.money)
				assert.is_not_nil(ns.db.global.xp)
				assert.is_not_nil(ns.db.global.rep)
				assert.is_not_nil(ns.db.global.prof)
				assert.is_not_nil(ns.db.global.travelPoints)
				assert.is_not_nil(ns.db.global.transmog)
			end)
		end)

		describe("with separateFrame = true (Party frame migration)", function()
			before_each(function()
				ns.db.global.partyLoot = {
					separateFrame = true,
					enabled = true,
					positioning = { anchorPoint = "LEFT", xOffset = 0, yOffset = 375 },
					sizing = { feedWidth = 280, maxRows = 8 },
					styling = { growUp = false, fontSize = 9 },
				}
			end)

			it("creates frames[2] from partyLoot appearance settings", function()
				loadV8(ns)
				ns.migrations[8]:run()

				local f2 = ns.db.global.frames[2]
				assert.is_not_nil(f2, "frames[2] should exist")
				assert.are.equal("Party", f2.name)
				assert.are.equal("LEFT", f2.positioning.anchorPoint)
				assert.are.equal(280, f2.sizing.feedWidth)
				assert.is_false(f2.styling.growUp)
			end)

			it("frame 2 features has only partyLoot.enabled = true", function()
				loadV8(ns)
				ns.migrations[8]:run()

				local f = ns.db.global.frames[2].features
				assert.is_true(f.partyLoot.enabled)
				assert.is_false(f.itemLoot.enabled)
				assert.is_false(f.currency.enabled)
				assert.is_false(f.money.enabled)
				assert.is_false(f.experience.enabled)
				assert.is_false(f.reputation.enabled)
				assert.is_false(f.profession.enabled)
				assert.is_false(f.travelPoints.enabled)
				assert.is_false(f.transmog.enabled)
			end)

			it("sets frame 1 partyLoot.enabled to false", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_false(ns.db.global.frames[1].features.partyLoot.enabled)
			end)

			it("sets nextFrameId to 3", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.are.equal(3, ns.db.global.nextFrameId)
			end)

			it("inherits global animations as party frame baseline", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.are.equal("fade", ns.db.global.frames[2].animations.enter.type)
			end)

			it("does not remove partyLoot.separateFrame", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_true(ns.db.global.partyLoot.separateFrame)
			end)

			it("does not remove partyLoot.positioning", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_not_nil(ns.db.global.partyLoot.positioning)
			end)
		end)

		describe("with separateFrame = false", function()
			before_each(function()
				ns.db.global.partyLoot = { separateFrame = false, enabled = true }
			end)

			it("does not create frames[2]", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_nil(ns.db.global.frames[2])
			end)

			it("sets nextFrameId to 2", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.are.equal(2, ns.db.global.nextFrameId)
			end)

			it("preserves partyLoot.enabled on frame 1", function()
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_true(ns.db.global.frames[1].features.partyLoot.enabled)
			end)
		end)

		describe("with no partyLoot key", function()
			it("does not error and does not create frames[2]", function()
				ns.db.global.partyLoot = nil
				loadV8(ns)
				ns.migrations[8]:run()

				assert.is_nil(ns.db.global.frames[2])
			end)
		end)

		it("sets migrationVersion to 8", function()
			loadV8(ns)
			ns.migrations[8]:run()

			assert.are.equal(8, ns.db.global.migrationVersion)
		end)
	end)

	describe("when migrationVersion >= 8", function()
		it("is a no-op", function()
			local ns = makeNs(8)
			ns.db.global.positioning = { anchorPoint = "BOTTOMLEFT" }
			loadV8(ns)
			ns.migrations[8]:run()

			assert.is_nil(ns.db.global.frames)
		end)
	end)

	describe("idempotency", function()
		it("running twice does not overwrite frames[1]", function()
			local ns = makeNs(7)
			ns.db.global.positioning = { anchorPoint = "BOTTOMLEFT" }
			ns.db.global.sizing = {}
			ns.db.global.styling = {}
			ns.db.global.animations = { enter = { type = "fade" } }
			ns.db.global.item = { enabled = true }
			ns.db.global.currency = { enabled = true }
			ns.db.global.money = { enabled = true }
			ns.db.global.xp = { enabled = true }
			ns.db.global.rep = { enabled = true }
			ns.db.global.prof = { enabled = true }
			ns.db.global.travelPoints = { enabled = true }
			ns.db.global.transmog = { enabled = true }
			loadV8(ns)
			ns.migrations[8]:run()

			-- Manually change the name and re-run by resetting the version guard
			ns.db.global.frames[1].name = "Custom"
			ns.db.global.migrationVersion = 7

			ns.migrations[8]:run()
			-- frames[1] already existed, so the second run must not overwrite it
			assert.are.equal("Custom", ns.db.global.frames[1].name)
		end)
	end)

	describe("nil-source (no old AceDB defaults, user never changed anything)", function()
		local ns

		before_each(function()
			ns = makeNs(7)
			-- All old top-level tables are nil — simulates a user jumping from
			-- a version where the old AceDB defaults have already been removed.
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
		end)

		it("does not error and creates frames[1]", function()
			loadV8(ns)
			assert.has_no.errors(function()
				ns.migrations[8]:run()
			end)
			assert.is_not_nil(ns.db.global.frames[1])
		end)

		it("fills positioning from legacy defaults", function()
			loadV8(ns)
			ns.migrations[8]:run()
			local p = ns.db.global.frames[1].positioning
			assert.are.equal("BOTTOMLEFT", p.anchorPoint)
			assert.are.equal(720, p.xOffset)
			assert.are.equal(375, p.yOffset)
			assert.are.equal("MEDIUM", p.frameStrata)
			assert.are.equal("UIParent", p.relativePoint)
		end)

		it("fills sizing from legacy defaults", function()
			loadV8(ns)
			ns.migrations[8]:run()
			local s = ns.db.global.frames[1].sizing
			assert.are.equal(330, s.feedWidth)
			assert.are.equal(10, s.maxRows)
			assert.are.equal(22, s.rowHeight)
			assert.are.equal(2, s.padding)
			assert.are.equal(18, s.iconSize)
		end)

		it("fills styling from legacy defaults", function()
			loadV8(ns)
			ns.migrations[8]:run()
			local s = ns.db.global.frames[1].styling
			assert.is_true(s.growUp)
			assert.are.equal(10, s.fontSize)
			assert.are.equal("LEFT", s.textAlignment)
			assert.is_false(s.enabledSecondaryRowText)
			assert.is_false(s.enableRowBorder)
		end)

		it("fills animations from legacy defaults", function()
			loadV8(ns)
			ns.migrations[8]:run()
			local a = ns.db.global.frames[1].animations
			assert.are.equal("fade", a.enter.type)
			assert.are.equal(0.3, a.enter.duration)
			assert.are.equal("left", a.enter.slide.direction)
			assert.is_false(a.exit.disable)
			assert.are.equal(5, a.exit.fadeOutDelay)
			assert.is_true(a.hover.enabled)
			assert.is_false(a.update.disableHighlight)
		end)

		it("fills all feature configs from legacy defaults", function()
			loadV8(ns)
			ns.migrations[8]:run()
			local f = ns.db.global.frames[1].features

			-- Item loot
			assert.is_true(f.itemLoot.enabled)
			assert.is_true(f.itemLoot.enableIcon)
			assert.is_true(f.itemLoot.itemCountTextEnabled)
			assert.is_not_nil(f.itemLoot.itemQualitySettings[0])
			assert.is_true(f.itemLoot.itemQualitySettings[0].enabled)
			assert.are.equal(0, f.itemLoot.itemQualitySettings[0].duration)

			-- Party loot
			assert.is_false(f.partyLoot.enabled)
			assert.is_true(f.partyLoot.enableIcon)
			assert.is_true(f.partyLoot.itemQualityFilter[0])

			-- Currency
			assert.is_true(f.currency.enabled)
			assert.is_true(f.currency.enableIcon)
			assert.are.equal(0.7, f.currency.lowerThreshold)

			-- Money
			assert.is_true(f.money.enabled)
			assert.is_true(f.money.showMoneyTotal)
			assert.is_false(f.money.accountantMode)

			-- Experience
			assert.is_true(f.experience.enabled)
			assert.is_true(f.experience.showCurrentLevel)

			-- Reputation
			assert.is_true(f.reputation.enabled)
			assert.is_true(f.reputation.enableRepLevel)

			-- Profession
			assert.is_true(f.profession.enabled)
			assert.is_true(f.profession.showSkillChange)

			-- Travel Points
			assert.is_true(f.travelPoints.enabled)

			-- Transmog
			assert.is_true(f.transmog.enabled)
			assert.is_true(f.transmog.enableTransmogEffect)
		end)
	end)

	describe("sparse-source (source tables present but most keys nil)", function()
		local ns

		before_each(function()
			ns = makeNs(7)
			-- Only a few fields explicitly set — everything else should fall
			-- back to legacy defaults.
			ns.db.global.positioning = { anchorPoint = "TOPRIGHT" }
			ns.db.global.sizing = { feedWidth = 400 }
			ns.db.global.styling = { growUp = false }
			ns.db.global.animations = { exit = { fadeOutDelay = 10 } }
			ns.db.global.item = { enabled = true, enableIcon = false }
			ns.db.global.partyLoot = { enabled = true }
			ns.db.global.currency = {}
			ns.db.global.money = { accountantMode = true }
			ns.db.global.xp = {}
			ns.db.global.rep = {}
			ns.db.global.prof = {}
			ns.db.global.travelPoints = {}
			ns.db.global.transmog = {}
		end)

		it("uses explicit values where present", function()
			loadV8(ns)
			ns.migrations[8]:run()
			local f1 = ns.db.global.frames[1]

			assert.are.equal("TOPRIGHT", f1.positioning.anchorPoint)
			assert.are.equal(400, f1.sizing.feedWidth)
			assert.is_false(f1.styling.growUp)
			assert.are.equal(10, f1.animations.exit.fadeOutDelay)
			assert.is_false(f1.features.itemLoot.enableIcon)
			assert.is_true(f1.features.partyLoot.enabled)
			assert.is_true(f1.features.money.accountantMode)
		end)

		it("fills missing keys from legacy defaults", function()
			loadV8(ns)
			ns.migrations[8]:run()
			local f1 = ns.db.global.frames[1]

			-- positioning: only anchorPoint was set
			assert.are.equal(720, f1.positioning.xOffset)
			assert.are.equal(375, f1.positioning.yOffset)
			assert.are.equal("MEDIUM", f1.positioning.frameStrata)
			assert.are.equal("UIParent", f1.positioning.relativePoint)

			-- sizing: only feedWidth was set
			assert.are.equal(10, f1.sizing.maxRows)
			assert.are.equal(22, f1.sizing.rowHeight)

			-- styling: only growUp was set
			assert.are.equal(10, f1.styling.fontSize)
			assert.are.equal("LEFT", f1.styling.textAlignment)
			assert.is_false(f1.styling.enabledSecondaryRowText)

			-- animations: only exit.fadeOutDelay was set
			assert.are.equal("fade", f1.animations.enter.type)
			assert.are.equal(0.3, f1.animations.enter.duration)
			assert.are.equal(1, f1.animations.exit.duration)

			-- item: only enabled and enableIcon were set
			assert.is_true(f1.features.itemLoot.itemCountTextEnabled)
			assert.is_not_nil(f1.features.itemLoot.itemQualitySettings[0])

			-- currency: empty table — all from legacy defaults
			assert.is_true(f1.features.currency.enabled)
			assert.is_true(f1.features.currency.enableIcon)
			assert.are.equal(0.7, f1.features.currency.lowerThreshold)
		end)

		it("handles sparse item quality settings", function()
			-- User only changed Epic quality
			ns.db.global.item.itemQualitySettings = {
				[4] = { enabled = false },
			}
			loadV8(ns)
			ns.migrations[8]:run()
			local qs = ns.db.global.frames[1].features.itemLoot.itemQualitySettings

			-- Epic: user value for enabled, legacy default for duration
			assert.is_false(qs[4].enabled)
			assert.are.equal(0, qs[4].duration)

			-- Others: fully from legacy defaults
			assert.is_true(qs[0].enabled)
			assert.are.equal(0, qs[0].duration)
			assert.is_true(qs[3].enabled)
		end)

		it("handles sparse item highlights", function()
			ns.db.global.item.itemHighlights = { mounts = false }
			loadV8(ns)
			ns.migrations[8]:run()
			local h = ns.db.global.frames[1].features.itemLoot.itemHighlights

			assert.is_false(h.mounts)
			-- Others from legacy defaults
			assert.is_true(h.legendary)
			assert.is_true(h.betterThanEquipped)
			assert.is_false(h.quest)
		end)

		it("handles sparse sounds", function()
			ns.db.global.item.sounds = {
				mounts = { enabled = true },
			}
			loadV8(ns)
			ns.migrations[8]:run()
			local s = ns.db.global.frames[1].features.itemLoot.sounds

			-- Mounts: user enabled, legacy default for sound
			assert.is_true(s.mounts.enabled)
			assert.are.equal("", s.mounts.sound)

			-- Others: fully from legacy defaults
			assert.is_false(s.legendary.enabled)
		end)

		it("handles sparse party loot quality filter", function()
			ns.db.global.partyLoot.itemQualityFilter = {
				[0] = false, -- user disabled Poor quality
			}
			loadV8(ns)
			ns.migrations[8]:run()
			local qf = ns.db.global.frames[1].features.partyLoot.itemQualityFilter

			assert.is_false(qf[0])
			-- Others from legacy defaults
			assert.is_true(qf[1])
			assert.is_true(qf[4])
		end)
	end)
end)
