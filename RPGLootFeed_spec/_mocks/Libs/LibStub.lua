local busted = require("busted")
local stub = busted.stub
local embedLibs = require("RPGLootFeed_spec._mocks.Libs.embedLibUtil")

local libStubReturn = {}

local function mockLibStub(lib, silence)
	if libStubReturn[lib] then
		return libStubReturn[lib]
	end

	libStubReturn[lib] = {}
	if lib == "AceAddon-3.0" then
		libStubReturn[lib] = {
			NewAddon = function(...)
				local addon = {}
				embedLibs(addon, "AceAddon-3.0", ...)
				return addon
			end,
		}
	elseif lib == "AceConfig-3.0" then
		stub(libStubReturn[lib], "RegisterOptionsTable")
	elseif lib == "AceConfigDialog-3.0" then
		stub(libStubReturn[lib], "AddToBlizOptions")
		stub(libStubReturn[lib], "Close")
		stub(libStubReturn[lib], "Open")
		stub(libStubReturn[lib], "SetDefaultSize")
	elseif lib == "AceConfigRegistry-3.0" then
		stub(libStubReturn[lib], "NotifyChange")
	elseif lib == "AceDB-3.0" then
		stub(libStubReturn[lib], "New", function()
			return { global = {} }
		end)
	elseif lib == "AceGUI-3.0" then
		stub(libStubReturn[lib], "Create", function()
			local newGui = {}
			stub(newGui, "AddChild")
			stub(newGui, "DisableButton")
			stub(newGui, "DoLayout")
			stub(newGui, "EnableResize")
			stub(newGui, "IsShown", function()
				return true
			end)
			stub(newGui, "SetLayout")
			stub(newGui, "SetTitle")
			stub(newGui, "SetStatusText")
			stub(newGui, "SetCallback")
			stub(newGui, "SetText")
			stub(newGui, "SetValue")
			stub(newGui, "SetColor")
			stub(newGui, "SetDisabled")
			stub(newGui, "SetFullWidth")
			stub(newGui, "SetFullHeight")
			stub(newGui, "SetItemValue")
			stub(newGui, "SetRelativeWidth")
			stub(newGui, "SetRelativeHeight")
			stub(newGui, "SetList")
			stub(newGui, "SetMultiselect")
			stub(newGui, "SetNumLines")
			stub(newGui, "SetPoint")
			stub(newGui, "SetWidth")
			stub(newGui, "SetHeight")
			stub(newGui, "SetLabel")
			stub(newGui, "SetImage")
			stub(newGui, "SetImageSize")
			stub(newGui, "SetImageCoords")
			stub(newGui, "Show")
			stub(newGui, "Hide")
			return newGui
		end)
	elseif lib == "AceLocale-3.0" then
		stub(libStubReturn[lib], "GetLocale").returns({})
		stub(libStubReturn[lib], "NewLocale").returns({})
	elseif lib == "LibSharedMedia-3.0" then
		stub(libStubReturn[lib], "Register")
		libStubReturn[lib].MediaType = { FONT = "font" }
	elseif lib == "Masque" then
		stub(libStubReturn[lib], "Group", function()
			local group = {}
			stub(group, "ReSkin")
			return group
		end)
	elseif lib == "C_Everywhere" then
		libStubReturn[lib].CurrencyInfo = _G.C_CurrencyInfo
		libStubReturn[lib].Item = _G.C_Item
	elseif lib == "LibDataBroker-1.1" then
		stub(libStubReturn[lib], "NewDataObject", function()
			local dataObj = {}
			stub(dataObj, "OnClick")
			stub(dataObj, "OnTooltipShow")
			return dataObj
		end)
	elseif lib == "LibDBIcon-1.0" then
		stub(libStubReturn[lib], "Register")
		stub(libStubReturn[lib], "Show")
		stub(libStubReturn[lib], "Hide")
		stub(libStubReturn[lib], "AddButtonToCompartment")
	elseif lib == "LibEasyMenu" then
		stub(libStubReturn[lib], "EasyMenu")
	elseif lib == "LibPixelPerfect-1.0" then
		stub(libStubReturn[lib], "PSize")
		stub(libStubReturn[lib], "PScale")
		stub(libStubReturn[lib], "PHeight")
		stub(libStubReturn[lib], "PWidth")
	else
		error("Unmocked library: " .. lib)
	end
	return libStubReturn[lib]
end

stub(_G, "LibStub", function(lib, silence)
	return mockLibStub(lib, silence)
end)

return libStubReturn
