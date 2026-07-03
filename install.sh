#!/usr/bin/env sh
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${LFG_INSTALL_DIR:-$HOME/.config/lfg}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

echo "Installing lfg to $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"
ln -sf "$REPO_ROOT/lfg.zsh" "$INSTALL_DIR/lfg.zsh"

SOURCE_LINE="source \"$INSTALL_DIR/lfg.zsh\""
if [ -f "$ZSHRC" ] && grep -Fxq "$SOURCE_LINE" "$ZSHRC"; then
  echo "Already sourced in $ZSHRC"
else
  echo "$SOURCE_LINE" >> "$ZSHRC"
  echo "Added source line to $ZSHRC"
fi

echo "Done. Restart your shell or run: source $INSTALL_DIR/lfg.zsh"
