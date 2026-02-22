# Row Layout Redesign

This document captures the design discussion and incremental plan for migrating the
row frame layout to use Blizzard's `HorizontalLayoutMixin` system. It serves as a
reference as we work through the changes incrementally.

## Background: Why Change?

### Current truncation is fragile

The legacy `TruncateItemLink` function (and the approach it represents) has several
problems:

- **O(n) character loop**: progressively strips characters one at a time until the
  text fits, recalculating width on every iteration.
- **Side-channel `tempFontString`**: width is measured by setting text on a hidden
  `FontString` created just for sizing — a brittle workaround.
- **Magic width math**: `maxWidth = feedWidth - (iconSize/4) - iconSize - (iconSize/4) - extraWidth` — the constants are guesses that break when config changes.
- **Locale-unsafe**: characters are stripped by byte index (`string.sub`), which
  corrupts multi-byte UTF-8 sequences common in non-Latin locales (Korean, Chinese,
  Russian item names).
- **Link-structure assumption**: the function parses `[ItemName]` out of a hyperlink
  string and reassembles it — any link format variation breaks it.

Blizzard's `FontStringMixin:Truncate(width, text)` (in
`Interface/AddOns/Blizzard_FrameXML/FontString.lua`) does a **binary search** over
the string and uses `GetUnboundedStringWidth()` after each `SetText`, which is both
faster and byte-safe.

However, **the WoW engine itself handles truncation natively** when both conditions
are met: `FontString:SetWidth(w)` plus `FontString:SetWordWrap(false)`. The engine
auto-renders `"..."` and `FontString:IsTruncated()` returns `true`. No helper
function of any kind is needed. `FontStringMixin:Truncate` and our own binary search
are both unnecessary.

### Current left/right text model can't express centering

The current `primaryTextFrame` uses two `FontString`s — one anchored `LEFT` and one
anchored `RIGHT` — both spanning the **full text width**. This means:

- You cannot center content without rethinking the anchor model entirely.
- The amount (`rightText`) and item name (`leftText`) overlap in the middle when
  both are long — the engine just clips them.
- There's no way to know how much space the amount occupies to constrain the name.

---

## Blizzard's HorizontalLayout System

**Source**: `wow-ui-source/AddOns/Blizzard_FrameXML/LayoutFrame.lua`

```lua
HorizontalLayoutMixin = CreateFromMixins(LayoutMixin)

function HorizontalLayoutMixin:LayoutChildren(children)
    -- Iterates children left-to-right via ipairs(children)
    -- Calls child:ClearAllPoints() and child:SetPoint("TOPLEFT", self, x, y)
    -- x advances by childWidth + spacing after each child
    -- Returns total width and max child height
end
```

Key variants:

| Template                                | Mixin(s)                                     | Behavior                                                      |
| --------------------------------------- | -------------------------------------------- | ------------------------------------------------------------- |
| `HorizontalLayoutFrameTemplate`         | `HorizontalLayoutMixin`                      | Fixed size — you set width/height; children lay out within it |
| `ResizingHorizontalLayoutFrameTemplate` | `ResizingLayoutMixin, HorizontalLayoutMixin` | Shrink-wraps to its children's natural width                  |

`ResizingLayoutMixin` overrides `GetFixedSize()` to return `nil, nil`, so the
container reports its own size as the sum of its children.

`LayoutMixin:Layout()` is what triggers the layout pass — it must be called manually
after adding/changing children or their sizes.

`GetLayoutChildren()` defaults to `self:GetChildren()` (creation order). It can be
overridden to return children in a different order — important for icon
left/right placement (see below).

### FontStringMixin:Truncate

**Source**: `wow-ui-source/AddOns/Blizzard_FrameXML/FontString.lua`

```lua
function FontStringMixin:Truncate(width, text)
    -- Binary search: finds longest prefix that fits within `width`
    -- Uses GetUnboundedStringWidth() for measurement — byte-safe
    -- Appends self.textTruncationString (default "...")
    -- Sets self.truncated = true if truncation occurred
end
```

This replaces all of our hand-rolled truncation. Requires the `FontString` to have
`FontStringMixin` mixed in:

```lua
Mixin(myFontString, FontStringMixin)
```

---

## Target Row Structure (Full Vision)

This is the end-state we are designing toward, documented here so incremental steps
stay coherent. We are **not** building all of this at once.

```
RowFrame  (fixed: feedWidth × rowHeight — not a layout frame)
└── OuterLayout  (ResizingHorizontalLayout, anchored by alignment config)
        ├── IconContainer     (fixed: iconSize × iconSize, shown/hidden)
        └── TextArea          (fixed height; width = feedWidth − iconOffset)
                ├── PrimaryLineLayout   (ResizingHorizontalLayout, anchored TOPLEFT)
                │       ├── nameText    (FontString — truncatable, takes remaining width)
                │       └── amountText  (FontString — natural/intrinsic width)
                └── SecondaryLineLayout (ResizingHorizontalLayout, anchored BOTTOMLEFT)
                        ├── sourceText  (FontString — natural width)
                        └── ...future slots
```

### Alignment (LEFT / CENTER / RIGHT)

`OuterLayout` uses `ResizingHorizontalLayout` so it shrink-wraps to content.
Alignment is a single anchor change on `OuterLayout` inside `RowFrame`:

```lua
-- LEFT (default):
outerLayout:SetPoint("LEFT", rowFrame, "LEFT")
-- CENTER:
outerLayout:SetPoint("CENTER", rowFrame, "CENTER")
-- RIGHT:
outerLayout:SetPoint("RIGHT", rowFrame, "RIGHT")
```

### Icon Position (LEFT / RIGHT)

Since `HorizontalLayoutMixin` iterates children in order, icon position is child
order. Override `GetLayoutChildren()` to return children in configured order without
recreating frames:

```lua
outerLayout.GetLayoutChildren = function(self)
    if ns.db.profile.iconPosition == ns.IconPosition.RIGHT then
        return self.textArea, self.iconContainer
    end
    return self.iconContainer, self.textArea  -- default LEFT
end
```

This preserves the current behavior where the text column always builds _outward from
the icon_.

### Width Budget for nameText

`OuterLayout` and `PrimaryLineLayout` are both resizing — they don't know their own
width until after `Layout()` runs. But `nameText` needs a fixed width to truncate
against, so a pre-calculation is needed:

```lua
local textAreaWidth = feedWidth - iconWidthOffset
local amountWidth = amountText:GetUnboundedStringWidth()  -- natural width of "x99"
local nameWidth = textAreaWidth - amountWidth - spacing
nameText:SetWidth(nameWidth)
FontStringMixin.Truncate(nameText, nameWidth, itemName)
```

`TextArea` gets `fixedWidth = textAreaWidth` so `PrimaryLineLayout` can use it as a
known boundary.

---

## Axes of Configuration (Future)

Once the layout system is in place, these are the config dimensions we anticipate:

| Setting           | Values                    | Drives                                                                   |
| ----------------- | ------------------------- | ------------------------------------------------------------------------ |
| `textAlignment`   | `LEFT`, `CENTER`, `RIGHT` | Anchor point of `OuterLayout` in `RowFrame`                              |
| `iconPosition`    | `LEFT`, `RIGHT`           | `childLayoutDirection` on `OuterLayout`                                  |
| `iconEnabled`     | bool                      | `IconContainer` shown/hidden; width = 0 when hidden                      |
| `showAmount`      | bool                      | `ItemCountText` shown/hidden in `PrimaryLineLayout`                      |
| `showSource`      | bool                      | `sourceText` shown/hidden in `SecondaryLineLayout`                       |
| `primaryTextMode` | `TRUNCATE`, `SHRINK`      | `SetWordWrap(false)` + engine truncation vs `AutoScalingFontStringMixin` |

The existing `amountPosition` (`TOP_LEFT`, `TOP_RIGHT`, `BOTTOM_LEFT`, `BOTTOM_RIGHT`)
concept maps onto _which line layout_ the amount child lives in, and its position
within that line (left vs right = child order). This can be revisited when we tackle
the secondary line.

---

## Incremental Plan

### Step 1 — Primary Line HorizontalLayout + Native Truncation (do this next)

**Scope**: `primaryTextFrame` only. Leave `secondaryTextFrame`, icon, outer alignment,
and outer `HorizontalLayoutMixin` for later steps.

**What changes**:

1. Introduce a `PrimaryLineLayout` frame with `HorizontalLayoutMixin` holding
   `PrimaryText` and `ItemCountText` as separate children with `layoutIndex` values.
2. Anchor `PrimaryLineLayout` to `Icon` (same logic currently on `PrimaryText`).
3. Set `PrimaryText:SetWordWrap(false)` once during setup — enables native truncation.
4. `PrimaryText:SetWidth(availableWidth - itemCountWidth - spacing)` in a deferred
   `LayoutPrimaryLine()` step; the engine renders `"..."` automatically.
5. For `leftAlign = false`, set `PrimaryLineLayout.childLayoutDirection = "rightToLeft"`
   instead of manually re-anchoring `ItemCountText`.
6. Delete `TruncateItemLink`, `CalculateTextWidth`, and `tempFontString` once confirmed.
7. Bonus: use `PrimaryText:IsTruncated()` in `RowTooltipMixin` to show the full
   item name in the tooltip when truncated — a free UX improvement.

### Step 2 — Secondary Line HorizontalLayout

Apply the same pattern to `secondaryTextFrame`: replace left/right `FontString`s with
a `ResizingHorizontalLayout` containing `sourceText` (and future slots).

### Step 3 — Outer Layout + Alignment Config

Introduce `OuterLayout` as a `ResizingHorizontalLayout` wrapping icon + text area.
Add `textAlignment` config option (`LEFT` default). Wire the single anchor change.

### Step 4 — Icon Position Config

Add `iconPosition` config (`LEFT` default). Implement the `GetLayoutChildren()`
override on `OuterLayout`.

---

## Open Questions

- **`amountPosition` refactor**: Currently `TOP_LEFT`/`TOP_RIGHT` puts the amount in
  the primary line at different child-order positions; `BOTTOM_*` moves it to the
  secondary line. With named layout children this becomes explicit slot assignment
  rather than string enum branching. Decide how to model this in Step 1 or 2.
- **Secondary line per-line alignment**: Should the secondary text line have its own
  independent alignment, or always inherit from the outer alignment? Likely inherit
  for now.
- **`fixedWidth` vs manual `SetWidth`**: Confirm whether setting `frame.fixedWidth`
  and calling `Layout()` is sufficient, or whether `SetWidth` still needs to be called
  explicitly on `TextArea`.
- **Pool reconstruction on alignment/icon-position change**: These are `rebuild()`
  config changes (not `refreshFeed()`), so full frame pool teardown is acceptable.
  Confirm this assumption holds.
