#!/bin/bash
# Mumble Native 1.6.870 — Apple Silicon installer
# Builds the official v1.6.870 client (Qt6, arm64), installs to
# /Applications/Mumble.app, and writes a shareable DMG to the Desktop.
set -euo pipefail

TAG="v1.6.870"
SRC="${MUMBLE_SRC:-$HOME/mumble-native-src}"
APP_DST="/Applications/Mumble.app"
DMG_OUT="$HOME/Desktop/Mumble-1.6.870-arm64.dmg"
LOG="$HOME/Library/Logs/Mumble-Native-Install.log"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

say()  { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\nLog: %s\n' "$*" "$LOG" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

keep_open() {
  if [ -t 0 ] && [ -t 1 ]; then
    printf '\nНажмите Enter, чтобы закрыть окно.\n'
    read -r _ || true
  fi
}
trap 'code=$?; if [ "$code" -ne 0 ]; then printf "\nУстановка прервалась (код %s).\nЛог: %s\n" "$code" "$LOG"; keep_open; fi' EXIT

printf '\n'
printf '  Mumble Native %s\n' "$TAG"
printf '  Apple Silicon · Qt6 · без Rosetta\n'
printf '  Лог: %s\n' "$LOG"

[ "$(uname -s)" = "Darwin" ] || die "Только macOS."

ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ]; then
  if [ "$(sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    die "Терминал запущен через Rosetta. Откройте обычный Terminal (без «Open using Rosetta») и запустите установщик снова."
  fi
  die "Нужен Mac на Apple Silicon (M1/M2/M3/M4). Intel не поддерживается."
fi
[ "$ARCH" = "arm64" ] || die "Неизвестная архитектура: $ARCH"

[ "$(id -u)" -ne 0 ] || die "Не запускайте от root. Скрипт сам спросит пароль, если понадобится."

FREE_GB="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
if [ "${FREE_GB:-0}" -lt 8 ]; then
  die "Нужно около 8 ГБ свободного места (сейчас ${FREE_GB:-?} ГБ)."
fi

# Reuse a tree that already built this tag.
if [ ! -d "$SRC/.git" ] && [ -d "$HOME/mumble-src/.git" ]; then
  SRC="$HOME/mumble-src"
  say "Нашёл уже скачанные исходники: $SRC"
fi

say "1/7  Инструменты компиляции"
if ! xcode-select -p >/dev/null 2>&1; then
  say "Откроется окно Apple — нажмите Install и дождитесь конца."
  xcode-select --install || true
  until xcode-select -p >/dev/null 2>&1; do
    sleep 8
  done
fi

say "2/7  Homebrew"
if ! have brew; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    say "Установка Homebrew (может спросить пароль Mac)."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  eval "$(brew shellenv)"
fi
have brew || die "Homebrew не появился в PATH."

say "3/7  Зависимости (cmake, Qt6, Opus…)"
brew update || true
brew install cmake ninja pkg-config qt6 boost libogg libvorbis flac \
  libsndfile protobuf openssl poco git || die "brew install не удался."

QT_PREFIX="$(brew --prefix qt6 2>/dev/null || brew --prefix qt)"
SSL_PREFIX="$(brew --prefix openssl)"
MACDEPLOYQT="$QT_PREFIX/bin/macdeployqt"
[ -x "$MACDEPLOYQT" ] || die "Не найден macdeployqt в $QT_PREFIX"

say "4/7  Исходники Mumble $TAG"
if [ -d "$SRC/.git" ]; then
  git -C "$SRC" fetch --tags --force origin "$TAG" || git -C "$SRC" fetch --tags origin
  git -C "$SRC" checkout -f "$TAG"
  git -C "$SRC" submodule update --init --recursive
else
  rm -rf "$SRC"
  git clone --branch "$TAG" --depth 1 --recurse-submodules --shallow-submodules \
    https://github.com/mumble-voip/mumble.git "$SRC"
fi

say "5/7  Сборка (первый раз 15–40 минут, дальше быстрее)"
BUILD="$SRC/build"
mkdir -p "$BUILD"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_PREFIX_PATH="$QT_PREFIX" \
  -DOpenSSL_ROOT="$SSL_PREFIX" \
  -Dice=OFF \
  -Dserver=OFF \
  -Denable-mysql=OFF \
  -Denable-postgresql=OFF \
  -Dwarnings-as-errors=OFF \
  || die "cmake не прошёл. См. лог."
cmake --build "$BUILD" --parallel "$JOBS" || die "Сборка не прошла."

APP="$BUILD/Mumble.app"
[ -d "$APP" ] || die "CMake не положил Mumble.app в $BUILD"

say "6/7  Бандл: Qt внутрь, подпись, карантин"
"$MACDEPLOYQT" "$APP" -always-overwrite || die "macdeployqt не прошёл."
codesign --force --deep --sign - "$APP" || die "codesign не прошёл."
xattr -cr "$APP" || true

if [ -d "$APP_DST" ]; then
  BAK="$HOME/Downloads/Mumble-backup-$(date +%Y%m%d-%H%M%S).app"
  say "Старый /Applications/Mumble.app → $BAK"
  ditto "$APP_DST" "$BAK"
  rm -rf "$APP_DST"
fi
ditto "$APP" "$APP_DST"
codesign --force --deep --sign - "$APP_DST" || true
xattr -cr "$APP_DST" || true

say "7/7  DMG на рабочий стол (его можно слать друзьям)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/mumble-dmg.XXXXXX")"
ditto "$APP_DST" "$STAGE/Mumble.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG_OUT"
if hdiutil create -volname "Mumble Native 1.6.870" -srcfolder "$STAGE" -ov -format UDZO "$DMG_OUT"; then
  xattr -cr "$DMG_OUT" || true
  say "DMG: $DMG_OUT"
else
  printf 'DMG не собрался — само приложение уже стоит в Программах.\n'
fi
rm -rf "$STAGE"

KIND="$(file "$APP_DST/Contents/MacOS/Mumble" 2>/dev/null || true)"
printf '\nГотово.\n'
printf '  Приложение : %s\n' "$APP_DST"
printf '  DMG        : %s\n' "$DMG_OUT"
printf '  Бинарник   : %s\n' "$KIND"
printf '\nПервый запуск: Control-клик по Mumble → Открыть.\n'
printf 'Микрофон macOS спросит сам. В Activity Monitor Kind должен быть Apple.\n'
printf 'Друзьям отдайте DMG с рабочего стола: перетащили Mumble в Applications — всё.\n'

open -a Mumble || open "$APP_DST" || true
open "$HOME/Desktop" || true

trap - EXIT
keep_open
exit 0
