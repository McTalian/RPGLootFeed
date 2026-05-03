---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local LootRollResultsConfig = {}

--- Build the AceConfig options group for Loot Roll Results on the given frame.
--- The feature is Retail-only; the toggle is hidden on Classic clients.
--- @param frameId integer
--- @param order number
--- @return table
function G_RLF.BuildLootRollResultsArgs(frameId, order)
	local function fc()
		return G_RLF.db.global.frames[frameId].features.lootRollResults
	end
	return {
		type = "group",
		handler = LootRollResultsConfig,
		name = G_RLF.L["Loot Roll Results Config"],
		order = order,
		-- Hide entirely on Classic; C_LootHistory is not available there.
		hidden = function()
			return not G_RLF:IsRetail()
		end,
		args = {
			enabled = {
				type = "toggle",
				name = G_RLF.L["Enable Loot Roll Results"],
				desc = G_RLF.L["EnableLootRollResultsDesc"],
				width = "double",
				get = function()
					return fc().enabled
				end,
				set = function(_, value)
					fc().enabled = value
					G_RLF.DbAccessor:UpdateFeatureModuleState("lootRollResults")
					G_RLF.LootDisplay:RefreshSampleRowsIfShown()
				end,
				order = 1,
			},
			lootRollResultsOptions = {
				type = "group",
				name = G_RLF.L["Loot Roll Results Options"],
				inline = true,
				disabled = function()
					return not fc().enabled
				end,
				order = 2,
				args = {
					backgroundOverride = G_RLF.ConfigCommon.CreateFeatureBackgroundOverrideGroup({
						frameId = frameId,
						featureKey = "lootRollResults",
						order = 0.75,
						isFeatureEnabled = function()
							return fc().enabled
						end,
					}),
					showIcon = {
						type = "toggle",
						name = G_RLF.L["Show Loot Roll Icon"],
						desc = G_RLF.L["ShowLootRollIconDesc"],
						width = "double",
						disabled = function()
							return not fc().enabled or G_RLF.db.global.misc.hideAllIcons
						end,
						get = function()
							return fc().enableIcon
						end,
						set = function(_, value)
							fc().enableIcon = value
							G_RLF.LootDisplay:RefreshSampleRowsIfShown()
						end,
						order = 0.5,
					},
					exitDelayOverride = {
						type = "range",
						name = G_RLF.L["Exit Delay Override"],
						desc = G_RLF.L["ExitDelayOverrideDesc"],
						min = 0,
						max = 30,
						step = 1,
						get = function()
							return fc().exitDelayOverride or 0
						end,
						set = function(_, value)
							fc().exitDelayOverride = value
						end,
						order = 3,
					},
				},
			},
		},
	}
end

return LootRollResultsConfig
