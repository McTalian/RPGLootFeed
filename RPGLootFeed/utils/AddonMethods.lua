---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

function G_RLF:fn(func, ...)
	---@type G_RLF | RLF_Module
	local s = self
	local function errorhandler(err)
		local suffix = "\n\n==== Addon Info " .. addonName .. " " .. G_RLF.addonVersion .. " ====\n\n"
		local status, trace = pcall(function()
			local logger = G_RLF.RLF:GetModule("Logger") --[[@as RLF_Logger]]
			if s.moduleName then
				return logger:Trace(s.moduleName)
			end
			return nil
		end)
		if status and trace then
			suffix = suffix .. "Log traces related to " .. s.moduleName .. "\n"
			suffix = suffix .. "-------------------------------------------------\n"
			suffix = suffix .. trace
			suffix = suffix .. "-------------------------------------------------\n\n"
		end
		suffix = suffix .. G_RLF.L["Issues"] .. "\n\n"

		return geterrorhandler()(err .. suffix)
	end
	-- Borrowed from AceAddon-3.0
	if type(func) == "function" then
		return xpcall(func, errorhandler, ...)
	else
		error("fn: func is not a function")
	end
end

local acr = LibStub("AceConfigRegistry-3.0")
function G_RLF:NotifyChange(...)
	acr:NotifyChange(...)
end

function G_RLF:Print(...)
	G_RLF.RLF:Print(...)
end

function G_RLF:IsRetail()
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

function G_RLF:IsClassic()
	return WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
end

function G_RLF:IsCataClassic()
	return WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC
end

function G_RLF:IsMoPClassic()
	return WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
end

function G_RLF:SendMessage(...)
	local args = { ... }
	RunNextFrame(function()
		G_RLF.RLF:SendMessage(unpack(args))
	end)
end

function G_RLF:RGBAToHexFormat(r, g, b, a)
	local red = string.format("%02X", math.floor(r * 255))
	local green = string.format("%02X", math.floor(g * 255))
	local blue = string.format("%02X", math.floor(b * 255))
	local alpha = string.format("%02X", math.floor((a or 1) * 255)) -- Default alpha to 1 if not provided

	-- Return in WoW format with |c prefix
	return "|c" .. alpha .. red .. green .. blue
end

local function log(...)
	local args = { ... }
	RunNextFrame(function()
		G_RLF:SendMessage("RLF_LOG", args)
	end)
end

--- Create debug log
--- @see RLF_Logger.addLogEntry
--- @param message string
--- @param source? string
--- @param type? string
--- @param id? string
--- @param content? string
--- @param amount? number | string
--- @param isNew? boolean
function G_RLF:LogDebug(message, source, type, id, content, amount, isNew)
	log(G_RLF.LogLevel.debug, message, source, type, id, content, amount, isNew)
end

--- Create info log
--- @see RLF_Logger.addLogEntry
--- @param message string
--- @param source? string
--- @param type? string
--- @param id? string
--- @param content? string
--- @param amount? number | string
--- @param isNew? boolean
function G_RLF:LogInfo(message, source, type, id, content, amount, isNew)
	log(G_RLF.LogLevel.info, message, source, type, id, content, amount, isNew)
end

--- Create warning log
--- @see RLF_Logger.addLogEntry
--- @param message string
--- @param source? string
--- @param type? string
--- @param id? string
--- @param content? string
--- @param amount? number | string
--- @param isNew? boolean
function G_RLF:LogWarn(message, source, type, id, content, amount, isNew)
	log(G_RLF.LogLevel.warn, message, source, type, id, content, amount, isNew)
end

--- Create error log
--- @see RLF_Logger.addLogEntry
--- @param message string
--- @param source? string
--- @param type? string
--- @param id? string
--- @param content? string
--- @param amount? number | string
--- @param isNew? boolean
function G_RLF:LogError(message, source, type, id, content, amount, isNew)
	log(G_RLF.LogLevel.error, message, source, type, id, content, amount, isNew)
end

function G_RLF:CreatePatternSegmentsForStringNumber(localeString)
	local preStart, preEnd = string.find(localeString, "%%s")
	if preStart == nil then
		-- Mainly for deDE which uses a slightly different format token
		preStart, preEnd = string.find(localeString, "%%1$s")
	end
	local prePattern = string.sub(localeString, 1, preStart - 1)
	local midStart, midEnd = string.find(localeString, "%%d", preEnd + 1)
	if midStart == nil then
		-- Mainly for deDE which uses a slightly different format token
		midStart, midEnd = string.find(localeString, "%%2$d", preEnd + 1)
	end
	local midPattern = string.sub(localeString, preEnd + 1, midStart - 1)
	local postPattern = string.sub(localeString, midEnd + 1)
	return { prePattern, midPattern, postPattern }
end

--- @return string?, number?
function G_RLF:ExtractDynamicsFromPattern(localeString, segments)
	local prePattern, midPattern, postPattern = unpack(segments)
	local preMatchStart, preMatchEnd = string.find(localeString, prePattern, 1, true)
	if preMatchStart then
		local msgLoop = localeString:sub(preMatchEnd + 1)
		local midMatchStart, midMatchEnd = string.find(msgLoop, midPattern, 1, true)
		if midMatchStart then
			local postMatchStart, postMatchEnd = string.find(msgLoop, postPattern, midMatchEnd, true)
			if postMatchStart then
				local str = msgLoop:sub(1, midMatchStart - 1)
				local num
				if midMatchEnd == postMatchStart then
					num = msgLoop:sub(midMatchEnd + 1)
				else
					num = msgLoop:sub(midMatchEnd + 1, postMatchStart - 1)
				end
				return str, tonumber(num)
			end
		end
	end

	return nil, nil
end

local menu = {
	{ text = addonName, isTitle = true, notCheckable = true },
	{
		text = G_RLF.L["Clear rows"],
		func = function()
			G_RLF.LootDisplay:HideLoot()
		end,
		notCheckable = true,
	},
}
local menuFrame = CreateFrame("Frame", addonName .. "MenuFrame", UIParent, "UIDropDownMenuTemplate")
local LibEasyMenu = LibStub("LibEasyMenu")

function G_RLF:OpenOptions(button)
	if button == "LeftButton" then
		G_RLF.acd:Open(addonName)
	elseif button == "RightButton" then
		local tmpMenu = {}
		for _, item in ipairs(menu) do
			table.insert(tmpMenu, item)
		end
		local unseenNotifications = G_RLF.Notifications:GetNumUnseenNotifications()
		if unseenNotifications > 0 then
			table.insert(tmpMenu, {
				text = string.format(G_RLF.L["View Notifications"], unseenNotifications),
				func = function()
					local notifModule = G_RLF.RLF:GetModule("Notifications") --[[@as RLF_Notifications]]
					if notifModule then
						notifModule:ViewAllNotifications()
					end
				end,
				notCheckable = true,
			})
		end
		if G_RLF.db.global.lootHistory.enabled then
			table.insert(tmpMenu, {
				text = G_RLF.L["Toggle Loot History"],
				func = function()
					G_RLF.RLF_MainLootFrame:ToggleHistoryFrame()
					local partyFrame = G_RLF.RLF_PartyLootFrame
					if partyFrame then
						partyFrame:ToggleHistoryFrame()
					end
				end,
				notCheckable = true,
			})
		end
		table.insert(tmpMenu, {
			text = G_RLF.L["Close"],
			func = function()
				CloseDropDownMenus()
			end,
			notCheckable = true,
		})
		LibEasyMenu:EasyMenu(tmpMenu, menuFrame, "cursor", 0, 0, "MENU")
	end
end

function G_RLF:TableToCommaSeparatedString(tbl)
	local result = {}
	for key, value in pairs(tbl) do
		if value then
			table.insert(result, key)
		end
	end
	return table.concat(result, ", ")
end

--- Get the frame's font flags as a string
--- @param frame? G_RLF.Frames
--- @return string
function G_RLF:FontFlagsToString(frame)
	frame = frame or G_RLF.Frames.MAIN
	local stylingDb = G_RLF.DbAccessor:Styling(frame)
	local flags = stylingDb.fontFlags
	return self:TableToCommaSeparatedString(flags)
end

function G_RLF:GenerateGUID()
	local random = math.random
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	return string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and random(0, 15) or random(8, 11)
		return string.format("%x", v)
	end)
end

function G_RLF:IsRLFStableRelease()
	--@alpha@
	if true then
		return false
	end
	--@end-alpha@
	--@beta@
	if true then
		return false
	end
	--@end-beta@
	return true
end

function G_RLF:ParseVersion(version)
	version = version or G_RLF.addonVersion
	local major, minor, patch = string.match(version, "v(%d+)%.(%d+)%.(%d+)")

	if major and minor and patch then
		return tonumber(major), tonumber(minor), tonumber(patch)
	else
		return nil, nil, nil
	end
end

function G_RLF:CompareWithVersion(myVersion, cmpVersion)
	local myVersion = myVersion
	local cmpVersion = cmpVersion
	local major1, minor1, patch1 = self:ParseVersion(cmpVersion)
	local major2, minor2, patch2 = self:ParseVersion(myVersion)

	if major1 and major2 then
		if major1 > major2 then
			return G_RLF.VersionCompare.NEWER
		elseif major1 < major2 then
			return G_RLF.VersionCompare.OLDER
		end

		if minor1 and minor2 then
			if minor1 > minor2 then
				return G_RLF.VersionCompare.NEWER
			elseif minor1 < minor2 then
				return G_RLF.VersionCompare.OLDER
			end

			if patch1 and patch2 then
				if patch1 > patch2 then
					return G_RLF.VersionCompare.NEWER
				elseif patch1 < patch2 then
					return G_RLF.VersionCompare.OLDER
				end
			end
		end
	end

	return G_RLF.VersionCompare.SAME -- Versions are equal or invalid
end

function G_RLF:ExtractItemLinks(message)
	local itemLinks = {}
	for itemLink in message:gmatch("|c.-|Hitem:.-|h%[.-%]|h|r") do
		table.insert(itemLinks, itemLink)
	end
	return itemLinks
end

function G_RLF:ExtractCurrencyLinks(message)
	local currencyLinks = {}
	for currencyLink in message:gmatch("|c.-|Hcurrency:.-|h%[.-%]|h|r") do
		table.insert(currencyLinks, currencyLink)
	end
	return currencyLinks
end

function G_RLF:ExtractCurrencyID(currencyLink)
	-- Currency links have the format: |cffffffff|Hcurrency:currencyID:amount|h[Name]|h|r
	local currencyID = currencyLink:match("|Hcurrency:(%d+):")
	return currencyID and tonumber(currencyID) or nil
end
