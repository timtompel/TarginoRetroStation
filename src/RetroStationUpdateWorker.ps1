param([string]$Root,[string]$Installed,[string]$Job,[int]$LauncherPid,[switch]$Automatic)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'FrontendUpdate.ps1')
function Show-RetroStationUpdateChoice($manifest){
    Add-Type -AssemblyName System.Drawing
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Nova versao do Targino RetroStation';ClientSize='640,420';StartPosition='CenterScreen';FormBorderStyle='FixedDialog';MaximizeBox=$false;MinimizeBox=$false;Font=(New-Object Drawing.Font('Segoe UI',10))}
    $title=New-Object Windows.Forms.Label -Property @{Text=('Versao '+$manifest.version+' disponivel');Left=22;Top=18;Width=590;Height=36;Font=(New-Object Drawing.Font('Segoe UI',17,[Drawing.FontStyle]::Bold))}
    $body=New-Object Windows.Forms.TextBox -Property @{Text=($manifest.notes+"`r`n`r`nA atualizacao e opcional. Nada sera baixado se escolher Agora nao.");Left=24;Top=65;Width=590;Height=265;Multiline=$true;ReadOnly=$true;ScrollBars='Vertical'}
    $yes=New-Object Windows.Forms.Button -Property @{Text='Atualizar agora';Left=310;Top=355;Width=150;Height=38;DialogResult='Yes'}
    $no=New-Object Windows.Forms.Button -Property @{Text='Agora nao';Left=470;Top=355;Width=145;Height=38;DialogResult='No'}
    $dialog.Controls.AddRange(@($title,$body,$yes,$no));$dialog.AcceptButton=$yes;$dialog.CancelButton=$no
    try{return $dialog.ShowDialog()}finally{$dialog.Dispose()}
}
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
    if((Show-RetroStationUpdateChoice $m) -ne 'Yes'){exit 0}
    $setup=Join-Path $Job $m.fileName
    Receive-FrontendFile $m.url $setup 512MB $null ''
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
}finally{
    [IO.File]::WriteAllText((Join-Path $Job 'completed'),[datetime]::UtcNow.ToString('o'))
}
