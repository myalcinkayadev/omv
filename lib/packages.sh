# The Stow packages omv links into $HOME, shared by install.sh, doctor.sh and bin/omv so the
# list can't drift between them. Sourced, not run.
# shellcheck disable=SC2034
readonly PACKAGES=(aerospace sketchybar claude swipeaerospace ghostty nvim btop hammerspoon)
