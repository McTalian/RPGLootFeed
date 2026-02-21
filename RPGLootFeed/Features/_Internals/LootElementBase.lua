---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

--- LootElementBase is a mixin table whose :new() method stamps all default fields
--- and shared methods onto a fresh element table.  No metatables are used – each
--- returned element is a fully-independent flat table suitable for direct mutation.
---@class LootElementBase
G_RLF.LootElementBase = {}

--- Creates a new loot element table with all RLF_BaseLootElement defaults populated.
--- Feature modules should call this to start building an element, then override
--- any fields they need before calling element:Show().
---@return RLF_BaseLootElement
function G_RLF.LootElementBase:new()
	---@class RLF_BaseLootElement
	local element = {}

	-- ── Identity / routing ─────────────────────────────────────────────────────
	element.key = nil
	element.type = nil
	element.eventChannel = "RLF_NEW_LOOT"

	-- ── Presentation flags ─────────────────────────────────────────────────────
	element.isLink = false
	element.isCustomLink = nil
	element.highlight = false

	-- ── Visuals ────────────────────────────────────────────────────────────────
	element.icon = nil
	element.quality = nil
	element.sellPrice = nil

	-- ── Quantity / count tracking ──────────────────────────────────────────────
	element.quantity = nil
	element.totalCount = nil
	element.itemCount = nil
	element.unit = nil

	-- ── Text providers ─────────────────────────────────────────────────────────
	element.textFn = nil
	element.secondaryTextFn = nil
	element.secondaryText = nil
	element.topLeftText = nil
	element.topLeftColor = nil

	-- ── RGBA color (default: opaque white) ─────────────────────────────────────
	element.r = 1
	element.g = 1
	element.b = 1
	element.a = 1

	-- ── Display timing ─────────────────────────────────────────────────────────
	element.showForSeconds = G_RLF.db.global.animations.exit.fadeOutDelay

	-- ── Capability stubs (feature modules must override) ──────────────────────
	--- Returns true if the feature module is currently enabled.
	element.IsEnabled = function()
		return false
	end

	-- ── Shared methods ─────────────────────────────────────────────────────────

	--- Override to restrict which display rows are shown.
	--- Returns true if this element should be displayed.
	---@param _itemName string
	---@param _itemQuality number
	---@return boolean
	function element:isPassingFilter(_itemName, _itemQuality)
		return true
	end

	--- Sends this element to the LootDisplay engine via the AceMessage bus.
	---@param itemName? string
	---@param itemQuality? number
	function element:Show(itemName, itemQuality)
		if self:isPassingFilter(itemName, itemQuality) then
			G_RLF:LogDebug("Show", addonName, self.type, self.key, nil, self.quantity)
			G_RLF:SendMessage(self.eventChannel, self)
		else
			G_RLF:LogDebug(
				"Skip Show, isPassingFilter returned false",
				addonName,
				self.type,
				self.key,
				tostring(itemName) .. " " .. tostring(itemQuality),
				self.quantity
			)
		end
	end

	--- Standard logging helper; called from LootDisplay when a row is shown.
	--- Kept as a plain function (not a method) to match the RLF_BaseLootElement type annotation.
	---@param text string
	---@param amount number
	---@param new boolean
	element.logFn = function(text, amount, new)
		local amountLogText = tostring(amount)
		local sign = "+"
		if element.quantity ~= nil and element.quantity < 0 then
			sign = "-"
		end
		if not new then
			amountLogText = format("%s (diff: %s%s)", amount, sign, math.abs(element.quantity))
		end
		G_RLF:LogInfo(element.type .. "Shown", addonName, element.type, element.key, text, amountLogText, new)
	end

	return element
end

return {}
