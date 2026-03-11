# Options / Config Layout Reorganization

## Purpose

This document enumerates the current options structure and explores ideas for
reorganizing it so users can find settings more intuitively, with future
expansion in mind.

---

## Implementation Status

| Phase | Description                                                                                | Status              |
| ----- | ------------------------------------------------------------------------------------------ | ------------------- |
| 1     | **General tab** — quick actions + Misc items moved out of Features                         | ✅ Done (`76cb7a3`) |
| 2     | **Loot Feeds rename** — `features` → `lootFeeds`, remove top-level enable toggle grid      | ✅ Done (`d4e278a`) |
| 3     | **Appearance tab** — collapse Positioning + Sizing + Styling + Animations under one parent | ✅ Done             |
| 4     | **Party Loot self-contained** — remove injected groups from Positioning/Sizing/Styling     | ✅ Done             |
| 5     | **Blizzard UI sub-groups** — split into Loot Behavior + Chat Filters                       | ✅ Done             |

Phases 3 and 4 are tightly coupled and should be done together.

---

## Current Structure (post-phase-2)

### Root Level (post-phase-4)

| Key             | Type        | Notes                      |
| --------------- | ----------- | -------------------------- |
| **General**     | group (tab) | order 1                    |
| **Loot Feeds**  | group (tab) | order 4 (`lootFeeds` key)  |
| **Appearance**  | group (tab) | order 5 (`appearance` key) |
| **Blizzard UI** | group (tab) | order 9                    |
| **About**       | group (tab) | order -1 (last)            |

### Appearance Tab (`appearance` key)

Contains four sub-groups registered under `G_RLF.options.args.appearance.args`:

| Sub-group key | File              | Order |
| ------------- | ----------------- | ----- |
| `positioning` | `Positioning.lua` | 1     |
| `sizing`      | `Sizing.lua`      | 2     |
| `styles`      | `Styling.lua`     | 3     |
| `timing`      | `Animations.lua`  | 4     |

Party Loot appearance options (positioning / sizing / styling) now live exclusively inside the **Party Loot** sub-group under Loot Feeds (`partyLootOptions.args.positioning/sizing/styling`).

---

### General Tab (`General.lua`)

| Option                         | Notes                               |
| ------------------------------ | ----------------------------------- |
| **Quick Actions** (inline)     |                                     |
| → Toggle Test Mode             | execute                             |
| → Clear Rows                   | execute                             |
| → Toggle Loot History          | execute                             |
| Show '1' Quantity              |                                     |
| Hide All Icons                 | global override                     |
| Show Minimap Icon              |                                     |
| Enable Loot History            |                                     |
| Loot History Size              | range, disabled if history off      |
| Hide Loot History Tab          |                                     |
| Enable Item/Currency Tooltips  |                                     |
| → Show only when SHIFT is held | sub-option (Tooltip Options inline) |
| Enable Secondary Row Text      | also affects font sizing in Styling |

---

### Loot Feeds Tab (`Features/Features.lua` + sub-configs)

No top-level toggle grid. Each sub-group starts with its own enable toggle;
the enable guard lives only inside the sub-group (per Q1 decision).

Sub-groups (all registered onto `options.args.lootFeeds.args` by their own files):

| Sub-group key      | File                     | Order |
| ------------------ | ------------------------ | ----- |
| `itemLootConfig`   | `ItemConfig.lua`         | 1     |
| `partyLootConfig`  | `PartyLootConfig.lua`    | 2     |
| `currencyConfig`   | `CurrencyConfig.lua`     | 3     |
| `moneyConfig`      | `MoneyConfig.lua`        | 4     |
| `experienceConfig` | `ExperienceConfig.lua`   | 5     |
| `repConfig`        | `ReputationConfig.lua`   | 6     |
| `professionConfig` | `ProfessionConfig.lua`   | 7     |
| `travelPoints`     | `TravelPointsConfig.lua` | 8     |
| `transmogConfig`   | `TransmogConfig.lua`     | 9     |

---

### Positioning / Sizing / Styling / Animations Tabs

_(Consolidated into the **Appearance** parent tab in phases 3 + 4.)_

Party Loot frame positioning/sizing/styling options are now fully self-contained
within the Party Loot sub-group under Loot Feeds — the inline injections into
the visual tabs have been removed.

---

## Pre-phase-2 Structure (historical reference)

### Root Level (original)

| Key                 | Type        | Notes               |
| ------------------- | ----------- | ------------------- |
| Toggle Test Mode    | execute     | Quick action button |
| Clear Rows          | execute     | Quick action button |
| Toggle Loot History | execute     | Quick action button |
| **Features**        | group (tab) | order 4             |
| **Positioning**     | group (tab) | order 5             |
| **Sizing**          | group (tab) | order 6             |
| **Styling**         | group (tab) | order 7             |
| **Animations**      | group (tab) | order 8             |
| **Blizzard UI**     | group (tab) | order 9             |
| **About**           | group (tab) | order -1 (last)     |

### Features Tab (original)

#### Top-level toggles (enable/disable each feed)

| Option                       | Notes       |
| ---------------------------- | ----------- |
| Enable Item Loot in Feed     |             |
| Enable Party Loot in Feed    |             |
| Enable Currency in Feed      | WotLK+ only |
| Enable Money in Feed         |             |
| Enable Experience in Feed    |             |
| Enable Reputation in Feed    |             |
| Enable Professions in Feed   |             |
| Enable Travel Points in Feed | Retail only |
| Enable Transmog in Feed      |             |

#### Miscellaneous (inline group, at bottom of Features)

| Option                         | Notes                               |
| ------------------------------ | ----------------------------------- |
| Show '1' Quantity              |                                     |
| Hide All Icons                 | global override                     |
| Show Minimap Icon              |                                     |
| Enable Loot History            |                                     |
| Loot History Size              | range, disabled if history off      |
| Hide Loot History Tab          |                                     |
| Enable Item/Currency Tooltips  |                                     |
| → Show only when SHIFT is held | sub-option                          |
| Enable Secondary Row Text      | also affects font sizing in Styling |

#### Item Loot Config (sub-group, order 1)

| Option                                                 | Notes                               |
| ------------------------------------------------------ | ----------------------------------- |
| Enable Item Loot                                       |                                     |
| **Item Loot Options** (inline)                         |                                     |
| → Show Item Icon                                       | disabled if Hide All Icons          |
| **Item Count Text** (inline)                           |                                     |
| → Enable Item Count Text                               |                                     |
| → Item Count Text Color                                |                                     |
| → Item Count Text Wrap Character                       |                                     |
| **Item Secondary Text Options** (inline)               |                                     |
| → Prices for Sellable Items                            | None / Vendor / AH variants         |
| → Auction House Source                                 | hidden if no AH addon               |
| → Vendor Icon Texture                                  | atlas name input + preview + revert |
| → Auction House Icon Texture                           | atlas name input + preview + revert |
| **Item Quality Filter** (inline)                       |                                     |
| → Reset All Duration Overrides                         | execute                             |
| → Poor / Common / Uncommon / Rare / Epic               | enabled toggle + duration override  |
| → Legendary / Artifact / Heirloom / WoW Token          | enabled toggle + duration override  |
| **Item Highlights** (inline)                           |                                     |
| → Highlight Mounts                                     |                                     |
| → Highlight Legendary Items                            |                                     |
| → Highlight Items Better Than Equipped                 |                                     |
| → Highlight Items with Tertiary Stats or Sockets       |                                     |
| → Highlight Quest Items                                |                                     |
| → Highlight New Transmog Items                         |                                     |
| **Item Loot Sounds** (inline)                          |                                     |
| → Play Sound for Mounts + sound selector               |                                     |
| → Play Sound for Legendary + sound selector            |                                     |
| → Play Sound for Better Than Equipped + sound selector |                                     |
| → Play Sound for New Transmog + sound selector         |                                     |
| **Item Text Style Overrides** (inline)                 |                                     |
| → Override Text Style for Quest Items + color          |                                     |

#### Party Loot Config (sub-group, order 2)

_(Full sub-group; its Positioning/Sizing/Styling is injected into those tabs when `separateFrame` is enabled — phase 4 will consolidate this into the sub-group itself.)_

| Option                                                      | Notes |
| ----------------------------------------------------------- | ----- |
| Enable Party Loot                                           |       |
| _(Party loot specific options — need to enumerate further)_ |       |

#### Currency Config (sub-group, order 3)

| Option                                   | Notes |
| ---------------------------------------- | ----- |
| Enable Currency                          |       |
| **Currency Options** (inline)            |       |
| → Show Currency Icon                     |       |
| **Currency Total Text Options** (inline) |       |
| → Enable Currency Total Text             |       |
| → Currency Total Text Color              |       |
| → Currency Total Text Wrap Character     |       |

#### Money Config (sub-group, order 4)

| Option                                       | Notes                   |
| -------------------------------------------- | ----------------------- |
| Enable Money                                 |                         |
| **Money Options** (inline)                   |                         |
| → Show Money Icon                            |                         |
| **Money Total Options** (inline)             |                         |
| → Show Money Total                           |                         |
| → Abbreviate Total                           |                         |
| → Only Income                                |                         |
| → Accountant Mode                            | disabled if Only Income |
| → Override Money Loot Sound + sound selector |                         |

#### Experience Config (sub-group, order 5)

| Option                              | Notes                         |
| ----------------------------------- | ----------------------------- |
| Enable Experience                   | duplicate of top-level toggle |
| **Experience Options** (inline)     |                               |
| → Show Experience Icon              |                               |
| → Experience Text Color             |                               |
| **Current Level Options** (inline)  |                               |
| → Show Current Level                |                               |
| → Current Level Color               |                               |
| → Current Level Text Wrap Character |                               |

#### Reputation Config (sub-group, order 6)

| Option                                | Notes                         |
| ------------------------------------- | ----------------------------- |
| Enable Reputation                     | duplicate of top-level toggle |
| **Reputation Options** (inline)       |                               |
| → Show Reputation Icon                |                               |
| → Default Rep Text Color              |                               |
| → Secondary Text Alpha                |                               |
| **Reputation Level Options** (inline) |                               |
| → Enable Reputation Level             |                               |
| → Reputation Level Color              |                               |
| → Reputation Level Wrap Character     |                               |

#### Profession Config (sub-group, order 7)

| Option                            | Notes                         |
| --------------------------------- | ----------------------------- |
| Enable Professions                | duplicate of top-level toggle |
| **Profession Options** (inline)   |                               |
| → Show Profession Icon            |                               |
| **Skill Change Options** (inline) |                               |
| → Show Skill Change               |                               |
| → Skill Text Color                |                               |
| → Skill Text Wrap Character       |                               |

#### Travel Points Config (sub-group, order 8, Retail only)

| Option                            | Notes                         |
| --------------------------------- | ----------------------------- |
| Enable Travel Points              | duplicate of top-level toggle |
| **Travel Point Options** (inline) |                               |
| → Show Travel Point Icon          |                               |
| → Travel Points Text Color        |                               |

#### Transmog Config (sub-group, order 9)

| Option                           | Notes                         |
| -------------------------------- | ----------------------------- |
| Enable Transmog                  | duplicate of top-level toggle |
| **Transmog Options** (inline)    |                               |
| → Show Transmog Icon             |                               |
| → Enable Transmog Effect         | Retail only                   |
| → Enable Blizzard Transmog Sound | Retail only                   |
| → Test Transmog Sound            | execute                       |

---

### Positioning Tab

| Option                                    | Notes                                   |
| ----------------------------------------- | --------------------------------------- |
| Anchor Relative To                        | UIParent, PlayerFrame, Minimap, BagBar  |
| Anchor Point                              | TOPLEFT, TOPRIGHT, … CENTER             |
| X Offset                                  | range −1500 to 1500                     |
| Y Offset                                  | range −1500 to 1500                     |
| Frame Strata                              | BACKGROUND … TOOLTIP                    |
| **Party Loot Frame Positioning** (inline) | injected; only shown if `separateFrame` |
| → Anchor Relative To                      |                                         |
| → Anchor Point                            |                                         |
| → X Offset                                |                                         |
| → Y Offset                                |                                         |

---

### Sizing Tab

| Option                               | Notes                                   |
| ------------------------------------ | --------------------------------------- |
| Feed Width                           | range 10–1000                           |
| Maximum Rows to Display              | range 1–20                              |
| Loot Item Height                     | range 5–100                             |
| Loot Item Icon Size                  | range 5–100                             |
| Loot Item Padding                    | range 0–10                              |
| **Party Loot Frame Sizing** (inline) | injected; only shown if `separateFrame` |

---

### Styling Tab

_(All options repeated wholesale for the Party Loot frame when `separateFrame` is enabled.)_

| Option                                              | Notes                                             |
| --------------------------------------------------- | ------------------------------------------------- |
| Text Alignment                                      | Left / Center / Right                             |
| Grow Up                                             | rows stack upward vs downward                     |
| **Background**                                      |                                                   |
| → Background Type                                   | Gradient / Textured                               |
| → Gradient Start Color                              | hidden if Textured                                |
| → Gradient End Color                                | hidden if Textured                                |
| → Background Texture                                | LSM picker; hidden if Gradient                    |
| → Background Texture Color                          | hidden if Gradient                                |
| → Backdrop Insets (Top/Right/Bottom/Left)           |                                                   |
| **Borders**                                         |                                                   |
| → Enable Row Borders                                |                                                   |
| → Row Border Texture                                | LSM picker; disabled if borders off               |
| → Row Border Thickness                              |                                                   |
| → Row Border Color                                  |                                                   |
| → Use Class Colors for Border                       |                                                   |
| **Text / Font**                                     |                                                   |
| → Enable Secondary Row Text                         | _also in Features > Misc_                         |
| → Enable Top-Left Icon Text                         |                                                   |
| → Top-Left Icon Font Size                           |                                                   |
| → Use Quality Color for Icon Text                   |                                                   |
| → Icon Text Color                                   |                                                   |
| → Use Font Object                                   | toggle (WoW built-in font object vs custom)       |
| → Font Object                                       | select; only if Use Font Object                   |
| → Font Face                                         | LSM picker; disabled if Use Font Object           |
| → Font Size (primary)                               |                                                   |
| → Font Size (secondary)                             | disabled if secondary text off or Use Font Object |
| → Font Flags (None/Outline/ThickOutline/Monochrome) | checkboxes                                        |
| → Font Shadow Color                                 |                                                   |
| → Font Shadow Offset X                              |                                                   |
| → Font Shadow Offset Y                              |                                                   |
| → Row Text Spacing                                  | 0 = auto                                          |
| **Party Loot Frame Styling** (inline)               | injected; only when `separateFrame`               |

---

### Animations Tab

| Option                           | Notes                                   |
| -------------------------------- | --------------------------------------- |
| **Row Enter Animation** (inline) |                                         |
| → Enter Animation Type           | None / Fade / Slide                     |
| → Enter Animation Duration       | range 0.1–1                             |
| → Slide Direction                | Left/Right/Up/Down; hidden unless Slide |
| **Row Exit Animation** (inline)  |                                         |
| → Disable Automatic Exit         | rows persist until manually cleared     |
| → Fade Out Delay                 | range 1–60; disabled if auto-exit off   |
| → Exit Animation Type            | None / Fade; disabled if auto-exit off  |
| → Exit Animation Duration        | range 0.1–3; disabled if auto-exit off  |
| **Hover Animation** (inline)     |                                         |
| → Enable Hover Animation         |                                         |
| → Hover Alpha                    | range 0–1                               |
| → Base Duration                  | range 0.1–1                             |
| **Update Animations** (inline)   |                                         |
| → Disable Highlight              |                                         |
| → Update Animation Duration      | disabled if highlight off               |
| → Loop Update Highlight          | disabled if highlight off               |

---

### Blizzard UI Tab

| Sub-group         | Option                           | Notes                                    |
| ----------------- | -------------------------------- | ---------------------------------------- |
| **Loot Behavior** | Enable Auto Loot                 | sets CVar                                |
|                   | _Alerts header_                  |                                          |
|                   | Disable Loot Toasts              |                                          |
|                   | Disable Money Alerts             |                                          |
|                   | Disable Boss Banner Elements     | None / All / Loot / My Loot / Group Loot |
| **Chat Filters**  | Disable Loot Chat Messages       | execute (removes LOOT message group)     |
|                   | Disable Currency Chat Messages   | execute (removes CURRENCY)               |
|                   | Disable Money Chat Messages      | execute (removes MONEY)                  |
|                   | Disable Experience Chat Messages | execute (removes COMBAT_XP_GAIN)         |
|                   | Disable Reputation Chat Messages | execute (removes COMBAT_FACTION_CHANGE)  |
|                   | Disable Skill Chat Messages      | execute (removes SKILL + TRADESKILLS)    |

---

## Observed Pain Points

1. **The Features tab is a mega-tab.** It mixes "which feeds are enabled" (9
   top-level toggles) with full per-feature detail configs (sub-groups), plus
   a grabby Miscellaneous bucket holding completely unrelated bits like the
   minimap icon, loot history, tooltips, and secondary row text.

2. **Duplicate enable toggles.** Each feature's enable toggle appears both
   inside the Features tab (top-level grid) _and_ again at the top of its
   sub-group config. Slightly confusing — clicking the top-level toggle
   enables the feature, but you have to drill into the sub-group to _configure_
   it, where you'll find the toggle again.

3. **Secondary Row Text is split.** The _enable_ toggle is in Features > Misc,
   but the font _size_ for secondary text is in Styling. Users who want to
   tweak that have to visit two places.

4. **Party Loot frame settings are scattered.** Its Positioning, Sizing, and
   Styling options are injected as inline groups inside the main Positioning,
   Sizing, and Styling tabs (only visible when `separateFrame` is on). This
   makes it feel invisible and hard to discover.

5. **Positioning, Sizing, Styling, and Animations are four separate tabs** for
   what is conceptually one topic: "what does the feed look like?" Users
   report difficulty finding, e.g., font settings (Styling) vs. row height
   (Sizing) vs. where it sits on screen (Positioning).

6. **Blizzard UI is a mix of one-time actions and toggles.** The "Disable X
   Chat Messages" buttons are one-shot executors (they remove the chat filter
   permanently), yet they sit alongside persistent toggle settings like
   Enable Auto Loot and Disable Loot Toasts.

---

## Proposed Reorganization Ideas

### Option A — Feature-centric ("Everything about X in one place")

```
RPGLootFeed
├── [General]           Quick actions (test, clear), minimap, tooltips, loot history
├── [Loot Feeds]        Per-feature sub-tabs, each with enable + full config
│   ├── Items
│   ├── Party Loot      (incl. its own position/size/style when separateFrame)
│   ├── Currency
│   ├── Money
│   ├── Experience
│   ├── Reputation
│   ├── Professions
│   ├── Travel Points   (Retail only)
│   └── Transmog
├── [Feed Display]      Combined: Positioning + Sizing + Styling + Animations
│   ├── Layout          Positioning + Sizing
│   ├── Style           Styling (all visual options)
│   └── Animations
├── [Blizzard UI]       Same as today
└── [About]
```

**Pros:** Single source of truth per feature. Party Loot gets its own full tab.
**Cons:** Appearance settings are duplicated (main frame + Party Loot frame).
Navigating between "how Items looks" and "how Currency looks" requires
jumping tabs.

---

### Option B — Purpose-centric ("What are you trying to do?")

```
RPGLootFeed
├── [Quick Setup]       All enable/disable toggles in one place + key global options
├── [Appearance]        Everything about how the feed looks
│   ├── Layout          Positioning + Sizing + Grow direction
│   ├── Style           Background, borders, fonts (shared styling)
│   └── Animations
├── [Feed Options]      Per-feature detail config (no enable toggles here)
│   ├── Items
│   ├── Party Loot
│   ├── …
├── [Blizzard UI]
└── [About]
```

**Pros:** Clear mental model — "I want to enable things" vs. "I want to
tweak behavior" vs. "I want to style things."
**Cons:** Still splits "enable" from "configure" for power users who want to
do both at once.

---

### Option C — Consolidated visual, per-feature behavior (recommended starting point)

```
RPGLootFeed
├── [General]
│   ├── Quick Actions   Test mode, Clear rows, Loot History toggle
│   ├── Minimap icon
│   ├── Tooltips
│   └── Loot History settings
├── [Loot Feeds]        Replaces current Features tab
│   ├── (9 enable toggles at top — same as today)
│   └── (Per-feature sub-groups — same as today, minus Misc)
├── [Display]           Replaces Positioning + Sizing + Styling + Animations
│   ├── Layout          Positioning + Sizing (feed width, rows, row height, icon size, padding)
│   ├── Styling         Background, borders, font, secondary text, icon text, row spacing
│   └── Animations      Enter / Exit / Hover / Update
├── [Blizzard UI]       Split into sub-groups:
│   ├── Loot Behavior   Auto Loot, Boss Banner
│   └── Chat Filters    All the "Disable X chat messages" executors
└── [About]
```

**Pros:** Reduces top-level tab count (7 → 5). Logically groups display
settings. Misc items get a real home (General). Blizzard UI becomes clearer.
**Cons:** Still doesn't fully solve Party Loot scatter.

---

### Option D — Hybrid: General + Feeds + Appearance (personal recommendation)

```
RPGLootFeed
├── [General]
│   Quick actions, minimap, tooltips, loot history, Hide All Icons,
│   Show '1' Quantity (global feed behaviors that don't belong to one feature)
│
├── [Loot Feeds]
│   Top-level: 9 enable/disable toggles
│   Sub-tabs per feature (each owns its full config, no duplicated top-level toggles)
│
├── [Appearance]
│   ├── Positioning     Anchor, offsets, strata
│   ├── Sizing          Width, rows, height, icon size, padding
│   ├── Styling         Background, borders, secondary text ENABLE (moved here!),
│   │                   fonts, icon text, row spacing
│   └── Animations      Enter / Exit / Hover / Update
│
├── [Party Loot Frame]  ← NEW dedicated tab (instead of injected inline groups)
│   Visible (but greyed out) when separateFrame is off, active when on
│   ├── Enable Separate Frame toggle (moved here as the gateway)
│   ├── Positioning
│   ├── Sizing
│   └── Styling
│
├── [Blizzard UI]
│   ├── Loot Behavior   Auto Loot, Boss Banner
│   └── Chat Filters    Disable X chat messages buttons
│
└── [About]
```

**Pros:**

- Cleans up Features tab significantly (Misc stuff has a proper home in General)
- Solves Secondary Row Text split (enable + font size both in Styling)
- Solves Party Loot scatter with a dedicated tab
- Appearance sub-grouping means users can hunt visually in one place
- Enable toggles appear once (only in Loot Feeds top level, not duplicated in sub-groups)
- Tab count reasonable: 6 real tabs + About

**Cons / Open Questions:**

- Tab count increases by 1 vs Option C (Party Loot becomes its own tab)
- If more "separate frame" types are added in the future (e.g., a dedicated
  currency frame), the pattern needs to scale — possibly a [Frames] tab with
  sub-tabs per frame?
- Does the Blizzard UI "Chat Filters" split feel too granular? Could stay flat.

---

## Future-Proofing Notes

- **Multiple frames:** If we ever support more than two frames (main + party),
  a dedicated [Frames] top-level tab with per-frame sub-tabs scales better
  than injecting positioning/sizing/styling inline everywhere.
- **Profiles:** If per-character vs. per-account scoping ever gets exposed to
  users as an option, that belongs in General or a dedicated Profiles tab.
- **Import/Export:** A share-settings feature would live naturally in General
  or About.
- **Notification / Alert rules:** If richer filtering (e.g., "only show epics
  from bosses") is added, that belongs in per-feature config sub-tabs, not a
  global Misc bucket.

---

## Decisions & Future Architecture Notes

### Q1 — Enable toggle placement

**Decision:** Enable toggle lives only in the feature's sub-group. When
disabled it collapses (hides) all the sub-group options beneath it so the
page stays clean. The duplicated top-level toggle grid in Features is removed.

### Q2 — Global defaults + per-feed overrides

**Decision / Future direction:** Tied to the row rearchitecture effort. The
long-term goal is "Global Defaults" for styling/display options that each
individual feed can selectively override (e.g., Item Loot uses a larger font,
Reputation uses a different background). This means the Appearance settings
should be structured as a "global defaults" layer, with each feed sub-group
eventually exposing an optional "Appearance overrides" section. The current
`Secondary Row Text` enable/disable is a candidate to move into Styling
(alongside the font size) as part of this restructure, since both halves of
that setting live there after the merge.

### Q3 — Party Loot Frame → treat as a Feed

**Decision:** Party Loot is a Feed, not a special frame. It should sit as a
peer under the Loot Feeds tab alongside Items, Currency, etc., and own its
own enable toggle + full config (including its current position/size/style
options) when a separate frame is active. The separate frame toggle becomes
part of Party Loot's Feed config, not a top-level concept.

**Future (multiple frames):** When multiple feed frames are supported, the
pattern extends naturally — any Feed can be anchored to a frame (default,
party, or user-created). Migration scripts will move existing config: all
current global settings → "default" frame; existing Party Loot `separateFrame`
settings → "party" frame. The frame concept will be surfaced as a top-level
dropdown (referencing the BeaconUnitFrames addon pattern) so users can switch
which frame's settings they are editing — this is the future home for all
per-frame positioning/sizing/styling that today lives scattered across tabs.

### Q4 — Chat filter buttons

**Decision (now):** Leave the one-shot "Disable X chat messages" execute
buttons in Blizzard UI > Chat Filters. They are a convenience utility and do
not need a new home yet.

**Future improvement:** Convert these from one-shot executors to per-chat-tab
toggles (e.g., "disable in the Main/Default chat tab only"), which is a
non-trivial Blizzard API change. Tracked as a low-priority enhancement.

### Q5 — Multiple feed frames (top-level dropdown)

**Future design:** Multiple frames is a highest-priority future feature. The
UI pattern to adopt is a top-level dropdown (like BeaconUnitFrames) that
selects which frame's config is being edited, applied at the root of the
Appearance tab (or potentially at the root of the entire options panel). Each
frame will own its own Positioning, Sizing, Styling, and Animations. Loot
Feeds will reference which frame they belong to rather than duplicating
display config. Reference the BeaconUnitFrames implementation when building
this.

---

## Revised Recommendation (Option D — updated)

```
RPGLootFeed
├── [General]
│   Quick actions (Test Mode, Clear Rows, Loot History window toggle),
│   minimap icon, tooltips, loot history settings,
│   Hide All Icons, Show '1' Quantity
│   (global feed behaviors with no per-feature home)
│
├── [Loot Feeds]
│   Per-feature sub-groups; NO top-level enable toggle grid.
│   Each sub-group starts with its own enable toggle; when off, all
│   options below it are hidden.
│   Sub-groups (in order):
│   ├── Items           (enable + item count, quality filter, highlights,
│   │                    secondary text/prices, sounds, style overrides)
│   ├── Party Loot      (enable + party-specific options + separate-frame
│   │                    toggle + positioning/sizing/styling when active)
│   ├── Currency
│   ├── Money
│   ├── Experience
│   ├── Reputation
│   ├── Professions
│   ├── Travel Points   (Retail only)
│   └── Transmog
│
├── [Appearance]        Global display defaults (future: per-frame via dropdown)
│   ├── Layout          Positioning + Sizing (feed width, rows, height, icon, padding)
│   ├── Styling         Background, borders, fonts (primary + secondary),
│   │                   secondary row text ENABLE (moved here from Features > Misc),
│   │                   icon text, row spacing
│   └── Animations      Enter / Exit / Hover / Update
│
├── [Blizzard UI]
│   ├── Loot Behavior   Enable Auto Loot, Disable Loot Toasts,
│   │                   Disable Money Alerts, Boss Banner config
│   └── Chat Filters    One-shot "Disable X chat messages" execute buttons
│                       (future: per-window toggles)
│
└── [About]
```

### Key changes from current state

| Current                                                                 | Revised                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 9 duplicate enable toggles at top of Features tab                       | Removed; toggles only in each sub-group                          |
| Party Loot: position/size/style injected into 3 other tabs              | All Party Loot config self-contained in its Loot Feeds sub-group |
| Features > Misc holds minimap, tooltips, loot history                   | Moved to General                                                 |
| Secondary Row Text enable in Features > Misc; font size in Styling      | Both in Styling                                                  |
| Positioning / Sizing / Styling / Animations as 4 top-level sibling tabs | Consolidated under Appearance with 3 sub-tabs                    |
| Blizzard UI: flat list mixing toggles and one-shot buttons              | Split into Loot Behavior (toggles) and Chat Filters (executors)  |

### Future-facing structure notes

- When **multiple frames** land, Appearance gains a frame-selector dropdown at
  its top level. Each frame owns its own Layout/Styling/Animations. The
  Party Loot "separate frame" approach is refactored to use the same frame
  concept with a "party" frame created by default if the old setting was on.
- When **per-feed appearance overrides** land (row rearchitecture), each Loot
  Feeds sub-group gains an optional "Appearance Overrides" collapsible section
  that inherits from the global Appearance defaults and allows selective
  override. This is additive and doesn't require restructuring the top level.
