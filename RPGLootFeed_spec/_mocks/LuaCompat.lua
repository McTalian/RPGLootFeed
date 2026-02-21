--- Lua runtime compatibility shims for the test environment.
---
--- WoW runs on Lua 5.1, but the test runner (LuaJIT / Lua 5.2+) may be missing
--- a handful of Lua 5.1 globals or expose them under different names.  Require
--- this module once at the top of any spec that does NOT use the full nsMocks
--- framework (which previously pulled these in via WoWGlobals.Functions).

-- Lua 5.2+ moved `unpack` into the `table` namespace.
_G.unpack = _G.unpack or table.unpack

-- WoW exposes `format` as a global alias for `string.format`.
_G.format = _G.format or string.format
