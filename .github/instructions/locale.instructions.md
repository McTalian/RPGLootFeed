---
name: Locale File Conventions
description: Lua coding standards and WoW addon patterns for RPGLootFeed
applyTo: "RPGLootFeed/locale/*.lua"
---

# Locale File Conventions

This document outlines the conventions for locale files in the RPGLootFeed project. Locale files are used to store translations and localized strings for different languages.

## Immutability of Existing Keys

**Never move, rename, or delete existing keys in locale files.** The translations are organized into regions separated by release versions. If a key becomes obsolete, leave it in place — removal is handled separately. If a key is being _replaced_ by a new one (e.g., evolving a setting), add the new key in the current release region at the top but **do not remove the old key** from its original region.

## Adding New Keys

**Only modify `enUS.lua`** when adding new keys. After adding keys, run `make organize_translations` to generate commented-out placeholder entries in all other locale files. This ensures translators can easily identify new keys that need translation. **Never manually edit non-`enUS` locale files** to add new keys — the script handles that.

## Region and Ordering Rules

**New releases are at the top of the file.** When adding new keys, place them in a `--#region <version>` / `--#endregion` block corresponding to the "next" release version (the one currently being developed). This helps maintain a clear history of when keys were added. Usually new keys are added in feature releases (minor version bumps) rather than patch releases, but this is not a strict rule.

**Keys within each region are sorted alphabetically.** When adding multiple keys to a region, maintain alphabetical order to keep diffs clean and keys easy to find.

## Key Naming Conventions

- **UI-visible labels** use their display text as the key (e.g., `L["Row Text Spacing"]`).
- **Description/help text** keys append `Desc` to a PascalCase identifier derived from the label (e.g., `L["RowTextSpacingDesc"]`).
- Keep key names in English regardless of the locale file.

## String Quoting

**Always use double quotes (`"`) for both keys and values.** The translation check scripts (`make missing_translation_check`, `make organize_translations`, `make missing_locale_key_check`) rely on pattern matching that expects double-quoted strings. Using single quotes or other delimiters will cause keys to be missed or misidentified by these tools.

## Non-`enUS` Locale File Structure

- Non-`enUS` locale files begin with `--@strip-comments@` (a build-tool directive to strip comments in packaged releases).
- Untranslated keys appear as commented-out lines prefixed with `-- ` (e.g., `-- L["Key"] = "English fallback"`).
- Translators uncomment and replace the English text with the translated value.
- The region structure (`--#region` / `--#endregion`) mirrors `enUS.lua` exactly — do not alter it manually.

## `main.lua`

`main.lua` simply calls `GetLocale()` to load the resolved locale table into `G_RLF.L`. It should not contain any key definitions and generally does not need to be modified.
