#!/usr/bin/env bash
# snotra-ensure.sh — ensure the meeting ear's transcription engine is present.
#
# Snotra captures on the meeting seat and transcribes with whisper.cpp. The
# engine is discovered, never assumed: this script reports what the seat has and
# installs what is missing (whisper-cli + one model).
#
# Per-OS install road:
#   Arch/omarchy  pacman -S whisper-cpp            (extra repo; CPU backend)
#   Debian/Ubuntu the packaged engine WITHOUT root: `apt-get download` the three
#                 .debs (~4 MB) and `dpkg-deb -x` them into $ENGINE_PREFIX. This
#                 is the road that works on a seat whose sudo wants a password
#                 (WSL2, a non-interactive shell). Falls back to
#                 `sudo apt-get install -y whisper.cpp`, then to naming that
#                 command for the operator.
#   otherwise     build whisper.cpp from source (needs cmake), or use an
#                 existing build
#
# The model is fetched from the whisper.cpp Hugging Face release (checksummed by
# HTTPS; ~466 MB for small.en). A seat that already has voxtype keeps its models
# — they are found in ~/.local/share/voxtype/models and never re-downloaded.
#
# Usage:
#   snotra-ensure.sh status
#   snotra-ensure.sh ensure [--install]
#   snotra-ensure.sh install
#   snotra-ensure.sh --version
#
# Env:
#   SNOTRA_WHISPER_BIN   — explicit engine override
#   SNOTRA_WHISPER_MODEL — explicit model override
#   SNOTRA_ENGINE_PREFIX — where the no-root packaged engine is unpacked
#                          (default ~/.local/opt/whisper.cpp)
#   SNOTRA_MODEL         — model name to fetch (default ggml-small.en)
#
# Exit: 0 engine + model present, 1 absent (nothing attempted), 2 usage,
#       3 the operator must run one command (sudo/build) — never a false success.
set -u

VERSION="1.0.1"
SNOTRA_MODEL="${SNOTRA_MODEL:-ggml-small.en}"
MODEL_BASE="${SNOTRA_MODEL_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main}"
ENGINE_PREFIX="${SNOTRA_ENGINE_PREFIX:-$HOME/.local/opt/whisper.cpp}"
OPERATOR_COMMAND=""

case "${1-}" in -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;; -h|--help|"") sed -n '2,/^set -u/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
CMD="${1-}"; shift || true
DO_INSTALL=0
case "$CMD" in ensure|status|install) ;; *) printf 'error: unknown command %s\nhelp: systems/snotra/services/ear/snotra-ensure.sh [status|ensure|install]\n' "$CMD" >&2; exit 2 ;; esac
while [ $# -gt 0 ]; do case "$1" in --install) DO_INSTALL=1; shift ;; *) shift ;; esac; done
[ "$CMD" = install ] && DO_INSTALL=1

have() { command -v "$1" >/dev/null 2>&1; }

# --- discovery (mirrors systems/snotra/services/ear/snotra-transcribe.sh) ---------------------------

find_whisper() {
  if [ -n "${SNOTRA_WHISPER_BIN:-}" ] && [ -x "$SNOTRA_WHISPER_BIN" ]; then printf '%s' "$SNOTRA_WHISPER_BIN"; return 0; fi
  local c
  for c in whisper-cli whisper-cpp whisper; do
    if have "$c"; then command -v "$c"; return 0; fi
  done
  local p
  for p in \
    "$ENGINE_PREFIX/bin/whisper-cli" \
    "$HOME/whisper.cpp.src/build/bin/whisper-cli" \
    "$HOME/whisper.cpp/build/bin/whisper-cli" \
    "$HOME/whisper.cpp.src/build/bin/main" \
    "$HOME/whisper.cpp/build/bin/main" \
    "/usr/local/bin/whisper-cli" "/usr/bin/whisper-cli"; do
    if [ -x "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

find_model() {
  if [ -n "${SNOTRA_WHISPER_MODEL:-}" ] && [ -f "$SNOTRA_WHISPER_MODEL" ]; then printf '%s' "$SNOTRA_WHISPER_MODEL"; return 0; fi
  local p
  for p in \
    "$HOME/whisper.cpp/models/${SNOTRA_MODEL}.bin" \
    "$HOME/whisper.cpp/models/ggml-small.en.bin" \
    "$HOME/whisper.cpp/models/ggml-base.en.bin" \
    "$HOME/.local/share/voxtype/models/${SNOTRA_MODEL}.bin" \
    "$HOME/.local/share/voxtype/models/ggml-small.en.bin" \
    "$HOME/.local/share/voxtype/models/ggml-base.en.bin" \
    "$HOME/.local/share/whisper.cpp/models/${SNOTRA_MODEL}.bin" \
    "/usr/share/whisper.cpp/models/${SNOTRA_MODEL}.bin" \
    "/usr/share/whisper/models/${SNOTRA_MODEL}.bin"; do
    if [ -f "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

# A voxtype-only seat transcribes through voxtype itself — still "the ear".
find_voxtype() { have voxtype && command -v voxtype; }

status() {
  local w m vx
  w="$(find_whisper || true)"
  m="$(find_model || true)"
  vx="$(find_voxtype || true)"
  printf 'snotra[1]{engine,model,voxtype,seat}:\n'
  if [ -n "$w" ] && [ -n "$m" ]; then
    printf '  "%s","%s","%s","%s"\n' "$w" "$m" "${vx:-—}" "$(hostname -s 2>/dev/null || hostnamectl --static 2>/dev/null || printf seat)"
    return 0
  fi
  if [ -n "$vx" ] && [ -n "$m" ]; then
    printf '  "voxtype","%s","%s","%s"\n' "$m" "$vx" "$(hostname -s 2>/dev/null || hostnamectl --static 2>/dev/null || printf seat)"
    return 0
  fi
  printf '  "%s","%s","%s","%s"\n' "${w:-—}" "${m:-—}" "${vx:-—}" "$(hostname -s 2>/dev/null || hostnamectl --static 2>/dev/null || printf seat)"
  return 1
}

# --- install ----------------------------------------------------------------

# The operator's one command, printed loudly and remembered as exit 3.
need_operator() {
  OPERATOR_COMMAND="$1"
  printf '\nsnotra: this seat needs the operator. Run exactly:\n\n  %s\n\n' "$1" >&2
}

# The same engine, unpacked without root. Debian/Ubuntu publish whisper.cpp as
# three small packages (`whisper.cpp`, `libwhisper1`, `libggml0`); `apt-get
# download` and `dpkg-deb -x` need no privilege, so a seat whose sudo wants a
# password still gets a real engine. The tree is laid out beside the binary so
# the ear's own door finds everything without a second lookup:
#
#   $ENGINE_PREFIX/bin/whisper-cli
#   $ENGINE_PREFIX/lib/libwhisper.so.1 · libggml.so.0 · libggml-base.so.0
#   $ENGINE_PREFIX/backends/libggml-cpu-*.so
#
# libggml finds its CPU kernel through a compiled-in directory
# (/usr/lib/x86_64-linux-gnu/ggml/backends0) that an unprivileged copy does not
# have, so the door names one kernel from `backends/`
# (snotra-transcribe.sh's pick_backend).
install_engine_from_packages() {
  have apt-get || return 1
  have dpkg-deb || return 1
  local tmp; tmp="$(mktemp -d 2>/dev/null)" || return 1
  printf 'snotra: unpacking the packaged engine into %s (no root) …\n' "$ENGINE_PREFIX" >&2
  if ! ( cd "$tmp" && apt-get download whisper.cpp libwhisper1 libggml0 ) >/dev/null 2>&1; then
    printf 'snotra: apt-get download did not answer\n' >&2
    rm -rf "$tmp"; return 1
  fi
  local deb
  for deb in "$tmp"/*.deb; do
    dpkg-deb -x "$deb" "$tmp/root" >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
  done
  # stage the tree, verify it, then move it into place — a half-copied prefix
  # would still be executable, and `status` would call it green.
  local stage="$tmp/stage"
  mkdir -p "$stage/bin" "$stage/lib" "$stage/backends" 2>/dev/null \
    || { rm -rf "$tmp"; return 1; }
  # only the binaries that run without extra libraries: whisper-cli (the ear),
  # whisper-server (the fleet ear lane) and whisper-quantize. whisper-stream
  # needs SDL2, which is not part of this unpack.
  local b
  for b in whisper-cli whisper-server whisper-quantize; do
    [ -x "$tmp/root/usr/bin/$b" ] && cp -a "$tmp/root/usr/bin/$b" "$stage/bin/"
  done
  find "$tmp/root/usr/lib" -maxdepth 3 -name 'libwhisper.so*' -exec cp -a {} "$stage/lib/" \; 2>/dev/null
  find "$tmp/root/usr/lib" -maxdepth 3 -name 'libggml*.so*' -exec cp -a {} "$stage/lib/" \; 2>/dev/null
  find "$tmp/root/usr/lib" -path '*ggml/backends0/*.so' -exec cp -a {} "$stage/backends/" \; 2>/dev/null
  if [ ! -x "$stage/bin/whisper-cli" ] || ! find "$stage/backends" -name 'libggml-cpu-*.so' | grep -q .; then
    printf 'snotra: the unpacked engine is incomplete\n' >&2
    rm -rf "$tmp"; return 1
  fi
  if ! LD_LIBRARY_PATH="$stage/lib" "$stage/bin/whisper-cli" -h >/dev/null 2>&1; then
    printf 'snotra: the unpacked engine does not start\n' >&2
    rm -rf "$tmp"; return 1
  fi
  mkdir -p "$(dirname "$ENGINE_PREFIX")" 2>/dev/null || true
  rm -rf "$ENGINE_PREFIX"
  if ! mv "$stage" "$ENGINE_PREFIX"; then
    printf 'snotra: could not move the engine into %s\n' "$ENGINE_PREFIX" >&2
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
  printf 'snotra: engine seated at %s/bin/whisper-cli\n' "$ENGINE_PREFIX" >&2
  return 0
}

install_engine() {
  local os_id=""
  [ -r /etc/os-release ] && os_id="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-}")"
  case "$os_id" in
    arch|omarchy|manjaro|endeavouros)
      if have pacman; then
        printf 'snotra: installing whisper-cpp via pacman …\n' >&2
        if sudo -n pacman -S --noconfirm whisper-cpp >/dev/null 2>&1; then
          printf 'snotra: whisper-cpp installed\n' >&2; return 0
        fi
      fi
      need_operator 'sudo pacman -S whisper-cpp'
      return 3 ;;
    debian|ubuntu|pop|linuxmint)
      # 1) no root at all — the road that works when sudo wants a password
      install_engine_from_packages && return 0
      # 2) root, only when sudo is passwordless
      if have apt-get && sudo -n apt-get install -y whisper.cpp >/dev/null 2>&1; then
        printf 'snotra: whisper.cpp installed\n' >&2; return 0
      fi
      # 3) the operator's one command
      need_operator 'sudo apt-get install -y whisper.cpp'
      return 3 ;;
  esac
  need_operator 'git clone https://github.com/ggerganov/whisper.cpp ~/whisper.cpp.src && cmake -S ~/whisper.cpp.src -B ~/whisper.cpp.src/build && cmake --build ~/whisper.cpp.src/build -j'
  return 3
}

install_model() {
  local dir="$HOME/whisper.cpp/models"
  mkdir -p "$dir"
  local url="$MODEL_BASE/${SNOTRA_MODEL}.bin"
  printf 'snotra: fetching %s …\n' "$url" >&2
  if have curl; then
    if curl -fL --retry 3 -o "$dir/${SNOTRA_MODEL}.bin.part" "$url" >/dev/null 2>&1; then
      mv "$dir/${SNOTRA_MODEL}.bin.part" "$dir/${SNOTRA_MODEL}.bin"
      printf 'snotra: model seated at %s/%s.bin\n' "$dir" "$SNOTRA_MODEL" >&2
      return 0
    fi
  fi
  rm -f "$dir/${SNOTRA_MODEL}.bin.part"
  need_operator "curl -fL -o $dir/${SNOTRA_MODEL}.bin $url"
  return 3
}

# Returns 0 when the seat can now transcribe, 3 when only the operator can
# finish it, 1 when the attempt failed for another reason.
install_all() {
  local rc=0
  if [ -z "$(find_whisper || true)" ] && [ -z "$(find_voxtype || true)" ]; then
    install_engine || rc=$?
    [ "$rc" -ne 0 ] && return "$rc"
  fi
  if [ -z "$(find_model || true)" ]; then
    install_model || rc=$?
    [ "$rc" -ne 0 ] && return "$rc"
  fi
  return 0
}

case "$CMD" in
  status) status; exit $? ;;
  install)
    install_all; rc=$?
    status || true
    [ "$rc" -ne 0 ] && exit "$rc"
    exit 0 ;;
  ensure)
    if status >/dev/null 2>&1; then status; exit 0; fi
    if [ "$DO_INSTALL" = 1 ]; then
      install_all; rc=$?
      status || true
      [ "$rc" -ne 0 ] && exit "$rc"
      exit 0
    fi
    status
    printf 'snotra: engine or model missing — run `systems/snotra/services/ear/snotra-ensure.sh install`\n' >&2
    exit 1 ;;
esac
