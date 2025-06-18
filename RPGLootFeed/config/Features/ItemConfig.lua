---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

local ItemConfig = {}

local lsm = G_RLF.lsm

local PricesEnum = G_RLF.PricesEnum

---@class RLF_DBGlobal
G_RLF.defaults.global = G_RLF.defaults.global or {}

---@class RLF_ConfigItemLoot
G_RLF.defaults.global.item = {
	enabled = true,
	itemCountTextEnabled = true,
	itemCountTextColor = { 0.737, 0.737, 0.737, 1 },
	itemCountTextWrapChar = G_RLF.WrapCharEnum.PARENTHESIS,
	itemQualitySettings = {
		[G_RLF.ItemQualEnum.Poor] = {
			enabled = true,
			duration = 0,
		},
		[G_RLF.ItemQualEnum.Common] = {
			enabled = true,
			duration = 0,
		},
		[G_RLF.ItemQualEnum.Uncommon] = {
			enabled = true,
			duration = 0,
		},
		[G_RLF.ItemQualEnum.Rare] = {
			enabled = true,
			duration = 0,
		},
		[G_RLF.ItemQualEnum.Epic] = {
			enabled = true,
			duration = 0,
		},
		[G_RLF.ItemQualEnum.Legendary] = {
			enabled = true,
			duration = 0,
		},
		[G_RLF.ItemQualEnum.Artifact] = {
			enabled = true,
			duration = 0,
		},
		[G_RLF.ItemQualEnum.Heirloom] = {
			enabled = true,
			duration = 0,
		},
	},
	itemHighlights = {
		boe = false,
		bop = false,
		quest = false,
		transmog = false,
		mounts = true,
		legendary = true,
		betterThanEquipped = true,
		hasTertiaryOrSocket = true,
	},
	---@type string
	auctionHouseSource = G_RLF.L["None"] --[[@as string]],
	pricesForSellableItems = PricesEnum.Vendor,
	vendorIconTexture = G_RLF:IsRetail() and "spellicon-256x256-selljunk" or "bags-junkcoin",
	auctionHouseIconTexture = G_RLF:IsRetail() and "auctioneer" or "Auctioneer",
	---@class RLF_ConfigItemLoot.Sounds
	sounds = {
		mounts = {
			enabled = false,
			sound = "",
		},
		legendary = {
			enabled = false,
			sound = "",
		},
		betterThanEquipped = {
			enabled = false,
			sound = "",
		},
		transmog = {
			enabled = false,
			sound = "",
		},
	},
	textStyleOverrides = {
		quest = {
			enabled = false,
			color = { 1, 1, 0, 1 }, -- Yellow
		},
	},
}

G_RLF.options.args.features.args.itemLootConfig = {
	type = "group",
	handler = ItemConfig,
	name = G_RLF.L["Item Loot Config"],
	order = G_RLF.mainFeatureOrder.ItemLoot,
	args = {
		enableItemLoot = {
			type = "toggle",
			name = G_RLF.L["Enable Item Loot in Feed"],
			desc = G_RLF.L["EnableItemLootDesc"],
			width = "double",
			get = function()
				return G_RLF.db.global.item.enabled
			end,
			set = function(_, value)
				G_RLF.db.global.item.enabled = value
				if value then
					G_RLF.RLF:EnableModule(G_RLF.FeatureModule.ItemLoot)
				else
					G_RLF.RLF:DisableModule(G_RLF.FeatureModule.ItemLoot)
				end
			end,
			order = 1,
		},
		itemLootOptions = {
			type = "group",
			inline = true,
			name = G_RLF.L["Item Loot Options"],
			disabled = function()
				return not G_RLF.db.global.item.enabled
			end,
			order = 1.1,
			args = {
				itemCountText = {
					type = "group",
					name = G_RLF.L["Item Count Text"],
					inline = true,
					order = 1.1,
					args = {
						itemCountTextEnabled = {
							type = "toggle",
							name = G_RLF.L["Enable Item Count Text"],
							desc = G_RLF.L["EnableItemCountTextDesc"],
							width = "double",
							get = function()
								return G_RLF.db.global.item.itemCountTextEnabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemCountTextEnabled = value
							end,
							order = 1,
						},
						itemCountTextColor = {
							type = "color",
							name = G_RLF.L["Item Count Text Color"],
							desc = G_RLF.L["ItemCountTextColorDesc"],
							width = "double",
							disabled = function()
								return not G_RLF.db.global.item.itemCountTextEnabled
							end,
							hasAlpha = true,
							get = function()
								return unpack(G_RLF.db.global.item.itemCountTextColor)
							end,
							set = function(_, r, g, b, a)
								G_RLF.db.global.item.itemCountTextColor = { r, g, b, a }
							end,
							order = 2,
						},
						itemCountTextWrapChar = {
							type = "select",
							name = G_RLF.L["Item Count Text Wrap Character"],
							desc = G_RLF.L["ItemCountTextWrapCharDesc"],
							disabled = function()
								return not G_RLF.db.global.item.itemCountTextEnabled
							end,
							values = G_RLF.WrapCharOptions,
							get = function()
								return G_RLF.db.global.item.itemCountTextWrapChar
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemCountTextWrapChar = value
							end,
							order = 3,
						},
					},
				},
				itemSecondaryTextOptions = {
					type = "group",
					name = G_RLF.L["Item Secondary Text Options"],
					inline = true,
					order = 1.2,
					args = {
						pricesForSellableItems = {
							type = "select",
							name = G_RLF.L["Prices for Sellable Items"],
							desc = G_RLF.L["PricesForSellableItemsDesc"],
							values = function()
								local values = {
									[PricesEnum.None] = G_RLF.L["None"],
									[PricesEnum.Vendor] = G_RLF.L["Vendor Price"],
								}
								if G_RLF.AuctionIntegrations.numActiveIntegrations > 0 then
									values[PricesEnum.AH] = G_RLF.L["Auction Price"]
									values[PricesEnum.VendorAH] = G_RLF.L["Vendor Price then Auction Price"]
									values[PricesEnum.AHVendor] = G_RLF.L["Auction Price then Vendor Price"]
									values[PricesEnum.Highest] = G_RLF.L["Highest Price"]
								end
								return values
							end,
							sorting = function()
								local order = {
									PricesEnum.None,
									PricesEnum.Vendor,
								}
								if G_RLF.AuctionIntegrations.numActiveIntegrations > 0 then
									table.insert(order, PricesEnum.AH)
									table.insert(order, PricesEnum.VendorAH)
									table.insert(order, PricesEnum.AHVendor)
									table.insert(order, PricesEnum.Highest)
								end

								return order
							end,
							get = function(info)
								if
									(
										G_RLF.db.global.item.pricesForSellableItems == PricesEnum.AH
										or G_RLF.db.global.item.pricesForSellableItems == PricesEnum.VendorAH
										or G_RLF.db.global.item.pricesForSellableItems == PricesEnum.AHVendor
										or G_RLF.db.global.item.pricesForSellableItems == PricesEnum.Highest
									) and G_RLF.AuctionIntegrations.numActiveIntegrations == 0
								then
									G_RLF.db.global.item.pricesForSellableItems = PricesEnum.Vendor
								end
								return G_RLF.db.global.item.pricesForSellableItems
							end,
							set = function(info, value)
								G_RLF.db.global.item.pricesForSellableItems = value
							end,
							order = 1,
						},
						auctionHouseSource = {
							type = "select",
							name = G_RLF.L["Auction House Source"],
							desc = G_RLF.L["AuctionHouseSourceDesc"],
							values = function()
								local values = {}
								values[G_RLF.AuctionIntegrations.nilIntegration:ToString()] =
									G_RLF.AuctionIntegrations.nilIntegration:ToString()

								local activeIntegrations = G_RLF.AuctionIntegrations.activeIntegrations
								local numActiveIntegrations = G_RLF.AuctionIntegrations.numActiveIntegrations
								if activeIntegrations and numActiveIntegrations >= 1 then
									for k, _ in pairs(activeIntegrations) do
										values[k] = k
									end
								end
								return values
							end,
							sorting = function()
								local values = {}
								values[1] = G_RLF.AuctionIntegrations.nilIntegration:ToString()

								local activeIntegrations = G_RLF.AuctionIntegrations.activeIntegrations
								local numActiveIntegrations = G_RLF.AuctionIntegrations.numActiveIntegrations
								if activeIntegrations and numActiveIntegrations >= 1 then
									local i = 2
									for k, _ in pairs(activeIntegrations) do
										values[i] = k
										i = i + 1
									end
								end
								return values
							end,
							disabled = function()
								return G_RLF.db.global.item.pricesForSellableItems == PricesEnum.Vendor
									or G_RLF.db.global.item.pricesForSellableItems == PricesEnum.None
							end,
							hidden = function()
								local activeIntegrations = G_RLF.AuctionIntegrations.activeIntegrations
								local numActiveIntegrations = G_RLF.AuctionIntegrations.numActiveIntegrations
								local hide = not activeIntegrations or numActiveIntegrations == 0
								if hide then
									G_RLF.db.global.item.auctionHouseSource =
										G_RLF.AuctionIntegrations.nilIntegration:ToString()
								end
								return hide
							end,
							get = function(info)
								local activeIntegrations = G_RLF.AuctionIntegrations.activeIntegrations
								local numActiveIntegrations = G_RLF.AuctionIntegrations.numActiveIntegrations
								if
									not activeIntegrations
									or not activeIntegrations[G_RLF.db.global.item.auctionHouseSource]
									or numActiveIntegrations == 0
								then
									G_RLF.db.global.item.auctionHouseSource =
										G_RLF.AuctionIntegrations.nilIntegration:ToString()
								end
								return G_RLF.db.global.item.auctionHouseSource
							end,
							set = function(info, value)
								G_RLF.db.global.item.auctionHouseSource = value
								if value ~= G_RLF.AuctionIntegrations.nilIntegration:ToString() then
									G_RLF.AuctionIntegrations.activeIntegration =
										G_RLF.AuctionIntegrations.activeIntegrations[value]
								else
									G_RLF.AuctionIntegrations.activeIntegration =
										G_RLF.AuctionIntegrations.nilIntegration
								end
							end,
							order = 2,
						},
						atlasIconDescription = {
							type = "description",
							name = G_RLF.L["AtlasIconDescription"],
							order = 2.99,
						},
						vendorIconTexture = {
							type = "input",
							name = G_RLF.L["Vendor Icon Texture"],
							desc = G_RLF.L["VendorIconTextureDesc"],
							width = "double",
							get = function()
								return G_RLF.db.global.item.vendorIconTexture
							end,
							set = function(_, value)
								G_RLF.db.global.item.vendorIconTexture = value
							end,
							validate = "ValidateAtlas",
							order = 3,
						},
						testVendorIcon = {
							type = "description",
							name = function()
								local icon = G_RLF.db.global.item.vendorIconTexture
								return ItemConfig:TestIcon(icon)
							end,
							width = "normal",
							order = 3.1,
						},
						revertVendorToDefault = {
							type = "execute",
							name = CreateAtlasMarkup("common-icon-undo", 16, 16),
							desc = G_RLF.L["RevertVendorIconToDefaultDesc"],
							func = function()
								G_RLF.db.global.item.vendorIconTexture = G_RLF.db.defaults.global.item.vendorIconTexture
							end,
							width = 0.35,
							order = 3.2,
						},
						auctionHouseIconTexture = {
							type = "input",
							name = G_RLF.L["Auction House Icon Texture"],
							desc = G_RLF.L["AuctionHouseIconTextureDesc"],
							width = "double",
							get = function()
								return G_RLF.db.global.item.auctionHouseIconTexture
							end,
							set = function(_, value)
								G_RLF.db.global.item.auctionHouseIconTexture = value
							end,
							validate = "ValidateAtlas",
							order = 4,
						},
						testAuctionHouseIcon = {
							type = "description",
							name = function()
								local icon = G_RLF.db.global.item.auctionHouseIconTexture
								return ItemConfig:TestIcon(icon)
							end,
							width = "normal",
							order = 4.1,
						},
						revertAuctionHouseToDefault = {
							type = "execute",
							name = CreateAtlasMarkup("common-icon-undo", 16, 16),
							desc = G_RLF.L["RevertAuctionHouseIconToDefaultDesc"],
							func = function()
								G_RLF.db.global.item.auctionHouseIconTexture =
									G_RLF.db.defaults.global.item.auctionHouseIconTexture
							end,
							width = 0.35,
							order = 4.2,
						},
					},
				},
				itemQualityFilter = {
					type = "group",
					name = G_RLF.L["Item Quality Filter"],
					desc = G_RLF.L["ItemQualityFilterDesc"],
					inline = true,
					order = 2,
					args = {
						resetAllDurationOverrides = {
							type = "execute",
							name = G_RLF.L["Reset All Duration Overrides"],
							desc = G_RLF.L["ResetAllDurationOverridesDesc"],
							func = function()
								for _, v in pairs(G_RLF.db.global.item.itemQualitySettings) do
									v.duration = 0
								end
							end,
							order = 0.5,
							width = "full",
						},
						poorEnabled = {
							type = "toggle",
							name = G_RLF.L["Poor"],
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Poor].enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Poor].enabled = value
							end,
							order = 2,
						},
						poorDuration = {
							type = "range",
							name = string.format(G_RLF.L["Duration (seconds)"], G_RLF.L["Poor"]),
							desc = string.format(G_RLF.L["DurationDesc"], G_RLF.L["Poor"]),
							min = 0,
							max = 30,
							step = 1,
							hidden = function()
								return not G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Poor].enabled
							end,
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Poor].duration
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Poor].duration = value
							end,
							order = 3,
						},
						commonEnabled = {
							type = "toggle",
							name = G_RLF.L["Common"],
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Common].enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Common].enabled = value
							end,
							order = 5,
						},
						commonDuration = {
							type = "range",
							name = string.format(G_RLF.L["Duration (seconds)"], G_RLF.L["Common"]),
							desc = string.format(G_RLF.L["DurationDesc"], G_RLF.L["Common"]),
							min = 0,
							max = 30,
							step = 1,
							hidden = function()
								return not G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Common].enabled
							end,
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Common].duration
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Common].duration = value
							end,
							order = 6,
						},
						uncommonEnabled = {
							type = "toggle",
							name = G_RLF.L["Uncommon"],
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Uncommon].enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Uncommon].enabled = value
							end,
							order = 8,
						},
						uncommonDuration = {
							type = "range",
							name = string.format(G_RLF.L["Duration (seconds)"], G_RLF.L["Uncommon"]),
							desc = string.format(G_RLF.L["DurationDesc"], G_RLF.L["Uncommon"]),
							min = 0,
							max = 30,
							step = 1,
							hidden = function()
								return not G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Uncommon].enabled
							end,
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Uncommon].duration
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Uncommon].duration = value
							end,
							order = 9,
						},
						rareEnabled = {
							type = "toggle",
							name = G_RLF.L["Rare"],
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Rare].enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Rare].enabled = value
							end,
							order = 11,
						},
						rareDuration = {
							type = "range",
							name = string.format(G_RLF.L["Duration (seconds)"], G_RLF.L["Rare"]),
							desc = string.format(G_RLF.L["DurationDesc"], G_RLF.L["Rare"]),
							min = 0,
							max = 30,
							step = 1,
							hidden = function()
								return not G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Rare].enabled
							end,
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Rare].duration
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Rare].duration = value
							end,
							order = 12,
						},
						epicEnabled = {
							type = "toggle",
							name = G_RLF.L["Epic"],
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Epic].enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Epic].enabled = value
							end,
							order = 14,
						},
						epicDuration = {
							type = "range",
							name = string.format(G_RLF.L["Duration (seconds)"], G_RLF.L["Epic"]),
							desc = string.format(G_RLF.L["DurationDesc"], G_RLF.L["Epic"]),
							min = 0,
							max = 30,
							step = 1,
							hidden = function()
								return not G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Epic].enabled
							end,
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Epic].duration
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Epic].duration = value
							end,
							order = 15,
						},
						legendaryEnabled = {
							type = "toggle",
							name = G_RLF.L["Legendary"],
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Legendary].enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Legendary].enabled = value
							end,
							order = 17,
						},
						legendaryDuration = {
							type = "range",
							name = string.format(G_RLF.L["Duration (seconds)"], G_RLF.L["Legendary"]),
							desc = string.format(G_RLF.L["DurationDesc"], G_RLF.L["Legendary"]),
							min = 0,
							max = 30,
							step = 1,
							hidden = function()
								return not G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Legendary].enabled
							end,
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Legendary].duration
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Legendary].duration = value
							end,
							order = 18,
						},
						artifactEnabled = {
							type = "toggle",
							name = G_RLF.L["Artifact"],
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Artifact].enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Artifact].enabled = value
							end,
							order = 20,
						},
						artifactDuration = {
							type = "range",
							name = string.format(G_RLF.L["Duration (seconds)"], G_RLF.L["Artifact"]),
							desc = string.format(G_RLF.L["DurationDesc"], G_RLF.L["Artifact"]),
							min = 0,
							max = 30,
							step = 1,
							hidden = function()
								return not G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Artifact].enabled
							end,
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Artifact].duration
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Artifact].duration = value
							end,
							order = 21,
						},
						heirloomEnabled = {
							type = "toggle",
							name = G_RLF.L["Heirloom"],
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Heirloom].enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Heirloom].enabled = value
							end,
							order = 23,
						},
						heirloomDuration = {
							type = "range",
							name = string.format(G_RLF.L["Duration (seconds)"], G_RLF.L["Heirloom"]),
							desc = string.format(G_RLF.L["DurationDesc"], G_RLF.L["Heirloom"]),
							min = 0,
							max = 30,
							step = 1,
							hidden = function()
								return not G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Heirloom].enabled
							end,
							get = function()
								return G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Heirloom].duration
							end,
							set = function(_, value)
								G_RLF.db.global.item.itemQualitySettings[G_RLF.ItemQualEnum.Heirloom].duration = value
							end,
							order = 24,
						},
					},
				},
				itemHighlights = {
					type = "group",
					name = G_RLF.L["Item Highlights"],
					desc = G_RLF.L["ItemHighlightsDesc"],
					inline = true,
					order = 3,
					args = {
						highlightMount = {
							type = "toggle",
							name = G_RLF.L["Highlight Mounts"],
							desc = G_RLF.L["HighlightMountsDesc"],
							width = "double",
							get = function(info)
								return G_RLF.db.global.item.itemHighlights.mounts
							end,
							set = function(info, value)
								G_RLF.db.global.item.itemHighlights.mounts = value
							end,
							order = 1,
						},
						highlightLegendary = {
							type = "toggle",
							name = G_RLF.L["Highlight Legendary Items"],
							desc = G_RLF.L["HighlightLegendaryDesc"],
							width = "double",
							get = function(info)
								return G_RLF.db.global.item.itemHighlights.legendary
							end,
							set = function(info, value)
								G_RLF.db.global.item.itemHighlights.legendary = value
							end,
							order = 2,
						},
						highlightBetterThanEquipped = {
							type = "toggle",
							name = G_RLF.L["Highlight Items Better Than Equipped"],
							desc = G_RLF.L["HighlightBetterThanEquippedDesc"],
							width = "double",
							get = function(info)
								return G_RLF.db.global.item.itemHighlights.betterThanEquipped
							end,
							set = function(info, value)
								G_RLF.db.global.item.itemHighlights.betterThanEquipped = value
							end,
							order = 3,
						},
						hasTertiaryOrSocket = {
							type = "toggle",
							name = G_RLF.L["Highlight Items with Tertiary Stats or Sockets"],
							desc = G_RLF.L["HighlightTertiaryOrSocketDesc"],
							width = "double",
							get = function(info)
								return G_RLF.db.global.item.itemHighlights.hasTertiaryOrSocket
							end,
							set = function(info, value)
								G_RLF.db.global.item.itemHighlights.hasTertiaryOrSocket = value
							end,
							order = 4,
						},
						-- highlightBoE = {
						--   type = "toggle",
						--   name = G_RLF.L["Highlight BoE Items"],
						--   desc = G_RLF.L["HighlightBoEDesc"],
						--   width = "double",
						--   get = function(info) return G_RLF.db.global.item.itemHighlights.boe end,
						--   set = function(info, value) G_RLF.db.global.item.itemHighlights.boe = value end,
						--   order = 3,
						-- },
						-- highlightBoP = {
						--   type = "toggle",
						--   name = G_RLF.L["Highlight BoP Items"],
						--   desc = G_RLF.L["HighlightBoPDesc"],
						--   width = "double",
						--   get = function(info) return G_RLF.db.global.item.itemHighlights.bop end,
						--   set = function(info, value) G_RLF.db.global.item.itemHighlights.bop = value end,
						--   order = 4,
						-- },
						highlightQuest = {
							type = "toggle",
							name = G_RLF.L["Highlight Quest Items"],
							desc = G_RLF.L["HighlightQuestDesc"],
							width = "double",
							get = function(info)
								return G_RLF.db.global.item.itemHighlights.quest
							end,
							set = function(info, value)
								G_RLF.db.global.item.itemHighlights.quest = value
							end,
							order = 5,
						},
						highlightTransmog = {
							type = "toggle",
							name = G_RLF.L["Highlight New Transmog Items"],
							desc = G_RLF.L["HighlightTransmogDesc"],
							width = "double",
							get = function(info)
								return G_RLF.db.global.item.itemHighlights.transmog
							end,
							set = function(info, value)
								G_RLF.db.global.item.itemHighlights.transmog = value
							end,
							order = 6,
						},
					},
				},
				itemSounds = {
					type = "group",
					name = G_RLF.L["Item Loot Sounds"],
					inline = true,
					order = 4,
					args = {
						mounts = {
							type = "toggle",
							name = G_RLF.L["Play Sound for Mounts"],
							desc = G_RLF.L["PlaySoundForMountsDesc"],
							width = "double",
							get = function()
								return G_RLF.db.global.item.sounds.mounts.enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.sounds.mounts.enabled = value
							end,
							order = 1,
						},
						playSelectedMountSound = {
							type = "execute",
							name = CreateAtlasMarkup("common-icon-forwardarrow", 16, 16),
							desc = G_RLF.L["TestMountSoundDesc"],
							func = function()
								PlaySoundFile(G_RLF.db.global.item.sounds.mounts.sound)
							end,
							disabled = function()
								return not G_RLF.db.global.item.sounds.mounts.enabled
									or G_RLF.db.global.item.sounds.mounts.sound == ""
							end,
							width = 0.35,
							order = 1.5,
						},
						mountSound = {
							type = "select",
							name = G_RLF.L["Mount Sound"],
							desc = G_RLF.L["MountSoundDesc"],
							values = "SoundOptionValues",
							get = function()
								return G_RLF.db.global.item.sounds.mounts.sound
							end,
							set = function(_, value)
								G_RLF.db.global.item.sounds.mounts.sound = value
							end,
							disabled = function()
								return not G_RLF.db.global.item.sounds.mounts.enabled
							end,
							order = 2,
							width = "full",
						},
						legendary = {
							type = "toggle",
							name = G_RLF.L["Play Sound for Legendary Items"],
							desc = G_RLF.L["PlaySoundForLegendaryDesc"],
							width = "double",
							get = function()
								return G_RLF.db.global.item.sounds.legendary.enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.sounds.legendary.enabled = value
							end,
							order = 3,
						},
						playSelectedLegendarySound = {
							type = "execute",
							name = CreateAtlasMarkup("common-icon-forwardarrow", 16, 16),
							desc = G_RLF.L["TestLegendarySoundDesc"],
							func = function()
								PlaySoundFile(G_RLF.db.global.item.sounds.legendary.sound)
							end,
							disabled = function()
								return not G_RLF.db.global.item.sounds.legendary.enabled
									or G_RLF.db.global.item.sounds.legendary.sound == ""
							end,
							width = 0.35,
							order = 3.5,
						},
						legendarySound = {
							type = "select",
							name = G_RLF.L["Legendary Sound"],
							desc = G_RLF.L["LegendarySoundDesc"],
							values = "SoundOptionValues",
							get = function()
								return G_RLF.db.global.item.sounds.legendary.sound
							end,
							set = function(_, value)
								G_RLF.db.global.item.sounds.legendary.sound = value
							end,
							disabled = function()
								return not G_RLF.db.global.item.sounds.legendary.enabled
							end,
							order = 4,
							width = "full",
						},
						betterThanEquipped = {
							type = "toggle",
							name = G_RLF.L["Play Sound for Items Better Than Equipped"],
							desc = G_RLF.L["PlaySoundForBetterDesc"],
							width = "double",
							get = function()
								return G_RLF.db.global.item.sounds.betterThanEquipped.enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.sounds.betterThanEquipped.enabled = value
							end,
							order = 5,
						},
						playSelectedBetterThanEquippedSound = {
							type = "execute",
							name = CreateAtlasMarkup("common-icon-forwardarrow", 16, 16),
							desc = G_RLF.L["TestBetterThanEquippedSoundDesc"],
							func = function()
								PlaySoundFile(G_RLF.db.global.item.sounds.betterThanEquipped.sound)
							end,
							disabled = function()
								return not G_RLF.db.global.item.sounds.betterThanEquipped.enabled
									or G_RLF.db.global.item.sounds.betterThanEquipped.sound == ""
							end,
							width = 0.35,
							order = 5.5,
						},
						betterThanEquippedSound = {
							type = "select",
							name = G_RLF.L["Better Than Equipped Sound"],
							desc = G_RLF.L["BetterThanEquippedSoundDesc"],
							values = "SoundOptionValues",
							get = function()
								return G_RLF.db.global.item.sounds.betterThanEquipped.sound
							end,
							set = function(_, value)
								G_RLF.db.global.item.sounds.betterThanEquipped.sound = value
							end,
							disabled = function()
								return not G_RLF.db.global.item.sounds.betterThanEquipped.enabled
							end,
							width = "full",
							order = 6,
						},
						transmog = {
							type = "toggle",
							name = G_RLF.L["Play Sound for New Transmog Items"],
							desc = G_RLF.L["PlaySoundForTransmogDesc"],
							width = "double",
							get = function()
								return G_RLF.db.global.item.sounds.transmog.enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.sounds.transmog.enabled = value
							end,
							order = 7,
						},
						playSelectedTransmogSound = {
							type = "execute",
							name = CreateAtlasMarkup("common-icon-forwardarrow", 16, 16),
							desc = G_RLF.L["TestTransmogSoundDesc"],
							func = function()
								PlaySoundFile(G_RLF.db.global.item.sounds.transmog.sound)
							end,
							disabled = function()
								return not G_RLF.db.global.item.sounds.transmog.enabled
									or G_RLF.db.global.item.sounds.transmog.sound == ""
							end,
							width = 0.35,
							order = 7.5,
						},
						transmogSound = {
							type = "select",
							name = G_RLF.L["Transmog Sound"],
							desc = G_RLF.L["TransmogSoundDesc"],
							values = "SoundOptionValues",
							get = function()
								return G_RLF.db.global.item.sounds.transmog.sound
							end,
							set = function(_, value)
								G_RLF.db.global.item.sounds.transmog.sound = value
							end,
							disabled = function()
								return not G_RLF.db.global.item.sounds.transmog.enabled
							end,
							width = "full",
							order = 8,
						},
					},
				},
				itemStyleOverrides = {
					type = "group",
					name = G_RLF.L["Item Text Style Overrides"],
					inline = true,
					order = 5,
					args = {
						questStyleOverrideEnabled = {
							type = "toggle",
							name = G_RLF.L["Override Text Style for Quest Items"],
							desc = G_RLF.L["QuestItemStyleOverrideDesc"],
							width = "double",
							get = function()
								return G_RLF.db.global.item.textStyleOverrides.quest.enabled
							end,
							set = function(_, value)
								G_RLF.db.global.item.textStyleOverrides.quest.enabled = value
							end,
							order = 1,
						},
						questStyleOverrideColor = {
							type = "color",
							name = G_RLF.L["Quest Item Color Text"],
							desc = G_RLF.L["QuestItemColorTextDesc"],
							width = "double",
							hasAlpha = true,
							disabled = function()
								return not G_RLF.db.global.item.textStyleOverrides.quest.enabled
							end,
							get = function()
								return unpack(G_RLF.db.global.item.textStyleOverrides.quest.color)
							end,
							set = function(_, r, g, b, a)
								G_RLF.db.global.item.textStyleOverrides.quest.color = { r, g, b, a }
							end,
							order = 2,
						},
					},
				},
			},
		},
	},
}

function ItemConfig:SoundOptionValues()
	local sounds = {}
	for k, v in pairs(lsm:HashTable(lsm.MediaType.SOUND)) do
		sounds[v] = k
	end
	return sounds
end

function ItemConfig:TestIcon(icon)
	local styleDb = G_RLF.DbAccessor:Styling()
	local secondaryFontSize = styleDb.secondaryFontSize
	local sizeCoeff = G_RLF.AtlasIconCoefficients[icon] or 1
	local atlasIconSize = secondaryFontSize * sizeCoeff
	return string.format(G_RLF.L["Chosen Icon"], CreateAtlasMarkup(icon, atlasIconSize, atlasIconSize))
end

function ItemConfig:ValidateAtlas(_, value)
	local info = C_Texture.GetAtlasInfo(value)

	if info then
		return true
	end

	return string.format(G_RLF.L["InvalidAtlasTexture"], value)
end
