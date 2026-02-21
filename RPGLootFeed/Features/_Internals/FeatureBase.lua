---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

--- FeatureBase is a factory that wraps G_RLF.RLF:NewModule so feature modules
--- do not call Ace directly.  This makes feature tests fully independent of
--- AceAddon plumbing: tests inject a mock ns.FeatureBase that returns a simple
--- stub table instead of a real AceModule.
---
--- Design notes:
---   * fn (the xpcall error-wrapper) is intentionally absent from the prototype.
---     Features should use explicit error handling rather than silent swallowing.
---   * G_RLF.db is NOT captured here; it is nil until AceDB runs in OnInitialize.
---@class RLF_FeatureBase
G_RLF.FeatureBase = {}

--- Creates and returns a new AceModule registered with the addon.
--- @param moduleName string  The unique module name (use G_RLF.FeatureModule.*)
--- @param ... string         Additional Ace mixin names (e.g. "AceEvent-3.0")
--- @return RLF_Module
function G_RLF.FeatureBase:new(moduleName, ...)
	return G_RLF.RLF:NewModule(moduleName, ...)
end

return {}
