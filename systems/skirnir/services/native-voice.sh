# Shared Windows/WSL bridge. Sourced by the existing file-only ear and mouth doors.
native_voice_available() {
  command -v powershell.exe >/dev/null 2>&1 && {
    command -v wslpath >/dev/null 2>&1 || command -v cygpath >/dev/null 2>&1;
  }
}
native_voice_path() {
  if command -v wslpath >/dev/null 2>&1; then wslpath -w "$1"; else cygpath -w "$1"; fi
}
native_voice_file() {
  local action="$1" value="$2" output="${3:-}" language="${4:-en}"
  local script
  script="$(native_voice_path "$SCRIPT_DIR/voice-file.ps1")" || return
  [ "$action" != transcribe ] || value="$(native_voice_path "$value")" || return
  [ -z "$output" ] || output="$(native_voice_path "$output")" || return
  powershell.exe -NoProfile -NonInteractive -File "$script" -Action "$action" \
    -Value "$value" -OutputFile "$output" -Language "$language"
}
