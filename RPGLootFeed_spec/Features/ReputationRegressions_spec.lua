local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local mock = busted.mock
local setup = busted.setup
local spy = busted.spy
local stub = busted.stub

describe("Reputation Regressions", function()
	local _ = match._
	local RepModule, ns
	local reputationMocks, gossipInfoMocks, delvesUIMocks, majorFactionMocks

	setup(function()
		require("RPGLootFeed_spec._mocks.WoWGlobals")
		require("RPGLootFeed_spec._mocks.WoWGlobals.Enum")
		require("RPGLootFeed_spec._mocks.WoWGlobals.Functions")
		reputationMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_Reputation")
		majorFactionMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_MajorFactions")
		gossipInfoMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_GossipInfo")
		delvesUIMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_DelvesUI")
	end)

	before_each(function()
		stub(_G, "LibStub")
		_G.WOW_PROJECT_ID = 1
		_G.WOW_PROJECT_MISTS_CLASSIC = 1
		ns = {
			RLF = {
				SendMessage = function() end,
				NewModule = function()
					return {
						Enable = function() end,
						Disable = function() end,
						fn = function(self, func, ...)
							return func(...)
						end,
					}
				end,
			},
			db = {
				global = {
					animations = {
						exit = {
							fadeOutDelay = 5,
						},
					},
					rep = {
						enabled = true,
						defaultRepColor = { 1, 1, 1, 1 },
					},
				},
				locale = {
					factionMap = {},
				},
			},
			L = {},
		}

		assert(loadfile("RPGLootFeed/utils/AddonMethods.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/utils/Enums.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/utils/GameVersionHelpers.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/Features/_Internals/LootDisplayProperties.lua"))("TestAddon", ns)

		ns.db.locale.factionMap["Рыболовы"] = 12345

		RepModule = assert(loadfile("RPGLootFeed/Features/Reputation.lua"))("TestAddon", ns)
	end)

	it("handles The Anglers in MOP Classic, ruRU", function()
		local spyElementNew = spy.on(RepModule.Element, "new")
		_G.FACTION_STANDING_INCREASED_ACH_BONUS =
			'Отношение фракции "%s" к вам улучшилось на %d (+%.1f дополнительно).'

		RepModule:OnInitialize()
		RepModule:PLAYER_ENTERING_WORLD(true, false)

		local success = RepModule:CHAT_MSG_COMBAT_FACTION_CHANGE(
			"CHAT_MSG_COMBAT_FACTION_CHANGE",
			'Отношение фракции "Рыболовы" к вам улучшилось на 1100 (+550.0 дополнительно).'
		)

		assert.spy(spyElementNew).was.called_with(RepModule.Element, 1100, "Рыболовы", _, _, _, 12345, _, 3)
	end)
end)
