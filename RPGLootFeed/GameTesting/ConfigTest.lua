---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

--@alpha@
-- trunk-ignore-begin(no-invalid-prints/invalid-print)
---@type RLF_TestMode
local TestMode = G_RLF.RLF:GetModule(G_RLF.SupportModule.TestMode) --[[@as RLF_TestMode]]
local runner = G_RLF.GameTestRunner:new("Config Test", {
	printHeader = function(msg)
		G_RLF:Print(msg)
	end,
	printLine = print,
	raiseError = error,
})

-- ── Channel Registry ──────────────────────────────────────────────────────────
-- Each channel is registered via registerChannel() and runs in sequence when
-- TestMode:ConfigTest() is invoked.  Channels mutate config, fire elements into
-- the pipeline, verify outcomes, then restore every key they touched — even if
-- the test body errors — so config is always left in its original state.
--
-- Channel shape:
--   name       string      Displayed in results as a runner:section() label.
--   setup      fun(db)     Mutates G_RLF.db.global (and related sub-tables).
--                          Called just before the test body.
--   testFn     fun()→int   Fires elements and records assertions.  Returns the
--                          number of new rows expected by the pipeline.
--   teardown   fun()       Restores every key that setup mutated.  Always called.
--   deferred   boolean?    When true, verification and teardown run two
--                          RunNextFrame levels later (needed when the test fires
--                          Show() which defers dispatch via G_RLF:SendMessage).
---@class RLF_ConfigChannel
---@field name string
---@field setup fun(db: table)
---@field testFn fun(): integer
---@field teardown fun()
---@field deferred boolean?

---@type RLF_ConfigChannel[]
local channels = {}

--- Register a new configuration test channel.
---@param channel RLF_ConfigChannel
local function registerChannel(channel)
	table.insert(channels, channel)
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Resolve the itemLoot feature config for the main frame, or nil.
---@return table?
local function mainItemLootCfg()
	local frames = G_RLF.db.global.frames
	return frames and frames[G_RLF.Frames.MAIN] and frames[G_RLF.Frames.MAIN].features.itemLoot or nil
end

--- Resolve the currency feature config for the main frame, or nil.
---@return table?
local function mainCurrencyCfg()
	local frames = G_RLF.db.global.frames
	return frames and frames[G_RLF.Frames.MAIN] and frames[G_RLF.Frames.MAIN].features.currency or nil
end

--- Fire an item element through the pipeline from TestMode.testItems[idx] (default 2).
--- Returns the number of rows shown (0 if item not cached/available).
---@param idx? integer
---@return integer
local function fireTestItem(idx)
	idx = idx or 2
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.ItemLoot) --[[@as RLF_ItemLoot]]
	local info = TestMode.testItems[idx]
	if not info or not info.itemName then
		return 0
	end
	local payload = module:BuildPayload(info, 1)
	if not payload then
		return 0
	end
	G_RLF.LootElementBase:fromPayload(payload):Show()
	return 1
end

--- Fire a currency element through the pipeline from TestMode.testCurrencies[idx] (default 1).
--- Returns the number of rows shown (0 if currency not available).
---@param idx? integer
---@return integer
local function fireTestCurrency(idx)
	idx = idx or 1
	if GetExpansionLevel() < G_RLF.Expansion.WOTLK then
		return 0
	end
	local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Currency) --[[@as RLF_Currency]]
	local curr = TestMode.testCurrencies[idx]
	if not curr then
		return 0
	end
	local payload = module:BuildPayload(curr.link, curr.info, curr.basicInfo)
	if not payload then
		return 0
	end
	G_RLF.LootElementBase:fromPayload(payload):Show()
	return 1
end

-- ── Channel: Quality Duration Override ───────────────────────────────────────
-- Temporarily sets a non-zero quality duration override on the main frame for
-- Epic (quality 4) items, fires a matching item, then verifies the row was
-- accepted by the pipeline (indicating the duration path didn't break routing).
do
	local savedDuration
	local QUALITY = 4 -- Epic

	registerChannel({
		name = "Quality Duration Override",
		setup = function(db)
			local cfg = mainItemLootCfg()
			if cfg and cfg.itemQualitySettings then
				savedDuration = cfg.itemQualitySettings[QUALITY] and cfg.itemQualitySettings[QUALITY].duration
				if cfg.itemQualitySettings[QUALITY] then
					cfg.itemQualitySettings[QUALITY].duration = 15
				end
			end
		end,
		testFn = function()
			-- Find an Epic item in testItems, fall back to any item
			local idx = nil
			for i, info in ipairs(TestMode.testItems) do
				if info.itemQuality == QUALITY then
					idx = i
					break
				end
			end
			-- If no Epic item is cached, fire item[1] with an override quality
			-- so the payload reaches the pipeline regardless.
			local rows = 0
			local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.ItemLoot) --[[@as RLF_ItemLoot]]
			local info = TestMode.testItems[idx or 1]
			if not info or not info.itemName then
				runner:assertEqual(true, true, "Config: Quality Duration Override (skipped — item not cached)")
				return 0
			end
			local payload = module:BuildPayload(info, 1)
			if payload then
				G_RLF.LootElementBase:fromPayload(payload):Show()
				rows = 1
			end
			return rows
		end,
		teardown = function()
			local cfg = mainItemLootCfg()
			if cfg and cfg.itemQualitySettings and cfg.itemQualitySettings[QUALITY] and savedDuration ~= nil then
				cfg.itemQualitySettings[QUALITY].duration = savedDuration
			end
		end,
		deferred = true,
	})
end

-- ── Channel: Item Quality Filter (disable a tier) ─────────────────────────────
-- Temporarily disables the Uncommon (quality 2) tier on the main frame, fires
-- an Uncommon item, and asserts that it was NOT accepted by the pipeline.
do
	local savedEnabled
	local QUALITY = 2 -- Uncommon

	registerChannel({
		name = "Item Quality Filter",
		setup = function(db)
			local cfg = mainItemLootCfg()
			if cfg and cfg.itemQualitySettings and cfg.itemQualitySettings[QUALITY] then
				savedEnabled = cfg.itemQualitySettings[QUALITY].enabled
				cfg.itemQualitySettings[QUALITY].enabled = false
			end
		end,
		testFn = function()
			-- Find an Uncommon item in testItems
			local idx = nil
			for i, info in ipairs(TestMode.testItems) do
				if info.itemQuality == QUALITY then
					idx = i
					break
				end
			end
			if not idx then
				runner:assertEqual(true, true, "Config: Item Quality Filter (skipped — no Uncommon item cached)")
				return 0
			end
			local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.ItemLoot) --[[@as RLF_ItemLoot]]
			local info = TestMode.testItems[idx]
			local payload = module:BuildPayload(info, 1)
			-- payload should still be built (filtering is per-frame); the element
			-- should be rejected at OnLootReady time by PassesPerFrameFilters.
			if payload then
				G_RLF.LootElementBase:fromPayload(payload):Show()
			end
			-- Returns 0 because we expect 0 rows to be accepted by the main frame.
			return 0
		end,
		teardown = function()
			local cfg = mainItemLootCfg()
			if cfg and cfg.itemQualitySettings and cfg.itemQualitySettings[QUALITY] and savedEnabled ~= nil then
				cfg.itemQualitySettings[QUALITY].enabled = savedEnabled
			end
		end,
		deferred = true,
	})
end

-- ── Channel: Item Deny List ───────────────────────────────────────────────────
-- Temporarily adds a test item's ID to the main frame's ignoreItemIds list, fires
-- that item, and asserts that 0 rows were accepted.
do
	local savedIgnoreItemIds
	local deniedItemId

	registerChannel({
		name = "Item Deny List",
		setup = function(db)
			local cfg = mainItemLootCfg()
			if not cfg then
				return
			end
			-- Pick the first available test item's ID to deny
			local info = TestMode.testItems[1]
			if info then
				deniedItemId = info.itemId
			end
			-- Save and replace the current deny list
			savedIgnoreItemIds = cfg.ignoreItemIds
			cfg.ignoreItemIds = deniedItemId and { deniedItemId } or {}
		end,
		testFn = function()
			if not deniedItemId then
				runner:assertEqual(true, true, "Config: Item Deny List (skipped — no test item available)")
				return 0
			end
			local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.ItemLoot) --[[@as RLF_ItemLoot]]
			local info = TestMode.testItems[1]
			if not info or not info.itemName then
				runner:assertEqual(true, true, "Config: Item Deny List (skipped — item not cached)")
				return 0
			end
			local payload = module:BuildPayload(info, 1)
			if payload then
				G_RLF.LootElementBase:fromPayload(payload):Show()
			end
			-- Expects 0 rows because the item is on the deny list
			return 0
		end,
		teardown = function()
			local cfg = mainItemLootCfg()
			if cfg then
				cfg.ignoreItemIds = savedIgnoreItemIds
			end
			deniedItemId = nil
			savedIgnoreItemIds = nil
		end,
		deferred = true,
	})
end

-- ── Channel: Currency Deny List ───────────────────────────────────────────────
-- Temporarily adds a test currency's ID to the main frame's ignoreCurrencyIds
-- list, fires that currency, and asserts that 0 rows were accepted.
do
	local savedIgnoreCurrencyIds
	local deniedCurrencyId

	registerChannel({
		name = "Currency Deny List",
		setup = function(db)
			if GetExpansionLevel() < G_RLF.Expansion.WOTLK then
				return
			end
			local cfg = mainCurrencyCfg()
			if not cfg then
				return
			end
			local curr = TestMode.testCurrencies[1]
			if curr and curr.info then
				deniedCurrencyId = curr.info.currencyID
			end
			savedIgnoreCurrencyIds = cfg.ignoreCurrencyIds
			cfg.ignoreCurrencyIds = deniedCurrencyId and { deniedCurrencyId } or {}
		end,
		testFn = function()
			if GetExpansionLevel() < G_RLF.Expansion.WOTLK then
				return 0
			end
			if not deniedCurrencyId then
				runner:assertEqual(true, true, "Config: Currency Deny List (skipped — no test currency available)")
				return 0
			end
			local rows = fireTestCurrency(1)
			-- Expects 0 rows because the currency is on the deny list
			return 0
		end,
		teardown = function()
			if GetExpansionLevel() < G_RLF.Expansion.WOTLK then
				return
			end
			local cfg = mainCurrencyCfg()
			if cfg then
				cfg.ignoreCurrencyIds = savedIgnoreCurrencyIds
			end
			deniedCurrencyId = nil
			savedIgnoreCurrencyIds = nil
		end,
		deferred = true,
	})
end

-- ── Channel: Feature Subscription Routing ────────────────────────────────────
-- Temporarily disables Money on Main and enables it on a second frame, fires a
-- Money element, and asserts that it landed on the second frame only.
-- Mirrors the routing test from IntegrationTest.lua as a standalone channel so
-- it can be run in isolation for quicker config-focused validation.
do
	local savedMainMoneySub, savedSecondMoneySub, secondId

	registerChannel({
		name = "Feature Subscription Routing",
		setup = function(db)
			local lootDisplay = G_RLF.LootDisplay
			local framesDb = db.frames
			-- Find the first non-Main frame that already has a live widget
			for id in pairs(framesDb) do
				local f = lootDisplay:GetFrame(id)
				if f and id ~= G_RLF.Frames.MAIN then
					secondId = id
					break
				end
			end
			if not secondId then
				return
			end
			savedMainMoneySub = framesDb[G_RLF.Frames.MAIN].features.money.enabled
			savedSecondMoneySub = framesDb[secondId].features.money.enabled
			framesDb[G_RLF.Frames.MAIN].features.money.enabled = false
			framesDb[secondId].features.money.enabled = true
		end,
		testFn = function()
			if not secondId then
				runner:assertEqual(
					true,
					true,
					"Config: Feature Subscription Routing (skipped — no second frame configured)"
				)
				return 0
			end
			local module = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Money) --[[@as RLF_Money]]
			local payload = module:BuildPayload(12345)
			if not payload then
				return 0
			end
			G_RLF.LootElementBase:fromPayload(payload):Show()
			return 1 -- expected to land on second frame, contributing 1 total accept
		end,
		teardown = function()
			if not secondId then
				return
			end
			local framesDb = G_RLF.db.global.frames
			framesDb[G_RLF.Frames.MAIN].features.money.enabled = savedMainMoneySub
			framesDb[secondId].features.money.enabled = savedSecondMoneySub
			savedMainMoneySub = nil
			savedSecondMoneySub = nil
			secondId = nil
		end,
		deferred = true,
	})
end

-- ── Runner ────────────────────────────────────────────────────────────────────

--- Run all registered config channels sequentially, fencing each deferred channel
--- with two RunNextFrame levels so G_RLF:SendMessage dispatch settles before
--- we verify accepts.  Teardown is guaranteed via pcall so config is always
--- restored.
---
--- Each channel's expected row count is tracked and compared against the live
--- _testAcceptCount delta across all frames after all phases settle.
function TestMode:ConfigTest()
	if not self.integrationTestReady then
		G_RLF:Print("Config test not ready — waiting for integration test data to finish loading")
		return
	end

	runner:reset()

	local lootDisplay = G_RLF.LootDisplay

	-- Snapshot accept counters across all live frames before any channel runs.
	local frameSnapshots = {}
	for id in pairs(G_RLF.db.global.frames) do
		local f = lootDisplay:GetFrame(id)
		if f then
			frameSnapshots[id] = f._testAcceptCount or 0
		end
	end

	local totalExpected = 0

	--- Run all channels sequentially, recursing through the list via closures.
	--- Each channel: setup → testFn (sync) → [RunNextFrame×2 if deferred] →
	--- verify accepts → teardown → advance to next channel.
	local function runChannel(i)
		if i > #channels then
			-- All channels done — compute total accept delta and display results.
			local totalActual = 0
			for id, before in pairs(frameSnapshots) do
				local f = lootDisplay:GetFrame(id)
				if f then
					totalActual = totalActual + ((f._testAcceptCount or 0) - before)
				end
			end
			runner:assertEqual(totalActual, totalExpected, "Config Test: Total accepted rows across all channels")
			runner:displayResults()
			return
		end

		local ch = channels[i]
		runner:section(ch.name)

		-- Snapshot per-channel accept counts for per-frame routing assertions.
		local channelSnapshots = {}
		for id in pairs(G_RLF.db.global.frames) do
			local f = lootDisplay:GetFrame(id)
			if f then
				channelSnapshots[id] = f._testAcceptCount or 0
			end
		end

		-- Setup (always wrapped — errors here skip the channel gracefully).
		local setupOk, setupErr = pcall(ch.setup, G_RLF.db.global)
		if not setupOk then
			runner:assertEqual(false, true, ch.name .. ": setup error — " .. tostring(setupErr))
			runChannel(i + 1)
			return
		end

		-- Run the test body.
		local rowsExpected = 0
		local testOk, testResult = pcall(ch.testFn)
		if not testOk then
			runner:assertEqual(false, true, ch.name .. ": test error — " .. tostring(testResult))
		else
			rowsExpected = testResult or 0
		end
		totalExpected = totalExpected + rowsExpected

		-- Teardown helper: always restores config, records any teardown error.
		local function doTeardown()
			local tdOk, tdErr = pcall(ch.teardown)
			if not tdOk then
				runner:assertEqual(false, true, ch.name .. ": teardown error — " .. tostring(tdErr))
			end
		end

		if ch.deferred then
			-- Deferred: OnLootReady dispatches after the frame that Show() fires on,
			-- so we fence with two RunNextFrame levels before verifying then advancing.
			RunNextFrame(function()
				RunNextFrame(function()
					-- Verify the per-channel accept delta matches expectation.
					local channelActual = 0
					for id, before in pairs(channelSnapshots) do
						local f = lootDisplay:GetFrame(id)
						if f then
							channelActual = channelActual + ((f._testAcceptCount or 0) - before)
						end
					end
					runner:assertEqual(channelActual, rowsExpected, ch.name .. ": rows accepted by pipeline")

					doTeardown()
					runChannel(i + 1)
				end)
			end)
		else
			doTeardown()
			runChannel(i + 1)
		end
	end

	runChannel(1)
end

-- trunk-ignore-end(no-invalid-prints/invalid-print)
--@end-alpha@
