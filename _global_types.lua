---@meta _
---@class ItemButton
---@field ProfessionQualityOverlay? Texture Overlay showing profession quality

---@meta _
---@class _G
---@field public SKILL_RANK_UP string

--- Base class for per-frame feature configuration.
---@class RLF_FeatureConfig
---@field enabled boolean

---@class RLF_FeatureConfig_ItemLoot : RLF_FeatureConfig
---@field itemCountTextEnabled boolean
---@field itemCountTextColor number[]
---@field itemCountTextWrapChar WrapCharEnum
---@field itemQualitySettings table
---@field itemHighlights table
---@field auctionHouseSource string
---@field pricesForSellableItems string
---@field vendorIconTexture string
---@field auctionHouseIconTexture string
---@field sounds table
---@field textStyleOverrides table
---@field enableIcon boolean

---@class RLF_FeatureConfig_PartyLoot : RLF_FeatureConfig
---@field itemQualityFilter table
---@field hideServerNames boolean
---@field onlyEpicAndAboveInRaid boolean
---@field onlyEpicAndAboveInInstance boolean
---@field ignoreItemIds table
---@field enableIcon boolean
---@field enablePartyAvatar boolean

---@class RLF_FeatureConfig_Currency : RLF_FeatureConfig
---@field currencyTotalTextEnabled boolean
---@field currencyTotalTextColor number[]
---@field currencyTotalTextWrapChar WrapCharEnum
---@field lowerThreshold number
---@field upperThreshold number
---@field lowestColor number[]
---@field midColor number[]
---@field upperColor number[]
---@field enableIcon boolean

---@class RLF_FeatureConfig_Money : RLF_FeatureConfig
---@field showMoneyTotal boolean
---@field moneyTotalColor number[]
---@field moneyTextWrapChar WrapCharEnum
---@field abbreviateTotal boolean
---@field accountantMode boolean
---@field onlyIncome boolean
---@field overrideMoneyLootSound boolean
---@field moneyLootSound string
---@field enableIcon boolean

---@class RLF_FeatureConfig_Experience : RLF_FeatureConfig
---@field experienceTextColor number[]
---@field showCurrentLevel boolean
---@field currentLevelColor number[]
---@field currentLevelTextWrapChar WrapCharEnum
---@field enableIcon boolean

---@class RLF_FeatureConfig_Reputation : RLF_FeatureConfig
---@field defaultRepColor number[]
---@field secondaryTextAlpha number
---@field enableRepLevel boolean
---@field repLevelColor number[]
---@field repLevelTextWrapChar WrapCharEnum
---@field enableIcon boolean

---@class RLF_FeatureConfig_Profession : RLF_FeatureConfig
---@field showSkillChange boolean
---@field skillColor number[]
---@field skillTextWrapChar WrapCharEnum
---@field enableIcon boolean

---@class RLF_FeatureConfig_TravelPoints : RLF_FeatureConfig
---@field textColor number[]
---@field enableIcon boolean

---@class RLF_FeatureConfig_Transmog : RLF_FeatureConfig
---@field enableTransmogEffect boolean
---@field enableBlizzardTransmogSound boolean
---@field enableIcon boolean

--- All per-frame feature configurations keyed by feature name.
---@class RLF_FrameFeatures
---@field itemLoot RLF_FeatureConfig_ItemLoot
---@field partyLoot RLF_FeatureConfig_PartyLoot
---@field currency RLF_FeatureConfig_Currency
---@field money RLF_FeatureConfig_Money
---@field experience RLF_FeatureConfig_Experience
---@field reputation RLF_FeatureConfig_Reputation
---@field profession RLF_FeatureConfig_Profession
---@field travelPoints RLF_FeatureConfig_TravelPoints
---@field transmog RLF_FeatureConfig_Transmog

--- Per-frame configuration stored under db.global.frames[id].
---@class RLF_ConfigReposition
---@field duration number

---@class RLF_ConfigAnimations
---@field enter table
---@field exit table
---@field hover table
---@field update table
---@field reposition RLF_ConfigReposition

---@class RLF_FrameConfig
---@field name string Display name shown in the config UI.
---@field positioning RLF_ConfigPositioning
---@field sizing RLF_ConfigSizing
---@field styling RLF_ConfigStyling
---@field animations RLF_ConfigAnimations
---@field features RLF_FrameFeatures
