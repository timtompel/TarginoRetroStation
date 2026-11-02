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
function New-RetroStationDownloadProgress([string]$Version){
    Add-Type -AssemblyName System.Drawing
    $form=New-Object Windows.Forms.Form -Property @{Text='Baixando atualizacao';ClientSize='460,130';StartPosition='CenterScreen';FormBorderStyle='FixedDialog';MaximizeBox=$false;MinimizeBox=$false;ControlBox=$false;TopMost=$true;Font=(New-Object Drawing.Font('Segoe UI',10))}
    $label=New-Object Windows.Forms.Label -Property @{Text=('Baixando a versao '+$Version+'...');Left=18;Top=14;Width=424;Height=24}
    $bar=New-Object Windows.Forms.ProgressBar -Property @{Left=20;Top=44;Width=420;Height=22;Minimum=0;Maximum=1000}
    $cancel=New-Object Windows.Forms.Button -Property @{Text='Cancelar';Left=340;Top=82;Width=100;Height=32}
    $cancel.Add_Click({[IO.File]::WriteAllText($script:cancelPath,'cancel');$this.Enabled=$false;$script:ui.Label.Text='Cancelando...'})
    $form.Controls.AddRange(@($label,$bar,$cancel))
    [pscustomobject]@{Form=$form;Label=$label;Bar=$bar}
}
function Update-RetroStationDownloadProgress($Ui,[long]$Received,[long]$Total){
    if($Total -gt 0){
        $Ui.Bar.Value=[int][Math]::Min(1000,[Math]::Floor(1000.0*$Received/$Total))
        $Ui.Label.Text=('Baixando: {0:N1} de {1:N1} MB' -f ($Received/1MB),($Total/1MB))
    }else{$Ui.Label.Text=('Baixando: {0:N1} MB' -f ($Received/1MB))}
    [Windows.Forms.Application]::DoEvents()
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
    $script:cancelPath=Join-Path $Job 'cancel'
    $script:expectedSize=[long]$m.size
    $script:ui=New-RetroStationDownloadProgress $m.version
    try{
        $script:ui.Form.Show();[Windows.Forms.Application]::DoEvents()
        $progress={param($received,$total) $size=if($total -gt 0){$total}else{$script:expectedSize};Update-RetroStationDownloadProgress $script:ui $received $size}
        Receive-FrontendFile $m.url $setup 512MB $progress $script:cancelPath
    }finally{$script:ui.Form.Close();$script:ui.Form.Dispose()}
    Assert-FrontendPackage $setup $m
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$setup;$psi.Arguments='--apply-update "'+$Root+'" '+$LauncherPid
    $psi.UseShellExecute=$false;$psi.WorkingDirectory=$Root
    $installer=[Diagnostics.Process]::Start($psi)
    [IO.File]::WriteAllText((Join-Path $Job 'ready-to-install'),(@{Version=$m.version;InstallerPid=$installer.Id}|ConvertTo-Json -Compress))
}catch [OperationCanceledException]{
    exit 0
}catch{
    [IO.File]::WriteAllText((Join-Path $Job 'error.txt'),$_.Exception.Message)
    if(-not $Automatic){[void][Windows.Forms.MessageBox]::Show('Nao foi possivel verificar/baixar a atualizacao. Nada foi instalado.'+"`r`n"+$_.Exception.Message,'Targino RetroStation','OK','Warning')}
    exit 1
}finally{
    [IO.File]::WriteAllText((Join-Path $Job 'completed'),[datetime]::UtcNow.ToString('o'))
}
