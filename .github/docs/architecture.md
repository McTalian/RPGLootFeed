# Architecture

## Project Structure

```
RPGLootFeed/
├── Core.lua                  # Main addon entry point, initialization, event handling
├── embeds.xml               # Ace3 library embeds
├── RPGLootFeed.toc          # AddOn metadata and load order
├── BlizzOverrides/          # Blizzard UI modifications
│   ├── BossBanner.lua       # Boss banner customizations
│   ├── LootToasts.lua       # Loot toast frame overrides
│   ├── MoneyAlerts.lua      # Money alert overrides
│   └── retryHook.lua        # Hook retry utility
├── config/                   # Configuration & options UI
│   ├── ConfigOptions.lua    # Base options structure
│   ├── About.lua            # About panel
│   ├── Animations.lua       # Animation settings
│   ├── BlizzardUI.lua       # Blizzard UI override settings
│   ├── Positioning.lua      # Frame positioning options
│   ├── Sizing.lua           # Frame sizing options
│   ├── Styling.lua          # Visual styling options
│   ├── Features/            # Feature-specific configs
│   │   ├── Features.lua     # Main feature toggles
│   │   ├── CurrencyConfig.lua
│   │   ├── ExperienceConfig.lua
│   │   ├── ItemLootConfig.lua
│   │   ├── MoneyConfig.lua
│   │   ├── PartyLootConfig.lua
│   │   ├── ProfessionConfig.lua
│   │   ├── ReputationConfig.lua
│   │   ├── TransmogConfig.lua
│   │   └── TravelPointsConfig.lua
│   ├── common/              # Shared config utilities
│   │   ├── common.lua       # Common config helpers
│   │   ├── db.utils.lua     # Database utilities
│   │   └── styling.base.lua # Shared styling logic
│   └── Migrations/          # Database migrations
│       └── v*.lua
├── Features/                 # Feature implementations
│   ├── ItemLoot/            # Item looting
│   │   ├── ItemAuction.lua  # Auction/sell value display
│   │   └── ItemLoot.lua     # Core item loot handling
│   ├── PartyLoot/           # Group/raid loot
│   │   └── PartyLoot.lua
│   ├── Currency/            # Currency gains
│   │   └── Currency.lua
│   ├── Reputation/          # Reputation gains
│   │   └── Reputation.lua
│   ├── Experience.lua       # XP gains
│   ├── Money.lua            # Gold/money looting
│   ├── Professions.lua      # Profession skill-ups
│   ├── Transmog.lua         # Transmog notifications
│   ├── TravelPoints.lua     # Flight points discovered
│   └── _Internals/          # Internal feature utilities
│       ├── AnimationManager.lua
│       ├── LootDisplayProperties.lua
│       └── LootMessageBuilder.lua
├── LootDisplay/             # UI display layer
│   ├── LootDisplay.lua      # Main display manager
│   ├── LootDisplayFrame.lua # Frame mixin
│   ├── LootDisplayRow.lua   # Row mixin
│   └── LootHistory.lua      # Loot history tracking
├── utils/                    # Utility modules
│   ├── Enums.lua            # Enumerations and constants
│   ├── Logger.lua           # Logging utilities
│   ├── Notifications.lua    # User notifications
│   ├── Queue.lua            # Queue data structure
│   └── Utils.lua            # General utilities
├── GameTesting/             # In-game testing support
│   └── TestMode.lua         # Test mode module
├── locale/                   # Localization strings
│   ├── enUS.lua             # English (base)
│   ├── deDE.lua, esES.lua, frFR.lua, etc.
├── Fonts/                    # Custom font files
├── Icons/                    # Addon icons and assets
└── Sounds/                   # Audio files
```

## Directory Conventions

### `/BlizzOverrides`

**Purpose**: Modifications to Blizzard's default UI behavior

**Contains**:

- Hooks into Blizzard UI frames
- Overrides for default loot notifications
- Optional modifications based on user settings

**Key Principle**: All modifications must be optional and configurable. Never force UI changes.

**Example**: `LootToasts.lua` disables the default loot toast frames when the user enables that option

**Dependencies**: Must handle missing Blizzard frames gracefully (different WoW versions may have different UI)

### `/config`

**Purpose**: All configuration options and data structures

**Contains**:

- AceConfig option tables
- Database schema definitions (defaults)
- User-facing configuration UI panels
- Database migrations

**Structure**:

- Top-level files handle general settings (positioning, sizing, styling, animations)
- `Features/` subdirectory contains feature-specific configuration
- `common/` contains shared configuration utilities
- `Migrations/` contains versioned database migrations

**Key Pattern**: Each config module defines its portion of `G_RLF.defaults` and `G_RLF.options`

**Example**: `CurrencyConfig.lua` defines `G_RLF.defaults.global.currency` and `G_RLF.options.args.features.args.currencyConfig`

### `/Features`

**Purpose**: Core feature logic and event handling

**Contains**:

- Event listeners (CHAT_MSG_LOOT, CHAT_MSG_CURRENCY, etc.)
- Data processing and formatting
- Integration with WoW APIs
- Loot message creation

**Does NOT contain**:

- UI rendering (use LootDisplay instead)
- Configuration UI (use config instead)

**Pattern**: Each feature module listens for relevant WoW events, processes the data, and enqueues formatted loot messages

**Example**: `Currency.lua` listens for `CHAT_MSG_CURRENCY`, extracts currency info, formats it, and adds it to the loot queue

**Important**: Features use `_Internals/` for shared functionality across features (animation management, message building, display properties)

### `/LootDisplay`

**Purpose**: UI rendering and display management

**Contains**:

- Frame creation and management
- Row pooling and recycling
- Queue processing
- Animation coordination
- Loot history tracking

**Responsibilities**:

- Process the loot queue
- Display items in available rows
- Handle frame positioning and sizing
- Manage row animations (fade in/out, slide)
- Track loot history for the history panel

**Key Component**: `LootDisplayFrame` and `LootDisplayRow` mixins provide the frame behavior

**Does NOT contain**: Feature-specific logic (that belongs in Features/)

### `/utils`

**Purpose**: Shared utilities and helper functions

**Contains**:

- Enumerations and constants
- Common helper functions
- Data structures (Queue)
- Logging infrastructure
- User notifications

**Pattern**: Pure functions and utilities with no side effects where possible

**Example**: `Queue.lua` provides a generic queue data structure used by LootDisplay

### `/locale`

**Purpose**: Internationalization and localization

**Contains**:

- Localized strings for all supported languages
- `enUS.lua` is the base locale (always loaded)
- Other locale files override base strings for their language

**Pattern**: Use `G_RLF.L["Key"]` to access localized strings throughout the addon

### `/GameTesting`

**Purpose**: In-game testing utilities

**Contains**:

- Test mode for previewing loot feed
- Sample data generation
- Integration test support

**Note**: This is for in-game testing, not unit tests (those are in `RPGLootFeed_spec/`)

## Key Architectural Patterns

### Event-Driven Architecture

Features listen for WoW events (like `CHAT_MSG_LOOT`) and respond by processing data and enqueuing loot messages.

### Queue-Based Display

Loot messages are enqueued and processed asynchronously by LootDisplay. This prevents UI blocking and allows for smooth animations.

### Modular Configuration

Each feature and setting is isolated in its own module, making it easy to enable/disable features and maintain configuration separately.

### Namespace Pattern

All addon code uses a shared namespace (`G_RLF`) passed via `local addonName, ns = ...` to avoid global pollution.

### Mixin Pattern

UI frames use mixins (`LootDisplayFrame`, `LootDisplayRow`) to encapsulate frame-specific behavior.

## Data Flow

1. **WoW Event Triggered** (e.g., player loots an item)
2. **Feature Module** listens for the event and processes it
3. **Message Builder** formats the loot message with styling
4. **Queue** stores the message for display
5. **LootDisplay** dequeues messages and assigns them to available rows
6. **Row Animation** fades in, displays, then fades out
7. **Loot History** (optional) records the loot for later viewing

## Ace3 Framework Integration

RPGLootFeed uses the Ace3 framework extensively:

- **AceAddon-3.0**: Core addon structure and module system
- **AceDB-3.0**: Configuration database with profiles
- **AceConfig-3.0**: Configuration UI generation
- **AceConfigDialog-3.0**: Configuration dialog display
- **AceEvent-3.0**: Event handling
- **AceHook-3.0**: Secure hooking of Blizzard functions
- **AceTimer-3.0**: Timer management
- **AceBucket-3.0**: Event bucketing for performance
- **AceConsole-3.0**: Slash command handling

## Load Order

The load order is defined in `RPGLootFeed.toc` and is critical:

1. **Library embeds** (`embeds.xml`)
2. **Type definitions** (`_global_types.lua`, `_lib_types.lua`)
3. **Utils** (Enums, Logger, Notifications, Queue, Utils)
4. **Config base** (ConfigOptions)
5. **Config modules** (Positioning, Sizing, Styling, Animations, Features, etc.)
6. **Feature implementations** (ItemLoot, Currency, Money, etc.)
7. **LootDisplay** (Frame mixins, display manager, history)
8. **BlizzOverrides** (last, to hook into Blizzard UI)
9. **Core** (last file, initializes everything)
10. **GameTesting** (loaded last for test mode)

This order ensures dependencies are available when modules load.
