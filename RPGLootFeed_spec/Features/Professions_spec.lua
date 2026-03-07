---@diagnostic disable: need-check-nil
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local stub = busted.stub

describe("Professions Module", function()
	local _ = match._
	---@type RLF_Professions, table
	local Professions, ns, sendMessageSpy

	before_each(function()
		sendMessageSpy = spy.new(function() end)

		-- Build a minimal ns from scratch – no nsMocks framework needed.
		-- Only the fields actually referenced by Professions.lua and LootElementBase.lua
		-- are included; everything else is intentionally absent.
		ns = {
			-- Captured as locals by Professions.lua at load time.
			DefaultIcons = { PROFESSION = 134400 },
			ItemQualEnum = { Rare = 3 },
			FeatureModule = { Profession = "Profession" },
			-- WoWAPI stub so Professions._professionsAdapter = G_RLF.WoWAPI.Professions
			-- resolves at load time (overridden per-test in before_each).
			WoWAPI = { Professions = {} },
			-- Closure wrappers call these as G_RLF:Method(...).
			LogDebug = function() end,
			LogInfo = function() end,
			LogWarn = function() end,
			-- RGBAToHexFormat used by BuildPayload to build the color prefix.
			RGBAToHexFormat = function()
				return "|cFFFFFFFF"
			end,
			-- CreatePatternSegmentsForStringNumber / ExtractDynamicsFromPattern are
			-- namespace methods (G_RLF:Method(...)) so they receive ns as first arg.
			CreatePatternSegmentsForStringNumber = function()
				return {}
			end,
			ExtractDynamicsFromPattern = function()
				return nil, nil
			end,
			SendMessage = sendMessageSpy,
			-- Runtime lookups by LootElementBase:fromPayload() and lifecycle methods.
			db = {
				global = {
					animations = { exit = { fadeOutDelay = 3 } },
					prof = {
						enabled = true,
						enableIcon = true,
						skillColor = { 1, 1, 1, 1 },
						showSkillChange = true,
						skillTextWrapChar = ".",
					},
					misc = { hideAllIcons = false },
				},
			},
		}

		-- Load real LootElementBase so elements are fully constructed.
		assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
		assert.is_not_nil(ns.LootElementBase)

		-- Mock FeatureBase – returns a minimal stub module so Professions tests
		-- are completely independent of AceAddon plumbing.
		ns.FeatureBase = {
			new = function(_, name)
				return {
					moduleName = name,
					Enable = function() end,
					Disable = function() end,
					IsEnabled = function()
						return true
					end,
					RegisterEvent = function() end,
					UnregisterEvent = function() end,
				}
			end,
		}

		-- Load Professions – the FeatureBase mock above is captured at load time.
		Professions = assert(loadfile("RPGLootFeed/Features/Professions.lua"))("TestAddon", ns)

		-- Inject a fresh mock adapter so tests control external WoW API calls
		-- without patching _G directly.  Tests that need specific behaviour set
		-- adapter fields directly before the act step.
		Professions._professionsAdapter = {
			GetProfessions = function()
				return 1, 2, 3, 4, 5
			end,
			GetProfessionInfo = function(id)
				return "Profession" .. id, "icon" .. id, id * 10, id * 20
			end,
			IssecretValue = function()
				return false
			end,
			GetSkillRankUpPattern = function()
				return "%s %s" -- placeholder; CreatePatternSegments is mocked
			end,
		}

		Professions:OnInitialize()
	end)

	describe("module lifecycle", function()
		it("is enabled when configuration allows", function()
			local enableStub = stub(Professions, "Enable").returns()
			local disableStub = stub(Professions, "Disable").returns()

			ns.db.global.prof.enabled = true
			Professions:OnInitialize()
			assert.spy(enableStub).was.called(1)
			assert.spy(disableStub).was.not_called()

			enableStub:clear()
			disableStub:clear()

			ns.db.global.prof.enabled = false
			Professions:OnInitialize()
			assert.spy(disableStub).was.called(1)
			assert.spy(enableStub).was.not_called()
		end)

		it("registers events on enable", function()
			local registerStub = stub(Professions, "RegisterEvent").returns()
			Professions:OnEnable()
			assert.spy(registerStub).was.called_with(Professions, "PLAYER_ENTERING_WORLD")
			assert.spy(registerStub).was.called_with(Professions, "CHAT_MSG_SKILL")
		end)

		it("unregisters events on disable", function()
			local unregisterStub = stub(Professions, "UnregisterEvent").returns()
			Professions:OnDisable()
			assert.spy(unregisterStub).was.called_with(Professions, "PLAYER_ENTERING_WORLD")
			assert.spy(unregisterStub).was.called_with(Professions, "CHAT_MSG_SKILL")
		end)
	end)

	describe("InitializeProfessions", function()
		it("populates profNameIconMap from adapter", function()
			Professions:InitializeProfessions()
			assert.are.same("icon1", Professions.profNameIconMap["Profession1"])
			assert.are.same("icon2", Professions.profNameIconMap["Profession2"])
		end)

		it("populates profLocaleBaseNames with all profession names", function()
			Professions:InitializeProfessions()
			assert.are.equal(5, #Professions.profLocaleBaseNames)
		end)
	end)

	describe("PLAYER_ENTERING_WORLD", function()
		it("initializes professions on world enter", function()
			Professions:PLAYER_ENTERING_WORLD()
			assert.are.equal(5, #Professions.profLocaleBaseNames)
			assert.are.same("icon1", Professions.profNameIconMap["Profession1"])
		end)
	end)

	describe("CHAT_MSG_SKILL", function()
		it("does nothing when no skill level is extracted", function()
			-- default ExtractDynamicsFromPattern returns nil, nil
			Professions:CHAT_MSG_SKILL("CHAT_MSG_SKILL", "some message")
			assert.spy(sendMessageSpy).was.not_called()
		end)

		it("ignores messages flagged as secret values", function()
			Professions._professionsAdapter.IssecretValue = function()
				return true
			end
			local logWarnSpy = spy.new(function() end)
			ns.LogWarn = logWarnSpy

			Professions:CHAT_MSG_SKILL("CHAT_MSG_SKILL", "some secret message")

			assert.spy(logWarnSpy).was.called(1)
			assert.spy(sendMessageSpy).was.not_called()
		end)

		it("shows loot element when a skill level is extracted", function()
			Professions:PLAYER_ENTERING_WORLD()

			ns.ExtractDynamicsFromPattern = spy.new(function()
				return "Cooking", "150"
			end)
			-- Re-load to capture the new ExtractDynamicsFromPattern mock.
			Professions = assert(loadfile("RPGLootFeed/Features/Professions.lua"))("TestAddon", ns)
			Professions._professionsAdapter = {
				GetProfessions = function()
					return 1, 2, 3, 4, 5
				end,
				GetProfessionInfo = function(id)
					return "Profession" .. id, "icon" .. id, id * 10, id * 20
				end,
				IssecretValue = function()
					return false
				end,
				GetSkillRankUpPattern = function()
					return "%s %s"
				end,
			}
			Professions:OnInitialize()
			Professions:PLAYER_ENTERING_WORLD()

			Professions:CHAT_MSG_SKILL("CHAT_MSG_SKILL", "Cooking 150")

			assert.spy(sendMessageSpy).was.called(1)
		end)

		it("falls back to DefaultIcons.PROFESSION when skill has no mapped icon", function()
			local iconCapture = nil
			local origNew = ns.LootElementBase.new
			ns.LootElementBase.new = function(self)
				local el = origNew(self)
				el.Show = function(el_self)
					iconCapture = el_self.icon
				end
				return el
			end

			ns.ExtractDynamicsFromPattern = function()
				return "UnknownSkill", "99"
			end
			Professions = assert(loadfile("RPGLootFeed/Features/Professions.lua"))("TestAddon", ns)
			Professions._professionsAdapter = {
				GetProfessions = function()
					return 1, 2, 3, 4, 5
				end,
				GetProfessionInfo = function(id)
					return "Profession" .. id, "icon" .. id, id * 10, id * 20
				end,
				IssecretValue = function()
					return false
				end,
				GetSkillRankUpPattern = function()
					return "%s %s"
				end,
			}
			Professions:OnInitialize()
			Professions:PLAYER_ENTERING_WORLD()

			Professions:CHAT_MSG_SKILL("CHAT_MSG_SKILL", "UnknownSkill 99")

			assert.are.equal(134400, iconCapture)
		end)
	end)

	describe("BuildPayload", function()
		it("creates a payload correctly", function()
			local payload = Professions:BuildPayload(1, "Expansion1", "icon1", 10, 5)
			assert.are.same("PROF_1", payload.key)
			assert.are.same("Professions", payload.type)
			assert.are.same("icon1", payload.icon)
			assert.are.same(5, payload.quantity)
			assert.are.same(3, payload.quality)
			assert.is_not_nil(payload.textFn)
			assert.is_not_nil(payload.itemCountFn)
			assert.is_not_nil(payload.IsEnabled)
		end)

		it("sets quality to ItemQualEnum.Rare", function()
			local payload = Professions:BuildPayload(1, "Alchemy", "icon1", 150, 1)
			assert.are.equal(3, payload.quality)
		end)

		it("clears icon when enableIcon is false", function()
			ns.db.global.prof.enableIcon = false
			local payload = Professions:BuildPayload(1, "Cooking", "icon1", 10, 1)
			assert.is_nil(payload.icon)
		end)

		it("clears icon when hideAllIcons is true", function()
			ns.db.global.misc.hideAllIcons = true
			local payload = Professions:BuildPayload(1, "Cooking", "icon1", 10, 1)
			assert.is_nil(payload.icon)
		end)

		it("textFn returns colored name with skill level", function()
			local payload = Professions:BuildPayload(1, "Cooking", "icon1", 150, 1)
			local text = payload.textFn()
			assert.is_not_nil(text:find("Cooking"))
			assert.is_not_nil(text:find("150"))
		end)

		it("secondaryTextFn returns empty string", function()
			local payload = Professions:BuildPayload(1, "Cooking", "icon1", 150, 1)
			assert.are.equal("", payload.secondaryTextFn())
		end)

		it("IsEnabled delegates to Professions:IsEnabled", function()
			local payload = Professions:BuildPayload(1, "Alchemy", "icon1", 100, 1)
			assert.is_true(payload.IsEnabled())
		end)

		it("itemCountFn returns quantity and options when showSkillChange is enabled", function()
			ns.db.global.prof.showSkillChange = true
			local payload = Professions:BuildPayload(1, "Cooking", "icon1", 150, 5)
			local value, options = payload.itemCountFn()
			assert.are.equal(5, value)
			assert.are.equal(".", options.wrapChar)
			assert.is_true(options.showSign)
		end)

		it("itemCountFn returns nil when showSkillChange is disabled", function()
			ns.db.global.prof.showSkillChange = false
			local payload = Professions:BuildPayload(1, "Cooking", "icon1", 150, 5)
			local value = payload.itemCountFn()
			assert.is_nil(value)
		end)
	end)
end)
