# WoW & RPGLootFeed Terminology

Quick reference for World of Warcraft and RPGLootFeed addon terminology.

## WoW Game Concepts

### Loot

Items, currency, or other rewards obtained by killing enemies, opening containers, completing quests, or other in-game activities.

**Types of Loot**:

- **Items**: Equipment, consumables, materials, etc.
- **Currency**: Special currencies like badges, tokens, or event-specific currency
- **Money**: Gold, silver, copper (the main monetary system)
- **Experience**: XP gained toward character level
- **Reputation**: Standing with various factions

### Item Quality

WoW items have quality levels indicated by color:

- **Poor** (Gray): Vendor trash
- **Common** (White): Basic items
- **Uncommon** (Green): Better than common
- **Rare** (Blue): High-quality items
- **Epic** (Purple): Very rare and powerful
- **Legendary** (Orange): Extremely rare and powerful
- **Artifact** (Gold/Orange): Legendary weapons from Legion expansion
- **Heirloom** (Light Blue): Account-bound leveling items that scale

### Party/Raid Loot

When in a group, loot distribution follows specific rules:

- **Personal Loot**: Each player gets their own loot (or nothing)
- **Group Loot**: Items roll among eligible players
- **Master Loot**: Leader distributes items (removed in modern WoW but code may reference it)
- **Need/Greed/Pass**: Roll types for group loot

### Chat Messages

WoW communicates many game events through chat messages:

- `CHAT_MSG_LOOT`: Item looting
- `CHAT_MSG_CURRENCY`: Currency gains
- `CHAT_MSG_MONEY`: Money looting
- `CHAT_MSG_COMBAT_FACTION_CHANGE`: Reputation changes
- `CHAT_MSG_SKILL`: Profession skill gains

### Transmog (Transmogrification)

System allowing players to change the appearance of their gear. RPGLootFeed can notify when a new transmog appearance is learned.

### Travel Points

Flight paths discovered throughout the game world. Also called "flight points" or "taxi points."

### Boss Banner

The large banner that appears at the top of the screen when defeating a boss encounter.

### Loot Toast

Small popup notification that appears when looting items (Blizzard's default notification).

### Money Alert

Blizzard's default notification for copper/silver/gold looting.

## RPGLootFeed Concepts

### Loot Feed

The customizable display window showing real-time loot notifications. Can be positioned and styled anywhere on screen.

### Main Frame vs Party Frame

RPGLootFeed supports two separate loot feeds:

- **Main Frame**: Shows the player's own loot
- **Party Frame**: Shows party/raid members' loot (optional, can be disabled or merged with main)

### Loot Row

An individual line in the loot feed displaying one loot event. Rows are pooled and recycled for performance.

### Loot Queue

Internal queue storing loot messages waiting to be displayed. Allows smooth animations even when multiple loot events occur simultaneously.

### Test Mode

A mode that generates sample loot messages for previewing and configuring the loot feed appearance.

### Sample Rows

Temporary loot rows shown when the configuration UI is open, allowing real-time preview of style changes.

### Bounding Box

A visible frame outline shown during configuration to help with positioning and sizing.

### Animation Phases

Loot rows go through animation stages:

- **Entry**: How the row appears (fade in, slide in, etc.)
- **Display**: How long the row stays visible
- **Exit**: How the row disappears (fade out, slide out, etc.)

### Item Highlights

Special highlighting rules for items meeting certain criteria:

- Transmog appearances
- High item level
- Specific item qualities
- Custom item IDs

### Loot History

A panel that records all loot obtained during the session, accessible via configuration UI or minimap icon.

### Blizzard UI Overrides

Optional modifications to WoW's default UI:

- Disable loot toasts
- Disable money alerts
- Disable or modify boss banner
- Enable auto-loot

### Item Auction Value

Integration with TradeSkillMaster (TSM) or Auctionator to display auction house values for looted items.

### Warband

Account-wide currency tracking introduced in recent WoW expansions. RPGLootFeed can show currency gains across all characters.

## Technical Terms

### Namespace (ns)

The addon's private table passed to each module via `local addonName, ns = ...`. Stored as `G_RLF` class.

**Purpose**: Avoid polluting the global namespace and share data between modules.

### Addon Namespace (`G_RLF`)

The global namespace object containing all addon data, functions, and modules. Annotated as `@class G_RLF`.

### AceAddon Module

An independent component of the addon using Ace3's module system. Each feature is typically its own module.

### Mixin

A pattern for adding behavior to frames. RPGLootFeed uses mixins for `LootDisplayFrame` and `LootDisplayRow`.

### Hook

Intercepting and modifying Blizzard function calls. Used to override default UI behavior.

- **Secure Hook**: Runs after the original function
- **Pre-Hook**: Runs before the original function
- **Raw Hook**: Replaces the original function

### TOC File

The Table of Contents file (`.toc`) defining addon metadata and file load order.

### LibSharedMedia (LSM)

A library providing access to shared fonts, textures, sounds, and other media across addons.

### LibDataBroker (LDB)

A library for creating minimap buttons and data display objects.

### Masque

An optional library for styling action buttons. RPGLootFeed can integrate with it for icon styling.

### ElvUI

A popular UI replacement addon. RPGLootFeed can detect and integrate with ElvUI's styling system.

### SavedVariables

Persistent data stored between game sessions. RPGLootFeed uses `RPGLootFeedDB` for settings and history.

### Database Schema

The structure of persistent data:

- `global`: Settings shared across all characters
- `profile`: Settings specific to a profile (can be shared between characters)
- `char`: Character-specific data
- `locale`: Locale-specific cached data (faction names, etc.)

### Migration

A versioned update to the database schema. Runs once per version to migrate old data to new structure.

### WrapChar (Wrap Character)

The character(s) used to wrap secondary text in loot messages:

- Parenthesis: `(text)`
- Bracket: `[text]`
- Angle: `<text>`
- etc.

### Frame Strata

Layer ordering for UI frames. Options include BACKGROUND, LOW, MEDIUM, HIGH, DIALOG, FULLSCREEN, etc.

### Anchor Point

The attachment point for frame positioning:

- **Relative Point**: Where to attach to (e.g., "UIParent")
- **Anchor Point**: Which part of the frame to attach (e.g., "CENTER", "TOPLEFT")
- **X/Y Offset**: Pixel offset from the anchor

### Grow Direction

The direction new loot rows appear:

- **Grow Up**: New rows appear above older rows
- **Grow Down**: New rows appear below older rows

### Left Align

Text alignment within loot rows:

- **Left Aligned**: Text and icons aligned to the left
- **Right Aligned**: Text and icons aligned to the right

### Item Link

A clickable link to an item in WoW's UI. Format: `|Hitem:itemID:...|h[Item Name]|h`

### Color Code

WoW's text coloring format: `|cAARRGGBB` where AA=alpha, RR=red, GG=green, BB=blue (all in hex)

### Texture Path

Path to a texture/image file, relative to WoW's directory:

- Example: `Interface\AddOns\RPGLootFeed\Icons\logo.blp`
- Use forward slashes (`/`) even on Windows

### BLP File

Blizzard's proprietary image format used for textures in WoW.

### Font String

A UI element for displaying text. Has properties like font, size, color, justification, etc.

### GUID (Globally Unique Identifier)

A unique identifier for an addon installation (not tied to character or account). Used for analytics only.

## WoW API Terms

### C_Item

A WoW API namespace for item-related functions like `C_Item.GetItemQualityColor()`.

### C_CurrencyInfo

API namespace for currency functions like `C_CurrencyInfo.GetCurrencyInfo()`.

### C_Reputation

API namespace for reputation/faction functions.

### C_TradeSkillUI

API namespace for profession/tradeskill functions.

### GetItemInfo

Classic WoW API function for retrieving item information.

### UnitName

Function to get a unit's name (player, target, party1, etc.).

### IsInGroup / IsInRaid

Functions to check if the player is in a party or raid.

### FrameXML

The Blizzard-provided UI code. Can be viewed in the `wow-ui-source` repository.

### LibStub

A library loading system used throughout WoW addons. Loads libraries by name and version.
