---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- ── External dependency locals ────────────────────────────────────────────────
local L = G_RLF.L
local LogDebug = function(...)
	G_RLF:LogDebug(...)
end

---@class AuctionIntegrations
---@field private initialized boolean
---@field public activeIntegrations table<string, table>
---@field public activeIntegration RLF_AH_Integ
---@field public numActiveIntegrations number
---@field public nilIntegration RLF_AH_Integ
---@field public Init fun(self: AuctionIntegrations): nil
---@field public GetAHPrice fun(self: AuctionIntegrations, itemLink: string): number|nil
local AuctionIntegrations = {}

---@class RLF_AH_Integ
---@field public Init fun(self: RLF_AH_Integ): boolean
---@field public ToString fun(self: RLF_AH_Integ): string
---@field public GetAHPrice fun(self: RLF_AH_Integ, itemLink: string): number|nil
local Integ_Base = {}

---@class Integ_Auctionator : RLF_AH_Integ
local Integ_Auctionator = {}

---@class Integ_TSM : RLF_AH_Integ
local Integ_TSM = {}

function AuctionIntegrations:Init()
	if self.initialized then
		return
	end

	self.initialized = true
	local possibleIntegrations = { Integ_Auctionator, Integ_TSM }
	self.nilIntegration = Integ_Base
	self.activeIntegrations = {}
	self.activeIntegration = nil

	self.numActiveIntegrations = 0
	for _, integration in ipairs(possibleIntegrations) do
		if integration:Init() then
			self.activeIntegrations[integration:ToString()] = integration
			self.numActiveIntegrations = self.numActiveIntegrations + 1
		end
	end

	LogDebug("Active AH integrations: " .. self.numActiveIntegrations)

	local ahSource = G_RLF.db.global.item.auctionHouseSource

	if self.numActiveIntegrations == 1 then
		for _, integration in pairs(self.activeIntegrations) do
			self.activeIntegration = integration
		end
	elseif ahSource then
		if ahSource == Integ_Base:ToString() then
			self.activeIntegration = self.nilIntegration
		end
		self.activeIntegration = self.activeIntegrations[ahSource]
		if not self.activeIntegration then
			self.activeIntegration = self.nilIntegration
		end
	end

	if self.activeIntegration and ahSource ~= self.activeIntegration:ToString() then
		G_RLF.db.global.item.auctionHouseSource = self.activeIntegration:ToString()
	end
end

function AuctionIntegrations:GetAHPrice(itemLink)
	if self.activeIntegration then
		return self.activeIntegration:GetAHPrice(itemLink)
	end

	return nil
end

function Integ_Base:Init()
	return true
end

function Integ_Base:ToString()
	return L["None"]
end

function Integ_Base:GetAHPrice(_)
	return nil
end

---Initialize the Auctionator integration
---@return boolean true if Auctionator is available and initialized
function Integ_Auctionator:Init()
	if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink then
		Auctionator.API.v1.RegisterForDBUpdate(addonName, function()
			LogDebug("Auctionator DB updated")
		end)
		return true
	end

	return false
end

---String representation of the Auctionator integration
---@return string localized "Auctionator"
function Integ_Auctionator:ToString()
	return L["Auctionator"]
end

---Get the AH price for an item
---@param itemLink string
---@return number | nil price in copper or nil if not found
function Integ_Auctionator:GetAHPrice(itemLink)
	local price = Auctionator.API.v1.GetAuctionPriceByItemLink(addonName, itemLink)
	if price then
		return price
	end

	return nil
end

---Initialize the TSM integration
---@return boolean true if TSM is available and initialized
function Integ_TSM:Init()
	return TSM_API ~= nil
end

---String representation of the TSM integration
---@return string localized "TSM"
function Integ_TSM:ToString()
	return L["TSM"]
end

---Get the AH price for an item
---@param itemLink string
---@return number | nil marketValue in copper or nil if not found
function Integ_TSM:GetAHPrice(itemLink)
	if TSM_API and TSM_API.ToItemString and TSM_API.GetCustomPriceValue then
		local itemString = TSM_API.ToItemString(itemLink)
		if itemString then
			local marketValue = TSM_API.GetCustomPriceValue("DBMarket", itemString)
			if marketValue then
				return marketValue
			end
		end
	end

	return nil
end

G_RLF.AuctionIntegrations = AuctionIntegrations

return AuctionIntegrations
