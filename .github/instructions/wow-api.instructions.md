---
name: WoW API & RPGLootFeed Context
description: WoW API usage patterns and RPGLootFeed-specific context
applyTo: "**/*.lua"
---

# WoW API & RPGLootFeed Context

## Key WoW APIs for RPGLootFeed

### Loot Events

RPGLootFeed primarily listens to chat messages for loot detection:

```lua
-- Register loot-related events
self:RegisterEvent("CHAT_MSG_LOOT")
self:RegisterEvent("CHAT_MSG_CURRENCY")
self:RegisterEvent("CHAT_MSG_MONEY")
self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
self:RegisterEvent("CHAT_MSG_SKILL")

-- Example handler
function ItemLoot:CHAT_MSG_LOOT(event, message, playerName, ...)
  -- Parse loot message
  -- Message format: "You receive loot: |Hitem:123|h[Item Name]|hx5."
  local itemLink, quantity = self:ParseLootMessage(message)
  if itemLink then
    self:ProcessItemLoot(itemLink, quantity, playerName)
  end
end
```

### C_Item (Item Information)

Get item details, handle async loading:

```lua
-- Get item info (may need to wait for server)
local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType,
      itemSubType, itemStackCount, itemEquipLoc, iconFileDataID, sellPrice,
      classID, subclassID, bindType, expacID, setID, isCraftingReagent
      = C_Item.GetItemInfo(itemID)

-- Handle async loading
if not itemName then
  -- Item data not loaded yet, will need to retry
  C_Timer.After(0.5, function()
    -- Try again after delay
  end)
end

-- Get item quality color
local r, g, b, hex = C_Item.GetItemQualityColor(itemQuality)

-- Get item icon
local iconID = C_Item.GetItemIconByID(itemID)
```

### C_CurrencyInfo (Currency Tracking)

Track currency gains (badges, tokens, etc.):

```lua
-- Get currency details
local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
-- Returns: { name, amount, iconFileID, maxQuantity, ... }

-- Get currency link
local currencyLink = C_CurrencyInfo.GetCurrencyLink(currencyID)

-- Listen for currency changes
self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

function Currency:CURRENCY_DISPLAY_UPDATE(event, currencyID, quantity)
  -- Currency amount changed
  self:ProcessCurrency(currencyID, quantity)
end
```

### C_Reputation (Faction Tracking)

Track reputation gains:

```lua
-- Get faction info
local factionData = C_Reputation.GetFactionDataByID(factionID)
-- Returns: { name, currentReactionThreshold, nextReactionThreshold,
--           currentStanding, factionID, ... }

-- Get major faction data (Dragonflight+)
if C_MajorFactions then
  local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
end

-- Listen for reputation changes
self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")

-- Legacy API (still used)
local name, description, standingID, barMin, barMax, barValue,
      atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep,
      isWatched, isChild, factionID, hasBonusRepGain, canBeLFGBonus
      = GetFactionInfoByID(factionID)
```

### C_TransmogCollection (Transmog Tracking)

Track transmog appearance unlocks:

```lua
-- Check if transmog API available (added in later expansions)
if C_TransmogCollection then
  -- Get appearance source info
  local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)

  -- Check if appearance is collected
  local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)

  -- Listen for transmog updates
  self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
end
```

### C_TradeSkillUI (Profession Tracking)

Track profession skill-ups:

```lua
-- Get trade skill info
if C_TradeSkillUI then
  local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
  -- Returns: { professionID, professionName, skillLevel, maxSkillLevel, ... }
end

-- Listen for skill changes
self:RegisterEvent("CHAT_MSG_SKILL")

-- Parse skill gain message
-- Format: "Your skill in <profession> has increased to <level>."
```

### Group Detection

Determine if player is in party/raid for party loot features:

```lua
-- Check group status
local inGroup = IsInGroup()
local inRaid = IsInRaid()
local isInstanceGroup = IsInInstance()

-- Get group size
local numGroupMembers = GetNumGroupMembers()
local numRaidMembers = GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)

-- Check if player is group leader
local isLeader = UnitIsGroupLeader("player")

-- Get instance type
local instanceName, instanceType, difficulty, difficultyName,
      maxPlayers, dynamicDifficulty, isDynamic, instanceID,
      instanceGroupSize, LfgDungeonID = GetInstanceInfo()
-- instanceType: "none", "party", "raid", "pvp", "arena", "scenario"
```

### UI and Frame APIs

Create and manage UI frames:

```lua
-- Create frame
local frame = CreateFrame("Frame", "MyFrameName", UIParent)

-- Set frame properties
frame:SetSize(width, height)
frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)
frame:SetFrameStrata("MEDIUM")

-- Create font string
local text = frame:CreateFontString(nil, "OVERLAY")
text:SetFont(fontPath, fontSize, fontFlags)
text:SetTextColor(r, g, b, a)
text:SetText("Display Text")

-- Create texture
local texture = frame:CreateTexture(nil, "BACKGROUND")
texture:SetTexture(texturePath)
texture:SetAllPoints(frame)
```

### LibSharedMedia (Fonts, Textures, Sounds)

Access shared media across addons:

```lua
local LSM = LibStub("LibSharedMedia-3.0")

-- Register custom media
LSM:Register(LSM.MediaType.FONT, "MyFont", "Interface/AddOns/RPGLootFeed/Fonts/font.ttf")
LSM:Register(LSM.MediaType.SOUND, "LootSound", "Interface/AddOns/RPGLootFeed/Sounds/sound.ogg")

-- Fetch media path
local fontPath = LSM:Fetch(LSM.MediaType.FONT, "Arial Narrow")
local soundPath = LSM:Fetch(LSM.MediaType.SOUND, "LootSound")

-- Play sound
PlaySoundFile(soundPath, "Master")
```

## Terminology Quick Reference

See [Glossary](../docs/glossary.md) for complete terminology reference.

**Key Terms:**

- **Item Link**: Clickable link format `|Hitem:id:...|h[Name]|h`
- **Item Quality**: Enum values (0-8) for Poor through Heirloom
- **Loot Feed**: The main display showing loot notifications
- **Main Frame**: Player's personal loot feed
- **Party Frame**: Group/raid members' loot feed
- **Queue**: Pending loot messages waiting to display
- **Row**: Individual loot notification in the feed
- **Test Mode**: Preview mode generating sample loot

## Common Patterns in RPGLootFeed

### Namespace Access

```lua
local addonName, ns = ...
local G_RLF = ns

-- Access enums
local quality = G_RLF.ItemQualEnum.Epic
local frame = G_RLF.Frames.MAIN

-- Access configuration
local enabled = G_RLF.db.global.currency.enabled
local color = G_RLF.db.global.rep.defaultRepColor

-- Access utilities
G_RLF.Logger:Debug("Message")
G_RLF:RGBAToHexFormat(r, g, b, a)

-- Access modules
G_RLF.LootDisplay:EnqueueLoot(lootData)
G_RLF.Notifications:AddNotification(title, message)
```

### Module Structure

```lua
-- utils/ - Shared utilities
G_RLF.Logger       -- Logging
G_RLF.Queue        -- Queue data structure
G_RLF.Notifications -- User notifications

-- config/ - Configuration
G_RLF.options      -- AceConfig option tables
G_RLF.defaults     -- Default configuration values

-- Features/ - Loot detection
ItemLoot           -- Item loot module
Currency           -- Currency module
Money              -- Money loot module
Reputation         -- Reputation gains
PartyLoot          -- Party/raid loot

-- LootDisplay/ - Display rendering
LootDisplay        -- Main display manager
LootDisplayFrame   -- Frame mixin
LootDisplayRow     -- Row mixin
LootHistory        -- Loot history tracking

-- BlizzOverrides/ - Blizzard UI mods
LootToasts         -- Disable loot toasts
MoneyAlerts        -- Disable money alerts
BossBanner         -- Modify boss banner
```

### Event Handling Pattern

```lua
-- Feature modules use AceEvent
local MyFeature = G_RLF.RLF:NewModule("MyFeature", "AceEvent-3.0")

function MyFeature:OnEnable()
  self:RegisterEvent("SOME_EVENT")
end

function MyFeature:SOME_EVENT(event, arg1, arg2)
  -- Process event
  if self:ShouldProcess(arg1) then
    self:ProcessData(arg1, arg2)
  end
end
```

### Loot Message Building

```lua
-- Build formatted loot message
local lootMessage = {
  icon = iconTexture,
  text = formattedText,
  color = { r, g, b, a },
  link = itemLink,
  quantity = count,
  -- ... additional fields
}

-- Enqueue for display
G_RLF.LootDisplay:EnqueueLoot(lootMessage, G_RLF.Frames.MAIN)
```

### Configuration Handlers

```lua
-- Config modules define handlers
local MyConfig = {}

-- Getter
function MyConfig:GetSomeValue()
  return G_RLF.db.global.myFeature.someValue
end

-- Setter with side effects
function MyConfig:SetSomeValue(info, value)
  G_RLF.db.global.myFeature.someValue = value
  -- Trigger updates
  G_RLF.LootDisplay:UpdateRowStyles()
end
```

### Error Handling

```lua
-- Validate input
if not itemLink or type(itemLink) ~= "string" then
  G_RLF.Logger:Error("Invalid item link")
  return
end

-- Guard against missing APIs
if not C_CurrencyInfo then
  G_RLF.Logger:Debug("Currency API not available")
  return
end

-- Handle async item data
local itemName = C_Item.GetItemInfo(itemID)
if not itemName then
  -- Item not loaded yet, schedule retry
  C_Timer.After(0.5, function()
    self:ProcessItem(itemID)
  end)
  return
end

-- Protect potentially failing calls
local success, result = pcall(function()
  return SomeRiskyFunction()
end)
if not success then
  G_RLF.Logger:Error("Function failed:", result)
end
```

## Animation and Display Patterns

### Frame Animations

```lua
-- Create animation group
local animGroup = frame:CreateAnimationGroup()

-- Add alpha animation (fade)
local fadeOut = animGroup:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1.0)
fadeOut:SetToAlpha(0.0)
fadeOut:SetDuration(0.5)
fadeOut:SetStartDelay(3.0)

-- Add translation (slide)
local slideOut = animGroup:CreateAnimation("Translation")
slideOut:SetOffset(100, 0)
slideOut:SetDuration(0.5)

-- Start animation
animGroup:Play()

-- Animation callbacks
animGroup:SetScript("OnFinished", function()
  -- Animation complete
end)
```

### Row Pooling Pattern

```lua
-- Get row from pool or create new
local function GetRow()
  if #rowPool > 0 then
    return table.remove(rowPool)
  else
    return CreateNewRow()
  end
end

-- Return row to pool
local function ReleaseRow(row)
  row:Hide()
  row:ClearAllPoints()
  table.insert(rowPool, row)
end
```

## Performance Best Practices

- **Use AceBucket** for rapid events (CHAT_MSG_LOOT in raids)
- **Cache item info** once loaded (don't repeatedly call C_Item.GetItemInfo)
- **Pool UI frames** instead of creating/destroying (see LootDisplayRow)
- **Throttle animations** in high-frequency situations
- **Use locals** for frequently accessed DB values

```lua
-- Good - cache and bucket
function ItemLoot:OnEnable()
  self:RegisterBucketEvent("CHAT_MSG_LOOT", 0.1, "ProcessLootBucket")
  self.itemCache = {}
end

function ItemLoot:GetItemInfo(itemID)
  if self.itemCache[itemID] then
    return self.itemCache[itemID]
  end

  local itemInfo = { C_Item.GetItemInfo(itemID) }
  if itemInfo[1] then
    self.itemCache[itemID] = itemInfo
    return itemInfo
  end
end

-- Bad - no caching or bucketing
function ItemLoot:CHAT_MSG_LOOT(event, message)
  local itemID = self:ParseItemID(message)
  local itemInfo = { C_Item.GetItemInfo(itemID) }  -- Repeated server calls
  -- Process immediately, can overwhelm UI with rapid loot
end
```

## Cross-Expansion Compatibility

RPGLootFeed supports multiple WoW expansions. Always check API availability:

```lua
-- Check for expansion-specific APIs
if C_TransmogCollection then
  -- Transmog system (Legion+)
  self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
end

if C_MajorFactions then
  -- Major factions (Dragonflight+)
  local factionData = C_MajorFactions.GetMajorFactionData(factionID)
end

-- Fallback to legacy APIs when needed
if C_Reputation and C_Reputation.GetFactionDataByID then
  local factionData = C_Reputation.GetFactionDataByID(factionID)
else
  -- Use legacy GetFactionInfoByID
  local name, standing = GetFactionInfoByID(factionID)
end
```

## See Also

- [Glossary](../docs/glossary.md) - Complete terminology reference
- [Resources](../docs/resources.md) - WoW API documentation and references
- [Architecture](../docs/architecture.md) - Project structure and patterns
- [Testing](../docs/testing.md) - Testing strategies and guidelines
