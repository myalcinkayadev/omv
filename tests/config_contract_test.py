"""Contracts between the config files. Reads files in this repo and nothing else."""

import re
import tomllib
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
AEROSPACE = REPO / "config/aerospace/.config/aerospace/aerospace.toml"
HAMMERSPOON = REPO / "config/hammerspoon/init.lua"
GHOSTTY = REPO / "config/ghostty/.config/ghostty/config"
PACKAGES = tuple(
    f"config/{name}" for name in ("aerospace", "sketchybar", "swipeaerospace", "ghostty", "nvim", "btop", "hammerspoon")
) + ("agents/claude",)
SWIPE = REPO / "config/swipeaerospace/.config/swipeareospace/config.toml"


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
FLAGS = REPO / "config/hammerspoon/flags.lua"
SKETCHYBARRC = REPO / "config/sketchybar/.config/sketchybar/sketchybarrc"
# The desktop itself, which every flag leaves loaded.
CORE_FEATURES = {"menu", "keys", "windows", "workspaces", "theme", "permissions"}
# Each optional feature module and the flag that loads it.
FEATURE_FLAGS = {
    "weather": "weather", "battery": "battery", "bluetooth": "bluetooth", "network": "network",
    "sound": "sound", "calendar": "calendar", "disk": "disk", "tailscale": "tailscale",
    "focus": "focus", "meeting": "meeting-mode", "clipboard": "clipboard", "translate": "translate", "capture": "capture",
    "reminders": "reminders", "note": "daily-note", "share": "airdrop", "nightshift": "night-light",
    "micmute": "mic-mute", "osd": "volume-popups", "procs": "processes", "lyrics": "lyrics",
    "agents": "claude", "waiting": "claude", "sendto": "send-to-agent", "digest": "away-digest", "prs": "github-prs", "ci": "github-ci", "devlayout": "dev-layout", "stalls": "stalls",
}

# Each bar item a flag hides; the workspaces, mode, clock and bar_fit are the desktop's own.
BAR_ITEM_FLAGS = {
    "now_playing": "now-playing", "battery": "battery", "volume": "sound", "bluetooth": "bluetooth",
    "wifi": "network", "ethernet": "network", "weather": "weather", "keep_awake": "keep-awake",
    "disk": "disk", "clipboard_paused": "clipboard", "nightlight": "night-light", "mic_muted": "mic-mute",
    "tailscale": "tailscale", "focus": "focus", "recording": "capture", "claude_waiting": "claude",
    "claude_usage": "claude", "github_prs": "github-prs", "github_ci": "github-ci", "reminder": "reminders", "meeting": "calendar",
}
BAR_CORE_ITEMS = {"aerospace_listener", "mode", "clock", "bar_fit"}


def bar_items_with_flags() -> dict[str, set[str]]:
    """Each item sketchybarrc adds, with the flags of the if omv_flag_on blocks around it."""
    found, stack = {}, []
    for line in SKETCHYBARRC.read_text(encoding="utf-8").splitlines():
        opened = re.match(r'\s*if omv_flag_on ([a-z-]+); then', line)
        if opened:
            stack.append(opened.group(1))
        elif re.match(r'\s*if\b', line):
            stack.append(None)
        elif re.match(r'\s*fi\b', line):
            stack.pop()
        for item in re.findall(r'--add item "?([\w.$]+)"?', line):
            found[item] = {flag for flag in stack if flag}
    return found


def flag_names() -> list[str]:
    return re.findall(r'^\s*\["([a-z-]+)"\]\s*=\s*(?:true|false)', FLAGS.read_text(encoding="utf-8"), re.M)

HAMMERSPOON_MODIFIERS = {"SUPER": "alt", "SUPER_SHIFT": "alt-shift"}
HAMMERSPOON_KEYS = {"return": "enter", "44": "slash"}


def load_aerospace() -> dict:
    return tomllib.loads(AEROSPACE.read_text(encoding="utf-8"))


def load_built_aerospace() -> dict:
    """aerospace.toml as omv builds it without a user file or workspaces file: omv's defaults."""
    import subprocess
    missing = str(REPO / "tests" / "no-such-file")
    built = subprocess.run(
        ["luajit", str(REPO / "install/aerospace_merge.lua"), str(AEROSPACE), missing, missing],
        capture_output=True, text=True, check=True,
    ).stdout
    return tomllib.loads(built)


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


# Features that run their commands with hs.task: hs.execute and hs.osascript.applescript wait
# on Hammerspoon's only thread, which freezes every card and key until the command finishes.
NON_BLOCKING_FEATURES = ("agents", "claudeprojects", "devlayout", "meeting", "procs", "network", "bluetooth", "waiting", "workspaces")
BLOCKING_CALL = re.compile(r"hs\.execute\(|hs\.osascript\.applescript\(|:waitUntilExit\(")


def blocking_calls(feature: str) -> list[str]:
    path = REPO / "config/hammerspoon/features" / f"{feature}.lua"
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines()
            if BLOCKING_CALL.search(line) and not line.lstrip().startswith("--")]


class ConfigContract(unittest.TestCase):
    def test_should_limit_the_bar_query_when_a_card_opens_under_the_bar(self) -> None:
        shell = (REPO / "config/hammerspoon/shell.lua").read_text(encoding="utf-8")
        anchored = shell[shell.index("function shell.anchored"):]
        anchored = anchored[:anchored.index("\nend\n")]
        self.assertIn("--query", anchored)
        self.assertRegex(anchored, r"alarm \d")

    def test_should_run_no_blocking_call_when_a_feature_was_made_non_blocking(self) -> None:
        for feature in NON_BLOCKING_FEATURES:
            with self.subTest(feature=feature):
                self.assertEqual(blocking_calls(feature), [])

    def test_should_bind_each_key_only_once_when_aerospace_and_hammerspoon_are_compared(self) -> None:
        self.assertEqual(aerospace_keys() & set(hammerspoon_keys()), set())

    def test_should_route_every_assigned_app_to_its_approved_workspace(self) -> None:
        routes = {}
        for rule in load_built_aerospace()["on-window-detected"]:
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

    def test_should_let_omv_theme_set_a_theme_in_hammerspoon(self) -> None:
        self.assertIn("omvSetTheme = ", HAMMERSPOON.read_text())

    def test_should_install_the_hs_command_after_loading_ipc(self) -> None:
        init = HAMMERSPOON.read_text()
        self.assertIn("hs.ipc.cliInstall(", init)
        self.assertLess(init.index('require("hs.ipc")'), init.index("hs.ipc.cliInstall("))

    def test_should_start_the_bar_only_when_none_is_running(self) -> None:
        self.assertIn(
            "exec-and-forget $HOME/.config/sketchybar/start.sh",
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
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn('icon.background.image="$CONFIG_DIR/icons/claude.png"', source)

    def test_should_ship_the_claude_logo_file(self) -> None:
        self.assertTrue((REPO / "config/sketchybar/.config/sketchybar/icons/claude.png").is_file())

    def test_should_keep_workspace_6_alive_when_empty(self) -> None:
        self.assertIn("6", load_aerospace()["persistent-workspaces"])

    def test_should_keep_the_dev_workspace_alive_when_empty(self) -> None:
        self.assertIn("7", load_aerospace()["persistent-workspaces"])

    def test_should_show_the_dev_workspace_on_the_main_monitor(self) -> None:
        self.assertEqual(load_aerospace()["workspace-to-monitor-force-assignment"]["7"], "main")

    def test_should_bind_the_dev_workspace_keys(self) -> None:
        self.assertEqual(
            [aerospace_keys() >= {"alt-7"}, aerospace_keys() >= {"alt-shift-7"}],
            [True, True],
        )

    def test_should_draw_an_item_per_workspace_aerospace_keeps(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn('for number in $("$PLUGIN_DIR/workspaces.sh"); do', source)

    def test_should_fall_back_to_seven_workspace_items_in_the_bar(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/plugins/workspaces.sh").read_text(encoding="utf-8")
        self.assertIn("numbers='1 2 3 4 5 6 7 '", source)

    def test_should_bind_workspace_6_keys(self) -> None:
        self.assertEqual(
            [aerospace_keys() >= {"alt-6"}, aerospace_keys() >= {"alt-shift-6"}],
            [True, True],
        )

    def test_should_go_to_each_workspace_with_option_and_the_numpad(self) -> None:
        bindings = load_aerospace()["mode"]["main"]["binding"]
        self.assertEqual(
            [bindings.get(f"alt-keypad{number}") for number in range(1, 8)],
            [f"workspace {number}" for number in range(1, 8)],
        )

    def test_should_send_the_window_to_each_workspace_with_option_shift_and_the_numpad(self) -> None:
        bindings = load_aerospace()["mode"]["main"]["binding"]
        self.assertEqual(
            [bindings.get(f"alt-shift-keypad{number}") for number in range(1, 8)],
            [f"move-node-to-workspace {number}" for number in range(1, 8)],
        )

    def test_should_bind_option_tab_to_workspace_back_and_forth(self) -> None:
        bindings = load_aerospace()["mode"]["main"]["binding"]
        self.assertEqual(bindings.get("alt-tab"), "workspace-back-and-forth")

    def test_should_bind_option_shift_i_in_hammerspoon(self) -> None:
        self.assertIn("alt-shift-i", hammerspoon_keys())

    def test_should_bind_option_m_in_hammerspoon(self) -> None:
        self.assertIn("alt-m", hammerspoon_keys())

    def test_should_redraw_the_mic_item_when_the_bar_restarts(self) -> None:
        source = (REPO / "config/hammerspoon/init.lua").read_text(encoding="utf-8")
        redraw = re.search(r"omvRedrawBar = later\(function\(\)(.*?)\nend\)", source, re.S)
        self.assertIsNotNone(redraw)
        self.assertIn("mic.redrawBar()", redraw.group(1))

    def test_should_list_projects_for_the_dev_layout_without_loading_the_agents_feature(self) -> None:
        # Loading the Agents feature starts its watchers, which the claude flag turns off.
        source = (REPO / "config/hammerspoon/features/devlayout.lua").read_text(encoding="utf-8")
        self.assertNotRegex(source, r'require\("features\.(agents|waiting)"\)')

    def test_should_start_no_watcher_or_timer_when_the_projects_reader_loads(self) -> None:
        source = (REPO / "config/hammerspoon/features/claudeprojects.lua").read_text(encoding="utf-8")
        self.assertNotRegex(source, r":start\(\)|doEvery|doAfter|watcher")

    def test_should_stop_a_waiting_location_retry_before_starting_another(self) -> None:
        source = (REPO / "config/hammerspoon/features/weather.lua").read_text(encoding="utf-8")
        read = re.search(r"local function readWeather\(tries\)\n(.*?)\nend\n", source, re.S)
        self.assertIsNotNone(read)
        body = read.group(1)
        self.assertLess(body.find("omvWeatherRetry:stop()"), body.find("omvWeatherRetry = hs.timer.doAfter"))
        self.assertNotEqual(body.find("omvWeatherRetry:stop()"), -1)

    def test_should_keep_the_weather_location_retry_from_garbage_collection(self) -> None:
        # Hammerspoon collects a timer nothing refers to, so the retry would never run.
        source = (REPO / "config/hammerspoon/features/weather.lua").read_text(encoding="utf-8")
        self.assertNotRegex(source, r"(?m)^\s*hs\.timer\.doAfter\(")

    def test_should_unmute_the_mic_when_its_bar_item_is_clicked(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        item = re.search(r"--add item mic_muted right[^\n]*\n[^\n]*", source)
        self.assertIsNotNone(item)
        self.assertIn("drawing=off", item.group(0))
        self.assertIn("omvToggleMic()", item.group(0))

    def test_should_subscribe_keep_awake_to_its_toggle_and_clicks(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
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
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("--subscribe disk system_woke mouse.clicked", source)

    def test_should_define_the_disk_card_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvToggleDisk = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_define_the_night_light_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvToggleNightLight = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_define_the_tailscale_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvToggleTailscale = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_define_the_focus_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvToggleFocus = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_define_the_stop_recording_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvStopRecording = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_stop_a_recording_from_the_bar(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("click_script=\"hs -c 'omvStopRecording()'\"", source)

    def test_should_define_the_lyrics_window_hook_in_hammerspoon(self) -> None:
        self.assertIn("omvToggleLyrics = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_run_the_fit_check_on_its_event(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("--subscribe bar_fit bar_fit system_woke display_change", source)

    def test_should_ask_hammerspoon_to_redraw_its_items_when_the_bar_starts(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("hs -t 2 -c 'omvRedrawBar()' >/dev/null 2>&1 &", source)

    def test_should_define_the_bar_redraw_in_hammerspoon(self) -> None:
        self.assertIn("omvRedrawBar = later(", HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_draw_the_focus_outline_at_1x_to_save_memory(self) -> None:
        commands = " ".join(load_aerospace()["after-startup-command"])
        self.assertIn("borders ", commands)
        self.assertIn("hidpi=off", commands)

    def test_should_place_claudes_item_left_of_the_weather(self) -> None:
        # Right-side items are added from the right edge inward, so a later one sits further left.
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertLess(source.index("--add item weather right"), source.index("--add item claude_waiting right"))

    def test_should_place_claudes_item_left_of_keep_awake(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertLess(source.index("--add item keep_awake right"), source.index("--add item claude_waiting right"))

    def test_should_give_the_status_icons_one_fixed_width(self) -> None:
        # Icons differ in width, so a fixed, centered slot keeps their centers evenly spaced.
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertRegex(source, r"STATUS_ICON=\([^)]*icon\.width=\d+[^)]*icon\.align=center")
        slots = []
        for name in ("battery", "volume", "wifi", "ethernet", "keep_awake"):
            settings = source[source.index(f"--set {name} "):source.index("--subscribe " + name)]
            slots.append('"${STATUS_ICON[@]}"' in settings)
        self.assertEqual(slots, [True] * 5)

    def test_should_place_the_waiting_pill_directly_right_of_claudes_usage(self) -> None:
        # The pill is added just before the usage item, so nothing sits between them.
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        items = re.findall(r"--add item (\S+) right", source)
        self.assertEqual(items[items.index("claude_waiting") + 1], "claude_usage")

    def test_should_draw_the_waiting_pill_without_an_icon(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        settings = source[source.index("--set claude_waiting"):source.index("--subscribe claude_waiting")]
        self.assertIn("icon.drawing=off", settings)

    def test_should_check_the_fit_when_a_right_side_item_changes(self) -> None:
        plugins = REPO / "config/sketchybar/.config/sketchybar/plugins"
        triggers = ["--trigger bar_fit" in (plugins / name).read_text(encoding="utf-8") for name in ("claude_usage.sh", "keep_awake.sh", "github_prs.sh", "github_ci.sh", "claude_waiting.sh")]
        triggers.append('"bar_fit"' in hammerspoon_source())
        self.assertEqual(triggers, [True, True, True, True, True, True])

    def test_should_bind_option_a_to_the_accordion_toggle(self) -> None:
        self.assertEqual(load_aerospace()["mode"]["main"]["binding"].get("alt-a"), "layout accordion tiles")

    def test_should_put_the_clock_at_the_far_right(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertLess(source.index("--add item clock right"), source.index("--add item battery right"))

    def test_should_open_the_calendar_card_when_the_clock_is_clicked(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("omvToggleCalendar()", source)

    def test_should_leave_no_calendar_popup_in_the_bar(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
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
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
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
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("omvToggleReminders()", source)

    def test_should_join_the_meeting_when_the_meeting_item_is_clicked(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        meeting = re.search(r"--add item meeting right(.*?)\n\n", source, re.S)
        self.assertIn("omvJoinMeeting()", meeting.group(1) if meeting else "")

    def test_should_subscribe_volume_to_clicks_for_the_sound_menu(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("--subscribe volume volume_change mouse.clicked mouse.scrolled", source)

    def test_should_subscribe_every_workspace_item_to_scrolling(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
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
        doctor = (REPO / "install/doctor.sh").read_text(encoding="utf-8")
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
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        subscribed = [re.search(rf"--subscribe {name} ([^\n]*)", source).group(1).split() for name in ("wifi", "ethernet")]
        self.assertEqual(["omv_network_change" in events for events in subscribed], [True, True])

    def test_should_redraw_battery_on_hammerspoons_battery_event(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        self.assertIn("omv_battery_change", re.search(r"--subscribe battery ([^\n]*)", source).group(1).split())

class PersonalSettings(unittest.TestCase):
    def test_should_load_the_users_ghostty_file_last_when_ghostty_reads_its_config(self) -> None:
        lines = [line.strip() for line in GHOSTTY.read_text(encoding="utf-8").splitlines()]
        includes = [line for line in lines if line.startswith("config-file")]
        self.assertEqual(includes[-1], "config-file = ?~/.config/omv/ghostty")
        self.assertLess(lines.index(includes[0]), lines.index(includes[-1]))

    def test_should_source_the_users_sketchybar_file_before_the_redraw_when_the_bar_starts(self) -> None:
        source = (REPO / "config/sketchybar/.config/sketchybar/sketchybarrc").read_text(encoding="utf-8")
        guarded = re.search(r'\[ -f "\$HOME/\.config/omv/sketchybar\.sh" \] && (source|\.) "\$HOME/\.config/omv/sketchybar\.sh"', source)
        self.assertIsNotNone(guarded)
        self.assertLess(guarded.start(), source.rindex("sketchybar --update"))

    def test_should_load_the_users_hammerspoon_file_last_in_pcall_when_the_config_loads(self) -> None:
        source = HAMMERSPOON.read_text(encoding="utf-8")
        loads = source.rfind("pcall(dofile, ")
        self.assertGreater(loads, 0)
        self.assertIn('/.config/omv/hammerspoon.lua', source[loads - 300:])
        self.assertNotRegex(source[loads:], r"\nomv[A-Za-z]+ = ")

    def test_should_load_the_users_neovim_file_in_pcall_when_neovim_starts(self) -> None:
        source = (REPO / "config/nvim/.config/nvim/init.lua").read_text(encoding="utf-8")
        self.assertIn("/.config/omv/nvim.lua", source)
        self.assertIn("filereadable", source)
        self.assertIn("pcall(dofile, ", source)


class BuiltAerospace(unittest.TestCase):
    USER_FILES = (
        "[mode.main.binding]\nalt-h = 'focus right'\n",
        "[mode.main.binding]\n'alt-shift-;' = 'mode service'\n\"alt-/\" = 'layout tiles'\n",
        "[gaps]\ninner.horizontal = 4\nouter.top = [{ monitor.\"built-in\" = 20 }, 40]\n",
        "[[on-window-detected]]\nif.app-id = 'com.apple.finder'\nrun = 'layout floating'\n",
        "[mode.resize.binding]\nh = 'resize width -100'\n",
        "after-startup-command = [\n  'exec-and-forget echo #1',\n]\n",
        "[key-mapping]\npreset = 'qwerty'\n",
        "# only a comment\n",
    )

    def test_should_build_valid_toml_when_the_user_file_is_one_of_the_common_kinds(self) -> None:
        import subprocess, tempfile
        for user in self.USER_FILES:
            with self.subTest(user=user), tempfile.NamedTemporaryFile("w", suffix=".toml") as file:
                file.write(user)
                file.flush()
                built = subprocess.run(
                    ["luajit", str(REPO / "install/aerospace_merge.lua"), str(AEROSPACE), file.name],
                    capture_output=True, text=True, check=True,
                ).stdout
                tomllib.loads(built)


class AgentDocs(unittest.TestCase):
    def test_should_pitch_agents_before_the_feature_list_when_the_readme_opens(self) -> None:
        readme = (REPO / "README.md").read_text(encoding="utf-8")
        agents = readme.find("## Built for coding agents")
        self.assertGreater(agents, 0)
        self.assertLess(agents, readme.index("## Features"))

    def test_should_point_the_readme_at_agents_md_when_it_explains_agent_setup(self) -> None:
        self.assertIn("](AGENTS.md)", (REPO / "README.md").read_text(encoding="utf-8"))

    def test_should_name_every_personal_settings_file_when_agents_md_explains_changes(self) -> None:
        guide = (REPO / "AGENTS.md").read_text(encoding="utf-8")
        for name in ("aerospace.toml", "ghostty", "sketchybar.sh", "hammerspoon.lua", "nvim.lua", "flags", "apps"):
            with self.subTest(name=name):
                self.assertIn(f"~/.config/omv/{name}", guide)

    def test_should_tell_agents_to_reload_when_agents_md_explains_changes(self) -> None:
        self.assertIn("omv reload", (REPO / "AGENTS.md").read_text(encoding="utf-8"))

    def test_should_tell_agents_not_to_edit_the_clone_when_agents_md_explains_changes(self) -> None:
        self.assertIn("never edit files in the omv folder", (REPO / "AGENTS.md").read_text(encoding="utf-8"))


class Leftovers(unittest.TestCase):
    def test_should_keep_the_built_header_in_one_file_when_scripts_need_it(self) -> None:
        holders = [
            path.name for path in (REPO / "install").iterdir()
            if path.is_file() and "Built by omv from its defaults" in path.read_text(encoding="utf-8", errors="ignore")
        ]
        self.assertEqual(holders, ["aerospace-header.txt"])

    def test_should_match_the_packages_list_when_uninstall_names_packages(self) -> None:
        uninstall = (REPO / "install/uninstall.sh").read_text(encoding="utf-8")
        packages = (REPO / "install/packages.sh").read_text(encoding="utf-8")
        def names(source: str, *variables: str) -> set[str]:
            found: set[str] = set()
            for variable in variables:
                match = re.search(rf"readonly {variable}=\(([^)]*)\)", source)
                self.assertIsNotNone(match, f"no one-line readonly {variable}=(...) list")
                found |= set(match.group(1).split())
            return found
        self.assertEqual(names(uninstall, "SETUP_PACKAGES", "OLDER_PACKAGES"), names(packages, "CONFIG_PACKAGES", "AGENT_PACKAGES"))

    def test_should_record_its_load_time_when_hammerspoon_loads_omv(self) -> None:
        self.assertRegex(HAMMERSPOON.read_text(encoding="utf-8"), r"\nomvLoadedAt = hs\.timer\.secondsSinceEpoch\(\)")

    def test_should_keep_spoons_loadable_when_hammerspoon_loads_from_the_repo(self) -> None:
        self.assertIn('/.hammerspoon/Spoons/?.spoon/init.lua', HAMMERSPOON.read_text(encoding="utf-8"))

    def test_should_fall_back_when_home_is_unset_when_init_lua_adds_the_spoons_path(self) -> None:
        line = next(l for l in HAMMERSPOON.read_text(encoding="utf-8").splitlines() if "/.hammerspoon/Spoons/" in l)
        self.assertIn('(os.getenv("HOME") or "")', line)

    def test_should_ignore_installed_spoons_when_hammerspoon_installs_one_into_the_repo(self) -> None:
        self.assertIn("config/hammerspoon/Spoons/", (REPO / ".gitignore").read_text(encoding="utf-8").splitlines())

    def test_should_load_each_optional_feature_only_behind_its_flag(self) -> None:
        source = HAMMERSPOON.read_text(encoding="utf-8")
        flagged = dict((module, flag) for flag, module in re.findall(r'feature\("([a-z-]+)", "features\.(\w+)"\)', source))
        self.assertEqual(flagged, FEATURE_FLAGS)

    def test_should_load_only_the_core_features_without_a_flag(self) -> None:
        source = HAMMERSPOON.read_text(encoding="utf-8")
        self.assertEqual(set(re.findall(r'require\("features\.(\w+)"\)', source)), CORE_FEATURES)

    def test_should_use_every_flag_somewhere(self) -> None:
        users = [HAMMERSPOON, HAMMERSPOON.parent / "features/windows.lua", HAMMERSPOON.parent / "features/menu.lua", SKETCHYBARRC, REPO / "bin/omv"]
        sources = "\n".join(path.read_text(encoding="utf-8") for path in users)
        used = lambda name: any(f"{before}{name}" in sources for before in ('"', " ", "."))
        unused = [name for name in flag_names() if not used(name)]
        self.assertEqual(unused, [])

    def test_should_add_each_optional_bar_item_only_behind_its_flag(self) -> None:
        items = bar_items_with_flags()
        self.assertEqual({item: items.get(item) for item in BAR_ITEM_FLAGS}, {item: {flag} for item, flag in BAR_ITEM_FLAGS.items()})

    def test_should_add_the_bar_core_items_without_a_flag(self) -> None:
        items = bar_items_with_flags()
        self.assertEqual({item: items.get(item) for item in BAR_CORE_ITEMS}, {item: set() for item in BAR_CORE_ITEMS})

    def test_should_open_the_calendar_from_the_clock_only_with_the_calendar_flag(self) -> None:
        source = SKETCHYBARRC.read_text(encoding="utf-8")
        self.assertRegex(source, r'if omv_flag_on calendar; then\s*\n\s*sketchybar --set clock click_script="hs -c \'omvToggleCalendar\(\)\'"')

    def test_should_document_every_flag_in_the_readme(self) -> None:
        readme = (REPO / "README.md").read_text(encoding="utf-8")
        self.assertEqual([name for name in flag_names() if f"`{name}`" not in readme], [])


if __name__ == "__main__":
    unittest.main()
