# The Stow packages omv links into $HOME, shared by install.sh, doctor.sh, uninstall.sh and
# bin/omv so the lists can't drift between them. Sourced, not run, after REPO_DIR is set.
# shellcheck disable=SC2034
readonly CONFIG_PACKAGES=(aerospace sketchybar swipeaerospace ghostty nvim btop hammerspoon)
readonly AGENT_PACKAGES=(claude)

# The folder Stow links a package from: the agents' packages live in agents/, the rest in config/.
package_dir() {
  case $1 in
    claude | opencode | pi) echo "$REPO_DIR/agents" ;;
    *) echo "$REPO_DIR/config" ;;
  esac
}
