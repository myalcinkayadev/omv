#!/usr/bin/env bash
# Behavior of voice-install.sh, which installs talk-back's Kokoro voice. brew, uv and the
# environment's python are stubs, so nothing is downloaded.

source "$(dirname "$0")/lib.sh"

readonly INSTALL=$REPO_DIR/config/hammerspoon/voice-install.sh

voice_dir() {
  echo "$HOME_DIR/.local/share/omv/voice"
}

# brew that has nothing installed: list fails and install is logged; installing uv puts a uv
# stub beside it, which PATH finds before the real one in /opt/homebrew/bin.
stub_empty_brew() {
  own_stub brew
  cat > "$STUB_DIR/brew" <<STUB
#!/bin/sh
echo "brew \$*" >> "\$CALL_LOG"
[ "\$1" = list ] && exit 1
[ "\$*" = "install uv" ] && ln -s "$SHARED_STUB" "$STUB_DIR/uv"
exit 0
STUB
}

# The environment's python, made by the stubbed uv venv, exiting with $1.
fake_python() {
  mkdir -p "$(voice_dir)/.venv/bin"
  printf '#!/bin/sh\necho "python $*" >> "$CALL_LOG"\nexit %s\n' "$1" > "$(voice_dir)/.venv/bin/python"
  chmod +x "$(voice_dir)/.venv/bin/python"
}

installs_what_is_missing() {
  stub_empty_brew
  fake_python 0
  run_in_sandbox "$INSTALL" install
  assert_called '^brew install uv$'
  assert_called '^brew install espeak-ng$'
}

pins_the_packages() {
  stub brew
  stub uv
  fake_python 0
  run_in_sandbox "$INSTALL" install
  assert_called 'uv pip install -q mlx-audio==0.6.8 misaki\[en\]==0.9.4 en-core-web-sm @ https://.*en_core_web_sm-3\.8\.0'
}

writes_ready_when_the_model_loads() {
  stub brew
  stub uv
  fake_python 0
  run_in_sandbox "$INSTALL" install
  [ -e "$(voice_dir)/ready" ] || fail 'ready missing'
}

no_ready_when_the_model_fails() {
  stub brew
  stub uv
  fake_python 1
  run_in_sandbox "$INSTALL" install 2>/dev/null && fail 'exited zero'
  [ ! -e "$(voice_dir)/ready" ] || fail 'ready written'
}

removes_the_folder() {
  mkdir -p "$(voice_dir)/.venv"
  : > "$(voice_dir)/ready"
  run_in_sandbox "$INSTALL" remove
  [ ! -e "$(voice_dir)" ] || fail 'folder left behind'
}

run_case 'should install uv and espeak-ng when missing' installs_what_is_missing
run_case 'should pin mlx-audio and misaki when installing' pins_the_packages
run_case 'should write ready when the model loads' writes_ready_when_the_model_loads
run_case 'should not write ready when the model fails' no_ready_when_the_model_fails
run_case 'should remove the folder when asked' removes_the_folder
finish
