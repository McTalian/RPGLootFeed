local Currency = {}

function Currency:OnUpdate(...)
	local currencyType, _quantity, quantityChange, _quantityGainSource, _quantityLostSource = ...

	if not G_RLF.db.global.currencyFeed then
		return
	end

	if currencyType == nil or not quantityChange or quantityChange <= 0 then
		return
	end

	local info = C_CurrencyInfo.GetCurrencyInfo(currencyType)
	if info == nil or info.description == "" then
		return
	end

	G_RLF.LootDisplay:ShowLoot(
		info.currencyID,
		C_CurrencyInfo.GetCurrencyLink(currencyType),
		info.iconFileID,
		quantityChange
	)
end

G_RLF.Currency = Currency
