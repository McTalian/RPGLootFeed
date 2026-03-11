#!/usr/bin/env python3
"""Stage 2 – AceConfig HTML Renderer

Reads .scripts/.output/options_dump.json (produced by make options-dump) and
writes a self-contained .scripts/.output/options.html that mirrors the layout
of the in-game RPGLootFeed settings panel:

  - Execute buttons across the top (testMode, clearRows, lootHistory)
  - Two-column layout: left nav tree | right content panel
  - Left nav: gold top-level section headers, indented white sub-items
  - Right panel: widgets for the currently selected nav item
  - Sub-groups rendered as labeled bordered fieldsets (nested as needed)
  - Metadata (internal key, full desc, dynamic flags) in hover tooltips only

Usage:
    make options-html
    uv run .scripts/render_options.py [--input PATH] [--output PATH]
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path
from typing import Any

_ATLAS_RE = re.compile(r"<AtlasMarkup:([^>]+)>")

SCRIPT_DIR = Path(__file__).parent
DEFAULT_INPUT = SCRIPT_DIR / ".output" / "options_dump.json"
DEFAULT_OUTPUT = SCRIPT_DIR / ".output" / "options.html"

# ---------------------------------------------------------------------------
# Value-resolution helpers
# ---------------------------------------------------------------------------


def _raw_str(val: Any, fallback: str = "") -> str:
    """Plain unescaped string for tooltip text."""
    if isinstance(val, dict):
        return str(val["_value"]) if "_value" in val else "[dynamic]"
    return str(val) if val is not None else fallback


def _resolve_str(val: Any, fallback: str = "") -> str:
    """HTML-escaped string for inline content."""
    return html.escape(_raw_str(val, fallback))


def _resolve_bool(val: Any, default: bool = False) -> bool:
    if isinstance(val, dict):
        return bool(val.get("_value", default))
    return bool(val) if val is not None else default


def _resolve_values(val: Any) -> tuple[dict[str, str], bool]:
    """Return ({key: label}, is_dynamic)."""
    if isinstance(val, dict):
        if "_resolved" in val:
            return {str(k): str(v) for k, v in val["_resolved"].items()}, True
        if "_type" in val:
            return {}, True
        return {str(k): str(v) for k, v in val.items()}, False
    return {}, False


def _get_value(node: dict) -> Any:
    g = node.get("get")
    return g["_value"] if isinstance(g, dict) and "_value" in g else None


def _get_color_rgba(node: dict) -> tuple[int, int, int, float] | None:
    """Return (r255, g255, b255, alpha) from a color node's get field, or None."""
    g = node.get("get")
    if not isinstance(g, dict) or "_r" not in g:
        return None

    def _ch(v: Any) -> int:
        return max(0, min(255, int((v or 0) * 255)))

    return (
        _ch(g.get("_r")),
        _ch(g.get("_g")),
        _ch(g.get("_b")),
        float(g.get("_a") or 1.0),
    )


def _is_hidden(node: dict) -> bool:
    return _resolve_bool(node.get("hidden"), False)


def _is_disabled(node: dict) -> bool:
    return _resolve_bool(node.get("disabled"), False)


def _sorted_children(args: dict) -> list[tuple[str, dict]]:
    pairs = [(k, v) for k, v in args.items() if isinstance(v, dict)]
    return sorted(
        pairs,
        key=lambda p: (
            (
                float(p[1].get("order", 0))
                if isinstance(p[1].get("order"), (int, float))
                else 0.0
            ),
            p[0],
        ),
    )


# ---------------------------------------------------------------------------
# Nav-tree builder
# ---------------------------------------------------------------------------


def _is_nav_subgroup(node: dict) -> bool:
    """A group that can appear as an indented sub-item in the nav tree."""
    return (
        isinstance(node, dict)
        and node.get("type") == "group"
        and not node.get("inline")
        and not node.get("guiInline")
    )


def _classify_root_group(node: dict) -> tuple[str, list[tuple[str, dict]]]:
    """Return ('container', sorted_sub_groups) or ('leaf', []).

    A group is a 'container' when it has >= 2 non-inline group children ---
    those children become the indented sub-items in the nav tree, matching the
    in-game AceConfig tree structure.  A container still renders its non-group
    direct children (e.g. enable toggles) in its own content panel.
    """
    all_children = _sorted_children(node.get("args", {}))
    sub_groups = [(k, v) for k, v in all_children if _is_nav_subgroup(v)]
    if len(sub_groups) >= 2:
        return "container", sub_groups
    return "leaf", []


def _build_nav(root_args: dict) -> tuple[list, list]:
    """Parse root args into (top_executes, nav_items).

    top_executes  list of (key, node) for root-level execute buttons shown in the top bar.
    nav_items     list of nav dicts with keys:
                    key, name, node, panel_id, mode ('container'|'leaf'), children
                  children is a (possibly empty) list of sub-nav dicts with the same
                  shape minus 'mode' and 'children'.
    """
    top_executes: list[tuple[str, dict]] = []
    nav_items: list[dict] = []

    for key, node in _sorted_children(root_args):
        t = node.get("type", "")
        if t == "execute":
            top_executes.append((key, node))
        elif t == "group":
            name = _resolve_str(node.get("name", key))
            mode, sub_groups = _classify_root_group(node)
            children: list[dict] = []
            if mode == "container":
                for ckey, cnode in sub_groups:
                    cname = _resolve_str(cnode.get("name", ckey))
                    children.append(
                        {
                            "key": ckey,
                            "name": cname,
                            "node": cnode,
                            "panel_id": f"p-{key}-{ckey}",
                        }
                    )
            nav_items.append(
                {
                    "key": key,
                    "name": name,
                    "node": node,
                    "panel_id": f"p-{key}",
                    "mode": mode,
                    "children": children,
                }
            )

    return top_executes, nav_items


# ---------------------------------------------------------------------------
# Tooltip data builder
# ---------------------------------------------------------------------------


def _tip(key: str, node: dict) -> str:
    """Build the tooltip string for an option (set as the data-tip HTML attribute).

    Shows the internal AceConfig key, the full description text, and flags for
    dynamic / hidden-by-default options.  Newlines are literal so JS can render
    them with white-space: pre-wrap.
    """
    parts = [f"key: {key}"]
    desc = _raw_str(node.get("desc"))
    if desc and desc != "[dynamic]":
        parts.append(desc)
    dyn_fields = [
        f
        for f in ("get", "hidden", "disabled", "values")
        if isinstance(node.get(f), dict) and node.get(f, {}).get("_dynamic")
    ]
    if dyn_fields:
        parts.append(f"[dynamic: {', '.join(dyn_fields)}]")
    if _is_hidden(node):
        parts.append("[hidden by default]")
    return html.escape("\n".join(parts), quote=True)


# ---------------------------------------------------------------------------
# Renderer
# ---------------------------------------------------------------------------


class Renderer:
    def __init__(self) -> None:
        self._buf: list[str] = []

    def _w(self, s: str) -> None:
        self._buf.append(s)

    def render(self, root: dict) -> str:
        top_executes, nav_items = _build_nav(root.get("args", {}))

        # The first sub-item of the first container, or first leaf, is the
        # default selected panel on page load.
        default_panel = ""
        for item in nav_items:
            if item["children"]:
                default_panel = item["children"][0]["panel_id"]
            else:
                default_panel = item["panel_id"]
            break

        self._w(HTML_HEAD)
        self._w('<div class="app">')

        # ── Top bar ────────────────────────────────────────────────────────
        self._w('<header class="top-bar">')
        self._w('<span class="addon-title">RPGLootFeed</span>')
        self._w('<div class="top-btn-row">')
        for key, node in top_executes:
            name = _resolve_str(node.get("name", key))
            tip = _tip(key, node)
            hcls = " top-btn-hidden" if _is_hidden(node) else ""
            self._w(
                f'<button class="top-btn{hcls}" data-tip="{tip}" disabled>{name}</button>'
            )
        self._w("</div>")
        self._w("</header>")

        # ── Workspace ─────────────────────────────────────────────────────
        self._w('<div class="workspace">')

        # ── Sidebar ───────────────────────────────────────────────────────
        self._w('<nav class="sidebar">')
        self._render_nav(nav_items)
        self._w("</nav>")

        # ── Content panels ────────────────────────────────────────────────
        self._w('<main class="content" id="content">')
        self._render_all_panels(nav_items)
        self._w("</main>")

        self._w("</div>")  # workspace
        self._w("</div>")  # app
        self._w('<div id="tooltip"></div>')
        self._w(HTML_FOOT.replace("__DEFAULT_PANEL__", default_panel))
        return "\n".join(self._buf)

    # ------------------------------------------------------------------
    # Nav
    # ------------------------------------------------------------------

    def _render_nav(self, nav_items: list[dict]) -> None:
        for item in nav_items:
            hcls = " nav-hidden" if _is_hidden(item["node"]) else ""
            if item["children"]:
                self._w(
                    f'<div class="nav-parent{hcls}" '
                    f'data-panel="{item["panel_id"]}" data-key="{item["key"]}" '
                    f'onclick="toggleParent(this)">'
                    f'<span class="nav-arrow">&#x25BC;</span>'
                    f'<span class="nav-parent-name">{item["name"]}</span>'
                    f"</div>"
                )
                self._w(f'<div class="nav-children" id="children-{item["key"]}">')
                for child in item["children"]:
                    chcls = " nav-hidden" if _is_hidden(child["node"]) else ""
                    self._w(
                        f'  <div class="nav-item{chcls}" '
                        f'data-panel="{child["panel_id"]}" '
                        f'onclick="selectNav(this)">{child["name"]}</div>'
                    )
                self._w("</div>")
            else:
                self._w(
                    f'<div class="nav-item{hcls}" '
                    f'data-panel="{item["panel_id"]}" '
                    f'onclick="selectNav(this)">{item["name"]}</div>'
                )

    # ------------------------------------------------------------------
    # Content panels
    # ------------------------------------------------------------------

    def _render_all_panels(self, nav_items: list[dict]) -> None:
        for item in nav_items:
            # For container groups the nav sub-items (group children) are NOT
            # rendered inline in the parent panel – you navigate to them via nav.
            excluded = {c["key"] for c in item["children"]}
            self._render_panel(item["panel_id"], item["key"], item["node"], excluded)
            for child in item["children"]:
                self._render_panel(child["panel_id"], child["key"], child["node"])

    def _render_panel(
        self,
        panel_id: str,
        key: str,
        node: dict,
        excluded_keys: set | None = None,
    ) -> None:
        self._w(f'<div class="panel" id="{panel_id}">')
        visible: list[tuple[str, dict]] = []
        hidden: list[tuple[str, dict]] = []
        for ckey, cnode in _sorted_children(node.get("args", {})):
            if excluded_keys and ckey in excluded_keys:
                continue
            (hidden if _is_hidden(cnode) else visible).append((ckey, cnode))
        for ckey, cnode in visible:
            self._render_node(ckey, cnode)
        if hidden:
            self._w('<details class="hidden-opts-section">')
            self._w(
                f'  <summary class="hidden-opts-summary">Hidden by default ({len(hidden)})</summary>'
            )
            for ckey, cnode in hidden:
                self._render_node(ckey, cnode, in_hidden=True)
            self._w("</details>")
        self._w("</div>")

    # ------------------------------------------------------------------
    # Node dispatch
    # ------------------------------------------------------------------

    def _render_node(
        self, key: str, node: dict, depth: int = 0, in_hidden: bool = False
    ) -> None:
        t = node.get("type", "")
        classes: list[str] = []
        if _is_disabled(node):
            classes.append("opt-disabled")
        if _is_hidden(node) and not in_hidden:
            classes.append("opt-hidden")

        dispatch = {
            "group": self._render_group,
            "toggle": self._render_toggle,
            "range": self._render_range,
            "select": self._render_select,
            "multiselect": self._render_multiselect,
            "color": self._render_color,
            "input": self._render_input,
            "execute": self._render_execute,
            "description": self._render_description,
            "header": self._render_header,
        }
        dispatch.get(t, self._render_unknown)(key, node, depth, classes)

    # ------------------------------------------------------------------
    # Widget renderers
    # ------------------------------------------------------------------

    def _render_group(self, key: str, node: dict, depth: int, extra: list[str]) -> None:
        name = _resolve_str(node.get("name", key))
        classes = ["opt-group"] + extra
        if node.get("inline") or node.get("guiInline"):
            classes.append("opt-group-inline")
        self._w(f'<fieldset class="{" ".join(classes)}">')
        self._w(f'  <legend class="opt-group-legend">{name}</legend>')
        visible: list[tuple[str, dict]] = []
        hidden: list[tuple[str, dict]] = []
        for ckey, cnode in _sorted_children(node.get("args", {})):
            (hidden if _is_hidden(cnode) else visible).append((ckey, cnode))
        for ckey, cnode in visible:
            self._render_node(ckey, cnode, depth + 1)
        if hidden:
            self._w('  <details class="hidden-opts-section">')
            self._w(
                f'    <summary class="hidden-opts-summary">Hidden by default ({len(hidden)})</summary>'
            )
            for ckey, cnode in hidden:
                self._render_node(ckey, cnode, depth + 1, in_hidden=True)
            self._w("  </details>")
        self._w("</fieldset>")

    def _render_toggle(
        self, key: str, node: dict, depth: int, extra: list[str]
    ) -> None:
        value = _get_value(node)
        symbol = "&#x2714;" if value else "&#x25A1;"  # ✔ or □
        self._opt_row(key, node, extra, f'<span class="chk-sym">{symbol}</span>')

    def _render_range(self, key: str, node: dict, depth: int, extra: list[str]) -> None:
        value = _get_value(node)
        mn = node.get("softMin") or node.get("min") or 0
        mx = node.get("softMax") or node.get("max") or 100
        step = node.get("step") or node.get("bigStep") or 1
        val_str = "—"
        if value is not None:
            val_str = f"{value * 100:.0f}%" if node.get("isPercent") else str(value)
        ctrl = (
            f'<input type="range" min="{mn}" max="{mx}" step="{step}" '
            f'value="{value if value is not None else mn}" disabled class="w-range">'
            f'<span class="range-val">{html.escape(val_str)}</span>'
        )
        self._opt_row(key, node, extra, ctrl, wide=True)

    def _render_select(
        self, key: str, node: dict, depth: int, extra: list[str]
    ) -> None:
        values, _ = _resolve_values(node.get("values"))
        current = _get_value(node)
        dialog_ctrl = node.get("dialogControl", "")

        sorting = node.get("sorting")
        if sorting and isinstance(sorting, list):
            ordered = [str(k) for k in sorting if str(k) in values]
            ordered += [k for k in values if k not in ordered]
        else:
            ordered = sorted(values.keys())

        if values:
            opts_html = "".join(
                f'<option{"  selected" if str(current) == k else ""}>{html.escape(values[k])}</option>'
                for k in ordered
            )
            ctrl = f'<select disabled class="w-select">{opts_html}</select>'
        else:
            ctrl = '<select disabled class="w-select"><option>[dynamic list]</option></select>'

        if dialog_ctrl:
            ctrl += f' <span class="dialog-ctrl">{html.escape(str(dialog_ctrl))}</span>'

        self._opt_row(key, node, extra, ctrl, wide=True)

    def _render_multiselect(
        self, key: str, node: dict, depth: int, extra: list[str]
    ) -> None:
        values, _ = _resolve_values(node.get("values"))
        name = _resolve_str(node.get("name", key))
        tip = _tip(key, node)
        width = node.get("width", "")
        w_cls = (
            " width-full"
            if width == "full"
            else " width-double" if width == "double" else ""
        )
        classes = ["opt-multiselect"] + extra

        self._w(f'<div class="{" ".join(classes)}{w_cls}" data-tip="{tip}">')
        self._w(f'  <span class="opt-name">{name}</span>')
        self._w('  <div class="multiselect-checks">')
        if values:
            for _k, label in sorted(values.items()):
                self._w(
                    f'    <label><input type="checkbox" disabled> {html.escape(label)}</label>'
                )
        else:
            self._w("    <em>[dynamic options]</em>")
        self._w("  </div>")
        self._w("</div>")

    def _render_color(self, key: str, node: dict, depth: int, extra: list[str]) -> None:
        has_alpha = node.get("hasAlpha", False)
        rgba = _get_color_rgba(node)
        if rgba:
            r, g, b, a = rgba
            css_color = f"rgba({r},{g},{b},{a:.2f})"
            title = f"rgba({r},{g},{b},{a:.2f})"
            ctrl = (
                f'<span class="color-swatch" '
                f'style="background:{css_color};color:{css_color}" '
                f'title="{html.escape(title)}">[&#x25A0;]</span>'
            )
        else:
            alpha_note = "A" if has_alpha else ""
            ctrl = (
                f'<span class="color-swatch" '
                f'title="RGB{alpha_note} — value unavailable">[&#x25A0;]</span>'
            )
        self._opt_row(key, node, extra, ctrl)

    def _render_input(self, key: str, node: dict, depth: int, extra: list[str]) -> None:
        value = _get_value(node)
        val_str = html.escape(str(value)) if value is not None else ""
        if node.get("multiline"):
            ctrl = f'<textarea disabled class="w-input">{val_str}</textarea>'
        else:
            ctrl = f'<input type="text" value="{val_str}" disabled class="w-input">'
        validate = node.get("validate")
        if isinstance(validate, str):
            ctrl += f' <span class="validate-badge">{html.escape(validate)}</span>'
        elif isinstance(validate, dict):
            ctrl += ' <span class="validate-badge">[validate fn]</span>'
        self._opt_row(key, node, extra, ctrl, wide=True)

    def _render_execute(
        self, key: str, node: dict, depth: int, extra: list[str]
    ) -> None:
        raw_name = _raw_str(node.get("name", key))
        m = _ATLAS_RE.search(raw_name)
        if m:
            name = f'<span class="atlas-badge" title="{html.escape(raw_name)}">{html.escape(m.group(1))}</span>'
        else:
            name = html.escape(raw_name)
        tip = _tip(key, node)
        width = node.get("width", "")
        extra_style = ""
        if width == "full":
            w_cls = " width-full"
        elif width == "double":
            w_cls = " width-double"
        elif isinstance(width, (int, float)):
            w_cls = " width-numeric"
            extra_style = f' style="width:{int(width * 100)}%"'
        else:
            w_cls = ""
        classes = ["opt-execute"] + extra
        self._w(
            f'<div class="{" ".join(classes)}{w_cls}"{extra_style}>'
            f'<button disabled class="w-btn" data-tip="{tip}">{name}</button>'
            f"</div>"
        )

    def _render_description(
        self, key: str, node: dict, depth: int, extra: list[str]
    ) -> None:
        text = _resolve_str(node.get("name", ""))
        tip = _tip(key, node)
        font_size = node.get("fontSize", "medium")
        image = node.get("image", "")
        prefix = ""
        if image:
            img_base = image.split("/")[-1]
            prefix = f'<span class="img-hint" title="{html.escape(image)}">[img: {html.escape(img_base)}]</span> '
        classes = ["opt-desc-block", f"fsz-{font_size}"] + extra
        self._w(f'<p class="{" ".join(classes)}" data-tip="{tip}">{prefix}{text}</p>')

    def _render_header(
        self, key: str, node: dict, depth: int, extra: list[str]
    ) -> None:
        text = _resolve_str(node.get("name", ""))
        self._w(f'<h4 class="opt-header">{text}</h4>')

    def _render_unknown(
        self, key: str, node: dict, depth: int, extra: list[str]
    ) -> None:
        t = node.get("type", "?")
        name = _resolve_str(node.get("name", key))
        tip = _tip(key, node)
        self._w(
            f'<div class="opt-unknown" data-tip="{tip}">'
            f'<span class="unk-type">{html.escape(t)}</span> {name}'
            f"</div>"
        )

    # ------------------------------------------------------------------
    # Shared option-row helper
    # ------------------------------------------------------------------

    def _opt_row(
        self,
        key: str,
        node: dict,
        extra: list[str],
        widget_html: str,
        wide: bool = False,
    ) -> None:
        """Emit a horizontal option row: [widget]  Name text."""
        name = _resolve_str(node.get("name", key))
        tip = _tip(key, node)
        width = node.get("width", "")
        extra_style = ""
        if width == "full":
            w_cls = " width-full"
        elif width == "double":
            w_cls = " width-double"
        elif width == "half":
            w_cls = " width-half"
        elif isinstance(width, (int, float)):
            w_cls = " width-numeric"
            extra_style = f' style="width:{int(width * 100)}%"'
        elif wide:
            w_cls = " opt-row-wide"
        else:
            w_cls = ""
        classes = ["opt-row"] + extra
        self._w(
            f'<div class="{" ".join(classes)}{w_cls}"{extra_style} data-tip="{tip}">'
            f'<span class="opt-widget">{widget_html}</span>'
            f'<span class="opt-name">{name}</span>'
            f"</div>"
        )


# ---------------------------------------------------------------------------
# HTML shell — CSS + structure
# ---------------------------------------------------------------------------

HTML_HEAD = """\
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>RPGLootFeed — Config Options</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 13px;
      background: #1c1c1c;
      color: #d0d0d0;
      height: 100vh;
      overflow: hidden;
    }
    .app { display: flex; flex-direction: column; height: 100vh; }

    /* ── Top bar ── */
    .top-bar {
      display: flex; align-items: center; gap: 10px;
      padding: 6px 14px; background: #111;
      border-bottom: 1px solid #3a3a3a; flex-shrink: 0;
    }
    .addon-title { font-weight: bold; color: #e0c060; font-size: 0.95rem; margin-right: 6px; }
    .top-btn-row { display: flex; gap: 8px; flex-wrap: wrap; }
    .top-btn {
      background: #3a1a1a; color: #d09050;
      border: 1px solid #703020; border-radius: 3px;
      padding: 4px 14px; cursor: not-allowed; font-size: 0.85rem;
    }
    .top-btn-hidden { opacity: 0.5; font-style: italic; }

    /* ── Workspace ── */
    .workspace { display: flex; flex: 1; overflow: hidden; }

    /* ── Sidebar ── */
    .sidebar {
      width: 190px; min-width: 140px;
      background: #181818; border-right: 1px solid #2e2e2e;
      overflow-y: auto; padding: 6px 0; flex-shrink: 0;
    }
    .nav-parent {
      display: flex; align-items: center; gap: 5px;
      padding: 6px 10px; cursor: pointer;
      color: #e0c060; font-weight: bold; font-size: 0.88rem;
      user-select: none;
    }
    .nav-parent:hover { background: #252525; }
    .nav-parent.active { background: #1c3a6a; }
    .nav-parent-name { flex: 1; }
    .nav-arrow { font-size: 0.65em; color: #888; flex-shrink: 0; }

    .nav-children { overflow: hidden; }
    .nav-children.collapsed { display: none; }
    .nav-children .nav-item { padding-left: 22px; }

    .nav-item {
      padding: 4px 10px; cursor: pointer;
      color: #c8c8c8; font-size: 0.87rem;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
      user-select: none;
    }
    .nav-item:hover  { background: #252535; }
    .nav-item.active { background: #1c3a6a; color: #fff; }
    .nav-hidden { opacity: 0.55; font-style: italic; }

    /* ── Content area ── */
    .content { flex: 1; overflow-y: auto; background: #1e1e1e; }
    .panel { display: none; padding: 12px 16px; }
    .panel.active { display: block; }

    /* ── Sub-groups (fieldsets) ── */
    fieldset.opt-group {
      border: 1px solid #3a3a3a; border-radius: 3px;
      margin: 8px 0; padding: 6px 10px 10px;
    }
    fieldset.opt-group-inline { border-style: dashed; }
    legend.opt-group-legend {
      color: #e0c060; font-weight: bold;
      font-size: 0.88rem; padding: 0 4px;
    }
    .opt-group.opt-disabled { opacity: 0.4; }
    .opt-group.opt-hidden   { opacity: 0.55; border-style: dashed; }

    /* ── Option rows ── */
    .opt-row {
      display: inline-flex; align-items: center; gap: 6px;
      padding: 3px 5px; margin: 2px 2px;
      border-radius: 3px; vertical-align: middle;
      cursor: default; min-width: 150px;
    }
    .opt-row:hover  { background: #252535; }
    .opt-row.opt-disabled { opacity: 0.4; }
    .opt-row.opt-hidden   { opacity: 0.55; border: 1px dashed #444; }
    .opt-row-wide  { min-width: 250px; }
    .width-full    { display: flex !important; width: 100%; }
    .width-double  { min-width: 320px; }
    .width-half    { min-width: 110px; max-width: 170px; }
    .opt-widget    { display: flex; align-items: center; gap: 3px; flex-shrink: 0; }
    .opt-name      { color: #d0d0d0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

    /* Toggle */
    .chk-sym { font-size: 1.05em; color: #90c090; min-width: 14px; text-align: center; }

    /* Range */
    .w-range   { width: 100px; accent-color: #5b9bd5; }
    .range-val { font-size: 0.8em; color: #888; min-width: 28px; }

    /* Select / input */
    .w-select, .w-input {
      background: #161616; border: 1px solid #484848;
      color: #c8c8c8; border-radius: 3px;
      padding: 2px 5px; font-size: 0.83em;
    }
    .w-select { max-width: 180px; }
    .w-input  { width: 100%; }
    textarea.w-input { resize: vertical; min-height: 2.5rem; }
    .dialog-ctrl {
      font-size: 0.68em; color: #6699cc; font-family: monospace;
      border: 1px solid #2a4a6a; border-radius: 3px; padding: 0 3px;
    }

    /* Color swatch */
    .color-swatch {
      font-size: 1.2em; cursor: default;
      border: 1px solid #555; border-radius: 2px; padding: 0 2px;
      /* background and color set inline when RGBA is available */
      color: #c070c0;
    }

    /* Execute */
    .opt-execute { display: inline-flex; margin: 2px 2px; vertical-align: middle; }
    .w-btn {
      background: #282828; color: #c8a836;
      border: 1px solid #504020; border-radius: 3px;
      padding: 3px 10px; cursor: not-allowed; font-size: 0.85em;
    }
    .w-btn:hover { background: #2a2a3a; }

    /* Multiselect */
    .opt-multiselect {
      display: inline-flex; flex-direction: column; gap: 3px;
      margin: 3px 2px; vertical-align: top;
    }
    .multiselect-checks { display: flex; flex-wrap: wrap; gap: 3px 10px; padding: 2px 0; }
    .multiselect-checks label { display: flex; align-items: center; gap: 4px; font-size: 0.83em; }

    /* Description */
    .opt-desc-block {
      color: #778899; font-style: italic; margin: 4px 0;
      padding: 3px 6px; border-left: 2px solid #2a2a3a;
    }
    .fsz-small  { font-size: 0.78em; }
    .fsz-medium { font-size: 0.88em; }
    .fsz-large  { font-size: 1.0em; }

    /* Header dividers */
    .opt-header {
      color: #c0a030; border-bottom: 1px solid #3a2800;
      font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.06em;
      margin: 10px 0 4px; padding-bottom: 3px;
    }

    /* Unknown */
    .opt-unknown { color: #887; font-size: 0.8em; font-style: italic; margin: 2px 4px; }
    .unk-type {
      font-size: 0.7em; background: #222; border: 1px solid #555;
      border-radius: 3px; padding: 0 3px; margin-right: 3px;
    }
    .img-hint { font-size: 0.77em; color: #556; }

    /* Numeric width (fractional AceConfig width values) */
    .width-numeric { display: inline-flex; }

    /* Atlas icon badge (execute buttons with CreateAtlasMarkup names) */
    .atlas-badge {
      font-size: 0.75em; background: #1a2a3a; color: #7ab0d0;
      border: 1px solid #2a5a7a; border-radius: 3px;
      padding: 1px 5px; font-family: monospace; cursor: default;
    }

    /* Validate badge on input widgets */
    .validate-badge {
      font-size: 0.68em; color: #a080c0;
      background: #1a0a2a; border: 1px solid #4a2a6a;
      border-radius: 3px; padding: 0 4px; font-family: monospace; margin-left: 3px;
    }

    /* Hidden-by-default details section */
    .hidden-opts-section {
      margin: 6px 0; border: 1px dashed #3a3040;
      border-radius: 3px; padding: 0 6px 4px;
    }
    .hidden-opts-summary {
      color: #7a6a8a; font-size: 0.78em; font-style: italic;
      cursor: pointer; padding: 3px 0; user-select: none;
    }
    .hidden-opts-summary:hover { color: #a090b0; }

    /* ── Tooltip ── */
    #tooltip {
      position: fixed; display: none;
      background: #1a1a1a; color: #d8d8d8;
      border: 1px solid #4a4a4a; border-radius: 4px;
      padding: 6px 10px; font-size: 0.78rem;
      max-width: 340px; white-space: pre-wrap; word-break: break-word;
      pointer-events: none; z-index: 9999; line-height: 1.5;
      box-shadow: 2px 3px 10px rgba(0,0,0,0.7);
    }
    #tooltip.visible { display: block; }
  </style>
</head>
<body>
"""

HTML_FOOT = """\
<script>
(function () {
  /* ── Tooltip ── */
  var tip = document.getElementById('tooltip');
  document.querySelectorAll('[data-tip]').forEach(function (el) {
    el.addEventListener('mouseenter', function () {
      tip.textContent = el.dataset.tip;
      tip.classList.add('visible');
    });
    el.addEventListener('mouseleave', function () {
      tip.classList.remove('visible');
    });
    el.addEventListener('mousemove', function (e) {
      var x = e.clientX + 14, y = e.clientY + 14;
      if (x + tip.offsetWidth  > window.innerWidth)  x = e.clientX - tip.offsetWidth  - 6;
      if (y + tip.offsetHeight > window.innerHeight) y = e.clientY - tip.offsetHeight - 6;
      tip.style.left = x + 'px';
      tip.style.top  = y + 'px';
    });
  });

  /* ── Nav ── */
  function showPanel(id) {
    document.querySelectorAll('.panel').forEach(function (p) { p.classList.remove('active'); });
    var el = document.getElementById(id);
    if (el) el.classList.add('active');
  }
  function clearActive() {
    document.querySelectorAll('.nav-item.active, .nav-parent.active').forEach(function (n) {
      n.classList.remove('active');
    });
  }
  window.selectNav = function (el) {
    clearActive();
    el.classList.add('active');
    showPanel(el.dataset.panel);
  };
  window.toggleParent = function (el) {
    var key      = el.dataset.key;
    var children = document.getElementById('children-' + key);
    var arrow    = el.querySelector('.nav-arrow');
    if (children) {
      children.classList.toggle('collapsed');
      arrow.textContent = children.classList.contains('collapsed') ? '\u25ba' : '\u25bc';
    }
    clearActive();
    el.classList.add('active');
    if (el.dataset.panel) showPanel(el.dataset.panel);
  };

  /* ── Default selection ── */
  var first = document.querySelector('[data-panel="__DEFAULT_PANEL__"]');
  if (first) {
    first.classList.add('active');
    showPanel("__DEFAULT_PANEL__");
  }
})();
</script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render AceConfig options JSON to HTML"
    )
    parser.add_argument(
        "--input", default=str(DEFAULT_INPUT), help="Path to options_dump.json"
    )
    parser.add_argument(
        "--output", default=str(DEFAULT_OUTPUT), help="Path to write options.html"
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.exists():
        print(f"ERROR: input file not found: {input_path}", file=sys.stderr)
        print("Run `make options-dump` first to generate it.", file=sys.stderr)
        sys.exit(1)

    with open(input_path, encoding="utf-8") as f:
        data = json.load(f)

    renderer = Renderer()
    out = renderer.render(data)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(out)

    print(f"[options-html] Wrote {len(out):,} bytes to {output_path}")


if __name__ == "__main__":
    main()
