---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local LootRollsConfig = {}

--- Build the AceConfig options group for Loot Rolls on the given frame.
--- The feature is Retail-only; the toggle is hidden on Classic clients.
--- @param frameId integer
--- @param order number
--- @return table
function G_RLF.BuildLootRollsArgs(frameId, order)
	local function fc()
		return G_RLF.db.global.frames[frameId].features.lootRolls
	end
	return {
		type = "group",
		handler = LootRollsConfig,
		name = G_RLF.L["Loot Rolls Config"],
		order = order,
		-- Hide entirely on Classic; C_LootHistory is not available there.
		hidden = function()
			return not G_RLF:IsRetail()
		end,
		args = {
			enabled = {
				type = "toggle",
				name = G_RLF.L["Enable Loot Rolls in Feed"],
				desc = G_RLF.L["EnableLootRollsDesc"],
				width = "double",
				get = function()
					return fc().enabled
				end,
				set = function(_, value)
					fc().enabled = value
					G_RLF.DbAccessor:UpdateFeatureModuleState("lootRolls")
					G_RLF.LootDisplay:RefreshSampleRowsIfShown()
				end,
				order = 1,
			},
			lootRollsOptions = {
				type = "group",
				name = G_RLF.L["Loot Rolls Options"],
				inline = true,
				disabled = function()
					return not fc().enabled
				end,
				order = 2,
				args = {
					backgroundOverride = G_RLF.ConfigCommon.CreateFeatureBackgroundOverrideGroup({
						frameId = frameId,
						featureKey = "lootRolls",
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
					enableLootRollActions = {
						type = "toggle",
						name = G_RLF.L["Enable Loot Roll Actions"],
						desc = G_RLF.L["EnableLootRollActionsDesc"],
						width = "double",
						get = function()
							return fc().enableLootRollActions
						end,
						set = function(_, value)
							fc().enableLootRollActions = value
							G_RLF.LootDisplay:RefreshSampleRowsIfShown()
						end,
						order = 3,
					},
					enableLootRollResults = {
						type = "toggle",
						name = G_RLF.L["Enable Loot Roll Results"],
						desc = G_RLF.L["EnableLootRollResultsDesc"],
						width = "double",
						get = function()
							return fc().enableLootRollResults
						end,
						set = function(_, value)
							fc().enableLootRollResults = value
							G_RLF.LootDisplay:RefreshSampleRowsIfShown()
						end,
						order = 5,
					},
					disableLootRollFrame = {
						type = "toggle",
						name = G_RLF.L["Disable Built-in Roll Frame"],
						desc = G_RLF.L["DisableLootRollFrameDesc"],
						width = "double",
						-- Only enabled when enableLootRollActions is true
						disabled = function()
							return not fc().enableLootRollActions
						end,
						get = function()
							return fc().disableLootRollFrame
						end,
						set = function(_, value)
							fc().disableLootRollFrame = value
							G_RLF.LootDisplay:RefreshSampleRowsIfShown()
						end,
						order = 4,
					},
				},
			},
		},
	}
end

return LootRollsConfig
