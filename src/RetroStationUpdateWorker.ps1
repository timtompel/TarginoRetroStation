param([string]$Root,[string]$Installed,[string]$Job,[int]$LauncherPid,[switch]$Automatic)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'FrontendUpdate.ps1')
try{
    $api=Join-Path $Job 'release.json'
    Receive-FrontendFile 'https://api.github.com/repos/timtompel/TarginoRetroStation/releases/latest' $api 1MB $null ''
    $release=Get-FrontendStableRelease ([IO.File]::ReadAllText($api)|ConvertFrom-Json)
    $envelope=Join-Path $Job 'update.json'
    Receive-FrontendFile $release.manifestUrl $envelope 65536 $null ''
    $m=Read-FrontendSignedManifest $envelope (Join-Path $PSScriptRoot 'UpdatePublicKey.xml')
    if($m.version -cne $release.version){throw 'Versao do manifesto difere da release.'}
    if(-not (Test-FrontendNewer $Installed $m.version)){
        if(-not $Automatic){[void][Windows.Forms.MessageBox]::Show('Voce ja esta na versao estavel mais recente: '+$Installed,'Targino RetroStation')};exit 0
    }
    $question='Versao estavel '+$m.version+" disponivel.`r`n`r`n"+$m.notes+"`r`n`r`nBaixar e instalar? O launcher sera fechado e reaberto. Seus dados serao preservados."
    if([Windows.Forms.MessageBox]::Show($question,'Atualizacao do Targino RetroStation','YesNo','Information') -ne 'Yes'){exit 0}
    $setup=Join-Path $Job $m.fileName
    Receive-FrontendFile $m.url $setup 64MB $null ''
    Assert-FrontendPackage $setup $m
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$setup;$psi.Arguments='--apply-update "'+$Root+'" '+$LauncherPid
    $psi.UseShellExecute=$false;$psi.WorkingDirectory=$Root
    $installer=[Diagnostics.Process]::Start($psi)
    [IO.File]::WriteAllText((Join-Path $Job 'ready-to-install'),(@{Version=$m.version;InstallerPid=$installer.Id}|ConvertTo-Json -Compress))
}catch{
    [IO.File]::WriteAllText((Join-Path $Job 'error.txt'),$_.Exception.Message)
    if(-not $Automatic){[void][Windows.Forms.MessageBox]::Show('Nao foi possivel verificar/baixar a atualizacao. Nada foi instalado.'+"`r`n"+$_.Exception.Message,'Targino RetroStation','OK','Warning')}
    exit 1
}
