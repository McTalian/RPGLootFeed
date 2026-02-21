---@see RLF_Communications
local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local setup = busted.setup
local spy = busted.spy
local stub = busted.stub
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it

describe("Communications module", function()
	local _ = match._

	describe("load order", function()
		it("loads the file successfully", function()
			local ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.FeatureInternals)
			local communicationsModule =
				assert(loadfile("RPGLootFeed/Features/_Internals/RLF_Communications.lua"))("TestAddon", ns)
			assert.is_not_nil(communicationsModule)
			assert.is_function(communicationsModule.OnInitialize)
			assert.is_function(communicationsModule.OnEnable)
			assert.is_function(communicationsModule.OnDisable)
			assert.is_function(communicationsModule.TransmitSay)
			assert.is_function(communicationsModule.TransmitYell)
			assert.is_function(communicationsModule.TransmitChannel)
			assert.is_function(communicationsModule.TransmitWhisper)
			assert.is_function(communicationsModule.TransmitParty)
			assert.is_function(communicationsModule.TransmitRaid)
			assert.is_function(communicationsModule.TransmitGuild)
			assert.is_function(communicationsModule.TransmitInstance)
			assert.is_function(communicationsModule.OnCommReceived)
			assert.is_function(communicationsModule.QueryGroupVersion)
			assert.is_function(communicationsModule.GROUP_JOINED)
			assert.is_function(communicationsModule.PLAYER_ENTERING_WORLD)
		end)
	end)

	describe("functionality", function()
		---@type test_G_RLF, RLF_Communications
		local ns, module, globalMocks
		before_each(function()
			require("RPGLootFeed_spec._mocks.WoWGlobals")
			globalMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.Functions")
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
			module = assert(loadfile("RPGLootFeed/Features/_Internals/RLF_Communications.lua"))("TestAddon", ns)
		end)

		after_each(function()
			globalMocks.IsInGuild:clear()
			globalMocks.IsInGroup:clear()
			globalMocks.IsInRaid:clear()
			nsMocks.LogDebug:clear()
		end)

		it("initializes the module", function()
			local spyLogDebug = nsMocks.LogDebug
			local spyEnable = spy.on(module, "Enable")

			module:OnInitialize()

			assert.spy(spyLogDebug).was.called(1)
			assert.spy(spyLogDebug).was.called_with(ns, "Communications:OnInitialize")
			assert.spy(spyEnable).was.called(1)
			assert.spy(spyEnable).was.called_with(module)
		end)

		it("enables the module", function()
			local spyLogDebug = nsMocks.LogDebug
			local spyRegisterComm = spy.on(module, "RegisterComm")
			local spyRegisterEvent = spy.on(module, "RegisterEvent")

			module:OnEnable()

			assert.spy(spyLogDebug).was.called(1)
			assert.spy(spyLogDebug).was.called_with(ns, "Communications:OnEnable")
			assert.equal(ns.addonVersion, module.lastVersionEncountered)
			assert.spy(spyRegisterComm).was.called_with(module, "TestAddon")
			assert.spy(spyRegisterEvent).was.called(2)
			assert.spy(spyRegisterEvent).was.called_with(module, "GROUP_JOINED")
			assert.spy(spyRegisterEvent).was.called_with(module, "PLAYER_ENTERING_WORLD")
		end)

		it("disables the module", function()
			local spyLogDebug = nsMocks.LogDebug
			local spyUnregisterAllComm = spy.on(module, "UnregisterAllComm")
			local spyUnregisterAllEvents = spy.on(module, "UnregisterAllEvents")

			module:OnDisable()

			assert.spy(spyLogDebug).was.called(1)
			assert.spy(spyLogDebug).was.called_with(ns, "Communications:OnDisable")
			assert.spy(spyUnregisterAllComm).was.called(1)
			assert.spy(spyUnregisterAllComm).was.called_with(module)
			assert.spy(spyUnregisterAllEvents).was.called(1)
			assert.spy(spyUnregisterAllEvents).was.called_with(module)
		end)

		it("queries group version upon joining a group", function()
			local spyLogDebug = nsMocks.LogDebug
			local spyQueryGroupVersion = spy.on(module, "QueryGroupVersion")
			local spyIsInGroup = globalMocks.IsInGroup.returns(false)
			local spyIsInRaid = globalMocks.IsInRaid.returns(false)

			module:GROUP_JOINED("GROUP_JOINED", "party", "12345abcde")

			assert.spy(spyLogDebug).was.called(1)
			assert
				.spy(spyLogDebug).was
				.called_with(ns, "GROUP_JOINED", "WOWEVENT", module.moduleName, nil, "GROUP_JOINED party 12345abcde")
			assert.spy(spyQueryGroupVersion).was.called(1)
			assert
				.spy(spyQueryGroupVersion).was
				.called_with(module, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
			assert.spy(spyIsInGroup).was.called(2)
			assert.spy(spyIsInRaid).was.called(2)
		end)

		describe("QueryGroupVersion", function()
			after_each(function()
				globalMocks.IsInGroup:clear()
				globalMocks.IsInRaid:clear()
				globalMocks.IsInGuild:clear()
			end)

			it("transmits to instance", function()
				local spyTransmitInstance = spy.on(module, "TransmitInstance")
				local spyTransmitRaid = spy.on(module, "TransmitRaid")
				local spyTransmitParty = spy.on(module, "TransmitParty")
				local spyIsInGroup = globalMocks.IsInGroup.invokes(function(t)
					if t == LE_PARTY_CATEGORY_INSTANCE then
						return true
					else
						return true
					end
				end)
				local spyIsInRaid = globalMocks.IsInRaid.returns(false)

				module:QueryGroupVersion(string.format(ns.CommsMessages.VERSION, ns.addonVersion))

				assert.spy(spyTransmitInstance).was.called(1)
				assert
					.spy(spyTransmitInstance).was
					.called_with(module, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
				assert.spy(spyTransmitRaid).was.called(0)
				assert.spy(spyTransmitParty).was.called(0)
				assert.spy(spyIsInGroup).was.called(1)
				assert.spy(spyIsInRaid).was.called(0)
			end)

			it("transmits to raid", function()
				local spyTransmitInstance = spy.on(module, "TransmitInstance")
				local spyTransmitRaid = spy.on(module, "TransmitRaid")
				local spyTransmitParty = spy.on(module, "TransmitParty")
				local spyIsInGroup = globalMocks.IsInGroup.invokes(function(t)
					if t == LE_PARTY_CATEGORY_INSTANCE then
						return false
					else
						return true
					end
				end)
				local spyIsInRaid = globalMocks.IsInRaid.invokes(function(t)
					if t == LE_PARTY_CATEGORY_INSTANCE then
						return false
					else
						return true
					end
				end)

				module:QueryGroupVersion(string.format(ns.CommsMessages.VERSION, ns.addonVersion))

				assert.spy(spyTransmitInstance).was.called(0)
				assert.spy(spyTransmitRaid).was.called(1)
				assert
					.spy(spyTransmitRaid).was
					.called_with(module, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
				assert.spy(spyTransmitParty).was.called(0)
				assert.spy(spyIsInGroup).was.called(1)
				assert.spy(spyIsInRaid).was.called(2)
			end)

			it("transmits to party", function()
				local spyTransmitInstance = spy.on(module, "TransmitInstance")
				local spyTransmitRaid = spy.on(module, "TransmitRaid")
				local spyTransmitParty = spy.on(module, "TransmitParty")
				local spyIsInGroup = globalMocks.IsInGroup.invokes(function(t)
					if t == LE_PARTY_CATEGORY_INSTANCE then
						return false
					else
						return true
					end
				end)
				local spyIsInRaid = globalMocks.IsInRaid.returns(false)

				module:QueryGroupVersion(string.format(ns.CommsMessages.VERSION, ns.addonVersion))

				assert.spy(spyTransmitInstance).was.called(0)
				assert.spy(spyTransmitRaid).was.called(0)
				assert.spy(spyTransmitParty).was.called(1)
				assert
					.spy(spyTransmitParty).was
					.called_with(module, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
				assert.spy(spyIsInGroup).was.called(2)
				assert.spy(spyIsInRaid).was.called(2)
			end)
		end)

		it("queries for new versions on enter world", function()
			local spyLogDebug = nsMocks.LogDebug
			local spyQueryGroupVersion = spy.on(module, "QueryGroupVersion")
			local spyTransmitGuild = spy.on(module, "TransmitGuild")
			local spyTransmitYell = spy.on(module, "TransmitYell")
			local spyTransmitChannel = spy.on(module, "TransmitChannel")
			globalMocks.IsInGuild.returns(true)
			globalMocks.IsInGroup.returns(false)
			globalMocks.IsInRaid.returns(false)
			nsMocks.IsClassic.returns(false)
			local expectedMessage = string.format(ns.CommsMessages.VERSION, ns.addonVersion)

			module:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", true, false)

			assert.spy(spyLogDebug).was.called(2)
			assert
				.spy(spyLogDebug).was
				.called_with(ns, "PLAYER_ENTERING_WORLD", "WOWEVENT", module.moduleName, nil, "PLAYER_ENTERING_WORLD true false")
			assert.spy(spyLogDebug).was.called_with(ns, "TransmitGuild " .. expectedMessage)
			assert.spy(spyQueryGroupVersion).was.called(1)
			assert
				.spy(spyQueryGroupVersion).was
				.called_with(_, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
			assert.spy(globalMocks.IsInGuild).was.called(1)
			assert.spy(spyTransmitGuild).was.called(1)
			assert.spy(spyTransmitGuild).was.called_with(_, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
			assert.spy(spyTransmitYell).was.called(0)
			assert.spy(spyTransmitChannel).was.called(0)
		end)

		it("queries for new versions on enter world pre-Shadowlands", function()
			local spyLogDebug = nsMocks.LogDebug
			local spyQueryGroupVersion = spy.on(module, "QueryGroupVersion")
			local spyTransmitGuild = spy.on(module, "TransmitGuild")
			local spyTransmitYell = spy.on(module, "TransmitYell")
			local spyTransmitChannel = spy.on(module, "TransmitChannel")
			globalMocks.GetExpansionLevel.returns(3)
			globalMocks.IsInGuild.returns(true)
			globalMocks.IsInGroup.returns(false)
			globalMocks.IsInRaid.returns(false)
			nsMocks.IsClassic.returns(false)
			local expectedMessage = string.format(ns.CommsMessages.VERSION, ns.addonVersion)

			module:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", true, false)

			assert.spy(spyLogDebug).was.called(2)
			assert
				.spy(spyLogDebug).was
				.called_with(ns, "PLAYER_ENTERING_WORLD", "WOWEVENT", module.moduleName, nil, "PLAYER_ENTERING_WORLD true false")
			assert.spy(spyLogDebug).was.called_with(ns, "TransmitGuild " .. expectedMessage)
			assert.spy(spyQueryGroupVersion).was.called(1)
			assert
				.spy(spyQueryGroupVersion).was
				.called_with(_, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
			assert.spy(globalMocks.IsInGuild).was.called(1)
			assert.spy(spyTransmitGuild).was.called(1)
			assert.spy(spyTransmitGuild).was.called_with(_, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
			assert.spy(spyTransmitYell).was.called(0)
			assert.spy(spyTransmitChannel).was.called(0)
		end)

		it("queries for new versions on enter world via yell for Classic", function()
			local spyLogDebug = nsMocks.LogDebug
			local spyQueryGroupVersion = spy.on(module, "QueryGroupVersion")
			local spyTransmitGuild = spy.on(module, "TransmitGuild")
			local spyTransmitYell = spy.on(module, "TransmitYell")
			local spyTransmitChannel = spy.on(module, "TransmitChannel")
			globalMocks.IsInGuild.returns(false)
			globalMocks.IsInGroup.returns(false)
			globalMocks.IsInRaid.returns(false)
			nsMocks.IsClassic.returns(true)
			local expectedMessage = string.format(ns.CommsMessages.VERSION, ns.addonVersion)

			module:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", false, true)

			assert.spy(spyLogDebug).was.called(2)
			assert
				.spy(spyLogDebug).was
				.called_with(ns, "PLAYER_ENTERING_WORLD", "WOWEVENT", module.moduleName, nil, "PLAYER_ENTERING_WORLD false true")
			assert.spy(spyLogDebug).was.called_with(ns, "TransmitYell " .. expectedMessage)
			assert.spy(spyQueryGroupVersion).was.called(1)
			assert
				.spy(spyQueryGroupVersion).was
				.called_with(module, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
			assert.spy(globalMocks.IsInGuild).was.called(1)
			assert.spy(spyTransmitGuild).was.called(0)
			assert.spy(spyTransmitYell).was.called(1)
			assert
				.spy(spyTransmitYell).was
				.called_with(module, string.format(ns.CommsMessages.VERSION, ns.addonVersion))
			assert.spy(spyTransmitChannel).was.called(0)
		end)

		describe("OnCommReceived", function()
			local expectedPrefix = "TestAddon"
			it("ignores messages without our prefix", function()
				local spyLogDebug = nsMocks.LogDebug
				local payload = "Some other message"
				local distribution = "WHISPER"
				local sender = "TestSender"

				module:OnCommReceived("SomeOtherAddon", payload, distribution, sender)

				assert.spy(spyLogDebug).was.called(0)
			end)

			it("ignores messages from ourselves", function()
				local spyLogDebug = nsMocks.LogDebug
				local payload = string.format(ns.CommsMessages.VERSION, ns.addonVersion)
				local distribution = "WHISPER"
				local sender = "Player"

				module:OnCommReceived(expectedPrefix, payload, distribution, sender)

				assert.spy(spyLogDebug).was.called(0)
			end)

			it("skips non-stable releases", function()
				local spyLogDebug = nsMocks.LogDebug
				nsMocks.IsRLFStableRelease.returns(false)
				local payload = string.format(ns.CommsMessages.VERSION, "1.0.1")
				local distribution = "WHISPER"
				local sender = "TestSender"

				module:OnCommReceived(expectedPrefix, payload, distribution, sender)

				assert.spy(spyLogDebug).was.called(2)
				assert
					.spy(spyLogDebug).was
					.called_with(ns, "OnCommReceived " .. expectedPrefix .. " " .. payload .. " " .. distribution .. " " .. sender)
				assert.spy(spyLogDebug).was.called_with(ns, "RLF is in alpha/beta, ignoring version check")
			end)

			it("creates a notification if a non-whisper has a newer version", function()
				local spyLogDebug = nsMocks.LogDebug
				nsMocks.IsRLFStableRelease.returns(true)
				nsMocks.CompareWithVersion.returns(ns.VersionCompare.NEWER)
				local spyAddNotification = nsMocks.Notifications.AddNotification
				local payload = string.format(ns.CommsMessages.VERSION, "1.0.2")
				local distribution = "PARTY"
				local sender = "TestSender"

				module:OnCommReceived(expectedPrefix, payload, distribution, sender)

				assert.spy(spyLogDebug).was.called(1)
				assert
					.spy(spyLogDebug).was
					.called_with(ns, "OnCommReceived " .. expectedPrefix .. " " .. payload .. " " .. distribution .. " " .. sender)
				assert.equal("1.0.2", module.lastVersionEncountered)
				assert.spy(spyAddNotification).was.called(1)
				assert
					.spy(spyAddNotification).was
					.called_with(
						ns.Notifications,
						ns.NotificationKeys.VERSION,
						string.format(ns.L["New version available"], "1.0.2")
					)
			end)

			it("whispers the requester if our version is newer than theirs", function()
				local spyLogDebug = nsMocks.LogDebug
				nsMocks.IsRLFStableRelease.returns(true)
				nsMocks.CompareWithVersion.returns(ns.VersionCompare.OLDER)
				local spyAddNotification = nsMocks.Notifications.AddNotification
				local spyTransmitWhisper = spy.on(module, "TransmitWhisper")
				local payload = string.format(ns.CommsMessages.VERSION, "1.0.2")
				local distribution = "PARTY"
				local sender = "TestSender"

				ns.addonVersion = "1.0.3"
				module.lastVersionEncountered = "1.0.3"

				module:OnCommReceived(expectedPrefix, payload, distribution, sender)

				assert.spy(spyLogDebug).was.called(2)
				assert
					.spy(spyLogDebug).was
					.called_with(ns, "OnCommReceived " .. expectedPrefix .. " " .. payload .. " " .. distribution .. " " .. sender)
				assert
					.spy(spyLogDebug).was
					.called_with(ns, "TransmitWhisper " .. string.format(ns.CommsMessages.VERSION, "1.0.3") .. " to " .. sender)
				assert.equal("1.0.3", module.lastVersionEncountered)
				assert.spy(spyAddNotification).was.called(0)
				assert.spy(spyTransmitWhisper).was.called(1)
				assert
					.spy(spyTransmitWhisper).was
					.called_with(module, string.format(ns.CommsMessages.VERSION, "1.0.3"), sender)
			end)

			it("adds a notification if a whisper response contains a newer version", function()
				local spyLogDebug = nsMocks.LogDebug
				nsMocks.IsRLFStableRelease.returns(true)
				nsMocks.CompareWithVersion.returns(ns.VersionCompare.NEWER)
				local spyAddNotification = nsMocks.Notifications.AddNotification
				local payload = string.format(ns.CommsMessages.VERSION, "1.0.2")
				local distribution = "WHISPER"
				local sender = "TestSender"

				module.lastVersionEncountered = "1.0.0"

				module:OnCommReceived(expectedPrefix, payload, distribution, sender)

				assert.spy(spyLogDebug).was.called(1)
				assert
					.spy(spyLogDebug).was
					.called_with(ns, "OnCommReceived " .. expectedPrefix .. " " .. payload .. " " .. distribution .. " " .. sender)
				assert.equal("1.0.2", module.lastVersionEncountered)
				assert.spy(spyAddNotification).was.called(1)
				assert
					.spy(spyAddNotification).was
					.called_with(
						ns.Notifications,
						ns.NotificationKeys.VERSION,
						string.format(ns.L["New version available"], "1.0.2")
					)
			end)
		end)
	end)
end)
