--- Stage 1 – AceConfig serializer with function evaluation
---
--- Walks G_RLF.options recursively and produces a JSON string.
--- All non-function field values are serialized directly (locale strings are
--- already resolved at config-load time and appear as plain strings here).
---
--- For evaluable functions:
---   get/hidden/disabled  – called via pcall with {} as the info arg;
---                          result stored in _value, _dynamic=true added.
---                          String method-refs are dispatched on node.handler.
---   values               – called via pcall with no args; result stored in
---                          _resolved, _dynamic=true always added.
---   set/func             – NOT called; recorded as {_type="function"}.
---
--- Designed to be loaded with loadfile() from dump_options.lua:
---   local serializer = assert(loadfile(".scripts/aceconfig_serializer.lua"))()

local M = {}

-- ---------------------------------------------------------------------------
-- Minimal JSON encoder
-- ---------------------------------------------------------------------------

local jsonEncode -- forward declaration

local function jsonString(s)
	s = tostring(s)
	return '"'
		.. s:gsub("\\", "\\\\")
			:gsub('"', '\\"')
			:gsub("\n", "\\n")
			:gsub("\r", "\\r")
			:gsub("\t", "\\t")
			:gsub("[%z\1-\31]", function(c)
				return ("\\u%04x"):format(c:byte())
			end)
		.. '"'
end

--- True when t is a non-empty sequential integer-keyed array (1..#t, no gaps).
local function isSequentialArray(t)
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
			return false
		end
		n = n + 1
	end
	return n > 0 and n == #t
end

local function jsonEncodeTable(t, indent, seen)
	if seen[t] then
		return '"[circular]"'
	end
	seen[t] = true

	local ni = indent .. "  "

	-- Encode as JSON array only for clean sequential integer keys
	if isSequentialArray(t) then
		local items = {}
		for i, v in ipairs(t) do
			items[i] = ni .. jsonEncode(v, ni, seen)
		end
		seen[t] = nil
		if #items == 0 then
			return "[]"
		end
		return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "]"
	end

	-- Encode as JSON object; sort keys for deterministic output
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local items = {}
	for _, k in ipairs(keys) do
		items[#items + 1] = ni .. jsonString(tostring(k)) .. ": " .. jsonEncode(t[k], ni, seen)
	end
	seen[t] = nil
	if #items == 0 then
		return "{}"
	end
	return "{\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "}"
end

jsonEncode = function(val, indent, seen)
	indent = indent or ""
	seen = seen or {}
	local t = type(val)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return val and "true" or "false"
	elseif t == "number" then
		if val ~= val then
			return '"NaN"'
		end
		if val == math.huge then
			return '"Infinity"'
		end
		if val == -math.huge then
			return '"-Infinity"'
		end
		-- Emit integers without a decimal point
		if val == math.floor(val) and math.abs(val) < 1e15 then
			return string.format("%.0f", val)
		end
		return tostring(val)
	elseif t == "string" then
		return jsonString(val)
	elseif t == "table" then
		return jsonEncodeTable(val, indent, seen)
	else
		-- function, userdata, thread → safe placeholder
		return '"[' .. t .. ']"'
	end
end

-- ---------------------------------------------------------------------------
-- AceConfig node walker
-- ---------------------------------------------------------------------------

--- Fields we copy verbatim (or handle with special logic for functions/args).
--- Order drives the iteration so that "type" always appears first in output.
local KNOWN_KEYS = {
	"type",
	"name",
	"desc",
	"order",
	"width",
	"inline",
	"guiInline",
	"childGroups",
	"args",
	"values",
	"sorting",
	"get",
	"set",
	"func",
	"hidden",
	"disabled",
	"min",
	"max",
	"step",
	"bigStep",
	"softMin",
	"softMax",
	"isPercent",
	"multiline",
	"dialogControl",
	"confirm",
	"validate",
	"image",
	"imageCoords",
	"imageWidth",
	"imageHeight",
	"fontSize",
	"descStyle",
	"tristate",
	"hasAlpha",
	"style",
	"icon",
	"iconCoords",
	"arg",
}

local IS_KNOWN = {}
for _, k in ipairs(KNOWN_KEYS) do
	IS_KNOWN[k] = true
end

-- Mark a field as a non-evaluable function placeholder (set/func)
local FUNC_PLACEHOLDER = { _type = "function" }

-- ---------------------------------------------------------------------------
-- Function evaluation helpers
-- ---------------------------------------------------------------------------

--- Attempt to evaluate a function or string method ref for get/hidden/disabled.
--- @param val        any     The field value (function or string).
--- @param handler    table|nil  The node's handler table (for string refs).
--- @param info       table   The fake info argument to pass.
--- @return boolean, any  ok, result
local function evalField(val, handler, info)
	if type(val) == "function" then
		return pcall(val, info)
	elseif type(val) == "string" and type(handler) == "table" then
		local method = handler[val]
		if type(method) == "function" then
			return pcall(method, handler, info)
		end
	end
	return false, nil
end

--- Attempt to evaluate a color get() — AceConfig color getters return r, g, b [, a].
--- @param val        any     The field value (function or string).
--- @param handler    table|nil  The node's handler table (for string refs).
--- @param info       table   The fake info argument to pass.
--- @return boolean, number|nil, number|nil, number|nil, number|nil  ok, r, g, b, a
local function evalColorGet(val, handler, info)
	if type(val) == "function" then
		local ok, r, g, b, a = pcall(val, info)
		if ok then
			return true, r, g, b, a
		end
	elseif type(val) == "string" and type(handler) == "table" then
		local method = handler[val]
		if type(method) == "function" then
			local ok, r, g, b, a = pcall(method, handler, info)
			if ok then
				return true, r, g, b, a
			end
		end
	end
	return false, nil, nil, nil, nil
end

--- Attempt to evaluate a function-valued `values` field.
--- @param val any  The field value (function or table).
--- @return boolean, any  ok, result
local function evalValues(val)
	if type(val) == "function" then
		return pcall(val)
	end
	return true, val
end

--- Serialize a single AceConfig option node (table).
--- @param node    table       An entry inside G_RLF.options.args (or nested args).
--- @param handler table|nil  Inherited handler from the parent group (may be
---                            overridden by node.handler).
--- @return table  A plain Lua table safe to JSON-encode.
function M.serializeNode(node, handler)
	if type(node) ~= "table" then
		return nil
	end

	-- Resolve the effective handler: node-level overrides parent
	local effectiveHandler = (type(node.handler) == "table" and node.handler) or handler

	local out = {}
	local INFO_STUB = {}

	for _, key in ipairs(KNOWN_KEYS) do
		local val = node[key]
		if val ~= nil then
			local vt = type(val)
			if key == "args" and vt == "table" then
				-- Recurse into child option nodes, passing down the effective handler
				local children = {}
				for childKey, childNode in pairs(val) do
					if type(childNode) == "table" then
						children[childKey] = M.serializeNode(childNode, effectiveHandler)
					end
				end
				out[key] = children
			elseif key == "get" then
				-- Color get() returns r, g, b [, a] — capture all four channels.
				-- All other get() calls return a single value.
				if out.type == "color" then
					local ok, r, g, b, a = evalColorGet(val, effectiveHandler, INFO_STUB)
					if ok then
						out[key] = { _type = "function", _dynamic = true, _r = r, _g = g, _b = b, _a = a }
					else
						out[key] = { _type = "function", _dynamic = true, _error = true }
					end
				else
					local ok, result = evalField(val, effectiveHandler, INFO_STUB)
					if ok then
						out[key] = { _type = "function", _dynamic = true, _value = result }
					else
						out[key] = { _type = "function", _dynamic = true, _error = true }
					end
				end
			elseif key == "hidden" or key == "disabled" then
				-- Evaluate: call with a stub info table; record _value and _dynamic
				local ok, result = evalField(val, effectiveHandler, INFO_STUB)
				if ok then
					out[key] = { _type = "function", _dynamic = true, _value = result }
				else
					out[key] = { _type = "function", _dynamic = true, _error = true }
				end
			elseif key == "values" then
				-- Evaluate function-valued values; static tables pass through
				if vt == "function" then
					local ok, result = evalValues(val)
					if ok and type(result) == "table" then
						out[key] = { _type = "function", _dynamic = true, _resolved = result }
					else
						out[key] = { _type = "function", _dynamic = true }
					end
				else
					-- Static table – copy as-is
					out[key] = val
				end
			elseif key == "set" or key == "func" then
				-- Setters and execute handlers are never called during dump
				if vt == "function" or vt == "string" then
					out[key] = FUNC_PLACEHOLDER
				end
			elseif vt == "function" then
				-- Other unevaluated function fields (confirm, validate, image, ...)
				out[key] = FUNC_PLACEHOLDER
			elseif vt == "table" then
				-- sorting, imageCoords, etc. – copy as-is
				out[key] = val
			else
				-- string, number, boolean
				out[key] = val
			end
		end
	end

	-- Capture any extra (non-standard) keys the config author added
	for key, val in pairs(node) do
		if not IS_KNOWN[key] and key ~= "handler" then
			local vt = type(val)
			if vt == "function" then
				out["_extra_" .. key] = FUNC_PLACEHOLDER
			elseif vt ~= "userdata" and vt ~= "thread" then
				out["_extra_" .. key] = val
			end
		end
	end

	return out
end

--- Serialize the root G_RLF.options table to a pretty-printed JSON string.
--- @param options table  G_RLF.options (or any AceConfig root group table).
--- @return string        Pretty-printed JSON.
function M.dump(options)
	local serialized = M.serializeNode(options)
	return jsonEncode(serialized, "")
end

return M
