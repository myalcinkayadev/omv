"""Contracts between the config files. Reads files in this repo and nothing else."""

import re
import tomllib
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
AEROSPACE = REPO / "aerospace/.config/aerospace/aerospace.toml"
HAMMERSPOON = REPO / "hammerspoon/.hammerspoon/init.lua"
PACKAGES = ("aerospace", "sketchybar", "ghostty", "nvim", "btop", "hammerspoon")

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
}
APPROVED_FLOATING = {
    "com.apple.finder",
    "com.apple.systempreferences",
    "com.apple.calculator",
}
HAMMERSPOON_MODIFIERS = {"SUPER": "alt", "SUPER_SHIFT": "alt-shift"}
HAMMERSPOON_KEYS = {"return": "enter"}


def load_aerospace() -> dict:
    return tomllib.loads(AEROSPACE.read_text(encoding="utf-8"))


def commands_for(rule: dict) -> list[str]:
    run = rule["run"]
    return [run] if isinstance(run, str) else run


def aerospace_keys() -> set[str]:
    return set(load_aerospace()["mode"]["main"]["binding"])


def hammerspoon_keys() -> list[str]:
    source = HAMMERSPOON.read_text(encoding="utf-8")
    bindings = re.findall(r'hs\.hotkey\.bind\((\w+),\s*"(\w+)"', source)
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

    def test_should_leave_no_omniwmctl_or_dmenu_reference_in_any_config(self) -> None:
        stale = [
            str(path.relative_to(REPO))
            for package in PACKAGES
            for path in (REPO / package).rglob("*")
            if path.is_file() and re.search(r"omniwmctl|dmenu", path.read_text(encoding="utf-8"))
        ]
        self.assertEqual(stale, [])


if __name__ == "__main__":
    unittest.main()
