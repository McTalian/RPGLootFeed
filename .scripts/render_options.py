#!/usr/bin/env python3
"""Stage 2 – AceConfig HTML Renderer

Reads .scripts/.output/options_dump.json (produced by make options-dump) and
writes a self-contained .scripts/.output/options.html that mirrors the layout
of the in-game RPGLootFeed settings panel.

Multi-frame layout (root childGroups="select"):
  - Tab bar at top: Global, Main (frame 1), + New Frame, Manage Frames
  - Per tab: left nav tree | right content panel
  - 3-level nav: tab → tree parent → tree children

Legacy flat layout (no select at root):
  - Execute buttons across the top
  - Two-column layout: left nav tree | right content panel

Common features:
  - Gold top-level section headers, indented white sub-items
  - Sub-groups rendered as labeled bordered fieldsets
  - Metadata (internal key, full desc, dynamic flags) in hover tooltips

Usage:
    make options-html
    uv run .scripts/render_options.py [--input PATH] [--output PATH]
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import re
import sys
from pathlib import Path
from typing import Any

_ATLAS_RE = re.compile(r"<AtlasMarkup:([^>]+)>")

SCRIPT_DIR = Path(__file__).parent
ASSETS_DIR = SCRIPT_DIR / "assets"

# Map WoW atlas names to local PNG files.  At import time we read each file
# and encode it as a base64 data URI so the output HTML stays self-contained.
_ATLAS_PNG_MAP: dict[str, str] = {}
for _atlas_name, _filename in {
    "UI-EventPoi-WorldSoulMemory": "worldsoul.png",
    "Crosshair_lootall_32": "lootall.png",
}.items():
    _path = ASSETS_DIR / _filename
    if _path.exists():
        _b64 = base64.b64encode(_path.read_bytes()).decode()
        _ATLAS_PNG_MAP[_atlas_name] = f"data:image/png;base64,{_b64}"


def _atlas_replace(text: str, height: int = 16) -> str:
    """Replace <AtlasMarkup:NAME> in *text* with an <img> tag (if we have
    a local PNG) or a styled text badge (fallback).

    *text* should already be HTML-escaped — we match the escaped form.
    """

    def _sub(m: re.Match) -> str:
        name = m.group(1)
        data_uri = _ATLAS_PNG_MAP.get(name)
        if data_uri:
            return (
                f'<img src="{data_uri}" alt="{html.escape(name)}" '
                f'class="atlas-icon" style="height:{height}px;vertical-align:middle">'
            )
        return (
            f'<span class="atlas-badge" title="{html.escape(name)}">'
            f"{html.escape(name)}</span>"
        )

    # Match both raw and HTML-escaped forms
    text = re.sub(r"&lt;AtlasMarkup:([^&]+)&gt;", _sub, text)
    text = _ATLAS_RE.sub(_sub, text)
    return text


DEFAULT_INPUT = SCRIPT_DIR / ".output" / "options_dump.json"
DEFAULT_OUTPUT = SCRIPT_DIR / ".output" / "options.html"

# ---------------------------------------------------------------------------
# Value-resolution helpers
# ---------------------------------------------------------------------------


def _raw_str(val: Any, fallback: str = "") -> str:
    """Plain unescaped string for tooltip text."""
    if isinstance(val, dict):
        if val.get("_error"):
            return "[unavailable]"
        return str(val["_value"]) if "_value" in val else "[dynamic]"
    return str(val) if val is not None else fallback


def _resolve_str(val: Any, fallback: str = "") -> str:
    """HTML-escaped string for inline content."""
    return html.escape(_raw_str(val, fallback))


def _resolve_bool(val: Any, default: bool = False) -> bool:
    if isinstance(val, dict):
        if val.get("_error"):
            return default  # evaluation failed — treat as "not set"
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


def _build_nav(root_args: dict, prefix: str = "") -> tuple[list, list]:
    """Parse root args into (top_executes, nav_items).

    top_executes  list of (key, node) for root-level execute buttons shown in the top bar.
    nav_items     list of nav dicts with keys:
                    key, name, node, panel_id, mode ('container'|'leaf'), children
                  children is a (possibly empty) list of sub-nav dicts with the same
                  shape minus 'mode' and 'children'.

    *prefix* is prepended to panel IDs to namespace them within a tab.
    """
    top_executes: list[tuple[str, dict]] = []
    nav_items: list[dict] = []

    for key, node in _sorted_children(root_args):
        t = node.get("type", "")
        if t == "execute":
            top_executes.append((key, node))
        elif t == "group":
            name = _atlas_replace(_resolve_str(node.get("name", key)))
            mode, sub_groups = _classify_root_group(node)
            children: list[dict] = []
            if mode == "container":
                for ckey, cnode in sub_groups:
                    cname = _atlas_replace(_resolve_str(cnode.get("name", ckey)))
                    children.append(
                        {
                            "key": ckey,
                            "name": cname,
                            "node": cnode,
                            "panel_id": f"p-{prefix}{key}-{ckey}",
                        }
                    )
            nav_items.append(
                {
                    "key": key,
                    "name": name,
                    "node": node,
                    "panel_id": f"p-{prefix}{key}",
                    "mode": mode,
                    "children": children,
                }
            )

    return top_executes, nav_items


def _build_tabs(root: dict) -> list[dict]:
    """Build tab list from a root node with ``childGroups='select'``.

    Each tab dict has: key, name, node, has_tree, top_executes, nav_items,
    hidden.
    """
    tabs: list[dict] = []
    for key, node in _sorted_children(root.get("args", {})):
        if node.get("type") != "group":
            continue
        has_tree = node.get("childGroups") == "tree"
        if has_tree:
            prefix = f"{key}-"
            top_executes, nav_items = _build_nav(node.get("args", {}), prefix=prefix)
        else:
            top_executes, nav_items = [], []
        name = _atlas_replace(_resolve_str(node.get("name", key)))
        tabs.append(
            {
                "key": key,
                "name": name,
                "node": node,
                "has_tree": has_tree,
                "top_executes": top_executes,
                "nav_items": nav_items,
                "hidden": _is_hidden(node),
            }
        )
    return tabs


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
    if desc and desc not in ("[dynamic]", "[unavailable]"):
        parts.append(desc)
    dyn_fields = [
        f
        for f in ("get", "hidden", "disabled", "values")
        if isinstance(node.get(f), dict) and node.get(f, {}).get("_dynamic")
    ]
    if dyn_fields:
        parts.append(f"[dynamic: {', '.join(dyn_fields)}]")
    err_fields = [
        f
        for f in ("get", "hidden", "disabled", "values")
        if isinstance(node.get(f), dict) and node.get(f, {}).get("_error")
    ]
    if err_fields:
        parts.append(f"[eval error: {', '.join(err_fields)}]")
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

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    def render(self, root: dict) -> str:
        if root.get("childGroups") == "select":
            return self._render_tabbed(root)
        return self._render_flat(root)

    # ------------------------------------------------------------------
    # Flat layout (legacy / non-select root)
    # ------------------------------------------------------------------

    def _render_flat(self, root: dict) -> str:
        top_executes, nav_items = _build_nav(root.get("args", {}))

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
    # Tabbed layout (root childGroups="select")
    # ------------------------------------------------------------------

    def _render_tabbed(self, root: dict) -> str:
        tabs = _build_tabs(root)
        if not tabs:
            return self._render_flat(root)

        first_tab = tabs[0]

        self._w(HTML_HEAD)
        self._w('<div class="app">')

        # ── Top bar ────────────────────────────────────────────────────────
        self._w('<header class="top-bar">')
        self._w('<span class="addon-title">RPGLootFeed</span>')
        self._w("</header>")

        # ── Tab bar ────────────────────────────────────────────────────────
        self._w('<div class="tab-bar">')
        for i, tab in enumerate(tabs):
            active = " active" if i == 0 else ""
            hcls = " tab-hidden" if tab["hidden"] else ""
            self._w(
                f'<button class="tab{active}{hcls}" data-tab="{tab["key"]}" '
                f'onclick="selectTab(this)">{tab["name"]}</button>'
            )
        self._w("</div>")

        # ── Workspace ─────────────────────────────────────────────────────
        self._w('<div class="workspace">')

        # ── Sidebar (one section per tab) ─────────────────────────────────
        self._w('<nav class="sidebar">')
        for i, tab in enumerate(tabs):
            active = " tab-sidebar-active" if i == 0 else ""
            self._w(f'<div class="tab-sidebar{active}" data-tab="{tab["key"]}">')
            if tab["nav_items"]:
                self._render_nav(tab["nav_items"])
            self._w("</div>")
        self._w("</nav>")

        # ── Content panels (all tabs) ─────────────────────────────────────
        self._w('<main class="content" id="content">')
        for tab in tabs:
            if tab["nav_items"]:
                self._render_all_panels(tab["nav_items"])
            else:
                # Simple tab — render all children as a single panel
                panel_id = f'p-{tab["key"]}'
                self._render_panel(panel_id, tab["key"], tab["node"])
        self._w("</main>")

        self._w("</div>")  # workspace
        self._w("</div>")  # app
        self._w('<div id="tooltip"></div>')

        # Default panel: first child of first tab's first nav item,
        # or the tab's direct panel for simple tabs.
        default_panel = ""
        if first_tab["nav_items"]:
            for item in first_tab["nav_items"]:
                if item["children"]:
                    default_panel = item["children"][0]["panel_id"]
                else:
                    default_panel = item["panel_id"]
                break
        else:
            default_panel = f'p-{first_tab["key"]}'

        self._w(
            HTML_FOOT.replace("__DEFAULT_PANEL__", default_panel).replace(
                "__DEFAULT_TAB__", first_tab["key"]
            )
        )
        return "\n".join(self._buf)

    # ------------------------------------------------------------------
    # Nav
    # ------------------------------------------------------------------

    def _render_nav(self, nav_items: list[dict]) -> None:
        for item in nav_items:
            hcls = " nav-hidden" if _is_hidden(item["node"]) else ""
            pid = item["panel_id"]
            if item["children"]:
                self._w(
                    f'<div class="nav-parent{hcls}" '
                    f'data-panel="{pid}" data-key="{pid}" '
                    f'onclick="toggleParent(this)">'
                    f'<span class="nav-arrow">&#x25BC;</span>'
                    f'<span class="nav-parent-name">{item["name"]}</span>'
                    f"</div>"
                )
                self._w(f'<div class="nav-children" id="children-{pid}">')
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
                    f'data-panel="{pid}" '
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
        name = _atlas_replace(html.escape(raw_name), height=16)
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

    /* ── Tab bar ── */
    .tab-bar {
      display: flex; gap: 0; background: #151515;
      border-bottom: 2px solid #3a3a3a; flex-shrink: 0;
      padding: 0 10px;
    }
    .tab {
      background: transparent; color: #999; border: none;
      padding: 7px 16px 6px; cursor: pointer; font-size: 0.88rem;
      border-bottom: 2px solid transparent;
      margin-bottom: -2px; transition: color 0.15s, border-color 0.15s;
      white-space: nowrap;
    }
    .tab:hover { color: #d0c080; }
    .tab.active {
      color: #e0c060; font-weight: bold;
      border-bottom-color: #e0c060;
    }
    .tab-hidden { opacity: 0.5; font-style: italic; }

    /* ── Workspace ── */
    .workspace { display: flex; flex: 1; overflow: hidden; }

    /* ── Sidebar ── */
    .sidebar {
      width: 190px; min-width: 140px;
      background: #181818; border-right: 1px solid #2e2e2e;
      overflow-y: auto; padding: 6px 0; flex-shrink: 0;
    }
    .tab-sidebar { display: none; }
    .tab-sidebar.tab-sidebar-active { display: block; }
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
    .atlas-icon { margin-right: 4px; }

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
      var wasCollapsed = children.classList.contains('collapsed');
      children.classList.toggle('collapsed');
      arrow.textContent = children.classList.contains('collapsed') ? '\\u25ba' : '\\u25bc';
      if (wasCollapsed) {
        /* Just expanded — auto-select the first child */
        var firstChild = children.querySelector('.nav-item');
        if (firstChild) {
          clearActive();
          el.classList.add('active');
          firstChild.classList.add('active');
          showPanel(firstChild.dataset.panel);
          return;
        }
      }
    }
    clearActive();
    el.classList.add('active');
    if (el.dataset.panel) showPanel(el.dataset.panel);
  };

  /* ── Tab switching ── */
  window.selectTab = function (el) {
    var tabKey = el.dataset.tab;

    /* Update tab buttons */
    document.querySelectorAll('.tab').forEach(function (t) { t.classList.remove('active'); });
    el.classList.add('active');

    /* Show correct sidebar section */
    document.querySelectorAll('.tab-sidebar').forEach(function (s) {
      s.classList.remove('tab-sidebar-active');
    });
    var sidebar = document.querySelector('.tab-sidebar[data-tab="' + tabKey + '"]');
    if (sidebar) sidebar.classList.add('tab-sidebar-active');

    /* Hide all panels and clear nav selection */
    document.querySelectorAll('.panel').forEach(function (p) { p.classList.remove('active'); });
    clearActive();

    /* Auto-select within the new tab's sidebar */
    if (sidebar) {
      var firstChild = sidebar.querySelector('.nav-children .nav-item');
      if (firstChild) { selectNav(firstChild); return; }
      var firstLeaf  = sidebar.querySelector('.nav-item');
      if (firstLeaf)  { selectNav(firstLeaf);  return; }
      var firstParent = sidebar.querySelector('.nav-parent');
      if (firstParent) { toggleParent(firstParent); return; }
    }

    /* Simple tab with no nav items — show its panel directly */
    var directPanel = document.getElementById('p-' + tabKey);
    if (directPanel) directPanel.classList.add('active');
  };

  /* ── Default selection ── */
  var defaultTab = document.querySelector('.tab[data-tab="__DEFAULT_TAB__"]');
  if (defaultTab) {
    selectTab(defaultTab);
  } else {
    /* Non-tabbed fallback */
    var first = document.querySelector('[data-panel="__DEFAULT_PANEL__"]');
    if (first) {
      first.classList.add('active');
      showPanel("__DEFAULT_PANEL__");
    }
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
