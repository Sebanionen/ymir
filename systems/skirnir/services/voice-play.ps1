param([Parameter(Mandatory=$true)][string]$AudioFile)
$ErrorActionPreference = 'Stop'
$player = New-Object System.Media.SoundPlayer $AudioFile
try { $player.Load(); $player.PlaySync() } finally { $player.Dispose() }
