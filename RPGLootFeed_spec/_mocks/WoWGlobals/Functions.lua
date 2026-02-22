local busted = require("busted")
local stub = busted.stub
local spy = busted.spy

local functions = {}

_G.format = string.format
_G.handledError = function(err)
	print("\n")
	print(err)
	print("The above error was thrown during a test and caught by xpcall")
	print("This is usually indicative of an issue, or an improperly mocked test")
	print("\n")
	return false
end
---@diagnostic disable-next-line: undefined-field
_G.unpack = table.unpack
---@diagnostic disable-next-line: duplicate-set-field
_G.strtrim = function(str, chars)
	if not str then
		return str
	end

	-- Default characters to trim: space, tab, carriage return, newline
	chars = chars or " \t\r\n"

	-- Create pattern for characters to trim (escape special pattern characters)
	local pattern_chars = chars:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

	-- Trim from left and right
	local trimmed = str:gsub("^[" .. pattern_chars .. "]*", ""):gsub("[" .. pattern_chars .. "]*$", "")

	return trimmed
end

string.trim = _G.strtrim

functions.RunNextFrame = stub(_G, "RunNextFrame", function(func)
	func()
end)

functions.CreateFrame = stub(_G, "CreateFrame")
functions.CreateFramePool = stub(_G, "CreateFramePool").returns({})
functions.GetChannelName = stub(_G, "GetChannelName")
functions.GetExpansionLevel = stub(_G, "GetExpansionLevel").returns(10)
functions.GetInventoryItemLink = stub(_G, "GetInventoryItemLink")
functions.GetCurrencyLink = stub(_G, "GetCurrencyLink").returns("|cffffffff|Hcurrency:241:0|h[Champion's Seal]|h|r")
functions.GetFactionInfoByID = stub(_G, "GetFactionInfoByID", function(id)
	return "Faction" .. id, "Description" .. id, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
end)
functions.GetFactionInfo = stub(_G, "GetFactionInfo", function(index)
	return "Faction" .. index, "Description" .. index, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
end)
functions.GetProfessions = stub(_G, "GetProfessions").returns(1, 2, 3, 4, 5)
functions.GetProfessionInfo = stub(_G, "GetProfessionInfo", function(id)
	return "Profession" .. id, "icon" .. id, id * 10, id * 20, nil, nil, nil, nil, nil, nil, "Expansion" .. id
end)
functions.date = stub(_G, "date").returns("2023-01-01 12:00:00")
functions.debugprofilestop = stub(_G, "debugprofilestop").returns(0)
functions.errorhandlerSpy = spy.new(function() end)
functions.geterrorhandler = stub(_G, "geterrorhandler", function()
	return functions.errorhandlerSpy
end)
functions.IsInGuild = stub(_G, "IsInGuild").returns(false)
functions.IsInGroup = stub(_G, "IsInGroup").returns(false)
functions.IsInRaid = stub(_G, "IsInRaid").returns(false)
functions.IsInInstance = stub(_G, "IsInInstance").returns(false)
functions.GetNumGroupMembers = stub(_G, "GetNumGroupMembers").returns(1)
functions.GetPlayerGuid = stub(_G, "GetPlayerGuid").returns("player")
functions.GetLocale = stub(_G, "GetLocale").returns("enUS")
functions.MuteSoundFile = stub(_G, "MuteSoundFile")
functions.UnmuteSoundFile = stub(_G, "UnmuteSoundFile")
functions.UnitGUID = stub(_G, "UnitGUID").returns("player")
functions.UnitLevel = stub(_G, "UnitLevel").returns(2)
functions.UnitName = stub(_G, "UnitName").returns("Player")
functions.UnitXP = stub(_G, "UnitXP").returns(10)
functions.UnitXPMax = stub(_G, "UnitXPMax").returns(50)
functions.UnitClass = stub(_G, "UnitClass").returns("Warrior", "WARRIOR", 1)
functions.UnitSex = stub(_G, "UnitSex").returns(2)
functions.GetMoney = stub(_G, "GetMoney").returns(123456)
functions.GetText = stub(_G, "GetText").returns("Test Text")
functions.CreateAtlasMarkup = stub(_G, "CreateAtlasMarkup").returns("<AtlasMarkup>")
functions.SetPortraitTexture = stub(_G, "SetPortraitTexture")

return functions
