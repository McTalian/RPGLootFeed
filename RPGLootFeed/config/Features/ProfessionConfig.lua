---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local ProfessionConfig = {}

--- Build the AceConfig options group for Profession on the given frame.
--- @param frameId integer
--- @param order number
--- @return table
function G_RLF.BuildProfessionArgs(frameId, order)
	local function fc()
		return G_RLF.db.global.frames[frameId].features.profession
	end
	return {
		type = "group",
		handler = ProfessionConfig,
		name = G_RLF.L["Profession Config"],
		order = order,
		args = {
			enableProfession = {
				type = "toggle",
				name = G_RLF.L["Enable Professions in Feed"],
				desc = G_RLF.L["EnableProfDesc"],
				width = "double",
				get = function()
					return fc().enabled
				end,
				set = function(_, value)
					fc().enabled = value
					G_RLF.DbAccessor:UpdateFeatureModuleState("profession")
				end,
				order = 1,
			},
			professionOptions = {
				type = "group",
				inline = true,
				name = G_RLF.L["Profession Options"],
				disabled = function()
					return not fc().enabled
				end,
				order = 1.1,
				args = {
					showIcon = {
						type = "toggle",
						name = G_RLF.L["Show Profession Icon"],
						desc = G_RLF.L["ShowProfessionIconDesc"],
						width = "double",
						disabled = function()
							return G_RLF.db.global.misc.hideAllIcons
						end,
						get = function()
							return fc().enableIcon
						end,
						set = function(_, value)
							fc().enableIcon = value
						end,
						order = 1,
					},
					skillChangeOptions = {
						type = "group",
						inline = true,
						name = G_RLF.L["Skill Change Options"],
						order = 1,
						args = {
							showSkillChange = {
								type = "toggle",
								name = G_RLF.L["Show Skill Change"],
								desc = G_RLF.L["ShowSkillChangeDesc"],
								width = "double",
								get = function()
									return fc().showSkillChange
								end,
								set = function(_, value)
									fc().showSkillChange = value
								end,
								order = 1,
							},
							skillColor = {
								type = "color",
								name = G_RLF.L["Skill Text Color"],
								desc = G_RLF.L["SkillColorDesc"],
								disabled = function()
									return not fc().showSkillChange
								end,
								hasAlpha = true,
								width = "double",
								get = function()
									return unpack(fc().skillColor)
								end,
								set = function(_, r, g, b, a)
									fc().skillColor = { r, g, b, a }
								end,
								order = 2,
							},
							skillTextWrapChar = {
								type = "select",
								name = G_RLF.L["Skill Text Wrap Character"],
								desc = G_RLF.L["SkillTextWrapCharDesc"],
								disabled = function()
									return not fc().showSkillChange
								end,
								get = function()
									return fc().skillTextWrapChar
								end,
								set = function(_, value)
									fc().skillTextWrapChar = value
								end,
								values = G_RLF.WrapCharOptions,
								style = "dropdown",
								order = 3,
							},
						},
					},
				},
			},
		},
	}
end
