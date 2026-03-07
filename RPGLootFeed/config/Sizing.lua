---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

--- Build the AceConfig sizing group args for the given frame ID.
--- Returns the full type="group" table ready to embed in a per-frame group.
--- @param id integer frame ID
--- @param order number position order within the parent group
--- @return table
function G_RLF.BuildSizingArgs(id, order)
	return {
		type = "group",
		name = G_RLF.L["Sizing"],
		desc = G_RLF.L["SizingDesc"],
		order = order,
		args = {
			feedWidth = {
				type = "range",
				name = G_RLF.L["Feed Width"],
				desc = G_RLF.L["FeedWidthDesc"],
				min = 10,
				max = 1000,
				get = function()
					return G_RLF.DbAccessor:Sizing(id).feedWidth
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Sizing(id).feedWidth = value
					G_RLF.LootDisplay:UpdateSize(id)
				end,
				order = 1,
			},
			maxRows = {
				type = "range",
				name = G_RLF.L["Maximum Rows to Display"],
				desc = G_RLF.L["MaxRowsDesc"],
				min = 1,
				softMin = 3,
				max = 20,
				step = 1,
				bigStep = 5,
				get = function()
					return G_RLF.DbAccessor:Sizing(id).maxRows
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Sizing(id).maxRows = value
					G_RLF.LootDisplay:UpdateSize(id)
				end,
				order = 2,
			},
			rowHeight = {
				type = "range",
				name = G_RLF.L["Loot Item Height"],
				desc = G_RLF.L["RowHeightDesc"],
				min = 5,
				max = 100,
				get = function()
					return G_RLF.DbAccessor:Sizing(id).rowHeight
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Sizing(id).rowHeight = value
					G_RLF.LootDisplay:UpdateSize(id)
				end,
				order = 3,
			},
			iconSize = {
				type = "range",
				name = G_RLF.L["Loot Item Icon Size"],
				desc = G_RLF.L["IconSizeDesc"],
				min = 5,
				max = 100,
				get = function()
					return G_RLF.DbAccessor:Sizing(id).iconSize
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Sizing(id).iconSize = value
					G_RLF.LootDisplay:UpdateRowStyles(id)
				end,
				order = 4,
			},
			rowPadding = {
				type = "range",
				name = G_RLF.L["Loot Item Padding"],
				desc = G_RLF.L["RowPaddingDesc"],
				min = 0,
				max = 10,
				get = function()
					return G_RLF.DbAccessor:Sizing(id).padding
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Sizing(id).padding = value
					G_RLF.LootDisplay:UpdateSize(id)
				end,
				order = 5,
			},
		},
	}
end
