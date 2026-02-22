# Step 1 Implementation Plan: Primary Line HorizontalLayout

Comprehensive plan for the first incremental change toward the row layout redesign.
See [row-layout-redesign.md](row-layout-redesign.md) for the full design vision.

---

## 1. Current State Analysis

### 1.1 Frame Structure

`PrimaryText`, `ItemCountText`, and `SecondaryText` are bare `FontString`s defined
in `RowText.xml` as children of `RLF_RowTextTemplate`:

```xml
<Frame name="RLF_RowTextTemplate" mixin="RLF_RowTextMixin" virtual="true">
    <Layers>
        <Layer level="ARTWORK">
            <FontString parentKey="PrimaryText" inherits="GameFontNormal" />
            <FontString parentKey="ItemCountText" inherits="GameFontNormal" hidden="true" />
            <FontString parentKey="SecondaryText" inherits="GameFontNormal" hidden="true" />
        </Layer>
    </Layers>
</Frame>
```

There is no layout container. All positioning is done via manual `SetPoint` calls:

- `PrimaryText` is anchored to `Icon.RIGHT` (left-align) or `Icon.LEFT` (right-align)
  in `RLF_RowTextMixin:StyleText()`.
- `ItemCountText` is anchored relative to `PrimaryText` in the same function:
  ```lua
  self.ItemCountText:SetPoint(anchor, self.PrimaryText, iconAnchor, xOffset, 0)
  -- left-align:  ItemCountText.LEFT  → PrimaryText.RIGHT xOffset
  -- right-align: ItemCountText.RIGHT → PrimaryText.LEFT  -xOffset
  ```
- `PrimaryText` has no `SetWidth` — its width is unconstrained. It clips when too
  long, but more importantly, it **overlaps** `ItemCountText` unless pre-truncated.

### 1.2 The Truncation Pipeline

Before `ShowText()` is called in `LootDisplayRow:Populate()`, an `extraWidth` value
is assembled from all the things that share horizontal space with `PrimaryText`:

```lua
-- Simplified from LootDisplayRow.lua ~line 240
extraWidth = (iconSize / 4)                                     -- icon gap
           + CalculateTextWidth(itemCountWrapChars, frameType)  -- wrap chars
           + itemCountWidth                                      -- "x99" etc.
           + portraitWidth (if unit portrait active)

self.link = G_RLF:TruncateItemLink(textFn(), extraWidth)
text = textFn(0, self.link)
```

`TruncateItemLink` (in `LootDisplay.lua` ~line 504):

```lua
local maxWidth = feedWidth - (iconSize/4) - iconSize - (iconSize/4) - extraWidth
-- ... linear character-strip loop using CalculateTextWidth (tempFontString) ...
```

`CalculateTextWidth` sets text on a hidden `tempFontString`, calls
`GetUnboundedStringWidth()`, and returns the width — the side-channel measurement.

### 1.3 `ItemCountText` Is Set Deferred

`UpdateItemCount()` is called via `RunNextFrame` after `ShowText()`. This means at
the time `TruncateItemLink` runs, the `ItemCountText` string hasn't been formatted
yet — the _expected_ count text width is calculated manually from the raw number.

### 1.4 The `leftAlign` Model

`leftAlign` in the config means "icon on the left side of the row". The downstream
effects:

- `leftAlign = true`: `PrimaryText.LEFT` → `Icon.RIGHT`, `ItemCountText.LEFT` → `PrimaryText.RIGHT`
- `leftAlign = false`: `PrimaryText.RIGHT` → `Icon.LEFT`, `ItemCountText.RIGHT` → `PrimaryText.LEFT`

Visual result:

```
left-align:  [Icon][ PrimaryText... ][ItemCountText]
right-align: [ItemCountText][ ...PrimaryText][Icon]
```

### 1.5 Problems Summarised

| Problem                                  | Location                  | Impact                                                                        |
| ---------------------------------------- | ------------------------- | ----------------------------------------------------------------------------- |
| Linear strip loop O(n)                   | `TruncateItemLink`        | Slow on long names; noticeable on many rows                                   |
| `tempFontString` side-channel            | `CalculateTextWidth`      | Brittle; font must be synced manually                                         |
| Magic constant math for `maxWidth`       | `TruncateItemLink`        | Wrong when config changes mid-session                                         |
| `string.sub` byte indexing               | `TruncateItemLink`        | Corrupts CJK / Cyrillic item names                                            |
| Link-structure parsing                   | `TruncateItemLink`        | Breaks on any non-standard link format                                        |
| Manual `extraWidth` assembly             | `LootDisplayRow:Populate` | Breaks if new elements share the row                                          |
| `ItemCountText` positioned by `SetPoint` | `StyleText()`             | Interacts badly with layout changes; position is tied to `PrimaryText` anchor |
| No container — text widths uncoordinated | `RowText.xml`             | Overlap is possible; centering is impossible                                  |

---

## 2. The `HorizontalLayoutMixin` Primer (Accurate)

**Source**: `wow-ui-source/Interface/AddOns/Blizzard_SharedXML/LayoutFrame.lua`

This is the **current** (live-branch) version — significantly more capable than the
older version documented elsewhere.

### Key properties consulted per-frame:

| Property                                  | Type   | Meaning                                                    |
| ----------------------------------------- | ------ | ---------------------------------------------------------- |
| `frame.spacing`                           | number | Gap between children                                       |
| `frame.leftPadding` / `rightPadding` etc. | number | Inset from frame edges                                     |
| `frame.fixedWidth` / `fixedHeight`        | number | Overrides resized dimension                                |
| `frame.childLayoutDirection`              | string | `"rightToLeft"` reverses child order                       |
| `child.layoutIndex`                       | number | Sort key for child ordering                                |
| `child.expand`                            | bool   | **HEIGHT** expansion only in Horizontal layout (see below) |
| `child.align`                             | string | `"bottom"` or `"center"` vertical alignment within row     |
| `child.ignoreInLayout`                    | bool   | Excludes this child from layout children list              |
| `child.includeAsLayoutChildWhenHidden`    | bool   | Includes hidden children in layout                         |

### ⚠️ Critical: `expand` expands HEIGHT, not WIDTH, in `HorizontalLayoutMixin`

A common misreading: `child.expand = true` in a `HorizontalLayoutMixin` causes the
child's **height** to be stretched to fill the container height — not its width.

There is no automatic "fill remaining width" for a child in a `HorizontalLayout`.
**PrimaryText width must be calculated and set manually before calling `Layout()`.**

### `LayoutMixin:Layout()` call chain:

1. `GetLayoutChildren()` — returns children sorted by `layoutIndex`, filtered by
   `IsShown()` (unless `includeAsLayoutChildWhenHidden`) and `ignoreInLayout`
2. `LayoutChildren(children)` — first pass: positions each child, accumulates width
3. If any child has `expand`, calls `LayoutChildren(children, frameW, frameH)` again
4. `CalculateFrameSize()` — applies `fixedWidth` / `fixedHeight` if set
5. `SetSize()` — updates the frame
6. `MarkClean()`

### `childLayoutDirection = "rightToLeft"` behaviour:

Children are positioned from the right edge leftward. Child with `layoutIndex=1` ends
up rightmost; child with `layoutIndex=2` is to its left. No code changes to the
children are needed to reverse visual order — only set this flag on the container.

This is how we handle `leftAlign = false` (icon-right) without reordering children.

---

## 3. FontString Truncation — Native Engine Behavior

**The WoW engine truncates FontStrings natively.** No binary search, no
`tempFontString`, no manual string-slicing.

The two required conditions:

1. `FontString:SetWidth(w)` — constrains the display width
2. `FontString:SetWordWrap(false)` — prevents the engine from wrapping instead

When both are set and the text would exceed `w` pixels, the engine automatically
renders trailing `"..."` and `FontString:IsTruncated()` returns `true`.

The current `PrimaryText` and `ItemCountText` have no `SetWordWrap` call anywhere
in the codebase (confirmed by grep) and no XML `wordWrap` attribute. `GameFontNormal`
does not set word wrap off by default, so **this must be explicitly called** during
frame setup — it is likely an existing visual bug that long names wrap rather than
truncate on single-line rows.

So `LayoutPrimaryLine()` becomes:

```lua
local primaryTextWidth = math.max(1, availableWidth - itemCountWidth - spacing)
self.PrimaryText:SetWidth(primaryTextWidth)
self.PrimaryText:SetWordWrap(false)       -- engine handles truncation with "..."
self.PrimaryText:SetText(self.rawPrimaryText)
self.PrimaryLineLayout:Layout()
```

No `TruncateToWidth` helper is needed. No `Utils/TextLayout.lua` file.

### 3.1 Bonus: `IsTruncated()` enables a tooltip improvement

Blizzard's own pattern when text may be truncated (e.g. `PanelTabButtonMixin:OnEnter`
in `SharedUIPanelTemplates.lua`):

```lua
function PanelTabButtonMixin:OnEnter()
    if self.Text:IsTruncated() then
        tooltip:SetText(self.Text:GetText())  -- show full text in tooltip
    end
end
```

We can use the same pattern in `RowTooltipMixin`: if `self.PrimaryText:IsTruncated()`,
show the full untruncated name alongside the item tooltip. This is a free UX win
that falls out of native truncation with no extra cost.

### 3.2 Future option: `AutoScalingFontStringMixin`

Found in `wow-ui-source/Interface/AddOns/Blizzard_SharedXML/SecureUtil.lua`:

```lua
-- Mix into a FontString to shrink text to fit without truncating,
-- by scaling it down until it fits or gets too small.
AutoScalingFontStringMixin = {}
```

Instead of `"..."` truncation, it scales the font size down proportionally until
the text fits the available width or hits a minimum line height threshold.
This would be a natural future config option: **「Truncate」vs「Shrink to fit」**.

No changes needed for Step 1 — just noting it here so the design accommodates it.
The `PrimaryLineLayout` width budget calculation is identical regardless of which
technique is applied to `PrimaryText`.

---

## 4. Target Architecture for Step 1

### 4.1 New `PrimaryLineLayout` container

Introduce a lightweight `Frame` container between the row and its text `FontString`s,
mixed with `HorizontalLayoutMixin`. This container holds `PrimaryText` and
`ItemCountText` as direct children with explicit `layoutIndex` values.

```
LootDisplayRow (existing row frame)
└── Icon  (existing ItemButton, unchanged)
└── PrimaryLineLayout  (new Frame + HorizontalLayoutMixin)
        ├── PrimaryText   (FontString, layoutIndex=1, width set manually)
        └── ItemCountText (FontString, layoutIndex=2, natural/intrinsic width)
└── SecondaryText  (existing FontString, unchanged for Step 1)
```

`PrimaryLineLayout` is anchored to `Icon` using the same anchor logic currently
applied directly to `PrimaryText` in `StyleText()`.

### 4.2 Width Budget

```
availableWidth = feedWidth - iconSize - (iconSize/4) - (portraitSize if applicable)
itemCountWidth = ItemCountText:GetUnboundedStringWidth()   -- after text is set
primaryTextWidth = availableWidth - itemCountWidth - layout.spacing
```

`PrimaryText:SetWidth(primaryTextWidth)` is called before `PrimaryLineLayout:Layout()`.
`TruncateToWidth(PrimaryText, primaryTextWidth, rawName)` is then called.

### 4.3 Solving the Deferred `ItemCountText` Problem

Currently `UpdateItemCount()` runs in `RunNextFrame` — after `ShowText()` has
already set and truncated `PrimaryText`. This ordering causes `TruncateItemLink` to
receive a manually pre-computed `extraWidth` as a substitute for the actual
`ItemCountText` width.

With the new approach, we consolidate into a single deferred layout step:

**New ordering**:

```
Populate():
    1. ShowText(rawText, ...) → sets PrimaryText with FULL availableWidth (no truncation yet)
    2. RunNextFrame:
        a. ShowItemCountText(count) → sets ItemCountText string
        b. Re-layout: PrimaryLineLayout:Layout() after SetWidth calculations + TruncateToWidth
```

This eliminates `extraWidth` pre-calculation entirely. `ItemCountText` width is
measured from the actual formatted string, not reconstructed from the raw number.

To enable this, `ShowText` needs to accept raw item name (not a pre-truncated link),
and truncation moves into the deferred step alongside `ItemCountText` setup.

### 4.4 Handling `leftAlign` (icon position)

`PrimaryLineLayout` gets `childLayoutDirection = "rightToLeft"` when
`leftAlign = false`. This reverses the visual order of `PrimaryText` and
`ItemCountText` without changing `layoutIndex` values:

```
leftAlign = true:  [PrimaryText...][ItemCountText]  (left-to-right, default)
leftAlign = false: [ItemCountText][...PrimaryText]  (right-to-left, reversed)
```

Setting `childLayoutDirection` is done in `StyleText()` alongside the existing
`PrimaryLineLayout:SetPoint(...)` anchor logic, replacing the current manual
`ItemCountText:SetPoint` calls.

---

## 5. File-by-File Changes

### 5.1 `RowText.xml`

**Remove** `ItemCountText` from the `<Layers>` block (it becomes a programmatic child
of `PrimaryLineLayout`, not an XML-defined sibling of `PrimaryText`).

**Add** `PrimaryLineLayout` as an XML frame or create it programmatically in `OnLoad`.

Option A — XML (preferred for clarity):

```xml
<Frame name="RLF_RowTextTemplate" mixin="RLF_RowTextMixin" virtual="true">
    <Frames>
        <Frame parentKey="PrimaryLineLayout" mixin="HorizontalLayoutMixin">
            <Layers>
                <Layer level="ARTWORK">
                    <FontString parentKey="PrimaryText"
                                inherits="GameFontNormal"
                                layoutIndex="1" />
                    <FontString parentKey="ItemCountText"
                                inherits="GameFontNormal"
                                hidden="true"
                                layoutIndex="2"
                                includeAsLayoutChildWhenHidden="true" />
                </Layer>
            </Layers>
        </Frame>
    </Frames>
    <Layers>
        <Layer level="ARTWORK">
            <FontString parentKey="SecondaryText" inherits="GameFontNormal" hidden="true" />
        </Layer>
    </Layers>
</Frame>
```

> **Note on `includeAsLayoutChildWhenHidden`**: `ItemCountText` is hidden when no
> count is shown. Setting this flag means `HorizontalLayoutMixin:GetLayoutChildren()`
> still includes it so its (zero) width is allocated — only needed if we always want
> the slot reserved. More likely we want to **exclude** it when hidden so `PrimaryText`
> gets the full width. Leave this flag off (default); when `ItemCountText` is hidden,
> `GetLayoutChildren()` omits it, and we recalculate `PrimaryText` width accordingly.

Option B — Programmatic in `RLF_RowTextMixin:CreatePrimaryLineLayout()` called from
`OnLoad`. More testable without XML parsing.

**Decision needed**: XML vs programmatic. XML makes hierarchy visible at a glance;
programmatic is easier to test in busted specs. Given existing mixin pattern,
**programmatic is recommended** for consistency with how `RowIconMixin`, etc. work.

### 5.2 `RowTextMixin.lua`

#### New: `CreatePrimaryLineLayout()`

```lua
function RLF_RowTextMixin:CreatePrimaryLineLayout()
    local layout = CreateFrame("Frame", nil, self)
    Mixin(layout, HorizontalLayoutMixin)
    layout.spacing = 0  -- set after icon size is known; see StyleText()

    -- PrimaryText moves from being a direct child of the row to being a child
    -- of the layout frame.
    self.PrimaryText:SetParent(layout)
    self.PrimaryText.layoutIndex = 1

    self.ItemCountText:SetParent(layout)
    self.ItemCountText.layoutIndex = 2

    self.PrimaryLineLayout = layout
end
```

#### Modified: `StyleText()`

Remove:

- `self.PrimaryText:SetPoint(...)` (was anchored to Icon directly)
- `self.ItemCountText:SetPoint(...)` (was anchored to PrimaryText)

Add:

- `self.PrimaryLineLayout.spacing = iconSize / 4`
- `self.PrimaryLineLayout.childLayoutDirection = leftAlign and nil or "rightToLeft"`
- `self.PrimaryLineLayout:ClearAllPoints()`
- `self.PrimaryLineLayout:SetPoint(anchor, self.Icon, iconAnchor, xOffset, 0)`
  (same anchor logic that was on `self.PrimaryText`)

#### Modified: `ShowText()`

Remove the current assumption that `text` is pre-truncated.
Rename param from `text` to `rawText`. Store `rawText` for use in deferred layout.

After setting `self.rawPrimaryText = rawText`:

```lua
self.PrimaryText:SetText(rawText)  -- temporary; overwritten in deferred step
```

#### New: `LayoutPrimaryLine()`

Called from `RunNextFrame` after `ShowItemCountText()` has run:

```lua
function RLF_RowTextMixin:LayoutPrimaryLine()
    local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
    local iconSize = sizingDb.iconSize
    local feedWidth = sizingDb.feedWidth

    local portraitOffset = 0
    if self.unit and G_RLF.db.global.partyLoot.enablePartyAvatar then
        local portraitSize = iconSize * 0.8
        portraitOffset = portraitSize - (portraitSize / 2)
    end

    local iconOffset = iconSize + (iconSize / 4)
    local availableWidth = feedWidth - iconOffset - portraitOffset

    local itemCountWidth = 0
    if self.ItemCountText:IsShown() then
        itemCountWidth = self.ItemCountText:GetUnboundedStringWidth()
            + self.PrimaryLineLayout.spacing
    end

    local primaryTextWidth = math.max(1, availableWidth - itemCountWidth)
    self.PrimaryText:SetWidth(primaryTextWidth)
    self.PrimaryText:SetWordWrap(false)   -- engine truncates with "..." natively
    self.PrimaryText:SetText(self.rawPrimaryText)

    self.PrimaryLineLayout:Layout()
end
```

No truncation helper function is needed — the engine handles it.

#### Modified: `ShowItemCountText()`

After the existing `self.ItemCountText:Show()` / `self.ItemCountText:Hide()` logic,
call `self:LayoutPrimaryLine()` at the end.

### 5.3 `LootDisplayRow.lua`

#### Modified: `Populate()` (and `Update()`)

Remove:

- The entire `extraWidth` assembly block
- `G_RLF:TruncateItemLink(textFn(), extraWidth)` call
- `self.link = ...` assignment that stores the pre-truncated link

Add:

- `self.rawLink = textFn()` — stores the untruncated link/name for deferred use

Change:

- `text = textFn(0, self.link)` → `text = textFn(0, self.rawLink)` (full link, no
  truncation yet; `ShowText` will accept it and truncation happens in `LayoutPrimaryLine`)

> **Edge case**: `self.link` is also used by `SetupTooltip()` and `ClickableButton`
> sizing. Tooltip should use the **untruncated** link anyway — this is a pre-existing
> correctness improvement. `ClickableButton` sizing currently reads
> `self.PrimaryText:GetStringWidth()` — this still works correctly because
> `LayoutPrimaryLine` will have set the final truncated width by the time it's visible.

### 5.4 `LootDisplay.lua`

Remove (after confirming no other callers):

- `G_RLF:TruncateItemLink(...)` function
- `G_RLF:CalculateTextWidth(...)` function
- `G_RLF.tempFontString` initialization

### 5.5 No new utility file needed

Native FontString truncation via `SetWidth` + `SetWordWrap(false)` replaces all
custom truncation logic. No `Utils/TextLayout.lua` is required.

---

## 6. Invariants — What Does NOT Change in Step 1

| Thing                                               | Reason unchanged                                                      |
| --------------------------------------------------- | --------------------------------------------------------------------- |
| `SecondaryText` anchoring                           | Not in scope; still anchored manually to Icon                         |
| `Icon` position logic (`RowIconMixin`)              | Unchanged                                                             |
| `leftAlign` config value and meaning                | Still drives anchor point; now also drives `childLayoutDirection`     |
| `StyleText()` caching logic                         | Cache keys may need `childLayoutDirection` added; rest unchanged      |
| `UpdateItemCount()` dispatch logic per feature type | Still calls `ShowItemCountText`                                       |
| All feature modules (`ItemLoot`, `Currency`, etc.)  | `textFn` contract unchanged — only callers in `LootDisplayRow` change |
| `SecondaryText` font styling                        | Unchanged                                                             |
| History mode / `LootDisplayFrame` data capture      | Reads from `PrimaryText:GetText()` — still valid after layout         |

---

## 7. Test Changes

### 7.1 `_mocks/Internal/LootDisplayRowFrame.lua`

- `mockFontString()` needs `GetUnboundedStringWidth` stub returning a sensible default
  (e.g. `80`). This is currently missing.
- `PrimaryLineLayout` mock frame needs to be added with a `Layout` stub and
  `spacing`, `childLayoutDirection` fields.
- Remove `CalculateTextWidth` and `TruncateItemLink` stubs from
  `_mocks/Internal/addonNamespace.lua` once the real functions are deleted.

### 7.2 `LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin_spec.lua`

- Tests for `StyleText()` currently assert `PrimaryText:SetPoint` and
  `ItemCountText:SetPoint` were called. These change to asserting
  `PrimaryLineLayout:SetPoint` and that `PrimaryLineLayout.childLayoutDirection`
  is set correctly for both `leftAlign = true` and `leftAlign = false`.
- New tests for `LayoutPrimaryLine()`:
  - `ItemCountText` hidden → `PrimaryText` gets full available width
  - `ItemCountText` shown → `PrimaryText` width = availableWidth - countWidth - spacing
  - Long item name → `TruncateToWidth` is called (spy on `PrimaryText:SetText`)

### 7.3 `LootDisplay/LootDisplayFrame/LootDisplayRow/LootDisplayRow_spec.lua`

- Assertions on `TruncateItemLink` being called should be removed.
- Assertions on `text = textFn(0, truncatedLink)` change to `text = textFn(0, rawLink)`.
- `extraWidth` assembly logic has no test coverage today — simply remove.

### 7.4 No `TruncateToWidth` specs needed

Native truncation is engine behavior — not our code, not our test responsibility.
The `LayoutPrimaryLine` spec (section 7.2) covers that `SetWidth` and `SetWordWrap`
are called with the correct values; correctness of the visual output is validated
in-game.

---

## 8. Open Questions / Risks

### 8.1 Is `HorizontalLayoutMixin` available without XML inheritance?

Blizzard's layout mixins are defined in `Blizzard_SharedXML` (loaded for all addons).
`HorizontalLayoutMixin` should be a global. Verify by `print(type(HorizontalLayoutMixin))`
in-game before relying on it.

If not available as a global (unlikely but possible in some game versions), we can
copy the relevant `LayoutChildren` logic as a local mixin — it's ~30 lines.

### 8.2 `FontString` as child of a `Frame` — does `SetParent` work correctly?

`PrimaryText` and `ItemCountText` are currently siblings of `Icon` on the row frame.
After Step 1 they become children of `PrimaryLineLayout`. `FontString:SetParent()`
should work, but verify that `GetLayoutChildren()` via `GetChildren()` and
`GetRegions()` picks them up correctly.

> LayoutMixin's `GetLayoutChildren()` calls both `self:GetChildren()` (Frames) and
> `self:GetRegions()` (FontStrings, Textures). FontStrings are **regions**, not
> children, so they should be returned by `GetRegions()`. Confirm `layoutIndex` is
> respected on regions, not only on child Frames.

### 8.3 `ClickableButton` sizing after truncation

`ClickableButton:SetSize(self.PrimaryText:GetStringWidth(), ...)` in `ShowText()`.
This must be called **after** `LayoutPrimaryLine()` sets the final text. Move
`ClickableButton` sizing into `LayoutPrimaryLine()`.

### 8.4 History mode bypass

`LootDisplayFrame` saves row data for history replay via:

```lua
rowText = row.PrimaryText:GetText()
```

After this change, `PrimaryText:GetText()` returns the **truncated** text, not the
original item link. For history, we want the original. Consider adding
`row.rawPrimaryText` to the saved history data.

### 8.5 `SetWordWrap(false)` must be set during frame setup, not just at truncation time

`SetWordWrap(false)` should be called once in `CreatePrimaryLineLayout()` or
`OnLoad`, not in `LayoutPrimaryLine()` on every update, since it only needs to
be set once per `FontString`. Moving it out of the hot path keeps `LayoutPrimaryLine`
leaner.

---

## 9. Implementation Order

1. **Add `PrimaryLineLayout` frame + `CreatePrimaryLineLayout()`** — introduce the
   container structure. At this point it's an inert wrapper; nothing changes visually.

2. **Migrate `StyleText()`** — swap `PrimaryText:SetPoint` and `ItemCountText:SetPoint`
   for `PrimaryLineLayout:SetPoint` and `childLayoutDirection`. Run in-game smoke test.

3. **Introduce `LayoutPrimaryLine()`** — wire the deferred layout step. Run in-game
   with long item names in CJK locale to verify truncation correctness.

4. **Refactor `LootDisplayRow:Populate()`** — remove `extraWidth` and `TruncateItemLink`
   call. Run full in-game integration test.

5. **Delete `TruncateItemLink` / `CalculateTextWidth` / `tempFontString`** — cleanup.

6. **Update tests** — update stubs and assertions to match new structure.
