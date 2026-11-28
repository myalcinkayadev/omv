#!/usr/bin/env bash
# The protocol of speak.py, talk-back's Kokoro voice, driven with a fake speaker, so neither
# the model nor mlx is needed.

source "$(dirname "$0")/lib.sh"

# Runs speak.serve over the lines in $1 with a speaker that writes nothing; prints its output.
serve() {
  printf '%b' "$1" | python3 -I -B -c '
import io, sys
sys.path.insert(0, sys.argv[1])
import speak
def fake(voice, text):
    if text == "boom":
        raise ValueError("boom")
    return "/tmp/line-" + voice + ".wav"
speak.serve(fake, sys.stdin, sys.stdout)
' "$REPO_DIR/config/hammerspoon"
}

says_ready() {
  [ "$(serve 'quit\n' | head -1)" = ready ] || fail "said: $(serve 'quit\n')"
}

gives_an_audio_path() {
  [ "$(serve 'say\taf_heart\tTests pass.\nquit\n' | sed -n 2p)" = "$(printf 'audio\t/tmp/line-af_heart.wav')" ] \
    || fail "said: $(serve 'say\taf_heart\tTests pass.\nquit\n')"
}

gives_a_problem_for_a_bad_line() {
  [ "$(serve 'say\trobot\tHi\nquit\n' | sed -n 2p)" = "$(printf 'problem\tbad line')" ] || fail "said: $(serve 'say\trobot\tHi\n')"
}

keeps_serving_after_a_failure() {
  [ "$(serve 'say\taf_heart\tboom\nsay\tam_michael\tok\nquit\n' | sed -n 3p)" = "$(printf 'audio\t/tmp/line-am_michael.wav')" ] \
    || fail "said: $(serve 'say\taf_heart\tboom\nsay\tam_michael\tok\n')"
}

run_case 'should say ready when the model loads' says_ready
run_case 'should give an audio path when asked to say a line' gives_an_audio_path
run_case 'should give a problem when a line is malformed' gives_a_problem_for_a_bad_line
run_case 'should keep serving when a line fails' keeps_serving_after_a_failure
finish
