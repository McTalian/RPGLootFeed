# Future: Global Appearance Defaults

## Context

This document captures a deferred feature for the multi-frame system. It was
discussed during the Phase 4 design review (2026-03-09) and intentionally
excluded from the initial multi-frame implementation to keep scope manageable.

## Problem

When a user has multiple frames, they may want most frames to share the same
styling/sizing/animation settings, with only one or two frames diverging.
Currently, each frame's appearance settings are fully independent — changing
the font in one frame doesn't affect any others. This means users who want
consistency must manually replicate changes across frames.

## Proposed Solution

Introduce a **global appearance defaults** layer that frames inherit from
unless explicitly overridden.

### DB Schema Additions

```lua
db.global.appearanceDefaults = {
    styling = { font = "Friz Quadrata TT", … },
    animations = { enterAnimation = "FADE", … },
    sizing = { feedWidth = 200, maxRows = 10, … },
    -- positioning excluded (inherently per-frame, except possibly strata)
}

-- Per-frame, each section gets an override flag:
db.global.frames[1].styling.useGlobalDefaults = true  -- true = inherited
db.global.frames[1].animations.useGlobalDefaults = true
db.global.frames[1].sizing.useGlobalDefaults = true
```

### Accessor Behavior

`DbAccessor:Styling(frameId)` would check `useGlobalDefaults`:

- If true → return `db.global.appearanceDefaults.styling`
- If false → return `db.global.frames[frameId].styling`

Writes while `useGlobalDefaults = true` could either:

- **Block**: Disable editing UI unless the override checkbox is checked
- **Auto-switch**: Automatically set `useGlobalDefaults = false` and copy
  globals into the frame-local table on first edit

Blocking is simpler and clearer to the user.

### Config UI

Each frame's Styling/Sizing/Animations tab would include:

- **"Use Global Defaults" checkbox** — when checked, the settings below are
  disabled/greyed out and values come from the global defaults
- **"Copy from Global" button** — populates the frame-local values from
  current global defaults (useful when switching from global to override)

The Global section in the top-level select dropdown would include:

- **Appearance Defaults** tab with the shared settings
- **"Apply to All Frames" button** — overwrites appearance in all frames
  that have `useGlobalDefaults = true` (or optionally all frames)

### Positioning Consideration

Positioning is inherently per-frame (each frame must be placed differently).
The exception might be **frame strata** and **frame level**, which a user
might reasonably want consistent across frames. This could be handled with
a separate `useGlobalStrata` flag or simply left per-frame.

## Why Deferred

1. The multi-frame feature is already a large schema change. Layering
   inheritance on top increases migration complexity and bug risk.
2. The current "copy appearance from Main on new frame creation" pattern
   covers the 80% case.
3. This feature can be added non-destructively later — adding
   `useGlobalDefaults` flags and a `appearanceDefaults` table requires
   only an additive migration (populate defaults from frame 1's values).
4. User feedback will clarify whether this is actually needed vs.
   nice-to-have.

## Migration Strategy

When implemented, a new migration (v9 or later) would:

1. Deep-copy `frames[1].styling/animations/sizing` into
   `db.global.appearanceDefaults`
2. Set `useGlobalDefaults = true` on all existing frames (preserving current
   behavior since all frames currently start as copies of Main)

## Dependencies

- Multi-frame feature must be stable first (Phase A complete)
- Per-frame `DbAccessor` pattern must be established
