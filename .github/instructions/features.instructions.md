---
name: Features — WoW API Reference
description: WoW API details for RPGLootFeed feature modules (loot detection, events, game data APIs, cross-expansion compat)
applyTo: "RPGLootFeed/Features/**/*.lua"
---

# Feature Module WoW API Reference

## Loot Detection Events

```lua
function MyFeature:OnEnable()
  self:RegisterEvent("CHAT_MSG_LOOT")
  self:RegisterEvent("CHAT_MSG_CURRENCY")
  self:RegisterEvent("CHAT_MSG_MONEY")
  self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
  self:RegisterEvent("CHAT_MSG_SKILL")
end

function ItemLoot:CHAT_MSG_LOOT(event, message, playerName, ...)
  -- Message format: "You receive loot: |Hitem:123|h[Item Name]|hx5."
  local itemLink, quantity = self:ParseLootMessage(message)
  if itemLink then
    self:ProcessItemLoot(itemLink, quantity, playerName)
  end
end
```

For high-frequency loot events (raids), use AceBucket to throttle processing:

```lua
function ItemLoot:OnEnable()
  self:RegisterBucketEvent("CHAT_MSG_LOOT", 0.1, "ProcessLootBucket")
  self.itemCache = {}
end

function ItemLoot:ProcessLootBucket(events)
  for _, args in pairs(events) do
    self:CHAT_MSG_LOOT("CHAT_MSG_LOOT", unpack(args))
  end
end
```

## C_Item

```lua
local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType,
      itemSubType, itemStackCount, itemEquipLoc, iconFileDataID, sellPrice,
      classID, subclassID, bindType, expacID, setID, isCraftingReagent
      = C_Item.GetItemInfo(itemID)

-- Async: item data may not be cached yet
if not itemName then
  C_Timer.After(0.5, function() self:ProcessItem(itemID) end)
  return
end

local r, g, b, hex = C_Item.GetItemQualityColor(itemQuality)
local iconID = C_Item.GetItemIconByID(itemID)
```

Cache item info to avoid repeated server calls:

```lua
function MyFeature:GetItemInfo(itemID)
  if self.itemCache[itemID] then return self.itemCache[itemID] end
  local info = { C_Item.GetItemInfo(itemID) }
  if info[1] then
    self.itemCache[itemID] = info
    return info
  end
end
```

## C_CurrencyInfo

```lua
local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
-- { name, amount, iconFileID, maxQuantity, ... }
local currencyLink = C_CurrencyInfo.GetCurrencyLink(currencyID)

function Currency:OnEnable()
  self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
end

function Currency:CURRENCY_DISPLAY_UPDATE(event, currencyID, quantity)
  self:ProcessCurrency(currencyID, quantity)
end
```

## C_Reputation

```lua
-- Modern API (Shadowlands+)
local factionData = C_Reputation.GetFactionDataByID(factionID)
-- { name, currentReactionThreshold, nextReactionThreshold, currentStanding, factionID, ... }

-- Major factions (Dragonflight+)
if C_MajorFactions then
  local data = C_MajorFactions.GetMajorFactionData(factionID)
end

-- Legacy fallback
local name, description, standingID, barMin, barMax, barValue,
      atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep,
      isWatched, isChild, factionID, hasBonusRepGain, canBeLFGBonus
      = GetFactionInfoByID(factionID)

self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
```

## C_TransmogCollection

```lua
if C_TransmogCollection then
  local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
  local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)
  self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
end
```

## C_TradeSkillUI

```lua
if C_TradeSkillUI then
  local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
  -- { professionID, professionName, skillLevel, maxSkillLevel, ... }
end

self:RegisterEvent("CHAT_MSG_SKILL")
-- Message format: "Your skill in <profession> has increased to <level>."
```

## Group Detection

```lua
local inGroup = IsInGroup()
local inRaid = IsInRaid()
local numMembers = GetNumGroupMembers()
local isLeader = UnitIsGroupLeader("player")

local instanceName, instanceType = GetInstanceInfo()
-- instanceType: "none", "party", "raid", "pvp", "arena", "scenario"
```

## Cross-Expansion Compatibility

Always check API availability before using expansion-specific APIs:

```lua
-- Modern API with legacy fallback
if C_Reputation and C_Reputation.GetFactionDataByID then
  local factionData = C_Reputation.GetFactionDataByID(factionID)
else
  local name, standing = GetFactionInfoByID(factionID)
end

-- Guard expansion-specific namespaces
if C_MajorFactions then
  local data = C_MajorFactions.GetMajorFactionData(factionID)
end
```
