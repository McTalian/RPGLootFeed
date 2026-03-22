---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local General = {}

G_RLF.options.args.general = {
	type = "group",
	handler = General,
	name = G_RLF.L["General"],
	desc = G_RLF.L["GeneralDesc1.32"],
	order = 1,
	args = {
		quickActions = {
			type = "group",
			inline = true,
			name = G_RLF.L["Quick Actions"],
			order = 1,
			args = {
				testMode = {
					type = "execute",
					name = G_RLF.L["Toggle Test Mode"],
					func = function()
						local TestMode = G_RLF.RLF:GetModule(G_RLF.SupportModule.TestMode) --[[@as RLF_TestMode]]
						TestMode:ToggleTestMode()
					end,
					order = 1,
				},
				clearRows = {
					type = "execute",
					name = G_RLF.L["Clear rows"],
					func = function()
						G_RLF.LootDisplay:HideLoot()
					end,
					order = 2,
				},
				lootHistory = {
					type = "execute",
					name = G_RLF.L["Toggle Loot History"],
					func = function()
						G_RLF.HistoryService:ToggleHistoryFrame()
					end,
					order = 3,
				},
			},
		},
		showMinimapIcon = {
			type = "toggle",
			name = G_RLF.L["Show Minimap Icon"],
			desc = G_RLF.L["ShowMinimapIconDesc"],
			width = "double",
			get = function()
				return not G_RLF.db.global.minimap.hide
			end,
			set = function(info, value)
				G_RLF.db.global.minimap.hide = not value
				if G_RLF.db.global.minimap.hide then
					G_RLF.DBIcon:Hide(addonName)
				else
					G_RLF.DBIcon:Show(addonName)
				end
			end,
			order = 2,
		},
		feedDisplay = {
			type = "group",
			inline = true,
			name = G_RLF.L["Feed Display"],
			order = 3,
			args = {
				showOneQuantity = {
					type = "toggle",
					name = G_RLF.L["Show '1' Quantity"],
					desc = G_RLF.L["ShowOneQuantityDesc"],
					width = "double",
					get = function(info, value)
						return G_RLF.db.global.misc.showOneQuantity
					end,
					set = function(info, value)
						G_RLF.db.global.misc.showOneQuantity = value
						G_RLF.LootDisplay:RefreshSampleRowsIfShown()
					end,
					order = 1,
				},
				hideAllIcons = {
					type = "toggle",
					name = G_RLF.L["Hide All Icons"],
					desc = G_RLF.L["HideAllIconsDesc"],
					width = "double",
					get = function(info, value)
						return G_RLF.db.global.misc.hideAllIcons
					end,
					set = function(info, value)
						G_RLF.db.global.misc.hideAllIcons = value
						G_RLF.LootDisplay:RefreshSampleRowsIfShown()
					end,
					order = 2,
				},
			},
		},
		lootHistoryOptions = {
			type = "group",
			inline = true,
			name = G_RLF.L["Loot History"],
			order = 4,
			args = {
				enableLootHistory = {
					type = "toggle",
					name = G_RLF.L["Enable Loot History"],
					desc = G_RLF.L["EnableLootHistoryDesc"],
					get = function()
						return G_RLF.db.global.lootHistory.enabled
					end,
					set = function(info, value)
						G_RLF.db.global.lootHistory.enabled = value
						---@type RLF_LootDisplayFrame
						local frame = G_RLF.RLF_MainLootFrame
						frame:UpdateTabVisibility()
					end,
					order = 1,
				},
				lootHistorySize = {
					type = "range",
					name = G_RLF.L["Loot History Size"],
					desc = G_RLF.L["LootHistorySizeDesc"],
					disabled = function()
						return not G_RLF.db.global.lootHistory.enabled
					end,
					min = 1,
					max = 1000,
					step = 1,
					get = function()
						return G_RLF.db.global.lootHistory.historyLimit
					end,
					set = function(info, value)
						G_RLF.db.global.lootHistory.historyLimit = value
					end,
					order = 2,
				},
				hideLootHistoryTab = {
					type = "toggle",
					name = G_RLF.L["Hide Loot History Tab"],
					desc = G_RLF.L["HideLootHistoryTabDesc"],
					width = "double",
					disabled = function()
						return not G_RLF.db.global.lootHistory.enabled
					end,
					get = function()
						return G_RLF.db.global.lootHistory.hideTab
					end,
					set = function(info, value)
						G_RLF.db.global.lootHistory.hideTab = value
						---@type RLF_LootDisplayFrame
						local frame = G_RLF.RLF_MainLootFrame
						frame:UpdateTabVisibility()
					end,
					order = 3,
				},
			},
		},
		tooltipOptions = {
			type = "group",
			name = G_RLF.L["Tooltip Options"],
			inline = true,
			order = 5,
			args = {
				enableTooltip = {
					type = "toggle",
					name = G_RLF.L["Enable Item/Currency Tooltips"],
					desc = G_RLF.L["EnableTooltipsDesc"],
					width = "double",
					get = function(info, value)
						return G_RLF.db.global.tooltips.hover.enabled
					end,
					set = function(info, value)
						G_RLF.db.global.tooltips.hover.enabled = value
					end,
					order = 1,
				},
				onlyShiftOnEnter = {
					type = "toggle",
					name = G_RLF.L["Show only when SHIFT is held"],
					desc = G_RLF.L["OnlyShiftOnEnterDesc"],
					width = "double",
					disabled = function()
						return not G_RLF.db.global.tooltips.hover.enabled
					end,
					get = function(info, value)
						return G_RLF.db.global.tooltips.hover.onShift
					end,
					set = function(info, value)
						G_RLF.db.global.tooltips.hover.onShift = value
					end,
					order = 2,
				},
			},
		},
		interactionsOptions = {
			type = "group",
			name = G_RLF.L["Interactions"],
			desc = G_RLF.L["InteractionsDesc"],
			inline = true,
			order = 6,
			args = {
				disableMouseInCombat = {
					type = "toggle",
					name = G_RLF.L["Disable Mouse Interactions In Combat"],
					desc = G_RLF.L["DisableMouseInCombatDesc"],
					width = "double",
					get = function()
						return G_RLF.db.global.interactions.disableMouseInCombat
					end,
					set = function(info, value)
						G_RLF.db.global.interactions.disableMouseInCombat = value
						G_RLF.LootDisplay:OnPlayerCombatChange()
					end,
					order = 1,
				},
				pinOnHover = {
					type = "toggle",
					name = G_RLF.L["Lock Row Position On Hover"],
					desc = G_RLF.L["LockRowPositionOnHoverDesc"],
					width = "double",
					get = function()
						return G_RLF.db.global.interactions.pinOnHover
					end,
					set = function(info, value)
						G_RLF.db.global.interactions.pinOnHover = value
					end,
					order = 2,
				},
			},
		},
	},
}

return General
