# AceConfig → HTML Renderer Utility

> **Status (2026-03-08):** Steps 1–5 and 7 are complete and working.
> Steps 6 and 8 remain; see [Remaining Work](#remaining-work) below.
> Run `make options-html` to regenerate the output at any time.

## Purpose

A developer/contributor tool that loads RPGLootFeed's AceConfig options tables
outside the game (using the existing busted mock infrastructure), serializes
them to JSON, and renders a static HTML page that visually mirrors the in-game
settings panel. Primary use cases:

1. **Design and iteration** — see the real option structure without launching
   WoW; rapidly prototype layout reorganizations.
2. **Localization contributions** — translators see every option name and
   description string in context, with the locale key annotated, so they can
   propose translations outside the game.
3. **Documentation / demos** — a linkable, shareable snapshot of what the
   settings look like for a given version. Could be generated as a CI artifact.

---

## Existing Infrastructure

The following pieces already exist and should be reused rather than rebuilt:

| Asset                                                 | Role in this utility                                                                                                       |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `RPGLootFeed_spec/_mocks/helper.lua`                  | Bootstraps all WoW global stubs (bit, Enum, Constants, C\_\* namespaces, etc.)                                             |
| `RPGLootFeed_spec/_mocks/Internal/addonNamespace.lua` | `addonNamespaceMocks:unitLoadedAfter(section)` — builds the `ns` table up to any load section, including locale and enums  |
| `RPGLootFeed_spec/_mocks/Libs/`                       | LibStub, AceAddon, AceLocale, LSM stubs needed so config files load cleanly                                                |
| `RPGLootFeed/locale/enUS.lua`                         | English locale — already loadable via `addonNamespaceMocks` at the `Locale` section                                        |
| `RPGLootFeed/utils/Enums.lua`                         | Loaded at `UtilsEnums` section; provides `G_RLF.EnterAnimationType`, `G_RLF.RowBackground`, etc. needed by config defaults |
| `addonNamespaceMocks.LoadSections.Config` (4)         | Loading through this section fully constructs `G_RLF.options` and `G_RLF.defaults`                                         |
| `.scripts/` (Python, `uv run`)                        | Pattern for standalone Python tooling; existing scripts (locale checkers, etc.) follow this convention                     |
| `Makefile`                                            | Pattern for adding `make` targets                                                                                          |

---

## What's Built

### Files

```
.scripts/
  dump_options.lua          ← Stage 1 entry point (busted spec)
  aceconfig_serializer.lua  ← recursive walk + JSON serialization logic
  render_options.py         ← Stage 2 HTML renderer
.scripts/.output/
  options_dump.json         ← Stage 1 output (gitignored)
  options.html              ← Stage 2 output (gitignored)
```

### Stage 1 — Lua → JSON dump (`dump_options.lua` + `aceconfig_serializer.lua`)

Implemented as a busted spec so it reuses the existing `package.path` setup.
Loads all config files in correct order (matching `config.xml` / `features.xml`)
and builds a fake live DB from `G_RLF.defaults` so `get()`/`hidden()`/`disabled()`
closures resolve real default values.

**Serialization behaviour per field type:**

| Field                                                                          | Serialization                                                                |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| `type`, `name`, `desc`, `order`, `width`, `inline`, `guiInline`, `childGroups` | Copied as-is                                                                 |
| `args`                                                                         | Recurse into child nodes                                                     |
| `values` (table)                                                               | Copied as-is (`{key: label}`)                                                |
| `values` (function)                                                            | Called; result stored in `_resolved`; always `_dynamic: true`                |
| `get` (non-color)                                                              | Called; result stored in `_value`; `_dynamic: true`                          |
| `get` (color node)                                                             | Called; all four channels stored as `_r`, `_g`, `_b`, `_a`; `_dynamic: true` |
| `hidden`, `disabled`                                                           | Called; result stored in `_value`; `_dynamic: true`                          |
| `set`, `func`                                                                  | Not called; recorded as `{_type: "function"}`                                |
| `validate`, `confirm`, `image`, other fn fields                                | Not called; recorded as `{_type: "function"}`                                |
| `sorting`, `imageCoords`, other tables                                         | Copied as-is                                                                 |
| Non-standard extra keys                                                        | Captured with `_extra_` prefix                                               |

**Mock enrichments** (`dump_options.lua` sets these up before loading configs):

- LSM `HashTable()` returns representative sample tables for font/background/border/sound
- `GetFonts()` returns a representative list of WoW font object names
- `ns.AuctionIntegrations` stub so ItemConfig closures don't error
- `CreateAtlasMarkup` mock returns `<AtlasMarkup:atlas-name>` so the atlas name survives into JSON

### Stage 2 — HTML renderer (`render_options.py`)

Self-contained HTML output (all CSS/JS inlined, no external deps).

**Layout:**

- Fixed top bar with addon title + root-level `execute` buttons
- Two-column workspace: left sidebar nav tree | right scrollable content panels
- Sidebar: gold top-level section headers, indented white sub-items; clicking navigates to the panel
- Content: each nav item has a dedicated panel; sub-groups render as `<fieldset>` with `<legend>`

**Widget rendering:**

| AceConfig type               | HTML                                                                                      |
| ---------------------------- | ----------------------------------------------------------------------------------------- |
| `group` (non-inline)         | `<fieldset>` + `<legend>` (gold header)                                                   |
| `group` (inline / guiInline) | `<fieldset class="opt-group-inline">` (dashed border)                                     |
| `toggle`                     | ✔ / □ symbol + label                                                                     |
| `range`                      | `<input type="range">` disabled, with current value display                               |
| `select`                     | `<select>` disabled, options from `values`; respects `sorting`; `dialogControl` annotated |
| `multiselect`                | Flex group of disabled checkboxes per key                                                 |
| `color`                      | Colored swatch with real `rgba(r,g,b,a)` from captured defaults                           |
| `input`                      | `<input type="text">` or `<textarea>` disabled; `validate` string shown as badge          |
| `execute`                    | `<button>` disabled; `CreateAtlasMarkup` names shown as `atlas-badge` pill                |
| `description`                | Styled `<p>` with `image` annotation if present                                           |
| `header`                     | `<h4>` divider with gold border                                                           |

**Additional features:**

- **Disabled state**: `opt-disabled` class (opacity) when `disabled()` returned `true`
- **Hidden options**: separated from visible siblings into a collapsed `<details class="hidden-opts-section">` at both panel and group level; not silently excluded
- **Numeric `width`**: fractional AceConfig widths (e.g. `0.35`) applied as inline `width: N%`
- **Dynamic placeholders**: `[dynamic list]` / `[dynamic]` where values depend on live game state
- **Tooltips**: hovering any option shows internal key, full description, and dynamic/hidden flags
- **Nav**: JS-driven panel switching; parent nodes collapse/expand their children

**Makefile targets:**

- `make options-dump` — runs Stage 1, writes `options_dump.json`
- `make options-html` — runs Stage 1 then Stage 2, writes `options.html`

---

## Architecture

The utility is two decoupled stages:

```
Stage 1: Lua dump script
  Loads config files via mock infrastructure → serializes G_RLF.options to JSON

Stage 2: HTML renderer
  Reads JSON → renders static HTML page
```

Keeping them separate means the renderer can be iterated in isolation (just
feed it updated JSON) and the JSON becomes a useful artifact on its own (e.g.
for diffs, tests, or other tooling).

---

## Stage 1 — Lua → JSON Dump (reference)

The following notes are kept for context; the implementation lives in
`.scripts/dump_options.lua` and `.scripts/aceconfig_serializer.lua`.

### Mock environment

`dump_options.lua` bootstraps the namespace through `addonNamespaceMocks.LoadSections.Utils`
then manually loads each config file (same order as `config.xml`/`features.xml`)
with `loadfile()`. It enriches the LSM, `GetFonts`, and `AuctionIntegrations` stubs
before loading so that function-valued `values` fields can resolve.

A deep-copy of `G_RLF.defaults` is assigned to `ns.db` so that `get()`/`hidden()`/`disabled()`
closures that read `G_RLF.db.global.*` see real default values rather than nil.

### Not yet implemented in Stage 1 — CLI flags

The dump script was designed to accept flags for parameterising the evaluation
environment, but these have not been built yet:

- `--expansion <level>` — controls expansion-gated `disabled` evaluations
- `--retail <true|false>` — controls retail-only `hidden` evaluations
- `--locale <code>` — load an alternative locale file (default: `enUS`)

The current implementation always uses: retail = `true`, enUS locale, and the
default expansion level returned by the `GetExpansionLevel` stub.

---

## Stage 2 — HTML Renderer (reference)

Implementation lives in `.scripts/render_options.py`.

`render_options.py --input PATH --output PATH` (both have defaults pointing at
`.scripts/.output/`). Called automatically by `make options-html`.

The `Renderer` class walks the JSON via `_build_nav()` (which classifies root
groups as nav containers or leaves), then emits panels and dispatches each node
to a per-type `_render_*` method. All CSS and JS are inlined in `HTML_HEAD` /
`HTML_FOOT` constants.

---

## Build Order — Progress

| Step | Status             | Description                                                                                             |
| ---- | ------------------ | ------------------------------------------------------------------------------------------------------- |
| 1    | ✅ Done            | Skeleton JSON serializer — locale strings resolved, structural skeleton output                          |
| 2    | ✅ Done            | Function evaluation — `get()`/`hidden()`/`disabled()` with `_dynamic` annotations                       |
| 3    | ✅ Done            | Values resolution — LSM, `GetFonts`, auction integrations stubs                                         |
| 4    | ✅ Done            | Basic HTML renderer — nav, groups, toggles, ranges                                                      |
| 5    | ✅ Done            | Full widget coverage — all 10 types; color RGBA, atlas badges, validate, numeric width, hidden sections |
| 6    | ⬜ Todo            | Locale annotation mode — `--mode=locale` translator output                                              |
| 7    | ✅ Done            | Makefile targets — `make options-dump` and `make options-html`                                          |
| 8    | ⬜ Todo (optional) | CI artifact — attach `options.html` to releases or PR comments                                          |

---

## Remaining Work

### Step 6 — Locale annotation mode

Add a `--mode=locale` flag to `render_options.py` that, instead of the full visual
HTML, produces a simplified translator-focused table. The design doc specified:

> Just a table of `locale_key | context (option name) | value (English text)`
> for every `name` and `desc` string encountered.

**Implementation sketch:**

- Walk the JSON the same way the renderer does.
- For each node with a non-empty `name` or `desc` string value, emit a row.
  - **locale_key**: the value itself is the already-resolved English string; the
    key cannot be recovered from the dump. Two options:
    1. Compare against `G_RLF.L` at dump time and record `_name_key` / `_desc_key`
       in the JSON (requires Stage 1 change).
    2. Accept that the table is `english_text | context | section` — still useful
       for translators scanning what to translate, even without the raw key.
- Output as either: a standalone HTML `<table>` (share-friendly), or a TSV file
  (paste into a spreadsheet).
- A new Makefile target `make options-locale` would invoke
  `uv run .scripts/render_options.py --mode=locale`.

**Preferred approach:** Option 1 (record keys in JSON) gives translators the raw
locale key they need to submit a patch. The serializer already has access to
`G_RLF.L` at dump time; it can reverse-lookup `name`/`desc` strings.

### Step 8 — CI artifact (optional)

A GitHub Actions workflow step that runs `make options-html` and attaches
`options.html` as a build artifact on each push / release tag. Low priority
until the tool is stable.

---

## Edge Cases (resolved and open)

### Resolved

- **Circular / forward references** — PartyLootConfig loaded before
  Positioning/Sizing/Styling so `Get*Options()` calls work; circular table
  detection in the serializer handles any remaining cases.
- **`width` as a number** — renderer applies inline `width: N%` via the
  `width-numeric` CSS class.
- **`dialogControl`** — annotated as a small `dialog-ctrl` badge next to the
  `<select>` widget.
- **`validate` as a string** — shown as a `validate-badge` on `input` nodes.
- **`inline = true` groups** — rendered with a dashed `opt-group-inline` border
  instead of a solid one.
- **`CreateAtlasMarkup` names** — the mock now returns `<AtlasMarkup:name>` so
  execute button names survive into the JSON and render as `atlas-badge` pills.
- **Color multi-return** — `get()` on color nodes returns `r, g, b, a`; all
  four channels are now captured separately and used to render real color swatches.

### Open

- **`--locale` flag** — non-enUS locales not yet loadable via the dump script.
- **`--expansion` / `--retail` flags** — expansion-gated and retail-only
  `hidden`/`disabled` results are always evaluated with the default stubs; you
  cannot currently simulate a non-retail or older-expansion run.
