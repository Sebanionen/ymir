[CmdletBinding()]
param(
    [ValidateSet('status','start','stop','restart')][string]$Action = 'status',
    [ValidateSet('whisper','kokoro','all')][string]$Engine = 'all',
    [switch]$Json
)
# Control installed engines only. No microphone, downloads or autostart registration.
$ErrorActionPreference = 'Stop'
function Setting([string]$Name, [string]$Default) {
    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (!$value) { $value = [Environment]::GetEnvironmentVariable($Name, 'User') }
    if ($value) { return $value }; return $Default
}
$homeRoot = Setting 'YMIR_HOME' (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ymirhome')
$runtime = Setting 'YMIR_VOICE_RUNTIME' (Join-Path $homeRoot 'hodd/state/runtime')
function Definition([string]$Name) {
    if ($Name -eq 'kokoro') {
        $dir = Join-Path $runtime 'kokoro'
        $manifest = Get-Content -Raw -LiteralPath (Join-Path $dir 'installation.json') | ConvertFrom-Json
        $port = [int]$manifest.start_environment.FASTKOKORO_PORT
        if ($manifest.start_environment.FASTKOKORO_HOST -ne '127.0.0.1') { throw 'Kokoro must bind loopback' }
        return @{ Dir=$dir; Exe=$manifest.start_executable; Arguments=@(); Port=$port;
            Health="http://127.0.0.1:$port/health"; Environment=$manifest.start_environment }
    }
    $dir = Join-Path $runtime 'snotra'
    $exe = Setting 'WHISPER_SERVER' (Join-Path $dir 'whisper-v1.9.2/Release/whisper-server.exe')
    $model = Setting 'WHISPER_MODEL' (Join-Path $dir 'models/ggml-small.bin')
    $port = [int](Setting 'WHISPER_PORT' '10300')
    return @{ Dir=$dir; Exe=$exe; Arguments=@('-m', ('"'+$model+'"'), '--host','127.0.0.1','--port',"$port");
        Port=$port; Health="http://127.0.0.1:$port/health"; Environment=$null }
}
function Listeners($Def) {
    @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object LocalPort -eq $Def.Port)
}
function OwnedProcesses($Def) {
    $listeners = @(Listeners $Def)
    $found = @()
    foreach ($listener in $listeners) {
        if ($listener.LocalAddress -ne '127.0.0.1') { throw 'Refusing non-loopback listener' }
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
        # FastKokoro's console entrypoint runs its adjacent venv python as a child.
        $expectedExe = [IO.Path]::GetFullPath($Def.Exe)
        $expectedPython = Join-Path (Split-Path $expectedExe) 'python.exe'
        $isEntry = $proc.ExecutablePath -eq $expectedExe
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.ParentProcessId)"
        $isChild = $proc.CommandLine -like ('*"'+$expectedExe+'"*') -and (
            $proc.ExecutablePath -eq $expectedPython -or (
                $parent.ExecutablePath -eq $expectedPython -and
                $parent.CommandLine -like ('*"'+$expectedExe+'"*')))
        if (!$proc -or !($isEntry -or $isChild)) { throw 'Listener belongs to another process; refusing control' }
        $found += $proc
    }
    @($found | Sort-Object ProcessId -Unique)
}
function Healthy($Def) {
    try { $response = Invoke-WebRequest -UseBasicParsing -Uri $Def.Health -TimeoutSec 3; return $response.StatusCode -eq 200 }
    catch { return $false }
}
function StopEngine($Def) {
    foreach ($proc in @(OwnedProcesses $Def)) {
        # Recheck executable and creation time immediately before stopping: no stale PID authority.
        $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.ProcessId)"
        if (!$current -or $current.CreationDate -ne $proc.CreationDate -or $current.ExecutablePath -ne $proc.ExecutablePath) { throw 'Process identity changed' }
        Stop-Process -Id $proc.ProcessId -ErrorAction Stop
    }
    for ($i=0; $i -lt 50; $i++) {
        if (@(Listeners $Def).Count -eq 0) { return }; Start-Sleep -Milliseconds 100
    }
    throw 'Listener did not stop'
}
function StartEngine($Def) {
    if (@(OwnedProcesses $Def).Count) {
        if (!(Healthy $Def)) { throw 'Existing engine is unhealthy; use restart' }; return
    }
    if (!(Test-Path -LiteralPath $Def.Exe -PathType Leaf)) { throw 'Installed executable missing' }
    $saved = @{}
    try {
        if ($Def.Environment) {
            foreach ($property in $Def.Environment.PSObject.Properties) {
                $saved[$property.Name] = [Environment]::GetEnvironmentVariable($property.Name,'Process')
                [Environment]::SetEnvironmentVariable($property.Name,[string]$property.Value,'Process')
            }
        }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-ffff'
        $options = @{ FilePath=$Def.Exe; WorkingDirectory=$Def.Dir; WindowStyle='Hidden'; PassThru=$true;
            RedirectStandardOutput=(Join-Path $Def.Dir "service-$stamp.out.log");
            RedirectStandardError=(Join-Path $Def.Dir "service-$stamp.err.log") }
        if ($Def.Arguments.Count) { $options.ArgumentList = $Def.Arguments }
        $started = Start-Process @options
    } finally {
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
    }
    for ($i=0; $i -lt 120; $i++) {
        if ((Healthy $Def) -and @(OwnedProcesses $Def).Count) { return }
        Start-Sleep -Milliseconds 500
    }
    throw 'Engine did not become healthy within 60 seconds; inspect private runtime logs'
}
try {
    $names = @($Engine); if ($Engine -eq 'all') { $names = @('whisper','kokoro') }
    $results = foreach ($name in $names) {
        $def = Definition $name
        if ($Action -in @('stop','restart')) { StopEngine $def }
        if ($Action -in @('start','restart')) { StartEngine $def }
        $processes = @(OwnedProcesses $def)
        [pscustomobject]@{ engine=$name; road='local Windows'; listening=($processes.Count -gt 0);
            healthy=($processes.Count -gt 0 -and (Healthy $def)); process_ids=@($processes | ForEach-Object ProcessId) }
    }
    if ($Json) { ConvertTo-Json -InputObject @($results) -Depth 4 }
    else {
        Write-Output ('voice_service[' + @($results).Count + ']{engine,road,listening,healthy}:')
        foreach ($row in $results) {
            Write-Output ('  "{0}","{1}","{2}","{3}"' -f $row.engine,$row.road,$row.listening,$row.healthy)
        }
    }
    exit 0
} catch {
    Write-Output 'voice_service[1]{status,detail}:'
    Write-Output ('  "error",' + (ConvertTo-Json -Compress -InputObject $_.Exception.Message))
    exit 1
}
