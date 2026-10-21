# Separate stable channel. Network/download work runs in another process, not the game UI.
function Start-RetroStationUpdate([switch]$Automatic){
    if($script:RetroUpdateProcess -and -not $script:RetroUpdateProcess.HasExited){return}
    if(@($script:Runs).Count -gt 0 -or @($script:Play.Values).Count -gt 0 -or $script:TarginoMusicLaunchPending){
        if(-not $Automatic){[void][Windows.Forms.MessageBox]::Show('Feche o jogo antes de atualizar.','Targino RetroStation')};return
    }
    $script:RetroUpdateJob=Join-Path $Arq ('Cache\Update\'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($script:RetroUpdateJob)
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi.Arguments='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $Arq 'RetroStationUpdateWorker.ps1')+'" -Root "'+$Root+'" -Installed "'+$AppVer+'" -Job "'+$script:RetroUpdateJob+'" -LauncherPid '+$PID
    if($Automatic){$psi.Arguments+=' -Automatic'}
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.WorkingDirectory=$Root
    $script:RetroUpdateProcess=[Diagnostics.Process]::Start($psi)
    [void](WriteJson (Join-Path $script:RetroUpdateJob 'active.json') @{WorkerPid=$script:RetroUpdateProcess.Id} 2)
}
function Initialize-RetroStationUpdates {
    . (Join-Path $Arq 'UpdateCache.ps1')
    Clear-RetroStationUpdateCache (Join-Path $Arq 'Cache\Update')
    $script:RetroUpdateTimer=New-Object Windows.Forms.Timer -Property @{Interval=1200}
    $script:RetroUpdateTimer.Add_Tick({
        if(-not $script:RetroUpdateJob){return}
        $signal=Join-Path $script:RetroUpdateJob 'ready-to-install'
        if([IO.File]::Exists($signal)){
            $ready=ReadJson $signal $false
            if(-not $ready){return}
            $activeInstaller=Get-Process -Id ([int]$ready.InstallerPid) -ErrorAction SilentlyContinue
            if(-not $activeInstaller){return}
            if(@($script:Runs).Count -gt 0 -or @($script:Play.Values).Count -gt 0 -or $script:TarginoMusicLaunchPending){return}
            $script:RetroUpdateTimer.Stop();$form.Close()
        }
    });$script:RetroUpdateTimer.Start()
    $form.Add_FormClosed({$script:RetroUpdateTimer.Stop();$script:RetroUpdateTimer.Dispose()})
    $form.Add_Shown({
        $path=Join-Path $DataDir 'retrostation-update-check.json'
        $previous=ReadJson $path $false
        $today=[datetime]::UtcNow.ToString('yyyy-MM-dd')
        if(-not $previous -or $previous.Day -ne $today){
            [void](WriteJson $path @{Day=$today} 2)
            Start-RetroStationUpdate -Automatic
        }
    })
}
