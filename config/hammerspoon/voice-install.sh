#!/usr/bin/env bash
# Usage: voice-install.sh install | remove
# Installs talk-back's Kokoro voice in ~/.local/share/omv/voice, about 1.5 GB: a Python
# environment with mlx-audio, Homebrew's espeak-ng and the model. "ready" there marks a whole
# install; it's written last, so one that failed half way never counts. remove deletes it all.

set -uo pipefail

PATH="$PATH:/opt/homebrew/bin"
readonly VOICE_DIR=$HOME/.local/share/omv/voice
readonly HERE=$(cd "$(dirname "$0")" && pwd)
# The English model misaki's text front end loads; it isn't on PyPI, and misaki fetches it with
# pip, which a uv environment hasn't got.
readonly SPACY_MODEL=https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl

install_voice() {
  local tool
  for tool in uv espeak-ng; do
    brew list --versions "$tool" >/dev/null 2>&1 || brew install "$tool" || return 1
  done
  rm -f "$VOICE_DIR/ready"
  mkdir -p "$VOICE_DIR"
  # --clear: a half-finished install left behind is replaced, not refused.
  uv venv -q --clear --python 3.12 "$VOICE_DIR/.venv" || return 1
  VIRTUAL_ENV="$VOICE_DIR/.venv" uv pip install -q "mlx-audio==0.6.8" "misaki[en]==0.9.4" "en-core-web-sm @ $SPACY_MODEL" || return 1
  # Speaking a line downloads the model and proves the whole chain works.
  "$HERE/speak.sh" check >/dev/null || return 1
  : > "$VOICE_DIR/ready"
}

case ${1:-} in
  install)
    install_voice || {
      echo "Couldn't install Kokoro for talk-back" >&2
      exit 1
    }
    ;;
  remove) rm -rf "$VOICE_DIR" ;;
  *)
    echo "usage: voice-install.sh install|remove" >&2
    exit 2
    ;;
esac
