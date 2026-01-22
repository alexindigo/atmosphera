"""
Terminal theme generation for multiple terminal emulators.

Generates native theme files from a unified terminal color schema.
Supports: foot, ghostty, kitty, alacritty, wezterm
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class TerminalColors:
    """Terminal color scheme data."""

    foreground: str
    background: str
    cursor: str
    cursor_text: str
    selection_fg: str
    selection_bg: str
    normal: dict[str, str]  # black, red, green, yellow, blue, magenta, cyan, white
    bright: dict[str, str]  # same keys

    # Extended colors (optional, for wezterm etc.)
    compose_cursor: Optional[str] = None
    scrollbar_thumb: Optional[str] = None
    split: Optional[str] = None
    visual_bell: Optional[str] = None

    # Indexed colors (optional)
    indexed: dict[int, str] = field(default_factory=dict)

    # Tab bar colors (optional, for wezterm)
    tab_bar: Optional[dict] = None

    @classmethod
    def from_dict(cls, data: dict) -> "TerminalColors":
        """Create TerminalColors from a dictionary (JSON schema format)."""
        return cls(
            foreground=data["foreground"],
            background=data["background"],
            cursor=data["cursor"],
            cursor_text=data.get("cursorText", data["background"]),
            selection_fg=data.get("selectionFg", data["foreground"]),
            selection_bg=data.get("selectionBg", data.get("cursor", "#585b70")),
            normal=data["normal"],
            bright=data["bright"],
            compose_cursor=data.get("composeCursor"),
            scrollbar_thumb=data.get("scrollbarThumb"),
            split=data.get("split"),
            visual_bell=data.get("visualBell"),
            indexed=data.get("indexed", {}),
            tab_bar=data.get("tabBar"),
        )


# Color name to index mapping for ANSI colors
COLOR_ORDER = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]


class TerminalGenerator:
    """Generate terminal themes in native formats."""

    def __init__(self, colors: TerminalColors):
        self.colors = colors

    def _strip_hash(self, color: str) -> str:
        """Remove # prefix from hex color."""
        return color.lstrip("#")

    def _ensure_hash(self, color: str) -> str:
        """Ensure # prefix on hex color."""
        return color if color.startswith("#") else f"#{color}"

    def generate_foot(self) -> str:
        """Generate foot terminal theme (INI format, no # prefix)."""
        c = self.colors
        lines = ["[colors]"]

        # Primary colors
        lines.append(f"foreground={self._strip_hash(c.foreground)}")
        lines.append(f"background={self._strip_hash(c.background)}")

        # Normal colors (regular0-7)
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"regular{i}={self._strip_hash(c.normal[name])}")

        # Bright colors (bright0-7)
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"bright{i}={self._strip_hash(c.bright[name])}")

        # Selection
        lines.append(f"selection-foreground={self._strip_hash(c.selection_fg)}")
        lines.append(f"selection-background={self._strip_hash(c.selection_bg)}")

        # Cursor (format: bg fg)
        lines.append(
            f"cursor={self._strip_hash(c.cursor_text)} {self._strip_hash(c.cursor)}"
        )

        return "\n".join(lines) + "\n"

    def generate_ghostty(self) -> str:
        """Generate ghostty theme (key=value with palette indices)."""
        c = self.colors
        lines = []

        # Palette (0-7 normal, 8-15 bright)
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"palette = {i}={self._ensure_hash(c.normal[name])}")
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"palette = {i + 8}={self._ensure_hash(c.bright[name])}")

        # Primary colors
        lines.append(f"background = {self._ensure_hash(c.background)}")
        lines.append(f"foreground = {self._ensure_hash(c.foreground)}")

        # Cursor
        lines.append(f"cursor-color = {self._ensure_hash(c.cursor)}")
        lines.append(f"cursor-text = {self._ensure_hash(c.cursor_text)}")

        # Selection
        lines.append(f"selection-background = {self._ensure_hash(c.selection_bg)}")
        lines.append(f"selection-foreground = {self._ensure_hash(c.selection_fg)}")

        return "\n".join(lines) + "\n"

    def generate_kitty(self) -> str:
        """Generate kitty theme (key value pairs with # prefix)."""
        c = self.colors
        lines = []

        # Colors 0-15
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"color{i} {self._ensure_hash(c.normal[name])}")
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"color{i + 8} {self._ensure_hash(c.bright[name])}")

        # Primary colors
        lines.append(f"background {self._ensure_hash(c.background)}")
        lines.append(f"selection_foreground {self._ensure_hash(c.cursor_text)}")
        lines.append(f"cursor {self._ensure_hash(c.cursor)}")
        lines.append(f"cursor_text_color {self._ensure_hash(c.cursor_text)}")
        lines.append(f"foreground {self._ensure_hash(c.foreground)}")
        lines.append(f"selection_background {self._ensure_hash(c.foreground)}")

        return "\n".join(lines) + "\n"

    def generate_alacritty(self) -> str:
        """Generate alacritty theme (TOML format)."""
        c = self.colors
        lines = ["# Colors (Noctalia)", ""]

        # Bright colors
        lines.append("[colors.bright]")
        for name in sorted(COLOR_ORDER):
            lines.append(f"{name} = '{self._ensure_hash(c.bright[name])}'")
        lines.append("")

        # Cursor
        lines.append("[colors.cursor]")
        lines.append(f"cursor = '{self._ensure_hash(c.cursor)}'")
        lines.append(f"text = '{self._ensure_hash(c.cursor_text)}'")
        lines.append("")

        # Normal colors
        lines.append("[colors.normal]")
        for name in sorted(COLOR_ORDER):
            lines.append(f"{name} = '{self._ensure_hash(c.normal[name])}'")
        lines.append("")

        # Primary
        lines.append("[colors.primary]")
        lines.append(f"background = '{self._ensure_hash(c.background)}'")
        lines.append(f"foreground = '{self._ensure_hash(c.foreground)}'")
        lines.append("")

        # Selection
        lines.append("[colors.selection]")
        lines.append(f"background = '{self._ensure_hash(c.selection_bg)}'")
        lines.append(f"text = '{self._ensure_hash(c.selection_fg)}'")

        return "\n".join(lines) + "\n"

    def generate_wezterm(self) -> str:
        """Generate wezterm theme (full TOML with metadata)."""
        c = self.colors
        lines = ["[colors]"]

        # Ansi colors array
        lines.append("ansi = [")
        for name in COLOR_ORDER:
            lines.append(f'    "{self._ensure_hash(c.normal[name])}",')
        lines.append("]")

        # Primary
        lines.append(f'background = "{self._ensure_hash(c.background)}"')

        # Brights array
        lines.append("brights = [")
        for name in COLOR_ORDER:
            lines.append(f'    "{self._ensure_hash(c.bright[name])}",')
        lines.append("]")

        # Extended colors
        if c.compose_cursor:
            lines.append(f'compose_cursor = "{self._ensure_hash(c.compose_cursor)}"')

        lines.append(f'cursor_bg = "{self._ensure_hash(c.cursor)}"')
        lines.append(f'cursor_border = "{self._ensure_hash(c.cursor)}"')
        lines.append(f'cursor_fg = "{self._ensure_hash(c.cursor_text)}"')
        lines.append(f'foreground = "{self._ensure_hash(c.foreground)}"')

        if c.scrollbar_thumb:
            lines.append(f'scrollbar_thumb = "{self._ensure_hash(c.scrollbar_thumb)}"')

        lines.append(f'selection_bg = "{self._ensure_hash(c.selection_bg)}"')
        lines.append(f'selection_fg = "{self._ensure_hash(c.selection_fg)}"')

        if c.split:
            lines.append(f'split = "{self._ensure_hash(c.split)}"')

        if c.visual_bell:
            lines.append(f'visual_bell = "{self._ensure_hash(c.visual_bell)}"')

        # Indexed colors
        if c.indexed:
            lines.append("")
            lines.append("[colors.indexed]")
            for idx, color in sorted(c.indexed.items()):
                lines.append(f'{idx} = "{self._ensure_hash(color)}"')

        # Tab bar (optional)
        if c.tab_bar:
            tb = c.tab_bar
            lines.append("")
            lines.append("[colors.tab_bar]")
            if "background" in tb:
                lines.append(f'background = "{self._ensure_hash(tb["background"])}"')
            if "inactiveTabEdge" in tb:
                lines.append(
                    f'inactive_tab_edge = "{self._ensure_hash(tb["inactiveTabEdge"])}"'
                )

            # Active tab
            if "activeTab" in tb:
                at = tb["activeTab"]
                lines.append("")
                lines.append("[colors.tab_bar.active_tab]")
                lines.append(f'bg_color = "{self._ensure_hash(at.get("bg", c.cursor))}"')
                lines.append(
                    f'fg_color = "{self._ensure_hash(at.get("fg", c.cursor_text))}"'
                )
                lines.append('intensity = "Normal"')
                lines.append("italic = false")
                lines.append("strikethrough = false")
                lines.append('underline = "None"')

            # Inactive tab
            if "inactiveTab" in tb:
                it = tb["inactiveTab"]
                lines.append("")
                lines.append("[colors.tab_bar.inactive_tab]")
                lines.append(
                    f'bg_color = "{self._ensure_hash(it.get("bg", c.background))}"'
                )
                lines.append(
                    f'fg_color = "{self._ensure_hash(it.get("fg", c.foreground))}"'
                )
                lines.append('intensity = "Normal"')
                lines.append("italic = false")
                lines.append("strikethrough = false")
                lines.append('underline = "None"')

            # Inactive tab hover
            if "inactiveTabHover" in tb:
                ith = tb["inactiveTabHover"]
                lines.append("")
                lines.append("[colors.tab_bar.inactive_tab_hover]")
                lines.append(
                    f'bg_color = "{self._ensure_hash(ith.get("bg", c.background))}"'
                )
                lines.append(
                    f'fg_color = "{self._ensure_hash(ith.get("fg", c.foreground))}"'
                )
                lines.append('intensity = "Normal"')
                lines.append("italic = false")
                lines.append("strikethrough = false")
                lines.append('underline = "None"')

            # New tab
            if "newTab" in tb:
                nt = tb["newTab"]
                lines.append("")
                lines.append("[colors.tab_bar.new_tab]")
                lines.append(
                    f'bg_color = "{self._ensure_hash(nt.get("bg", c.selection_bg))}"'
                )
                lines.append(
                    f'fg_color = "{self._ensure_hash(nt.get("fg", c.foreground))}"'
                )
                lines.append('intensity = "Normal"')
                lines.append("italic = false")
                lines.append("strikethrough = false")
                lines.append('underline = "None"')

            # New tab hover
            if "newTabHover" in tb:
                nth = tb["newTabHover"]
                lines.append("")
                lines.append("[colors.tab_bar.new_tab_hover]")
                lines.append(
                    f'bg_color = "{self._ensure_hash(nth.get("bg", c.bright["black"]))}"'
                )
                lines.append(
                    f'fg_color = "{self._ensure_hash(nth.get("fg", c.foreground))}"'
                )
                lines.append('intensity = "Normal"')
                lines.append("italic = false")
                lines.append("strikethrough = false")
                lines.append('underline = "None"')

        # Metadata
        lines.append("")
        lines.append("[metadata]")
        lines.append('author = "Noctalia"')
        lines.append('name = "Noctalia"')

        return "\n".join(lines) + "\n"

    def generate(self, terminal_id: str) -> str:
        """Generate theme for specified terminal."""
        generators = {
            "foot": self.generate_foot,
            "ghostty": self.generate_ghostty,
            "kitty": self.generate_kitty,
            "alacritty": self.generate_alacritty,
            "wezterm": self.generate_wezterm,
        }

        if terminal_id not in generators:
            raise ValueError(f"Unknown terminal: {terminal_id}")

        return generators[terminal_id]()
