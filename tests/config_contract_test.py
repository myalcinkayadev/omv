"""Contracts between the config files. Reads files in this repo and nothing else."""

import re
import tomllib
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
AEROSPACE = REPO / "aerospace/.config/aerospace/aerospace.toml"
HAMMERSPOON = REPO / "hammerspoon/.hammerspoon/init.lua"
GHOSTTY = REPO / "ghostty/.config/ghostty/config"
PACKAGES = ("aerospace", "sketchybar", "claude", "ghostty", "nvim", "btop", "hammerspoon")

APPROVED_ROUTES = {
    "com.mitchellh.ghostty": "1",
    "dev.zed.Zed": "2",
    "net.imput.helium": "3",
    "md.obsidian": "4",
    "notion.id": "4",
    "com.linear": "4",
    "com.apple.Notes": "5",
    "com.apple.MobileSMS": "5",
    "net.whatsapp.WhatsApp": "5",
    "com.hnc.Discord": "5",
    "com.apple.Music": "6",
    "com.spotify.client": "6",
}
APPROVED_FLOATING = {
    "com.apple.finder",
    "com.apple.systempreferences",
    "com.apple.calculator",
}
HAMMERSPOON_MODIFIERS = {"SUPER": "alt", "SUPER_SHIFT": "alt-shift"}
HAMMERSPOON_KEYS = {"return": "enter", "44": "slash"}


def load_aerospace() -> dict:
    return tomllib.loads(AEROSPACE.read_text(encoding="utf-8"))


def commands_for(rule: dict) -> list[str]:
    run = rule["run"]
    return [run] if isinstance(run, str) else run


def aerospace_keys() -> set[str]:
    return set(load_aerospace()["mode"]["main"]["binding"])


def hammerspoon_keys() -> list[str]:
    source = HAMMERSPOON.read_text(encoding="utf-8")
    bindings = re.findall(r'bindKey\((SUPER\w*),\s*"?(\w+)"?', source)
    return [
        f"{HAMMERSPOON_MODIFIERS[modifier]}-{HAMMERSPOON_KEYS.get(key, key)}"
        for modifier, key in bindings
    ]


class ConfigContract(unittest.TestCase):
    def test_should_bind_each_key_only_once_when_aerospace_and_hammerspoon_are_compared(self) -> None:
        self.assertEqual(aerospace_keys() & set(hammerspoon_keys()), set())

    def test_should_route_every_assigned_app_to_its_approved_workspace(self) -> None:
        routes = {}
        for rule in load_aerospace()["on-window-detected"]:
            for command in commands_for(rule):
                match = re.fullmatch(r"move-node-to-workspace (\w+)", command)
                if match:
                    routes[rule["if"]["app-id"]] = match.group(1)
        self.assertEqual(routes, APPROVED_ROUTES)

    def test_should_float_finder_system_settings_and_calculator(self) -> None:
        floating = {
            rule["if"]["app-id"]
            for rule in load_aerospace()["on-window-detected"]
            if "layout floating" in commands_for(rule)
        }
        self.assertEqual(floating, APPROVED_FLOATING)

    def test_should_run_start_btop_when_aerospace_starts(self) -> None:
        self.assertIn(
            "exec-and-forget $HOME/.config/ghostty/start-btop.sh",
            load_aerospace()["after-startup-command"],
        )

    def test_should_use_new_window_script_for_option_enter(self) -> None:
        self.assertIn(
            "exec-and-forget $HOME/.config/ghostty/new-window.sh",
            load_aerospace()["mode"]["main"]["binding"]["alt-enter"],
        )

    def test_should_leave_no_open_na_ghostty_in_any_config(self) -> None:
        stale = [
            str(path.relative_to(REPO))
            for package in PACKAGES
            for path in (REPO / package).rglob("*")
            if path.is_file() and re.search(r'open -na Ghostty|"-na", "Ghostty"', path.read_text(encoding="utf-8", errors="ignore"))
        ]
        self.assertEqual(stale, [])

    def test_should_find_the_hammerspoon_keys_when_parsing_init_lua(self) -> None:
        self.assertIn("alt-slash", hammerspoon_keys())

    def test_should_leave_resize_mode_when_escape_or_enter_is_pressed(self) -> None:
        resize = load_aerospace()["mode"]["resize"]["binding"]
        self.assertEqual(
            ["mode main" in resize[key] for key in ("esc", "enter")],
            [True, True],
        )

    def test_should_have_no_ctrl_option_bindings_left(self) -> None:
        self.assertEqual([key for key in aerospace_keys() if key.startswith("ctrl-alt")], [])

    def test_should_bind_the_quick_terminal_in_the_ghostty_config(self) -> None:
        self.assertIn(
            "keybind = global:alt+backquote=toggle_quick_terminal",
            GHOSTTY.read_text(encoding="utf-8"),
        )

    def test_should_show_the_claude_logo_when_the_usage_item_is_drawn(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn('icon.background.image="$CONFIG_DIR/icons/claude.png"', source)

    def test_should_ship_the_claude_logo_file(self) -> None:
        self.assertTrue((REPO / "sketchybar/.config/sketchybar/icons/claude.png").is_file())

    def test_should_keep_workspace_6_alive_when_empty(self) -> None:
        self.assertIn("6", load_aerospace()["persistent-workspaces"])

    def test_should_bind_workspace_6_keys(self) -> None:
        self.assertEqual(
            [aerospace_keys() >= {"alt-6"}, aerospace_keys() >= {"alt-shift-6"}],
            [True, True],
        )

    def test_should_subscribe_every_workspace_item_to_scrolling(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn('--subscribe "space.$number" mouse.scrolled', source)

    def test_should_leave_no_omniwmctl_or_dmenu_reference_in_any_config(self) -> None:
        stale = [
            str(path.relative_to(REPO))
            for package in PACKAGES
            for path in (REPO / package).rglob("*")
            if path.is_file() and re.search(r"omniwmctl|dmenu", path.read_text(encoding="utf-8", errors="ignore"))
        ]
        self.assertEqual(stale, [])


if __name__ == "__main__":
    unittest.main()
