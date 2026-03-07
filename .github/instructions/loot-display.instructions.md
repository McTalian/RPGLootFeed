---
name: LootDisplay — UI & Animation Reference
description: Frame APIs, LibSharedMedia, animations, and row pooling patterns for the LootDisplay module
applyTo: "RPGLootFeed/LootDisplay/**/*.lua"
---

# LootDisplay UI & Animation Reference

## Frame APIs

```lua
-- Create frame
local frame = CreateFrame("Frame", "MyFrameName", UIParent)
frame:SetSize(width, height)
frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)
frame:SetFrameStrata("MEDIUM")

-- Font string
local text = frame:CreateFontString(nil, "OVERLAY")
text:SetFont(fontPath, fontSize, fontFlags)
text:SetTextColor(r, g, b, a)
text:SetText("Display Text")

-- Texture
local texture = frame:CreateTexture(nil, "BACKGROUND")
texture:SetTexture(texturePath)
texture:SetAllPoints(frame)
```

## LibSharedMedia

```lua
local LSM = LibStub("LibSharedMedia-3.0")

-- Register custom media
LSM:Register(LSM.MediaType.FONT, "MyFont", "Interface/AddOns/RPGLootFeed/Fonts/font.ttf")
LSM:Register(LSM.MediaType.SOUND, "LootSound", "Interface/AddOns/RPGLootFeed/Sounds/sound.ogg")

-- Fetch registered media
local fontPath = LSM:Fetch(LSM.MediaType.FONT, "Arial Narrow")
local soundPath = LSM:Fetch(LSM.MediaType.SOUND, "LootSound")
PlaySoundFile(soundPath, "Master")
```

## Animation Patterns

```lua
-- Create animation group on a frame
local animGroup = frame:CreateAnimationGroup()

-- Fade out
local fadeOut = animGroup:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1.0)
fadeOut:SetToAlpha(0.0)
fadeOut:SetDuration(0.5)
fadeOut:SetStartDelay(3.0)

-- Slide out
local slideOut = animGroup:CreateAnimation("Translation")
slideOut:SetOffset(100, 0)
slideOut:SetDuration(0.5)

animGroup:Play()
animGroup:SetScript("OnFinished", function()
  -- Cleanup after animation completes
end)
```

## Row Pooling

Rows are pooled and reused to avoid frame create/destroy overhead on every loot event:

```lua
-- Get row from pool or create new
local function GetRow()
  if #rowPool > 0 then
    return table.remove(rowPool)
  else
    return CreateNewRow()
  end
end

-- Return row to pool when done
local function ReleaseRow(row)
  row:Hide()
  row:ClearAllPoints()
  table.insert(rowPool, row)
end
```

## Performance

- Never create or destroy row frames per loot event — always pool them
- Throttle animations in high-frequency situations (raids)
- Cache `G_RLF.db.global` subkeys to avoid repeated table traversal during render
