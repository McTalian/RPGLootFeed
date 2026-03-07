---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

-- Enumerate available frames to anchor to
local function EnumerateFrames()
	local frames = {
		[-1] = G_RLF.L["Screen"],
	}
	local framesToCheck = {
		["UIParent"] = G_RLF.L["UIParent"],
		["PlayerFrame"] = G_RLF.L["PlayerFrame"],
		["Minimap"] = G_RLF.L["Minimap"],
		["MainMenuBarBackpackButton"] = G_RLF.L["BagBar"],
	}
	for f, s in pairs(framesToCheck) do
		if _G[f] then
			frames[f] = s
		end
	end
	return frames
end

--- Build the AceConfig positioning group args for the given frame ID.
--- Returns the full type="group" table ready to embed in a per-frame group.
--- @param id integer frame ID
--- @param order number position order within the parent group
--- @return table
function G_RLF.BuildPositioningArgs(id, order)
	return {
		type = "group",
		name = G_RLF.L["Positioning"],
		desc = G_RLF.L["PositioningDesc"],
		order = order,
		args = {
			relativeTo = {
				type = "select",
				name = G_RLF.L["Anchor Relative To"],
				desc = G_RLF.L["RelativeToDesc"],
				get = function()
					return G_RLF.DbAccessor:Positioning(id).relativePoint
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Positioning(id).relativePoint = value
					G_RLF.LootDisplay:UpdatePosition(id)
				end,
				values = EnumerateFrames(),
				order = 1,
			},
			anchorPoint = {
				type = "select",
				name = G_RLF.L["Anchor Point"],
				desc = G_RLF.L["AnchorPointDesc"],
				get = function()
					return G_RLF.DbAccessor:Positioning(id).anchorPoint
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Positioning(id).anchorPoint = value
					G_RLF.LootDisplay:UpdatePosition(id)
				end,
				values = {
					["TOPLEFT"] = G_RLF.L["Top Left"],
					["TOPRIGHT"] = G_RLF.L["Top Right"],
					["BOTTOMLEFT"] = G_RLF.L["Bottom Left"],
					["BOTTOMRIGHT"] = G_RLF.L["Bottom Right"],
					["TOP"] = G_RLF.L["Top"],
					["BOTTOM"] = G_RLF.L["Bottom"],
					["LEFT"] = G_RLF.L["Left"],
					["RIGHT"] = G_RLF.L["Right"],
					["CENTER"] = G_RLF.L["Center"],
				},
				order = 2,
			},
			xOffset = {
				type = "range",
				name = G_RLF.L["X Offset"],
				desc = G_RLF.L["XOffsetDesc"],
				min = -1500,
				max = 1500,
				get = function()
					return G_RLF.DbAccessor:Positioning(id).xOffset
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Positioning(id).xOffset = value
					G_RLF.LootDisplay:UpdatePosition(id)
				end,
				order = 3,
			},
			yOffset = {
				type = "range",
				name = G_RLF.L["Y Offset"],
				desc = G_RLF.L["YOffsetDesc"],
				min = -1500,
				max = 1500,
				get = function()
					return G_RLF.DbAccessor:Positioning(id).yOffset
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Positioning(id).yOffset = value
					G_RLF.LootDisplay:UpdatePosition(id)
				end,
				order = 4,
			},
			frameStrata = {
				type = "select",
				name = G_RLF.L["Frame Strata"],
				desc = G_RLF.L["FrameStrataDesc"],
				get = function()
					return G_RLF.DbAccessor:Positioning(id).frameStrata
				end,
				set = function(_, value)
					G_RLF.DbAccessor:Positioning(id).frameStrata = value
					G_RLF.LootDisplay:UpdateStrata(id)
				end,
				values = {
					["BACKGROUND"] = G_RLF.L["Background"],
					["LOW"] = G_RLF.L["Low"],
					["MEDIUM"] = G_RLF.L["Medium"],
					["HIGH"] = G_RLF.L["High"],
					["DIALOG"] = G_RLF.L["Dialog"],
					["TOOLTIP"] = G_RLF.L["Tooltip"],
				},
				sorting = {
					"BACKGROUND",
					"LOW",
					"MEDIUM",
					"HIGH",
					"DIALOG",
					"TOOLTIP",
				},
				order = 5,
			},
		},
	}
end
