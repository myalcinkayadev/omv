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


def hammerspoon_source() -> str:
    """init.lua and every feature module, since the cards live in features/."""
    folder = HAMMERSPOON.parent
    files = [HAMMERSPOON, *sorted((folder / "features").glob("*.lua"))]
    return "\n".join(path.read_text(encoding="utf-8") for path in files)

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
    "com.apple.systempreferences",
    "com.apple.calculator",
}
# Finder names a Get Info window after the item, as in "report.txt Info".
FINDER_INFO_TITLE = " Info$"
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


def floating_rules() -> list[dict]:
    return [rule for rule in load_aerospace()["on-window-detected"] if "layout floating" in commands_for(rule)]


def finder_title_filters() -> list[str]:
    return [
        rule["if"]["window-title-regex-substring"]
        for rule in floating_rules()
        if rule["if"]["app-id"] == "com.apple.finder" and "window-title-regex-substring" in rule["if"]
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

    def test_should_float_system_settings_and_calculator(self) -> None:
        floating = {
            rule["if"]["app-id"]
            for rule in floating_rules()
            if "window-title-regex-substring" not in rule["if"]
        }
        self.assertEqual(floating, APPROVED_FLOATING)

    def test_should_float_a_finder_window_when_its_title_ends_in_info(self) -> None:
        self.assertIn(FINDER_INFO_TITLE, finder_title_filters())

    def test_should_match_a_get_info_title_with_the_finder_filter(self) -> None:
        self.assertRegex("report.txt Info", FINDER_INFO_TITLE)

    def test_should_keep_a_finder_folder_window_tiled_when_info_is_in_its_name(self) -> None:
        self.assertNotRegex("Info Docs", FINDER_INFO_TITLE)

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

    def test_should_go_to_each_workspace_with_option_and_the_numpad(self) -> None:
        bindings = load_aerospace()["mode"]["main"]["binding"]
        self.assertEqual(
            [bindings.get(f"alt-keypad{number}") for number in range(1, 7)],
            [f"workspace {number}" for number in range(1, 7)],
        )

    def test_should_send_the_window_to_each_workspace_with_option_shift_and_the_numpad(self) -> None:
        bindings = load_aerospace()["mode"]["main"]["binding"]
        self.assertEqual(
            [bindings.get(f"alt-shift-keypad{number}") for number in range(1, 7)],
            [f"move-node-to-workspace {number}" for number in range(1, 7)],
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

    def test_should_bind_option_shift_d_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-d", hammerspoon_keys())

    def test_should_bind_option_shift_g_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-g", hammerspoon_keys())

    def test_should_bind_option_shift_a_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-a", hammerspoon_keys())

    def test_should_bind_option_shift_c_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-c", hammerspoon_keys())

    def test_should_bind_option_shift_u_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-u", hammerspoon_keys())

    def test_should_bind_option_shift_x_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-x", hammerspoon_keys())

    def test_should_subscribe_the_disk_item_to_clicks(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("--subscribe disk system_woke mouse.clicked", source)

    def test_should_define_the_disk_card_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvToggleDisk = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_define_the_tailscale_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvToggleTailscale = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_define_the_focus_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvToggleFocus = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_define_the_stop_recording_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvStopRecording = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_stop_a_recording_from_the_bar(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("click_script=\"hs -c 'omvStopRecording()'\"", source)

    def test_should_define_the_lyrics_window_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvToggleLyrics = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_run_the_fit_check_on_its_event(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("--subscribe bar_fit bar_fit system_woke display_change", source)

    def test_should_ask_hammerspoon_to_redraw_its_items_when_the_bar_starts(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("hs -t 2 -c 'omvRedrawBar()' >/dev/null 2>&1 &", source)

    def test_should_define_the_bar_redraw_in_hammerspoon(self) -> None:
        self.assertIn("omvRedrawBar = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_draw_the_focus_outline_at_1x_to_save_memory(self) -> None:
        commands = " ".join(load_aerospace()["after-startup-command"])
        self.assertIn("borders ", commands)
        self.assertIn("hidpi=off", commands)

    def test_should_place_claudes_item_left_of_the_weather(self) -> None:
        # Right-side items are added from the right edge inward, so a later one sits further left.
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertLess(source.index("--add item weather right"), source.index("--add item claude_waiting right"))

    def test_should_place_claudes_item_left_of_keep_awake(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertLess(source.index("--add item keep_awake right"), source.index("--add item claude_waiting right"))

    def test_should_give_the_status_icons_one_fixed_width(self) -> None:
        # Icons differ in width, so a fixed, centered slot keeps their centers evenly spaced.
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertRegex(source, r"STATUS_ICON=\([^)]*icon\.width=\d+[^)]*icon\.align=center")
        slots = []
        for name in ("battery", "volume", "wifi", "ethernet", "keep_awake"):
            settings = source[source.index(f"--set {name} "):source.index("--subscribe " + name)]
            slots.append('"${STATUS_ICON[@]}"' in settings)
        self.assertEqual(slots, [True] * 5)

    def test_should_place_the_waiting_pill_directly_right_of_claudes_usage(self) -> None:
        # The pill is added just before the usage item, so nothing sits between them.
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        items = re.findall(r"--add item (\S+) right", source)
        self.assertEqual(items[items.index("claude_waiting") + 1], "claude_usage")

    def test_should_draw_the_waiting_pill_without_an_icon(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        settings = source[source.index("--set claude_waiting"):source.index("--subscribe claude_waiting")]
        self.assertIn("icon.drawing=off", settings)

    def test_should_check_the_fit_when_a_right_side_item_changes(self) -> None:
        plugins = REPO / "sketchybar/.config/sketchybar/plugins"
        triggers = ["--trigger bar_fit" in (plugins / name).read_text(encoding="utf-8") for name in ("claude_usage.sh", "keep_awake.sh", "github_prs.sh", "claude_waiting.sh")]
        triggers.append('"bar_fit"' in hammerspoon_source())
        self.assertEqual(triggers, [True, True, True, True, True])

    def test_should_bind_option_a_to_the_accordion_toggle(self) -> None:
        self.assertEqual(load_aerospace()["mode"]["main"]["binding"].get("alt-a"), "layout accordion tiles")

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

    def test_should_join_the_meeting_when_the_meeting_item_is_clicked(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        meeting = re.search(r"--add item meeting right(.*?)\n\n", source, re.S)
        self.assertIn("omvJoinMeeting()", meeting.group(1) if meeting else "")

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


    def test_should_list_in_the_brewfiles_every_tool_and_app_doctor_checks(self) -> None:
        doctor = (REPO / "doctor.sh").read_text(encoding="utf-8")
        brewfiles = (REPO / "Brewfile").read_text(encoding="utf-8") + (REPO / "Brewfile.apps").read_text(encoding="utf-8")
        tools = re.search(r"for tool in ([^;]+); do", doctor).group(1).split()
        apps = re.search(r"for app in ([^;]+); do", doctor).group(1).split()
        # swiftc comes with Xcode's Command Line Tools, which Homebrew doesn't install.
        missing = [name for name in tools + apps if name != "swiftc" and name.lower() not in brewfiles.lower()]
        self.assertEqual(missing, [])

    def test_should_keep_the_helium_and_zed_apps_out_of_the_main_brewfile(self) -> None:
        installs = re.findall(r'^(?:brew|cask) "([^"]+)"', (REPO / "Brewfile").read_text(encoding="utf-8"), re.M)
        self.assertEqual([name for name in installs if name in ("helium-browser", "zed")], [])

    def test_should_redraw_wifi_and_ethernet_on_hammerspoons_network_event(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        subscribed = [re.search(rf"--subscribe {name} ([^\n]*)", source).group(1).split() for name in ("wifi", "ethernet")]
        self.assertEqual(["omv_network_change" in events for events in subscribed], [True, True])

    def test_should_redraw_battery_on_hammerspoons_battery_event(self) -> None:
        source = (REPO / "sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("omv_battery_change", re.search(r"--subscribe battery ([^\n]*)", source).group(1).split())

if __name__ == "__main__":
    unittest.main()
