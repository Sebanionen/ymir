#!/usr/bin/env bash
# build.sh — build the installer each host can actually build.
#
#   packaging/build.sh --exe     # Windows installer  → Ymir-Setup-<version>.exe   (NSIS, needs makensis)
#   packaging/build.sh --mac     # macOS installer    → Ymir-<version>.pkg         (pkgbuild, macOS only)
#   packaging/build.sh --check   # what this host can build, and with what
#
# Honest boundaries, stated up front:
#   • The .exe is an NSIS installer, so it can be built on Linux or Windows —
#     NSIS is a compiler, not a Windows VM.
#   • The .pkg needs Apple's own pkgbuild/productbuild: it is built ON a Mac, or
#     in CI on a macos runner (.github/workflows/ymir-installers.yml). Signing and
#     notarisation need the operator's Apple credentials and are deliberately not
#     attempted here.
set -u

VERSION="$(git -C "$(dirname "${BASH_SOURCE[0]}")" describe --tags --always 2>/dev/null || printf '0.1.0')"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/packaging/out"
REPO="${YMIR_REPO:-$(git -C "$ROOT" remote get-url origin 2>/dev/null || printf 'https://github.com/zerwiz/ymir.git')}"

have() { command -v "$1" >/dev/null 2>&1; }

can_exe() { have makensis; }
can_mac() { [ "$(uname -s)" = "Darwin" ] && have pkgbuild; }

check() {
  printf 'installers[3]{target,buildable,why}:\n'
  printf '  "windows .exe","%s","%s"\n' \
    "$([ "$(can_exe && echo y)" = y ] && printf yes || printf no)" \
    "$(can_exe && printf 'makensis present' || printf 'makensis absent — apt-get install nsis (or choco install nsis), or let CI build it')"
  printf '  "macos .pkg","%s","%s"\n' \
    "$([ "$(can_mac && echo y)" = y ] && printf yes || printf no)" \
    "$(can_mac && printf 'pkgbuild present' || printf 'pkgbuild is Apple-only — build on a Mac, or in CI on a macos runner')"
  printf '  "universal .command","yes","shipped as a file; double-clickable on any Mac (no build step)"\n'
}

# Every source an .nsi names must exist BEFORE makensis is asked. NSIS says only
# "!include: could not find file" (or fails a File silently into an empty installer), and the
# stdout of makensis used to be thrown away — which is how a moved path (Rule 22) broke the
# Windows build for a month with nothing anywhere saying so (2026-11-03).
preflight_nsi() {  # <nsi>
  local nsi="$1" dir rel target rc=0
  dir="$(dirname "$nsi")"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in /*|[A-Za-z]:*) target="$rel" ;; *) target="$dir/$rel" ;; esac
    target="${target//\\//}"
    [ -e "$target" ] && continue
    printf 'error: %s names a file that does not exist\n' "$nsi" >&2
    printf '       File "%s"\n' "$rel" >&2
    printf 'help:  the file it means is probably elsewhere in the tree — fix the directive\n' >&2
    printf '       (bin/gates/guards/packaging-guard.sh refuses this in CI as well)\n' >&2
    rc=1
  done < <(sed -n 's/^[[:space:]]*File[[:space:]]\{1,\}//p' "$nsi" | sed -n 's/.*"\([^"]*\)"[[:space:]]*;\{0,1\}.*$/\1/p')
  return "$rc"
}

exe() {
  # The DIRECTIVES are judged first, because that check needs no compiler: a .nsi naming a
  # path that is not in the tree is broken on every host, including one with no makensis.
  preflight_nsi "$ROOT/packaging/windows/ymir-setup.nsi" || exit 1
  if ! can_exe; then
    printf 'error: makensis not found\nhelp: sudo apt-get install -y nsis\n' >&2
    printf 'help: or build in CI — .github/workflows/ymir-installers.yml\n' >&2
    exit 1
  fi
  mkdir -p "$OUT"
  local log="$OUT/makensis.log"
  if ! makensis -DREPO="$REPO" -DVERSION="$VERSION" ${YMIR_INSTALLER_ROLE:+-DROLE="$YMIR_INSTALLER_ROLE"} \
        "$ROOT/packaging/windows/ymir-setup.nsi" >"$log" 2>&1; then
    printf 'error: makensis failed — its own last lines:\n' >&2
    tail -12 "$log" | sed 's/^/    /' >&2
    printf 'help: full log %s\nhelp: run it by hand: makensis -DREPO=%s packaging/windows/ymir-setup.nsi\n' "$log" "$REPO" >&2
    exit 1
  fi
  mv -f "$ROOT/packaging/windows/Ymir-Setup-"*.exe "$OUT/" 2>/dev/null || true
  printf 'installers[1]{target,artifact}:\n  "windows .exe","%s"\n' "$OUT/$(ls "$OUT" | grep '\.exe$' | head -1)"
}

pkg() {
  if ! can_mac; then
    printf 'error: pkgbuild is Apple-only; this host cannot build a .pkg\nhelp: on a Mac run: packaging/build.sh --mac\nhelp: or CI on a macos runner — .github/workflows/ymir-installers.yml\n' >&2
    exit 1
  fi
  mkdir -p "$OUT"
  local stage="$OUT/stage"
  rm -rf "$stage"; mkdir -p "$stage/Applications/Ymir"
  cp "$ROOT/packaging/macos/Ymir Installer.command" "$stage/Applications/Ymir/"
  chmod +x "$stage/Applications/Ymir/Ymir Installer.command"
  cp "$ROOT/bin/host/bootstrap-macos.sh" "$stage/Applications/Ymir/" \
    || { printf 'error: bin/host/bootstrap-macos.sh is not in this tree — the .pkg would ship without its bootstrapper\nhelp: packaging-guard.sh checks every input a shipped installer names\n' >&2; exit 1; }
  pkgbuild --root "$stage" --identifier com.ymir.installer --version "$VERSION" --install-location / "$OUT/Ymir-$VERSION.pkg" >/dev/null \
    || { printf 'error: pkgbuild failed\nhelp: run it by hand to see why\n' >&2; exit 1; }
  printf 'installers[1]{target,artifact}:\n  "macos .pkg","%s"\n' "$OUT/Ymir-$VERSION.pkg"
}

case "${1:-}" in
  --exe) exe ;;
  --mac) pkg ;;
  --check|"") check ;;
  -v|-V|--version) printf '%s\n' "$VERSION" ;;
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) printf 'error: unknown flag %s\nhelp: packaging/build.sh [--exe|--mac|--check]\n' "$1" >&2; exit 2 ;;
esac
