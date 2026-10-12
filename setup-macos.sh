#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != Darwin ]; then
    echo "ERROR: This setup script is for macOS." >&2
    exit 1
fi
if [ "$(id -u)" = 0 ]; then
    echo "Запустите bash setup-macos.sh без sudo. Homebrew сам запросит нужные права." >&2
    exit 1
fi

find_brew() {
    if command -v brew >/dev/null 2>&1; then command -v brew; return 0; fi
    local candidate search_paths="${BREW_SEARCH_PATHS-/opt/homebrew/bin/brew /usr/local/bin/brew}"
    for candidate in $search_paths; do
        if [ -x "$candidate" ]; then echo "$candidate"; return 0; fi
    done
    return 1
}

BREW_BIN=$(find_brew || true)
if [ -z "$BREW_BIN" ]; then
    echo "Homebrew не установлен. Запускается официальный установщик с brew.sh."
    INSTALL_SCRIPT=$(mktemp)
    trap 'rm -f "$INSTALL_SCRIPT"' EXIT
    curl --fail --location --proto '=https' --proto-redir '=https' \
        https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$INSTALL_SCRIPT"
    /bin/bash "$INSTALL_SCRIPT"
    BREW_BIN=$(find_brew) || { echo "ERROR: Homebrew installation did not complete." >&2; exit 1; }
fi

eval "$("$BREW_BIN" shellenv)"
brew install git python e2fsprogs
echo ""
echo "Зависимости для macOS без Docker установлены."
echo "Подготовка флешки: sudo bash run.sh --backend native"
echo "Готовый установщик: добавьте --installer-dir ./installers"
