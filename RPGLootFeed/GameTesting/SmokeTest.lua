---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local C = LibStub("C_Everywhere")

--@alpha@
-- trunk-ignore-begin(no-invalid-prints/invalid-print)
---@type RLF_TestMode
local TestMode = G_RLF.RLF:GetModule(G_RLF.SupportModule.TestMode) --[[@as RLF_TestMode]]
local runner = G_RLF.GameTestRunner:new("Smoke Test", {
	printHeader = function(msg)
		G_RLF:Print(msg)
	end,
	printLine = print,
	raiseError = error,
})

local function testGetItemInfo(id)
	local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType, expansionID, _, isCraftingReagent =
		C.Item.GetItemInfo(id)
	runner:assertEqual(itemName ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemName")
	runner:assertEqual(itemLink ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemLink")
	runner:assertEqual(itemQuality ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemQuality")
	runner:assertEqual(itemLevel ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemLevel")
	runner:assertEqual(itemMinLevel ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemMinLevel")
	runner:assertEqual(itemType ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemType")
	runner:assertEqual(itemSubType ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemSubType")
	runner:assertEqual(itemStackCount ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemStackCount")
	runner:assertEqual(itemEquipLoc ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemEquipLoc")
	runner:assertEqual(itemTexture ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").itemTexture")
	runner:assertEqual(sellPrice ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").sellPrice")
	runner:assertEqual(classID ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").classID")
	runner:assertEqual(subclassID ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").subclassID")
	runner:assertEqual(bindType ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").bindType")
	runner:assertEqual(expansionID ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").expansionID")
	runner:assertEqual(isCraftingReagent ~= nil, true, "Global: C.Item.GetItemInfo(" .. id .. ").isCraftingReagent")
end

local function testWoWGlobals()
	runner:assertEqual(type(EventRegistry), "table", "Global: EventRegistry")
	runner:assertEqual(type(C.CVar.SetCVar), "function", "Global C.CVar.SetCVar")
	local value, defaultValue, isStoredServerAccount, isStoredServerCharacter, isLockedFromUser, isSecure, isReadonly =
		C.CVar.GetCVarInfo("autoLootDefault")
	runner:assertEqual(value ~= nil, true, "Global: C.CVar.GetCVarInfo autoLootDefault value")
	runner:assertEqual(defaultValue ~= nil, true, "Global: C.CVar.GetCVarInfo autoLootDefault defaultValue")
	runner:assertEqual(
		isStoredServerAccount ~= nil,
		true,
		"Global: C.CVar.GetCVarInfo autoLootDefault isStoredServerAccount"
	)
	runner:assertEqual(
		isStoredServerCharacter ~= nil,
		true,
		"Global: C.CVar.GetCVarInfo autoLootDefault isStoredServerCharacter"
	)
	runner:assertEqual(isLockedFromUser ~= nil, true, "Global: C.CVar.GetCVarInfo autoLootDefault isLockedFromUser")
	runner:assertEqual(isSecure ~= nil, true, "Global: C.CVar.GetCVarInfo autoLootDefault isSecure")
	runner:assertEqual(isReadonly ~= nil, true, "Global: C.CVar.GetCVarInfo autoLootDefault isReadonly")
	runner:assertEqual(type(ChatFrameUtil.ForEachChatFrame), "function", "Global: ChatFrameUtil.ForEachChatFrame")
	runner:assertEqual(type(ChatFrame_RemoveMessageGroup), "function", "Global: ChatFrame_RemoveMessageGroup")
	runner:assertEqual(type(Enum.ItemQuality), "table", "Global: Enum.ItemQuality")
	runner:assertEqual(type(GetFonts), "function", "Global: GetFonts")

	if GetExpansionLevel() > G_RLF.Expansion.CLASSIC then
		runner:assertEqual(type(GetPlayerGuid), "function", "Global: GetPlayerGuid")
	end

	if GetExpansionLevel() >= G_RLF.Expansion.DF then
		runner:assertEqual(type(GetNameAndServerNameFromGUID), "function", "Global: GetNameAndServerNameFromGUID")
	end

	if GetExpansionLevel() >= G_RLF.Expansion.WOD then
		runner:assertEqual(type(BossBanner), "table", "Global: BossBanner")
	end

	runner:assertEqual(type(LootAlertSystem.AddAlert), "function", "Global: LootAlertSystem.AddAlert")

	if GetExpansionLevel() >= G_RLF.Expansion.WOTLK then
		runner:assertEqual(type(C.CurrencyInfo.GetCurrencyInfo), "function", "Global: C.CurrencyInfo.GetCurrencyInfo")
		local info = C.CurrencyInfo.GetCurrencyInfo(241)
		runner:assertEqual(info ~= nil, true, "Global: C.CurrencyInfo.GetCurrencyInfo(241)")
		runner:assertEqual(info.description ~= nil, true, "Global: C.CurrencyInfo.GetCurrencyInfo(241).description")
		runner:assertEqual(info.iconFileID ~= nil, true, "Global: C.CurrencyInfo.GetCurrencyInfo(241).iconFileID")
		runner:assertEqual(info.currencyID ~= nil, true, "Global: C.CurrencyInfo.GetCurrencyInfo(241).currencyID")
	end
	if GetExpansionLevel() >= G_RLF.Expansion.SL then
		runner:assertEqual(C.CurrencyInfo.GetCurrencyLink(1813) ~= nil, true, "Global: C.CurrencyInfo.GetCurrencyLink")
	end

	runner:assertEqual(type(UnitXP), "function", "Global: UnitXP")
	runner:assertEqual(type(UnitXPMax), "function", "Global: UnitXPMax")
	runner:assertEqual(type(UnitLevel), "function", "Global: UnitLevel")
	runner:assertEqual(type(C.Item.GetItemInfo), "function", "Global: C.Item.GetItemInfo")
	runner:assertEqual(type(GetInventoryItemLink), "function", "Global: GetInventoryItemLink")
	local legSlot = G_RLF.equipSlotMap["INVTYPE_LEGS"] --[[@as number]]
	local link = GetInventoryItemLink("player", legSlot)
	local isCached = C.Item.GetItemInfo(link) ~= nil
	if not isCached then
		G_RLF:Print("Item not cached, skipping GetItemInfo test")
	else
		testGetItemInfo(link)
	end
	runner:assertEqual(type(GetMoney), "function", "Global: GetMoney")
	runner:assertEqual(
		type(C.CurrencyInfo.GetCoinTextureString),
		"function",
		"Global: C.CurrencyInfo.GetCoinTextureString"
	)
	runner:assertEqual(type(FACTION_STANDING_INCREASED), "string", "Global: FACTION_STANDING_INCREASED")
	runner:assertEqual(
		type(FACTION_STANDING_INCREASED_ACH_BONUS),
		"string",
		"Global: FACTION_STANDING_INCREASED_ACH_BONUS"
	)
	runner:assertEqual(type(FACTION_STANDING_INCREASED_BONUS), "string", "Global: FACTION_STANDING_INCREASED_BONUS")
	runner:assertEqual(
		type(FACTION_STANDING_INCREASED_DOUBLE_BONUS),
		"string",
		"Global: FACTION_STANDING_INCREASED_DOUBLE_BONUS"
	)
	runner:assertEqual(type(FACTION_STANDING_DECREASED), "string", "Global: FACTION_STANDING_DECREASED")

	if GetExpansionLevel() >= G_RLF.Expansion.SL then
		runner:assertEqual(
			type(FACTION_STANDING_INCREASED_ACCOUNT_WIDE),
			"string",
			"Global: FACTION_STANDING_INCREASED_ACCOUNT_WIDE"
		)
		runner:assertEqual(
			type(FACTION_STANDING_DECREASED_ACCOUNT_WIDE),
			"string",
			"Global: FACTION_STANDING_DECREASED_ACCOUNT_WIDE"
		)
	end

	if GetExpansionLevel() >= G_RLF.Expansion.TWW then
		runner:assertEqual(
			type(FACTION_STANDING_INCREASED_ACH_BONUS_ACCOUNT_WIDE),
			"string",
			"Global: FACTION_STANDING_INCREASED_ACH_BONUS_ACCOUNT_WIDE"
		)
	end

	runner:assertEqual(type(C.Reputation), "table", "Global: C.Reputation")

	if GetExpansionLevel() >= G_RLF.Expansion.DF then
		runner:assertEqual(type(C.Reputation.IsMajorFaction), "function", "Global: C.Reputation.IsMajorFaction")
		runner:assertEqual(type(ACCOUNT_WIDE_FONT_COLOR), "table", "Global: ACCOUNT_WIDE_FONT_COLOR")
	end

	if GetExpansionLevel() >= G_RLF.Expansion.LEGION then
		runner:assertEqual(type(C.Reputation.IsFactionParagon), "function", "Global: C.Reputation.IsFactionParagon")
	end

	if GetExpansionLevel() >= G_RLF.Expansion.TWW then
		runner:assertEqual(type(C.Reputation.GetFactionDataByID), "function", "Global: C.Reputation.GetFactionDataByID")
	end

	runner:assertEqual(type(FACTION_GREEN_COLOR), "table", "Global: FACTION_GREEN_COLOR")
	runner:assertEqual(type(FACTION_BAR_COLORS), "table", "Global: FACTION_BAR_COLORS")
end

function TestMode:SmokeTest()
	runner:reset()
	testWoWGlobals()
	runner:displayResults()
end

-- trunk-ignore-end(no-invalid-prints/invalid-print)
--@end-alpha@
