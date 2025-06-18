---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local About = {}

---@class RLF_DBGlobal
G_RLF.defaults.global = G_RLF.defaults.global or {}

---@class RLF_ConfigAbout
G_RLF.defaults.global.about = {}

About.argOrder = {
	["title"] = 1,
	["version"] = 2,
	["discordDescription"] = 3,
	["joinDiscord"] = 4,
	["issuesAndRequests"] = 5,
	["issuesLink"] = 6,
	["author"] = -4,
	["githubLink"] = -3,
	["tipsLink"] = -2,
	["credits"] = -1,
}

G_RLF.options.args.about = {
	type = "group",
	handler = About,
	name = G_RLF.L["About"],
	desc = G_RLF.L["AboutDesc"],
	order = G_RLF.level1OptionsOrder.about,
	args = {
		title = {
			type = "header",
			name = G_RLF.L["AboutTitle"],
			order = About.argOrder.title,
		},
		version = {
			type = "description",
			name = string.format(G_RLF.L["Version"], G_RLF.addonVersion) .. "\n\n",
			order = About.argOrder.version,
		},
		discordDescription = {
			type = "description",
			fontSize = "medium",
			image = "Interface/AddOns/RPGLootFeed/Icons/logo.blp",
			name = G_RLF.L["JoinDiscordDesc"],
			order = About.argOrder.discordDescription,
		},
		joinDiscord = {
			type = "input",
			name = G_RLF.L["JoinDiscord"],
			width = "full",
			get = function()
				return "https://discord.gg/czRYVWhe33"
			end,
			order = About.argOrder.joinDiscord,
		},
		issuesAndRequests = {
			type = "description",
			name = G_RLF.L["IssuesAndRequests"],
			order = About.argOrder.issuesAndRequests,
		},
		issuesLink = {
			type = "input",
			name = G_RLF.L["GitHubIssuesLink"],
			width = "full",
			get = function()
				return "https://github.com/McTalian/RPGLootFeed/issues/new/choose"
			end,
			order = About.argOrder.issuesLink,
		},

		author = {
			type = "description",
			image = "Interface/AddOns/RPGLootFeed/Icons/mctalian_logo.png",
			name = G_RLF.L["Author"],
			order = About.argOrder.author,
		},
		githubLink = {
			type = "input",
			name = G_RLF.L["AuthorGitHub"],
			width = "full",
			get = function()
				return "https://github.com/McTalian"
			end,
			order = About.argOrder.githubLink,
		},
		tipsLink = {
			type = "input",
			name = G_RLF.L["TipsLink"],
			width = "full",
			get = function()
				return "https://buymeacoffee.com/mctalian"
			end,
			order = About.argOrder.tipsLink,
		},
		credits = {
			type = "description",
			name = function()
				local translationCredits = G_RLF.L["Credits"]
				local esMX = "* esMX by Lalz420"
				local frFR = "* frFR by polki92"
				local ruRU = "* ruRU by ZamestoTV"
				if GetLocale() == "ruRU" then
					ruRU = ruRU .. ", Карнажж (Пламегор)"
				else
					ruRU = ruRU .. ", Carnage (Flamegor)"
				end
				local zhCN = "* zhCN by byezero"
				return string.format(
					translationCredits,
					"\n",
					"\n" .. esMX .. "\n" .. frFR .. "\n" .. ruRU .. "\n" .. zhCN .. "\n" .. "\n"
				)
			end,
			order = About.argOrder.credits,
		},
	},
}
