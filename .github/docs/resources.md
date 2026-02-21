# Development Resources

Essential references for developing the RPGLootFeed addon.

## WoW UI Source Repository

**Location**: `../wow-ui-source` (relative to project root, or in workspace)

The `wow-ui-source` repository contains WoW client-generated UI source code. This is **the most valuable resource** for understanding the underlying API and functionality of the WoW UI.

**When to Reference**:

- Understanding how Blizzard implements similar features
- Finding undocumented API functions
- Learning proper usage patterns for WoW APIs
- Ensuring compatibility with WoW client expectations
- Following best practices for WoW addon development

**Always reference this repository** when working on the addon to ensure changes are compatible with the WoW client and follow best practices.

## Key Files in wow-ui-source

### Loot Frame

**File**: `Interface/AddOns/Blizzard_LootFrame/Blizzard_LootFrame.lua`

The default loot window implementation.

**Useful for**:

- Understanding loot event handling
- Learning loot distribution mechanics
- Finding loot-related API functions

### Group Loot Frame

**File**: `Interface/AddOns/Blizzard_GroupLootUI/Blizzard_GroupLootFrame.lua`

Group loot roll frames (Need/Greed/Pass).

**Useful for**:

- Understanding group loot mechanics
- Finding party/raid loot events

### Loot Toast Frame

**File**: `Interface/AddOns/Blizzard_UIWidgets/Blizzard_UIWidgetTemplateToast.lua`

The default loot toast notifications that appear on screen.

**Useful for**:

- Understanding how Blizzard displays loot notifications
- Learning what to hook/override for custom loot notifications

### Boss Banner

**File**: `Interface/AddOns/Blizzard_BossBanner/Blizzard_BossBanner.lua`

The large banner that appears when defeating bosses.

**Useful for**:

- Understanding boss loot display
- Finding hooks for boss banner modifications
- Learning about boss encounter events

### Item API Documentation

**File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`

Documents the `C_Item` namespace and related item functions.

**Contains**:

- `C_Item.GetItemInfo()` - Get item details
- `C_Item.GetItemQualityColor()` - Get quality color
- `C_Item.GetItemIconByID()` - Get item icon
- Item-related events

### Currency API Documentation

**File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/CurrencyInfoDocumentation.lua`

Documents the `C_CurrencyInfo` namespace.

**Contains**:

- `C_CurrencyInfo.GetCurrencyInfo()` - Get currency details
- `C_CurrencyInfo.GetCurrencyListInfo()` - List currencies
- Currency events like `CURRENCY_DISPLAY_UPDATE`

### Reputation API Documentation

**File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ReputationInfoDocumentation.lua`

Documents reputation/faction APIs.

**Contains**:

- Reputation standing functions
- Faction reward information
- Major faction (Dragonflight+) APIs

### Transmog API Documentation

**File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/TransmogDocumentation.lua`

Documents the `C_TransmogCollection` namespace.

**Contains**:

- `C_TransmogCollection.GetSourceInfo()` - Get transmog source details
- Appearance collection tracking
- Transmog events

### Trade Skill API Documentation

**File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua`

Documents profession/tradeskill APIs.

**Contains**:

- `C_TradeSkillUI.GetTradeSkillLine()` - Get profession info
- Skill gain tracking
- Profession events

### Shared XML Templates

**File**: `Interface/SharedXML/SharedBasicControls.xml`

Common UI templates used throughout WoW's interface.

**Useful for**:

- Understanding frame templates
- Learning standard UI patterns
- Creating consistent UI elements

## Common WoW API Patterns

### Accessing Item Information

```lua
-- Get item info (may require waiting for server response)
local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
      itemStackCount, itemEquipLoc, iconFileDataID, sellPrice, classID, subclassID,
      bindType, expacID, setID, isCraftingReagent = C_Item.GetItemInfo(itemID)

-- Get item quality color
local r, g, b, hex = C_Item.GetItemQualityColor(itemQuality)

-- Create item link
local itemLink = select(2, C_Item.GetItemInfo(itemID))
```

### Listening to Loot Events

```lua
-- Register for loot events
self:RegisterEvent("CHAT_MSG_LOOT")
self:RegisterEvent("LOOT_OPENED")
self:RegisterEvent("LOOT_CLOSED")

-- Handle loot message
function MyAddon:CHAT_MSG_LOOT(event, message, ...)
    -- Parse loot message
    -- Example message: "You receive loot: |cff9d9d9d|Hitem:12345|h[Item Name]|h."
end
```

### Currency Tracking

```lua
-- Get currency info
local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
-- currencyInfo contains: name, amount, iconFileID, etc.

-- Listen for currency changes
self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

function MyAddon:CURRENCY_DISPLAY_UPDATE(event, currencyID)
    -- Currency amount changed
end
```

### Reputation Tracking

```lua
-- Get faction info
local name, description, standingID, barMin, barMax, barValue,
      atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep,
      isWatched, isChild, factionID, hasBonusRepGain, canBeLFGBonus =
      GetFactionInfoByID(factionID)

-- Listen for reputation changes
self:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
```

### Group Detection

```lua
-- Check if in group
local inParty = IsInGroup()
local inRaid = IsInRaid()

-- Get group type
local isInstance, instanceType = IsInInstance()
-- instanceType: "party", "raid", "pvp", "arena", "none"
```

### Hooking Blizzard Functions

```lua
-- Secure hook (runs after original)
hooksecurefunc("BlizzardFunction", function(...)
    -- Your code here
end)

-- Pre-hook using AceHook
self:RawHook("BlizzardFunction", function(...)
    -- Your code here before original
    return self.hooks.BlizzardFunction(...)
end, true)

-- Post-hook using AceHook
self:SecureHook("BlizzardFunction", function(...)
    -- Your code here after original
end)
```

## External Library Documentation

### Ace3 Libraries

**Repository**: https://www.wowace.com/projects/ace3

**Documentation**: https://www.wowace.com/projects/ace3/pages/api

**Key Libraries**:

- **AceAddon-3.0**: Addon and module management
- **AceDB-3.0**: SavedVariables database management with profiles
- **AceConfig-3.0**: Configuration option table creation
- **AceConfigDialog-3.0**: Configuration UI display
- **AceEvent-3.0**: Event registration and handling
- **AceHook-3.0**: Function hooking (secure and insecure)
- **AceTimer-3.0**: Timer scheduling
- **AceBucket-3.0**: Event bucketing for performance
- **AceConsole-3.0**: Slash command handling
- **AceGUI-3.0**: GUI widget library

### LibSharedMedia-3.0

**Repository**: https://www.wowace.com/projects/libsharedmedia-3-0

Provides shared fonts, textures, sounds, and other media across addons.

**Usage**:

```lua
local LSM = LibStub("LibSharedMedia-3.0")

-- Register custom font
LSM:Register(LSM.MediaType.FONT, "MyFont", "Path/To/Font.ttf")

-- Get font path
local fontPath = LSM:Fetch(LSM.MediaType.FONT, "MyFont")
```

### LibDataBroker-1.1

**Repository**: https://github.com/tekkub/libdatabroker-1-1

Creates minimap buttons and data display objects.

**Usage**:

```lua
local LDB = LibStub("LibDataBroker-1.1")

local dataObj = LDB:NewDataObject("MyAddon", {
    type = "launcher",
    icon = "Interface\\Icons\\INV_Misc_QuestionMark",
    OnClick = function() end,
    OnTooltipShow = function(tooltip) end,
})
```

### LibDBIcon-1.0

**Repository**: https://www.wowace.com/projects/libdbicon-1-0

Manages minimap button positioning and visibility.

**Usage**:

```lua
local LibDBIcon = LibStub("LibDBIcon-1.0")
LibDBIcon:Register("MyAddon", dataObj, savedVarsTable.minimap)
```

### Masque

**Repository**: https://github.com/SFX-WoW/Masque

Button skinning library (optional dependency).

**Usage**:

```lua
local Masque = LibStub("Masque", true)
if Masque then
    local group = Masque:Group("MyAddon")
    group:AddButton(button)
end
```

## Testing Resources

### wowless

**Repository**: https://github.com/Meorawr/wowless

A WoW Lua environment for testing addons outside the game client (experimental).

**Status**: Pre-alpha, but worth exploring for future testing improvements.

### wow-build-tools

**Repository**: https://github.com/McTalian/wow-build-tools

Build and packaging tool for WoW addons.

**Key Commands** (via Makefile):

- `make dev` - Build and copy to WoW AddOns directory
- `make watch` - Auto-rebuild on file changes
- `make toc_check` - Validate TOC file references

**Important Note**: Only git-tracked files are copied during build. Run `git add` before building to include new files.

## Online Resources

### WoW API Documentation (Wowpedia)

**URL**: https://wowpedia.fandom.com/wiki/World_of_Warcraft_API

Community-maintained documentation of WoW's API functions.

**Note**: May not always be up-to-date with latest WoW patches. Prefer `wow-ui-source` when available.

### WoWInterface Forums

**URL**: https://www.wowinterface.com/forums/

Active community for WoW addon developers. Good for asking questions and finding solutions to common problems.

### CurseForge / Wago Addons

**URL**: https://www.curseforge.com/wow/addons

Addon distribution platform. Useful for researching how other addons solve similar problems.

**URL**: https://addons.wago.io/

Alternative addon distribution platform with modern features.

## Development Tools

### VS Code Extensions

**Recommended**:

- **Lua** (sumneko.lua): Lua language server with excellent autocomplete
- **WoW Bundle** (Ketho.wow-bundle): WoW API autocomplete and documentation
- **GitHub Copilot**: AI-powered code completion (obviously!)

### BugGrabber & BugSack

In-game error catching and display. Essential for debugging.

**Install**: Available on CurseForge

### /fstack

In-game command to view the frame stack and identify UI frames.

**Usage**: `/fstack` then hover over UI elements

### /tinspect

Shows details about a table or variable.

**Usage**: `/tinspect GlobalTableName`

### /etrace

Monitors events firing in real-time.

**Usage**: `/etrace` to start, `/etrace` again to stop
