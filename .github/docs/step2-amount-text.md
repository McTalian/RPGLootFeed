# Step 2 Implementation Plan: AmountText FontString Separation

Separates the `" x2"` quantity suffix out of `PrimaryText` into its own
non-truncatable `AmountText` FontString as the second layout child of
`PrimaryLineLayout` (shifting `ItemCountText` to `layoutIndex=3`).

See [row-layout-redesign.md](row-layout-redesign.md) for the full design vision and
[step1-primary-line-layout.md](step1-primary-line-layout.md) for Step 1 context.

---

## 1. Current State (post-Step 1)

`PrimaryLineLayout` has two layout children:

| `layoutIndex` | FontString      | Role                                 |
| ------------- | --------------- | ------------------------------------ |
| 1             | `PrimaryText`   | Item link + quantity suffix (`"x2"`) |
| 2             | `ItemCountText` | Bag count / skill delta / rep level  |

`textFn(existingQuantity, link)` returns the concatenated string
`"[Item Name] x2"`. `PrimaryText` holds both the link text and the suffix.

### Problem

`PrimaryText` truncates under `SetWidth + SetWordWrap(false)`. When truncation
fires, the `"..."` ellipsis may swallow or misplace the quantity suffix, producing
`"[Very Long Item N... x2"` or even `"[Very Long Item Nam..."` with the suffix
lost entirely depending on budget math order.

---

## 2. Goal

| `layoutIndex` | FontString      | Role                    | Truncatable? |
| ------------- | --------------- | ----------------------- | ------------ |
| 1             | `PrimaryText`   | Item link only          | Yes          |
| 2             | `AmountText`    | `"x2"` suffix           | No           |
| 3             | `ItemCountText` | Bag count / skill / rep | No           |

`PrimaryText` is always truncatable and only ever contains the item link.
`AmountText` is a fixed-width label that the layout engine positions after
`PrimaryText` without ever clipping it.

---

## 3. New `element.amountTextFn` Field

A new **optional** field added to elements that produce a quantity suffix.
Features that do **not** produce a suffix leave this field `nil` — `AmountText`
stays hidden on their rows.

### Contract

```lua
-- Returns the formatted suffix string, or "" to hide AmountText.
-- existingQuantity: the row's current accumulated quantity (same arg as textFn).
element.amountTextFn = function(existingQuantity)
    local effectiveQuantity = (existingQuantity or 0) + element.quantity
    if effectiveQuantity == 1 and not G_RLF.db.global.misc.showOneQuantity then
        return ""
    end
    return "x" .. effectiveQuantity
end
```

**No leading space.** `PrimaryLineLayout.spacing` (= `iconSize/4`) already inserts
a pixel gap between adjacent layout children. A baked-in `" "` would double the
visual gap.

### Features that get `amountTextFn`

| Feature         | Has quantity suffix? | Change required                                |
| --------------- | -------------------- | ---------------------------------------------- |
| `ItemLoot`      | Yes (`"x2"`)         | Add `amountTextFn`; strip suffix from `textFn` |
| `PartyLoot`     | Yes (`"x2"`)         | Add `amountTextFn`; strip suffix from `textFn` |
| `Currency`      | Yes (`"x2"`)         | Add `amountTextFn`; strip suffix from `textFn` |
| `Transmog`      | No                   | No change                                      |
| `Professions`   | No                   | No change                                      |
| `Experience`    | No                   | No change                                      |
| `Reputation`    | No                   | No change                                      |
| `Money`         | No                   | No change                                      |
| `TravelPoints`  | No                   | No change                                      |
| `Notifications` | No                   | No change                                      |

### `textFn` after the change (ItemLoot example)

```lua
element.textFn = function(existingQuantity, truncatedLink)
    if not truncatedLink then
        return itemLink   -- zero-arg path: return raw link (unchanged)
    end
    -- Now returns only the link, no suffix
    local text = truncatedLink
    if element.isQuestItem and G_RLF.db.global.item.textStyleOverrides.quest.enabled then
        local r, g, b, a = unpack(G_RLF.db.global.item.textStyleOverrides.quest.color)
        text = text:gsub("|c.-|", RGBAToHexFormat(r, g, b, a) .. "|")
    end
    return text
end

element.amountTextFn = function(existingQuantity)
    local effectiveQuantity = (existingQuantity or 0) + element.quantity
    if effectiveQuantity == 1 and not G_RLF.db.global.misc.showOneQuantity then
        return ""
    end
    return "x" .. effectiveQuantity
end
```

---

## 4. `CreatePrimaryLineLayout()` Changes

```lua
function RLF_RowTextMixin:CreatePrimaryLineLayout()
    local layout = CreateFrame("Frame", nil, self)
    Mixin(layout, LayoutMixin, HorizontalLayoutMixin)
    layout.spacing = 0   -- updated in StyleText()

    self.PrimaryText:SetParent(layout)
    self.PrimaryText.layoutIndex = 1
    self.PrimaryText:SetWordWrap(false)

    -- NEW: AmountText — quantity suffix, non-truncatable, initially hidden.
    local amountText = layout:CreateFontString(nil, "OVERLAY")
    amountText.layoutIndex = 2
    amountText:SetWordWrap(false)
    amountText:Hide()
    self.AmountText = amountText

    -- ItemCountText shifts from layoutIndex=2 → layoutIndex=3.
    self.ItemCountText:SetParent(layout)
    self.ItemCountText.layoutIndex = 3

    self.PrimaryLineLayout = layout
end
```

`AmountText` is created programmatically (consistent with `PrimaryLineLayout` itself;
avoids XML parser dependency in unit tests).

---

## 5. `StyleText()` Changes

In the `fontChanged` block, apply the same font to `AmountText` as to `PrimaryText`
and `ItemCountText`:

```lua
-- In the useFontObjects branch:
self.AmountText:SetFontObject(font)

-- In the fontFace branch (ApplyFontStyle):
ApplyFontStyle(self.AmountText, fontPath, fontSize, fontFlagsString,
               fontShadowColor, fontShadowOffsetX, fontShadowOffsetY)
```

---

## 6. New `ShowAmountText(amountText, r, g, b, a)` Method

```lua
--- Show or hide the AmountText (quantity suffix) FontString.
--- @param amountText string|nil  The formatted suffix (e.g. "x2"), or "" / nil to hide.
--- @param r number  Red channel — matches the PrimaryText color.
--- @param g number  Green channel.
--- @param b number  Blue channel.
--- @param a number  Alpha channel.
function RLF_RowTextMixin:ShowAmountText(amountText, r, g, b, a)
    if amountText and amountText ~= "" then
        self.AmountText:SetText(amountText)
        self.AmountText:SetTextColor(r, g, b, a)
        self.AmountText:Show()
    else
        self.AmountText:Hide()
    end
end
```

**Color**: `AmountText` uses the same `r, g, b, a` passed to `ShowText` so it
visually matches the primary text. This means quest-colored items get a
quest-colored suffix, negative amounts get red, etc. A separate configurable color
for `AmountText` is not planned at this time.

---

## 7. `LayoutPrimaryLine()` Budget Math Changes

`AmountText` is now a third non-truncatable region that consumes horizontal budget
before `PrimaryText` gets its share:

```lua
-- Existing: subtract ItemCountText width
local itemCountWidth = 0
if self.ItemCountText:IsShown() then
    itemCountWidth = self.ItemCountText:GetUnboundedStringWidth()
        + self.PrimaryLineLayout.spacing
end

-- NEW: subtract AmountText width
local amountTextWidth = 0
if self.AmountText:IsShown() then
    amountTextWidth = self.AmountText:GetUnboundedStringWidth()
        + self.PrimaryLineLayout.spacing
end

local maxPrimaryWidth = math.max(1, availableWidth - amountTextWidth - itemCountWidth)
local naturalWidth = self.PrimaryText:GetUnboundedStringWidth()
local primaryTextWidth = math.min(naturalWidth, maxPrimaryWidth)
self.PrimaryText:SetWidth(primaryTextWidth)
```

`AmountText` has no `SetWidth` call — it is never truncated.

---

## 8. `ShowText()` Changes

`ShowText` currently ignores `AmountText`. It still does — `ShowAmountText` is
called separately by the `BootstrapFromElement`/`UpdateQuantity` orchestrators. No
change to `ShowText` itself is needed.

**Rationale**: `ShowText` doesn't know whether the current row has a quantity suffix
(that lives in the element, not the row config). Keeping the concern in the
orchestrator preserves the existing pattern.

---

## 9. `BootstrapFromElement()` Changes

```lua
-- Store the function so UpdateQuantity can call it later without the element.
self.amountTextFn = element.amountTextFn

if isLink then
    self.link = textFn()
    text = textFn(0, self.link)
    self:SetupTooltip()
else
    text = textFn()
end

-- ... (existing icon / secondary text / styles / ShowText calls) ...

self:ShowText(text, r, g, b, a)

-- NEW: show the amount suffix alongside the initial text.
local amountText = self.amountTextFn and self.amountTextFn(0) or ""
self:ShowAmountText(amountText, r, g, b, a)
```

`ShowAmountText` must be called **after** `ShowText` (which calls `LayoutPrimaryLine`
on the first pass). `ShowAmountText` changes `AmountText` visibility, which affects
the budget. A second `LayoutPrimaryLine` call is needed — add it at the end of
`ShowAmountText` (see §6 above), or have `ShowAmountText` call it directly.

> **Decision needed**: Should `ShowAmountText` call `LayoutPrimaryLine()` itself
> (keeping `ShowText`'s pattern), or should `BootstrapFromElement` call it
> explicitly after both `ShowText` and `ShowAmountText`?
>
> **Proposed**: `ShowAmountText` calls `self:LayoutPrimaryLine()` at the end —
> mirrors `ShowItemCountText`'s pattern exactly.

---

## 10. `UpdateQuantity()` Changes

```lua
-- Existing: update text and amount
local text = element.textFn(self.amount, self.link)
self.amount = self.amount + element.quantity
-- ...
self:ShowText(text, r, g, b, a)

-- NEW: update the suffix for the new accumulated amount.
local amountText = element.amountTextFn and element.amountTextFn(self.amount) or ""
self:ShowAmountText(amountText, r, g, b, a)
```

Note `self.amount` is already updated before the `ShowAmountText` call, so
`element.amountTextFn(self.amount)` correctly reflects the new total.

`element.amountTextFn` is used directly (rather than `self.amountTextFn`) because
the element is in scope. Either would work — the closure captures `element` by
reference and `element.quantity` is the delta for this update. The `self.amountTextFn`
stored at bootstrap time is the same closure.

---

## 11. `Reset()` Changes

```lua
self.AmountText:SetText(nil)
self.AmountText:Hide()
self.amountTextFn = nil
```

---

## 12. History Mode (`UpdateWithHistoryData`)

**No change for now.** History rows store `data.rowText` which was set at bootstrap
time. Under the new code `data.rowText` will be the link-only string (no suffix).
The `x2` suffix will simply not appear in history. This is acceptable — history mode
is a read-only replay and the row still identifies the item and its link correctly.

If full-fidelity history display is desired in the future, `data.amountText` can be
added to the history record and displayed via a `ShowAmountText` call in
`UpdateWithHistoryData`. That is out of scope here.

---

## 13. Mocks (`LootDisplayRowFrame.lua`)

Add `AmountText` alongside `PrimaryText` and `ItemCountText` in `M.new()`:

```lua
row.AmountText = mockFontString()
```

No other mock changes required. `mockFontString()` already provides all the stubs
`ShowAmountText` and `LayoutPrimaryLine` need (`SetText`, `SetTextColor`,
`Show`, `Hide`, `IsShown`, `GetUnboundedStringWidth`).

---

## 14. Specs (`RowTextMixin_spec.lua`)

### `CreatePrimaryLineLayout` / load-order block

Add `ShowAmountText` to the exposed-functions assertion.

### `StyleText` block

Assert `AmountText.SetFont` (and `AmountText.SetFontObject`) is called in the same
font-changed cases as `PrimaryText` and `ItemCountText`.

### New `ShowAmountText` describe block

```
ShowAmountText
  shows AmountText and sets text when amountText is non-empty
  hides AmountText when amountText is an empty string
  hides AmountText when amountText is nil
  sets text color matching the provided r/g/b/a
  calls LayoutPrimaryLine after visibility change
```

### `LayoutPrimaryLine` block — new cases

```
when AmountText is shown
  subtracts AmountText width + spacing from primaryText budget
  PrimaryText width still capped at maxPrimaryWidth when both AmountText and ItemCountText shown
when AmountText is hidden
  AmountText width does not affect primaryText budget (same as before)
```

---

## 15. Decisions

1. **`AmountText` color**: Use the same `r, g, b, a` as `PrimaryText`.
   Quest-colored items → quest-colored suffix. Negative amounts → red suffix.
   No separate DB setting.

2. **`AmountText` in XML vs programmatic**: Programmatic in
   `CreatePrimaryLineLayout()`, consistent with the rest of Step 1.

3. **`ShowAmountText` calls `LayoutPrimaryLine`?**: ✅ Yes — mirrors
   `ShowItemCountText` exactly. `ShowAmountText` is responsible for triggering
   re-layout after it changes `AmountText` visibility.

4. **`UpdateQuantity` uses `element.amountTextFn` or `self.amountTextFn`?**: ✅
   Use `element.amountTextFn` directly in `UpdateQuantity` (element is in scope).
   `self.amountTextFn` is stored at bootstrap time for any future path that needs
   to refresh without the element in scope.
