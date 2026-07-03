# Oh-My-Zsh plugin entry point for lfg.
#
# Place this repository (or a copy/symlink of it) in:
#   ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/lfg
# and add "lfg" to the plugins array in your .zshrc.

0="${ZERO:-${(%):-%N}}"
LFG_PLUGIN_DIR="${0:A:h}"

source "${LFG_PLUGIN_DIR}/lfg.zsh"
