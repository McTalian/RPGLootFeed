# Step 1 Implementation Plan: Primary Line HorizontalLayout

Comprehensive plan for the first incremental change toward the row layout redesign.
See [row-layout-redesign.md](row-layout-redesign.md) for the full design vision.

---

## 1. Current State Analysis

### 1.1 Frame Structure

`PrimaryText`, `ItemCountText`, and `SecondaryText` are bare `FontString`s defined
in [RowText.xml](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowText.xml) as children of `RLF_RowTextTemplate`:

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
  in [`RLF_RowTextMixin:StyleText()`](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua#L59).
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
-- Simplified from LootDisplayRow.lua (BootstrapFromElement, line 237)
extraWidth = (iconSize / 4)                                     -- icon gap
           + CalculateTextWidth(itemCountWrapChars, frameType)  -- wrap chars
           + itemCountWidth                                      -- "x99" etc.
           + portraitWidth (if unit portrait active)

self.link = G_RLF:TruncateItemLink(textFn(), extraWidth)
text = textFn(0, self.link)
```

[`TruncateItemLink`](../../RPGLootFeed/LootDisplay/LootDisplay.lua#L504) (in [LootDisplay.lua](../../RPGLootFeed/LootDisplay/LootDisplay.lua)):

```lua
local maxWidth = feedWidth - (iconSize/4) - iconSize - (iconSize/4) - extraWidth
-- ... linear character-strip loop using CalculateTextWidth (tempFontString) ...
```

`CalculateTextWidth` sets text on a hidden `tempFontString`, calls
`GetUnboundedStringWidth()`, and returns the width — the side-channel measurement.

### 1.3 `ItemCountText` Is Set Deferred

[`UpdateItemCount()`](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua#L247) is called via `RunNextFrame` after [`ShowText()`](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua#L369). This means at
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

**Source**: [wow-ui-source/Interface/AddOns/Blizzard_SharedXML/LayoutFrame.lua](../../../wow-ui-source/Interface/AddOns/Blizzard_SharedXML/LayoutFrame.lua)

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

Found in [wow-ui-source/Interface/AddOns/Blizzard_SharedXML/SecureUtil.lua](../../../wow-ui-source/Interface/AddOns/Blizzard_SharedXML/SecureUtil.lua):

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

`PrimaryLineLayout` uses **plain `HorizontalLayoutMixin`** (not `ResizingHorizontalLayoutMixin`). Its `fixedWidth` is set explicitly before each `Layout()` call to `availableWidth`, keeping the container a fixed, predictable size. `PrimaryText:SetWidth()` then controls the truncation budget within that fixed container.

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

`PrimaryLineLayout.fixedWidth = availableWidth` is set before `Layout()` so the
container has a known fixed size. `PrimaryText:SetWidth(primaryTextWidth)` controls
how much of that space the text occupies, with the remainder reserved for
`ItemCountText`. The engine then handles truncation natively.

### 4.3 Solving the Deferred `ItemCountText` Problem

Currently `UpdateItemCount()` runs in `RunNextFrame` — after `ShowText()` has
already set and truncated `PrimaryText`. This ordering causes `TruncateItemLink` to
receive a manually pre-computed `extraWidth` as a substitute for the actual
`ItemCountText` width.

With the new approach, we consolidate into a single deferred layout step:

**New ordering**:

```
Populate():
    1. ShowText(rawText, ...) → calls LayoutPrimaryLine() immediately with ItemCountText hidden
    2. RunNextFrame:
        a. ShowItemCountText(count) → sets ItemCountText string, shows/hides it
        b. ShowItemCountText calls LayoutPrimaryLine() again with final ItemCountText width
```

`LayoutPrimaryLine()` is the **universal layout entry point** — it is called from
`ShowText()` for all rows (link and non-link alike), and again from
`ShowItemCountText()` once the count text is known. On the first call, `ItemCountText`
is hidden so `primaryTextWidth = availableWidth` (full width). On the second call,
the actual count width is measured and `primaryTextWidth` shrinks accordingly.

This eliminates `extraWidth` pre-calculation entirely. `ItemCountText` width is
measured from the actual formatted string, not reconstructed from the raw number.
`ShowText` no longer needs to accept a pre-truncated link — it stores `rawPrimaryText`
and delegates layout to `LayoutPrimaryLine()`.

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

### 5.1 [RowText.xml](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowText.xml)

**Remove** `ItemCountText` from the `<Layers>` block — it becomes a programmatic child
of `PrimaryLineLayout` via `SetParent()` in `CreatePrimaryLineLayout()`.

`PrimaryLineLayout` is **created programmatically** in `RLF_RowTextMixin:CreatePrimaryLineLayout()`
called from `OnLoad`. No XML changes are needed to introduce the layout frame.

> **Decision (confirmed)**: Programmatic creation is preferred over XML for consistency
> with how `RowIconMixin` and other mixins work, and because it is easier to stub in
> busted unit specs without an XML parser.

### 5.2 [RowTextMixin.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua)

#### New: `CreatePrimaryLineLayout()`

```lua
function RLF_RowTextMixin:CreatePrimaryLineLayout()
    local layout = CreateFrame("Frame", nil, self)
    -- Both mixins are required: LayoutMixin provides Layout() / GetLayoutChildren();
    -- HorizontalLayoutMixin provides LayoutChildren() (the horizontal positioning logic).
    -- This mirrors the XML template: mixin="LayoutMixin, HorizontalLayoutMixin"
    -- See: Blizzard_SharedXML/LayoutFrame.xml (HorizontalLayoutFrame template)
    Mixin(layout, LayoutMixin, HorizontalLayoutMixin)
    layout.spacing = 0  -- set after icon size is known; see StyleText()

    -- PrimaryText moves from being a direct child of the row to being a child
    -- of the layout frame.
    self.PrimaryText:SetParent(layout)
    self.PrimaryText.layoutIndex = 1
    self.PrimaryText:SetWordWrap(false)   -- set once here, not in the hot path

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
- `self.PrimaryLineLayout:SetPoint(anchor, self.Icon, iconAnchor, xOffset, 0)` —
  the icon-relative anchor that was previously on `self.PrimaryText`

When `SecondaryText` is active, the vertical split anchors also move from
`PrimaryText` to `PrimaryLineLayout`:

```lua
-- was: self.PrimaryText:SetPoint("BOTTOM", self, "CENTER", 0, padding)
self.PrimaryLineLayout:SetPoint("BOTTOM", self, "CENTER", 0, padding)
```

The `SecondaryText:SetPoint("TOP", self, "CENTER", 0, -padding)` is unchanged
since `SecondaryText` is not a layout child.

#### Modified: `ShowText()`

Remove the current assumption that `text` is pre-truncated.
Rename param from `text` to `rawText`. Store `rawText` on `self` for use by
`LayoutPrimaryLine()`:

```lua
self.rawPrimaryText = rawText
self.PrimaryText:SetText(rawText)  -- initial render; LayoutPrimaryLine refines
```

Remove the existing `if self.link then self.ClickableButton:SetSize(...) end` block —
`LayoutPrimaryLine()` now owns button geometry.

At the end of `ShowText()`, call `self:LayoutPrimaryLine()`. This handles all
non-deferred rows (Money, XP, Reputation, etc.) that never reach `ShowItemCountText()`.
`ItemCountText` is hidden at this point so `primaryTextWidth = availableWidth`.

#### New: `LayoutPrimaryLine()`

Called from `ShowText()` immediately, and again from `ShowItemCountText()` once
the count string is set:

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
    self.PrimaryText:SetText(self.rawPrimaryText)
    -- SetWordWrap(false) is set once in CreatePrimaryLineLayout(), not here

    self.PrimaryLineLayout.fixedWidth = availableWidth
    self.PrimaryLineLayout:Layout()

    -- ClickableButton geometry is owned here, not in ShowText() or SetupTooltip()
    if self.link then
        self.ClickableButton:ClearAllPoints()
        self.ClickableButton:SetPoint("LEFT", self.PrimaryText, "LEFT")
        self.ClickableButton:SetSize(
            self.PrimaryText:GetStringWidth(),
            self.PrimaryText:GetStringHeight()
        )
    end
end
```

No truncation helper function is needed — the engine handles it.

`ClickableButton` geometry (anchor + size) is set **only** in `LayoutPrimaryLine()`. The
calls previously in `ShowText()` and `SetupTooltip()` are removed (see §5.2 and §5.5).
After `Layout()` the engine has applied truncation, so `GetStringWidth()` returns the
correct visible width.

#### Modified: `ShowItemCountText()`

After the existing `self.ItemCountText:Show()` / `self.ItemCountText:Hide()` logic,
call `self:LayoutPrimaryLine()` at the end. This is the second call for rows that
have a count (Items, Currency, Reputation levels, XP levels, Professions skill
changes) — it remeasures the count text and recalculates `primaryTextWidth`.

### 5.3 [LootDisplayRow.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootDisplayRow.lua)

#### Modified: `Populate()` (and `Update()`)

Remove:

- The entire `extraWidth` assembly block
- `G_RLF:TruncateItemLink(textFn(), extraWidth)` call

Change:

- `self.link = G_RLF:TruncateItemLink(textFn(), extraWidth)` →
  `self.link = textFn()` — store the full untruncated link directly
- `text = textFn(0, self.link)` — unchanged; `self.link` is now simply the
  untruncated link and is used as-is for the initial render

`self.link` keeps its existing name and role. Post-refactor it naturally holds the
full item link, which is exactly what [`SetupTooltip()`](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTooltipMixin.lua#L10)
(`GameTooltip:SetHyperlink(self.link)`) and `UpdateItemCount()` (`C_Item.GetItemInfo(self.link)`)
already expect. No rename, no new field, no callsite updates needed.

Display truncation is handled entirely by `LayoutPrimaryLine()` via
`PrimaryText:SetWidth()` + engine native truncation.

### 5.4 [LootDisplay.lua](../../RPGLootFeed/LootDisplay/LootDisplay.lua)

Remove (after confirming no other callers):

- [`G_RLF:TruncateItemLink(...)`](../../RPGLootFeed/LootDisplay/LootDisplay.lua#L504) function
- [`G_RLF:CalculateTextWidth(...)`](../../RPGLootFeed/LootDisplay/LootDisplay.lua#L481) function
- [`G_RLF.tempFontString`](../../RPGLootFeed/LootDisplay/LootDisplay.lua#L23) initialization

### 5.5 [RowTooltipMixin.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTooltipMixin.lua)

#### Modified: `SetupTooltip()`

Remove the three lines that position and size `ClickableButton`:

```lua
-- REMOVE these three lines:
self.ClickableButton:ClearAllPoints()
self.ClickableButton:SetPoint("LEFT", self.PrimaryText, "LEFT")
self.ClickableButton:SetSize(self.PrimaryText:GetStringWidth(), self.PrimaryText:GetStringHeight())
```

`LayoutPrimaryLine()` is called (from `ShowText()` / `ShowItemCountText()`) before
`SetupTooltip()` in the row lifecycle, so the button is already correctly sized when
`SetupTooltip()` runs. `SetupTooltip()` retains only the `self.ClickableButton:Show()`
call and all tooltip event handler registration.

### 5.6 No new utility file needed

Native FontString truncation via `SetWidth` + `SetWordWrap(false)` replaces all
custom truncation logic. No `Utils/TextLayout.lua` is required.

---

## 6. Invariants — What Does NOT Change in Step 1

| Thing                                               | Reason unchanged                                                                                                                |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `SecondaryText` anchoring                           | Not in scope; still anchored manually to Icon                                                                                   |
| `Icon` position logic (`RowIconMixin`)              | Unchanged                                                                                                                       |
| `leftAlign` config value and meaning                | Still drives anchor point; now also drives `childLayoutDirection`                                                               |
| `StyleText()` caching logic                         | Cache keys may need `childLayoutDirection` added; rest unchanged                                                                |
| `UpdateItemCount()` dispatch logic per feature type | Still calls `ShowItemCountText`                                                                                                 |
| All feature modules (`ItemLoot`, `Currency`, etc.)  | `textFn` contract unchanged — only callers in `LootDisplayRow` change                                                           |
| `SecondaryText` font styling                        | Unchanged                                                                                                                       |
| History mode / `LootDisplayFrame` data capture      | `PrimaryText:GetText()` returns the **full set text** (`rawPrimaryText`), not the visually truncated display — no change needed |

> **No database or configuration changes** are introduced in Step 1. This is a purely
> internal layout refactor — no migration script, no new config options, and no schema
> changes are required.

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
  - `PrimaryLineLayout.fixedWidth` is set to `availableWidth` in both cases
  - `PrimaryText:SetWordWrap` is **not** called in `LayoutPrimaryLine()` (it is set
    once in `CreatePrimaryLineLayout()`)

### 7.3 `LootDisplay/LootDisplayFrame/LootDisplayRow/LootDisplayRow_spec.lua`

- Assertions on `TruncateItemLink` being called should be removed.
- Assertions on `self.link` should verify it holds the **full untruncated** link
  (i.e. `textFn()` result directly, without pre-truncation).
- `extraWidth` assembly logic has no test coverage today — simply remove.

### 7.4 No truncation helper specs needed

Native truncation is engine behavior — not our code, not our test responsibility.
The `LayoutPrimaryLine` spec (section 7.2) covers that `SetWidth` is called with
the correct value and `fixedWidth` is set on the container; visual correctness is
validated in-game.

---

## 8. Open Questions / Risks

### 8.1 Is `HorizontalLayoutMixin` available without XML inheritance? ✅ Resolved

`HorizontalLayoutMixin` is a global table — verified in-game on **Retail, Classic Era
(Vanilla), Classic (Mists of Pandaria), and Classic (Burning Crusade Anniversary)**.
All clients pass all checks; no version-specific branching or shims are needed.

`HorizontalLayoutMixin` provides **only** `LayoutChildren()` — the horizontal-positioning
implementation. `Layout()`, `GetLayoutChildren()`, `CalculateFrameSize()` etc. live on
`LayoutMixin` (which is `CreateFromMixins(BaseLayoutMixin)`).

The correct programmatic setup (mirroring the XML `HorizontalLayoutFrame` template
which uses `mixin="LayoutMixin, HorizontalLayoutMixin"`) is:

```lua
Mixin(layout, LayoutMixin, HorizontalLayoutMixin)
```

Using only `Mixin(layout, HorizontalLayoutMixin)` results in `Layout` being nil at
call time — confirmed by in-game test. Both mixins are required. Both are globals
across all tested clients.

### 8.2 `FontString` as child of a `Frame` — does `SetParent` work correctly? ✅ Resolved

Verified in-game:

- `GetRegions()` returns both FontStrings (count = 2) ✅
- `Layout()` completes without error ✅
- `layoutIndex` order is respected (fs1 laid out left of fs2) ✅
- Hidden child (`fs2:Hide()`) is excluded from layout — `fs1.left` is unchanged, meaning `PrimaryText` correctly claims the full width when `ItemCountText` is hidden ✅

FontStrings created via `CreateFontString` are owned as regions by their parent frame and are correctly picked up by `GetLayoutChildren()` via `GetRegions()`. `layoutIndex` is honoured on regions, not only child Frames.

### 8.3 `ClickableButton` sizing after truncation ✅ Resolved

`ClickableButton:SetSize()` appeared in **two** places:

- [`ShowText()` line 382](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua#L382)
- [`SetupTooltip()` line 17](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTooltipMixin.lua#L17)

Both are removed. `LayoutPrimaryLine()` now exclusively owns `ClickableButton` geometry
(anchor + size), called after `Layout()` when `GetStringWidth()` reflects the final
truncated display width. See §5.2 (`ShowText()` modifications) and §5.5 for details.

### 8.4 History mode bypass ✅ Resolved — non-issue

`LootDisplayFrame` saves row data for history replay via:

```lua
rowText = row.PrimaryText:GetText()
```

This is **not affected** by native engine truncation. `FontString:GetText()` always
returns the exact string passed to `SetText()` — the WoW engine truncates the
**display rendering** (via `SetWidth` + `SetWordWrap(false)`) but does not mutate the
internally stored text value. Since `LayoutPrimaryLine()` calls
`self.PrimaryText:SetText(self.rawPrimaryText)`, `GetText()` continues to return the
full original text after layout, which is correct for history replay.

No `row.rawPrimaryText` field is needed in the history data struct.

### 8.5 `SetWordWrap(false)` is set once during frame setup

`SetWordWrap(false)` is called once in `CreatePrimaryLineLayout()` when `PrimaryText`
is re-parented, not in `LayoutPrimaryLine()` on every update. This is reflected in
the `CreatePrimaryLineLayout()` snippet in §5.2 and confirmed as resolved.

### 8.6 Double `RunNextFrame` causes a 2-frame flash for `ItemLoot` / `Professions`

For `ItemLoot` and `Professions`, the call chain is:

```
ShowText()                  → LayoutPrimaryLine()  (frame N: initial layout, full-width text)
  └─ RunNextFrame:
       UpdateItemCount()
         └─ RunNextFrame:
              ShowItemCountText()  → LayoutPrimaryLine()  (frame N+2: refined layout)
```

`ShowItemCountText()` fires **2 frames** after `ShowText()`. This means the row
displays for two frames with the text at full available width before the count
string is factored in and the final `PrimaryText` truncation is applied.

For most item names this is imperceptible, but for very long names in narrow feeds
the text may momentarily extend past its budget. This is a **known timing artefact**
of Step 1 — it is not introduced by this change (the single `RunNextFrame` in
`UpdateItemCount()` already causes a deferred update today), but the second nesting
makes it one frame later than it could be. Fix is deferred to a later step if the
flash is visually noticeable in testing.

---

## 9. Implementation Order

### Step 0 — In-Game Pre-Checks (before writing any layout code)

**0a. (Addresses §8.1 — Resolved)** Both `LayoutMixin` and `HorizontalLayoutMixin` are
confirmed globals. Use `Mixin(layout, LayoutMixin, HorizontalLayoutMixin)` — using only
`HorizontalLayoutMixin` leaves `Layout()` nil at runtime.

**0b. (Addresses §8.2 — Resolved)** FontStrings are picked up by `GetRegions()`,
`layoutIndex` ordering is honoured on regions, and hidden FontStrings are correctly
excluded from layout. All verified in-game.

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
