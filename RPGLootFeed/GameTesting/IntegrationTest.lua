---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

--@alpha@
-- trunk-ignore-begin(no-invalid-prints/invalid-print)
---@type RLF_TestMode
local TestMode = G_RLF.RLF:GetModule("TestMode") --[[@as RLF_TestMode]]
local tests = {}
local prints = ""
local successCount = 0
local failureCount = 0

local function assertEqual(actual, expected, testName, err)
	tests[testName] = {
		result = actual == expected,
		expected = expected,
		actual = actual,
		err = err,
	}
	if actual == expected then
		prints = prints .. "|cff00ff00•|r"
		successCount = successCount + 1
	else
		prints = prints .. "|cffff0000x|r"
		failureCount = failureCount + 1
	end
end

local function runTestSafely(testFunction, testName, ...)
	local success, err = pcall(testFunction, ...)
	assertEqual(success, true, testName, err)
end

local function displayResults()
	G_RLF:Print("Integration Test")
	print(prints)
	print("|cff00ff00Successes: " .. successCount .. "|r")
	if failureCount > 0 then
		print("|cffff0000Failures: " .. failureCount .. "|r")
	end

	local msg = ""
	for testName, testData in pairs(tests) do
		if not testData.result then
			msg = msg
				.. "|cffff0000Failure: "
				.. testName
				.. " failed: expected "
				.. tostring(testData.expected)
				.. ", got "
				.. tostring(testData.actual)
			if testData.err then
				msg = msg .. " Error: " .. testData.err
			end
			msg = msg .. "|r|n\n"
		end
	end

	if failureCount > 0 then
		error(msg)
	end
end

local function runExperienceIntegrationTest()
	local module = G_RLF.RLF:GetModule("Experience") --[[@as RLF_Experience]]
	local e = module.Element:new(1337)
	runTestSafely(e.Show, "LootDisplay: Experience", e)
	return 1
end

local function runMoneyIntegrationTest()
	local module = G_RLF.RLF:GetModule("Money") --[[@as RLF_Money]]
	local e = module.Element:new(12345)
	if not e then
		G_RLF:Print("Money element not created, something went wrong")
		return 1
	end
	runTestSafely(e.Show, "LootDisplay: Money", e)
	return 1
end

local function runItemLootIntegrationTest()
	local module = G_RLF.RLF:GetModule("ItemLoot") --[[@as RLF_ItemLoot]]
	local info = TestMode.testItems[2]
	local amountLooted = 1
	local rowsShown = 0
	local e = module.Element:new(info, amountLooted)
	if info.itemName == nil then
		G_RLF:Print("Item not cached, skipping ItemLoot test")
	else
		e.highlight = true
		runTestSafely(e.Show, "LootDisplay: Item", e, info.itemName, info.itemQuality)
		e = module.Element:new(info, amountLooted)
		e.highlight = true
		runTestSafely(e.Show, "LootDisplay: Item Quantity Update", e, info.itemName, info.itemQuality)
		rowsShown = rowsShown + 1
	end
	return rowsShown
end

local function runPartyLootIntegrationTest()
	local module = G_RLF.RLF:GetModule("PartyLoot") --[[@as RLF_PartyLoot]]
	local info = TestMode.testItems[2]
	local amountLooted = 1
	local e = module.Element:new(info, amountLooted, "player")
	runTestSafely(e.Show, "LootDisplay: Party Item", e, info.itemName, info.itemQuality)
	return 1
end

local function runCurrencyIntegrationTest()
	local module = G_RLF.RLF:GetModule("Currency") --[[@as RLF_Currency]]
	local testObj = TestMode.testCurrencies[2]
	local amountLooted = 1
	testObj.basicInfo.displayAmount = amountLooted
	local e = module.Element:new(testObj.link, testObj.info, testObj.basicInfo)
	if not e then
		G_RLF:Print("Currency element not created, something went wrong")
		return 1
	end
	runTestSafely(e.Show, "LootDisplay: Currency", e)
	e = module.Element:new(testObj.link, testObj.info, testObj.basicInfo)
	if not e then
		G_RLF:Print("Currency update element not created, something went wrong")
		return 1
	end
	runTestSafely(e.Show, "LootDisplay: Currency Quantity Update", e)
	return 1
end

local function runReputationIntegrationTest()
	local module = G_RLF.RLF:GetModule("Reputation") --[[@as RLF_Reputation]]
	local testObj = TestMode.testFactions[2]
	local amountLooted = 664
	local e = module.Element:new(amountLooted, testObj)
	runTestSafely(e.Show, "LootDisplay: Reputation", e)
	e = module.Element:new(amountLooted, testObj)
	runTestSafely(e.Show, "LootDisplay: Reputation Quantity Update", e)
	return 1
end

local function runProfessionIntegrationTest()
	local module = G_RLF.RLF:GetModule("Professions") --[[@as RLF_Professions]]
	local icon = "4620671"
	-- So far, MoP Classic and below doesn't have this icon
	if not G_RLF:IsRetail() then
		icon = G_RLF.DefaultIcons.PROFESSION
	end
	local e = module.Element:new("Cooking", "Cooking", icon, 3, nil, 1)
	runTestSafely(e.Show, "LootDisplay: Professions", e)
	e = module.Element:new("Cooking", "Cooking", icon, 4, nil, 2)
	runTestSafely(e.Show, "LootDisplay: Professions Quantity Update", e)
	return 1
end

function TestMode:IntegrationTest()
	if not self.integrationTestReady then
		G_RLF:Print("Integration test not ready")
		return
	end

	tests = {}
	prints = ""
	successCount = 0
	failureCount = 0
	local frame = G_RLF.RLF_MainLootFrame
	if not frame then
		assertEqual(frame, true, "G_RLF.RLF_MainLootFrame")
		return
	end
	local snapshotRowHistory = #frame.rowHistory or 0
	local partyFrame = nil
	if G_RLF.db.global.partyLoot.enabled and G_RLF.db.global.partyLoot.separateFrame then
		partyFrame = G_RLF.RLF_PartyLootFrame
		if not partyFrame then
			assertEqual(partyFrame, true, "G_RLF.RLF_PartyLootFrame")
			return
		end
		snapshotRowHistory = snapshotRowHistory + #partyFrame.rowHistory
	end

	local newRowsExpected = 0
	newRowsExpected = newRowsExpected + runExperienceIntegrationTest()
	newRowsExpected = newRowsExpected + runMoneyIntegrationTest()
	newRowsExpected = newRowsExpected + runItemLootIntegrationTest()
	if GetExpansionLevel() >= G_RLF.Expansion.SL then
		newRowsExpected = newRowsExpected + runCurrencyIntegrationTest()
	end
	if G_RLF.db.global.partyLoot.enabled then
		newRowsExpected = newRowsExpected + runPartyLootIntegrationTest()
	end
	newRowsExpected = newRowsExpected + runReputationIntegrationTest()
	newRowsExpected = newRowsExpected + runProfessionIntegrationTest()

	assertEqual(frame ~= nil, true, "G_RLF.RLF_MainLootFrame")
	C_Timer.After(
		G_RLF.db.global.animations.exit.fadeOutDelay + G_RLF.db.global.animations.exit.duration + 1,
		function()
			local newHistoryRows = #frame.rowHistory - snapshotRowHistory
			if partyFrame then
				newHistoryRows = newHistoryRows + #partyFrame.rowHistory
			end
			assertEqual(newHistoryRows, newRowsExpected, "G_RLF.RLF_MainLootFrame: rowHistory")
			displayResults()
		end
	)
end

-- trunk-ignore-end(no-invalid-prints/invalid-print)
--@end-alpha@
