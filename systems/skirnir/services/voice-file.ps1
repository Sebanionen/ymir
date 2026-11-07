param([ValidateSet('transcribe','speak')][string]$Action,
      [string]$Value, [string]$OutputFile, [string]$Language = 'en', [switch]$Play)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$env:PYTHONIOENCODING = 'utf-8'
if ($Action -eq 'speak' -and $Language -ne 'en') {
    Write-Error 'English speech only; Swedish speech is unavailable'; exit 2
}
$engine = 'whisper'; if ($Action -eq 'speak') { $engine = 'kokoro' }
$global:LASTEXITCODE = 0
$control = & (Join-Path $PSScriptRoot 'voice-service.ps1') -Action start -Engine $engine
if ($LASTEXITCODE -ne 0) { Write-Output $control; exit $LASTEXITCODE }
$arguments = @((Join-Path $PSScriptRoot 'voice-io.py'), $Action, $Value, '--lang', $Language)
if ($OutputFile) { $arguments += @('--output', $OutputFile) }
& python @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Play) {
    if (!$OutputFile -or [IO.Path]::GetExtension($OutputFile) -ne '.wav') { throw 'Playback requires WAV' }
    $player = New-Object System.Media.SoundPlayer $OutputFile
    try { $player.Load(); $player.PlaySync() } finally { $player.Dispose() }
}
exit 0
