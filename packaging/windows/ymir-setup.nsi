; ymir-setup.nsi — the Windows bootstrap installer (Ymir-Setup.exe).
;
; It does one honest thing: install the Windows bootstrap and run it. Ymir's host
; on Windows is Ubuntu inside WSL2, so the "installer" sets that up and then
; hands over to bin/engine/ymir-install.sh inside the distro. It is not a native
; Windows build of Ymir, and it does not pretend to be.
;
; Build (from the repo root, on Linux or Windows):
;   packaging/build.sh --exe
;   makensis -DREPO=https://github.com/<you>/ymir.git packaging/windows/ymir-setup.nsi
;
; Requires NSIS 3.x (Ubuntu: apt-get install nsis; Windows: choco install nsis).

Unicode true
!include "MUI2.nsh"
!include "x64.nsh"

!ifndef REPO
  !define REPO "https://github.com/zerwiz/ymir.git"
!endif
!ifndef VERSION
  !define VERSION "0.1.0"
!endif
; The ROLE the Linux seat is installed as. A bootstrapper that passes no role makes every
; role-gated step SKIP, so the install reports success as a half-install (RULES/25).
!ifndef ROLE
  !define ROLE "dev"
!endif

!define APPNAME "Ymir"
Name "${APPNAME} — set up the Linux host (Ubuntu on WSL2)"
OutFile "Ymir-Setup-${VERSION}.exe"
InstallDir "$LOCALAPPDATA\Ymir"
InstallDirRegKey HKCU "Software\Ymir" "InstallDir"
RequestExecutionLevel admin          ; enabling WSL requires elevation

VIProductVersion "0.1.0.0"
VIAddVersionKey "ProductName" "Ymir"
VIAddVersionKey "CompanyName" "Ymir"
VIAddVersionKey "FileDescription" "Ymir bootstrap — installs Ubuntu on WSL2 and Ymir inside it"
VIAddVersionKey "FileVersion" "${VERSION}"

!define MUI_ABORTWARNING

; ── pages ────────────────────────────────────────────────────────────────────
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; ── install ──────────────────────────────────────────────────────────────────
Section "Bootstrap" SecBootstrap
  SetOutPath "$INSTDIR"
  ; The host layers moved under bin/host/ (Rule 22). NSIS resolves a relative File
  ; against THIS script, and a missing source is a compile error — so the path is
  ; checked by bin/gates/guards/packaging-guard.sh and by packaging/build.sh.
  File "/oname=bootstrap-windows.ps1" "..\..\bin\host\bootstrap-windows.ps1"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  WriteRegStr HKCU "Software\Ymir" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Ymir" "Repo" "${REPO}"

  ; The powershell bootstrap prints its own TOON rows to the log window, so the
  ; operator sees exactly what happened (WSL enabled, distro installed, Ymir in).
  DetailPrint "Setting up the Linux host (Ubuntu on WSL2)…"
  nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\bootstrap-windows.ps1" -Repo "${REPO}" -Role "${ROLE}"'
  Pop $0
  ${If} $0 != 0
    DetailPrint "bootstrap returned $0 — read the log above; a reboot may be required."
  ${EndIf}
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\bootstrap-windows.ps1"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Ymir"
  ; The Ubuntu distro and its data are the operator's — never removed here.
  ; To remove them: wsl --unregister Ubuntu
SectionEnd
