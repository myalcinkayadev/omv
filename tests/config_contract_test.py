"""Contracts between the config files. Reads files in this repo and nothing else."""

import re
import tomllib
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
AEROSPACE = REPO / "aerospace/.config/aerospace/aerospace.toml"
HAMMERSPOON = REPO / "hammerspoon/.hammerspoon/init.lua"
GHOSTTY = REPO / "ghostty/.config/ghostty/config"
PACKAGES = ("aerospace", "sketchybar", "claude", "swipeaerospace", "ghostty", "nvim", "btop", "hammerspoon")
SWIPE = REPO / "swipeaerospace/.config/swipeareospace/config.toml"

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


def load_swipe() -> dict:
    return tomllib.loads(SWIPE.read_text(encoding="utf-8"))


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

    def test_should_bind_option_tab_to_workspace_back_and_forth(self) -> None:
        bindings = load_aerospace()["mode"]["main"]["binding"]
        self.assertEqual(bindings.get("alt-tab"), "workspace-back-and-forth")

    def test_should_bind_option_shift_i_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-i", hammerspoon_keys())

    def test_should_subscribe_keep_awake_to_its_toggle_and_clicks(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("--subscribe keep_awake keep_awake_toggle mouse.clicked", source)

    def test_should_wrap_around_when_swiping_like_the_bar_scroll(self) -> None:
        self.assertIs(load_swipe().get("wrap"), True)

    def test_should_leave_the_swipe_up_overview_off(self) -> None:
        self.assertIs(load_swipe().get("swipeUpOverview"), False)

    def test_should_use_three_fingers_for_swipes(self) -> None:
        self.assertEqual(load_swipe().get("fingers"), "Three")

    def test_should_bind_option_escape_in_hammerspoon(self) -> None:
        self.assertIn("alt-escape", hammerspoon_keys())

    def test_should_bind_option_shift_u_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-u", hammerspoon_keys())

    def test_should_run_the_fit_check_on_its_event(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("--subscribe bar_fit bar_fit system_woke display_change", source)

    def test_should_check_the_fit_when_a_right_side_item_changes(self) -> None:
        plugins = REPO / "sketchybar/.config/sketchybar/plugins"
        triggers = ["--trigger bar_fit" in (plugins / name).read_text(encoding="utf-8") for name in ("claude_usage.sh", "keep_awake.sh")]
        triggers.append('"bar_fit"' in HAMMERSPOON.read_text(encoding="utf-8"))
        self.assertEqual(triggers, [True, True, True])

    def test_should_put_the_clock_at_the_far_right(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertLess(source.index("--add item clock right"), source.index("--add item battery right"))

    def test_should_open_the_calendar_card_when_the_clock_is_clicked(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("omvToggleCalendar()", source)

    def test_should_leave_no_calendar_popup_in_the_bar(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertNotIn("popup.clock", source)

    def test_should_start_borders_after_aerospace_starts(self) -> None:
        started = [c for c in load_aerospace()["after-startup-command"] if c.startswith("exec-and-forget borders ")]
        self.assertEqual(len(started), 1)

    def test_should_draw_the_border_in_the_card_gray_at_2pt(self) -> None:
        started = next(c for c in load_aerospace()["after-startup-command"] if c.startswith("exec-and-forget borders "))
        self.assertEqual(
            ["active_color=0xff8d8d8d" in started, "width=2.0" in started],
            [True, True],
        )

    def test_should_notify_only_when_ghostty_is_not_focused(self) -> None:
        self.assertIn("notify-on-command-finish = unfocused", GHOSTTY.read_text(encoding="utf-8"))

    def test_should_notify_for_commands_longer_than_10_seconds(self) -> None:
        self.assertIn("notify-on-command-finish-after = 10s", GHOSTTY.read_text(encoding="utf-8"))

    def test_should_bind_option_space_in_hammerspoon(self) -> None:
        self.assertIn("alt-space", hammerspoon_keys())

    def test_should_bind_option_shift_s_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-s", hammerspoon_keys())

    def test_should_subscribe_now_playing_to_track_changes_clicks_and_scrolling(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("--subscribe now_playing now_playing_change mouse.clicked mouse.scrolled", source)

    def test_should_watch_music_and_spotify_for_track_changes(self) -> None:
        source = HAMMERSPOON.read_text(encoding="utf-8")
        self.assertEqual(
            ["com.apple.Music.playerInfo" in source, "com.spotify.client.PlaybackStateChanged" in source],
            [True, True],
        )

    def test_should_bind_option_shift_m_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-m", hammerspoon_keys())

    def test_should_list_reminders_when_the_bar_item_is_clicked(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("omvToggleReminders()", source)

    def test_should_open_the_calendar_card_when_the_meeting_item_is_clicked(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        meeting = re.search(r"--add item meeting right(.*?)\n\n", source, re.S)
        self.assertIn("omvToggleCalendar()", meeting.group(1) if meeting else "")

    def test_should_subscribe_volume_to_clicks_for_the_sound_menu(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("--subscribe volume volume_change mouse.clicked mouse.scrolled", source)

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
