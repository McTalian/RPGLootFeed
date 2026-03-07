---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

--@alpha@
-- trunk-ignore-begin(no-invalid-prints/invalid-print)
---@type RLF_TestMode
local TestMode = G_RLF.RLF:GetModule(G_RLF.SupportModule.TestMode) --[[@as RLF_TestMode]]
local runner = G_RLF.GameTestRunner:new("Integration Test", {
	printHeader = function(msg)
		G_RLF:Print(msg)
	end,
	printLine = print,
	raiseError = error,
})

local function runExperienceIntegrationTest()
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Experience) --[[@as RLF_Experience]]
	local LootElementBase = G_RLF.LootElementBase

	local payload = module:BuildPayload(1336)
	if not payload then
		G_RLF:Print("Experience payload not created, something went wrong")
		return 1
	end
	local e = LootElementBase:fromPayload(payload)
	runner:runTestSafely(e.Show, "LootDisplay: Experience", e)

	local payload2 = module:BuildPayload(1)
	if not payload2 then
		G_RLF:Print("Experience update payload not created, something went wrong")
		return 1
	end
	local e2 = LootElementBase:fromPayload(payload2)
	runner:runTestSafely(e2.Show, "LootDisplay: Experience Update", e2)
	return 1
end

local function runMoneyIntegrationTest()
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Money) --[[@as RLF_Money]]
	local payload = module:BuildPayload(12345)
	if not payload then
		G_RLF:Print("Money payload not created, something went wrong")
		return 1
	end
	local e = G_RLF.LootElementBase:fromPayload(payload)
	runner:runTestSafely(e.Show, "LootDisplay: Money", e)
	return 1
end

local function runTravelPointsIntegrationTest()
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.TravelPoints) --[[@as RLF_TravelPoints]]
	local payload = module:BuildPayload(50)
	local e = G_RLF.LootElementBase:fromPayload(payload)
	runner:runTestSafely(e.Show, "LootDisplay: TravelPoints", e)
	return 1
end

local function runItemLootIntegrationTest()
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.ItemLoot) --[[@as RLF_ItemLoot]]
	local info = TestMode.testItems[2]
	local amountLooted = 1
	local rowsShown = 0
	local e = module.Element:new(info, amountLooted)
	if info.itemName == nil then
		G_RLF:Print("Item not cached, skipping ItemLoot test")
	else
		e.highlight = true
		runner:runTestSafely(e.Show, "LootDisplay: Item", e, info.itemName, info.itemQuality)
		e = module.Element:new(info, amountLooted)
		e.highlight = true
		runner:runTestSafely(e.Show, "LootDisplay: Item Quantity Update", e, info.itemName, info.itemQuality)
		rowsShown = rowsShown + 1
	end
	return rowsShown
end

--- Exercises the PartyLoot BuildPayload → fromPayload → Show pipeline directly.
local function runPartyLootIntegrationTest()
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.PartyLoot) --[[@as RLF_PartyLoot]]
	local LootElementBase = G_RLF.LootElementBase
	local info = TestMode.testItems[2]
	local amountLooted = 1
	local payload = module:BuildPayload(info, amountLooted, "player")
	if not payload then
		G_RLF:Print("PartyLoot payload not created, something went wrong")
		return 1
	end
	local e = LootElementBase:fromPayload(payload)
	runner:runTestSafely(e.Show, "LootDisplay: Party Item", e, info.itemName, info.itemQuality)
	return 1
end

--- Exercises the Currency BuildPayload → fromPayload → Show pipeline directly.
local function runCurrencyIntegrationTest()
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Currency) --[[@as RLF_Currency]]
	local LootElementBase = G_RLF.LootElementBase
	local testObj = TestMode.testCurrencies[2]
	local amountLooted = 1
	testObj.basicInfo.displayAmount = amountLooted
	local payload = module:BuildPayload(testObj.link, testObj.info, testObj.basicInfo)
	if not payload then
		G_RLF:Print("Currency payload not created, something went wrong")
		return 1
	end
	local e = LootElementBase:fromPayload(payload)
	runner:runTestSafely(e.Show, "LootDisplay: Currency", e)
	payload = module:BuildPayload(testObj.link, testObj.info, testObj.basicInfo)
	if not payload then
		G_RLF:Print("Currency update payload not created, something went wrong")
		return 1
	end
	e = LootElementBase:fromPayload(payload)
	runner:runTestSafely(e.Show, "LootDisplay: Currency Quantity Update", e)
	return 1
end

--- Builds a synthetic UnifiedFactionData and exercises the
--- BuildPayload → fromPayload → Show pipeline directly.
--- Works on both Retail and Classic since it bypasses the event layer.
local function runReputationPayloadIntegrationTest()
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Reputation) --[[@as RLF_Reputation]]
	local LootElementBase = G_RLF.LootElementBase

	---@type UnifiedFactionData
	local testFactionData = {
		factionId = 99999,
		name = TestMode.testFactions[1] or "Test Faction",
		delta = 668,
		icon = G_RLF.DefaultIcons.REPUTATION,
		standing = 21000,
		rank = "Honored",
		quality = G_RLF.ItemQualEnum.Rare,
		contextInfo = "Integration test context",
	}

	local payload = module:BuildPayload(testFactionData)
	if not payload then
		G_RLF:Print("Reputation payload not created, something went wrong")
		return 1
	end
	local e = LootElementBase:fromPayload(payload)
	runner:runTestSafely(e.Show, "LootDisplay: Reputation", e)

	-- Second call with same key should stack/update the existing row
	local payload2 = module:BuildPayload(testFactionData)
	if not payload2 then
		G_RLF:Print("Reputation update payload not created, something went wrong")
		return 1
	end
	payload2.quantity = payload2.quantity + 1
	local e2 = LootElementBase:fromPayload(payload2)
	runner:runTestSafely(e2.Show, "LootDisplay: Reputation Update", e2)

	return 1
end

local function runReputationIntegrationTest()
	local rowsShown = runReputationPayloadIntegrationTest()

	-- On non-Retail (Classic), also exercise the CHAT_MSG_COMBAT_FACTION_CHANGE event path
	if
		not G_RLF:IsRetail()
		or not C_EventUtils.IsEventValid
		or not C_EventUtils.IsEventValid("FACTION_STANDING_CHANGED")
	then
		local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Reputation) --[[@as RLF_Reputation]]
		local amountLooted = 664

		local testObj = TestMode.testFactions[2]
		runner:runTestSafely(
			module.CHAT_MSG_COMBAT_FACTION_CHANGE,
			"LootDisplay: Reputation with Bonus (Chat)",
			module,
			"CHAT_MSG_COMBAT_FACTION_CHANGE",
			string.format(_G.FACTION_STANDING_INCREASED_ACH_BONUS, testObj, amountLooted, amountLooted / 2)
		)
		runner:runTestSafely(
			module.CHAT_MSG_COMBAT_FACTION_CHANGE,
			"LootDisplay: Reputation with Bonus Update (Chat)",
			module,
			"CHAT_MSG_COMBAT_FACTION_CHANGE",
			string.format(_G.FACTION_STANDING_INCREASED_ACH_BONUS, testObj, amountLooted, amountLooted / 2)
		)

		testObj = TestMode.testFactions[1]
		runner:runTestSafely(
			module.CHAT_MSG_COMBAT_FACTION_CHANGE,
			"LootDisplay: Reputation (Chat)",
			module,
			"CHAT_MSG_COMBAT_FACTION_CHANGE",
			string.format(_G.FACTION_STANDING_INCREASED, testObj, 1030)
		)
		runner:runTestSafely(
			module.CHAT_MSG_COMBAT_FACTION_CHANGE,
			"LootDisplay: Reputation Update (Chat)",
			module,
			"CHAT_MSG_COMBAT_FACTION_CHANGE",
			string.format(_G.FACTION_STANDING_INCREASED, testObj, 307)
		)
		rowsShown = rowsShown + 2
	end

	return rowsShown
end

--- Exercises the Profession BuildPayload → fromPayload → Show pipeline directly.
local function runProfessionIntegrationTest()
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Profession) --[[@as RLF_Professions]]
	local LootElementBase = G_RLF.LootElementBase
	local icon = 4620671
	-- So far, MoP Classic and below doesn't have this icon
	if not G_RLF:IsRetail() then
		icon = G_RLF.DefaultIcons.PROFESSION
	end
	local payload = module:BuildPayload("Cooking", "Cooking", icon, 3, 1)
	local e = LootElementBase:fromPayload(payload)
	runner:runTestSafely(e.Show, "LootDisplay: Professions", e)
	payload = module:BuildPayload("Cooking", "Cooking", icon, 4, 2)
	e = LootElementBase:fromPayload(payload)
	runner:runTestSafely(e.Show, "LootDisplay: Professions Quantity Update", e)
	return 1
end

local function runTransmogIntegrationTest()
	local appearanceId = 285269
	if not G_RLF:IsRetail() then
		return 0
	end
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Transmog) --[[@as RLF_Transmog]]
	runner:runTestSafely(
		module.TRANSMOG_COLLECTION_SOURCE_ADDED,
		"LootDisplay: Transmog",
		module,
		"TRANSMOG_COLLECTION_SOURCE_ADDED",
		appearanceId
	)
	return 1
end

function TestMode:IntegrationTest()
	if not self.integrationTestReady then
		G_RLF:Print("Integration test not ready")
		return
	end

	runner:reset()
	local frame = G_RLF.RLF_MainLootFrame
	if not frame then
		runner:assertEqual(frame, true, "G_RLF.RLF_MainLootFrame")
		return
	end
	local snapshotRowHistory = #frame.rowHistory or 0
	local partyFrame = nil
	if G_RLF.db.global.partyLoot.enabled and G_RLF.db.global.partyLoot.separateFrame then
		partyFrame = G_RLF.RLF_PartyLootFrame
		if not partyFrame then
			runner:assertEqual(partyFrame, true, "G_RLF.RLF_PartyLootFrame")
			return
		end
		snapshotRowHistory = snapshotRowHistory + #partyFrame.rowHistory
	end

	local newRowsExpected = 0
	newRowsExpected = newRowsExpected + runExperienceIntegrationTest()
	newRowsExpected = newRowsExpected + runMoneyIntegrationTest()
	if G_RLF:IsRetail() then
		newRowsExpected = newRowsExpected + runTravelPointsIntegrationTest()
	end
	newRowsExpected = newRowsExpected + runItemLootIntegrationTest()
	if GetExpansionLevel() >= G_RLF.Expansion.WOTLK then
		newRowsExpected = newRowsExpected + runCurrencyIntegrationTest()
	end
	if G_RLF.db.global.partyLoot.enabled then
		newRowsExpected = newRowsExpected + runPartyLootIntegrationTest()
	end
	newRowsExpected = newRowsExpected + runReputationIntegrationTest()
	newRowsExpected = newRowsExpected + runProfessionIntegrationTest()
	if G_RLF.db.global.transmog.enabled then
		newRowsExpected = newRowsExpected + runTransmogIntegrationTest()
	end

	runner:assertEqual(frame ~= nil, true, "G_RLF.RLF_MainLootFrame")
	C_Timer.After(
		G_RLF.db.global.animations.exit.fadeOutDelay + G_RLF.db.global.animations.exit.duration + 1,
		function()
			local newHistoryRows = #frame.rowHistory - snapshotRowHistory
			if partyFrame then
				newHistoryRows = newHistoryRows + #partyFrame.rowHistory
			end
			runner:assertEqual(newHistoryRows, newRowsExpected, "G_RLF.RLF_MainLootFrame: rowHistory")
			runner:displayResults()
		end
	)
end

-- trunk-ignore-end(no-invalid-prints/invalid-print)
--@end-alpha@
