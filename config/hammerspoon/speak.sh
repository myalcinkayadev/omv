#!/bin/sh
# Usage: speak.sh serve | check
# Talk-back's Kokoro voice, run in the environment voice-install.sh makes; speak.py says what
# it prints. Exits 1 when that environment isn't there.

voice_dir=$HOME/.local/share/omv/voice
python=$voice_dir/.venv/bin/python
[ -x "$python" ] || {
  echo "Kokoro isn't installed: omv voice install" >&2
  exit 1
}
# The model lives beside the environment, so removing the folder removes it too.
export HF_HOME="$voice_dir/models"
exec "$python" "$(dirname "$0")/speak.py" "$@"
