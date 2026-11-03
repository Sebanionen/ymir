[CmdletBinding()]
param([int]$UiPort = 3988, [int]$ApiPort = 3989)
$ErrorActionPreference = 'Stop'
# A worktree-only preview. No main deployment, shared service stop or secret file.
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$homeRoot = [Environment]::GetEnvironmentVariable('YMIR_HOME', 'User')
if (!$homeRoot) { $homeRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ymirhome' }
$state = Join-Path $homeRoot ('hodd/state/runtime/skirnir-preview-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
foreach ($port in @($UiPort,$ApiPort)) {
    if (Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object LocalPort -eq $port) {
        throw "Preview port $port is occupied; choose a free preview port. No process was stopped."
    }
}
$node = (Get-Command node.exe -ErrorAction Stop).Source
$bun = $env:YMIR_BUN
if (!$bun) {
    $candidate = Get-Command bun -ErrorAction Stop
    if ($candidate.Source.EndsWith('.exe')) { $bun = $candidate.Source }
    else { $bun = Join-Path (Split-Path $candidate.Source) 'node_modules/bun/bin/bun.exe' }
}
if (!(Test-Path -LiteralPath $bun)) { throw 'Set YMIR_BUN to the installed bun executable.' }
$vite = Join-Path $root 'apps/hlidskjalf/node_modules/vite/bin/vite.js'
if (!(Test-Path -LiteralPath $vite)) { throw 'Install the Hlidskjalf package dependencies first.' }
New-Item -ItemType Directory -Force $state | Out-Null
$names = @('PORT','HLIDSKJALF_API_PORT','HLIDSKJALF_PORT','HLIDSKJALF_HOST','YMIR_HOME','YMIR_HOARD',
    'YMIR_CONFIG_DIR','YMIR_SESSION_SECRET','HLIDSKJALF_AUTH','SKIRNIR_HOME','SKIRNIR_VOICE_TMP','VITE_DEMO','VITE_API_URL')
$prior = @{}; foreach ($name in $names) { $prior[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    $env:PORT="$ApiPort"; $env:HLIDSKJALF_API_PORT="$ApiPort"; $env:HLIDSKJALF_PORT="$UiPort"
    $env:HLIDSKJALF_HOST='127.0.0.1'
    $env:YMIR_HOME=Join-Path $state 'preview-home'; $env:YMIR_HOARD=Join-Path $env:YMIR_HOME 'hodd'
    $env:YMIR_CONFIG_DIR=Join-Path $state 'config'
    # Process-only signing key: do not read the real gate's key or credentials.
    $env:YMIR_SESSION_SECRET=[Guid]::NewGuid().ToString('N')+[Guid]::NewGuid().ToString('N')
    $env:HLIDSKJALF_AUTH=$null; $env:VITE_DEMO=$null; $env:VITE_API_URL=$null
    $env:SKIRNIR_HOME=$homeRoot; $env:SKIRNIR_VOICE_TMP=Join-Path $state 'voice-turns'
    $api = Start-Process -FilePath $bun -ArgumentList @('--no-env-file',('"'+(Join-Path $root 'apps/hlidskjalf/server/index.ts')+'"')) `
        -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'api.out.log') -RedirectStandardError (Join-Path $state 'api.err.log')
    $ui = Start-Process -FilePath $node -ArgumentList @(('"'+$vite+'"'),'--host','127.0.0.1','--port',"$UiPort",'--strictPort') `
        -WorkingDirectory (Join-Path $root 'apps/hlidskjalf') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'ui.out.log') -RedirectStandardError (Join-Path $state 'ui.err.log')
    [pscustomobject]@{ source=$root; state=$state; apiPid=$api.Id; uiPid=$ui.Id;
        apiCreated=$api.StartTime.ToString('o'); uiCreated=$ui.StartTime.ToString('o');
        url="http://127.0.0.1:$UiPort/#/skirnir" } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $state 'preview.json')
    for ($i=0; $i -lt 30; $i++) {
        try {
            $gate=Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$ApiPort/api/skirnir/voice/status" -TimeoutSec 2
            $page=Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$UiPort" -TimeoutSec 2
            if ($gate.StatusCode -eq 200 -and $page.StatusCode -eq 200) {
                Write-Output "Local worktree preview: http://127.0.0.1:$UiPort/#/skirnir"
                Write-Output "Private preview evidence: $state"; exit 0
            }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    throw 'Preview did not answer; inspect its private logs. No shared service was stopped.'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,$prior[$name],'Process') }
}
