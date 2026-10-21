$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms
$web=Join-Path $project 'dist\TarginoRetroStation-1.5.2-WebSetup.exe'
if((Get-Item -LiteralPath $web).Length -gt 512KB){throw 'Bootstrapper grande demais'}
$assembly=[Reflection.Assembly]::LoadFile($web)
$names=$assembly.GetManifestResourceNames()
foreach($name in @('BootstrapWorker.ps1','FrontendUpdate.ps1','Hashing.ps1','UpdateCache.ps1','UpdatePublicKey.xml')){if($names -notcontains $name){throw ('Recurso ausente '+$name)}}
if($names -contains 'hydra.payload.zip'){throw 'Web installer incorpora pacote completo'}
$stream=$assembly.GetManifestResourceStream('UpdatePublicKey.xml');$reader=New-Object IO.StreamReader($stream)
try{$key=$reader.ReadToEnd()}finally{$reader.Dispose()}
if($key.Trim() -cne [IO.File]::ReadAllText((Join-Path $project 'src\UpdatePublicKey.xml')).Trim()){throw 'Chave do bootstrapper difere da producao'}
$dialog=[Activator]::CreateInstance($assembly.GetType('Bootstrapper'))
try{
    if(@($dialog.Controls|Where-Object {$_.Text -eq 'Baixar instalador'}).Count -ne 1){throw 'Acao inicial ausente'}
    $sample=Join-Path $project ('build\tamper-'+[guid]::NewGuid().ToString('N')+'.exe');[IO.File]::WriteAllBytes($sample,[byte[]]@(1,2,3,4))
    $flags=[Reflection.BindingFlags]'Instance,NonPublic';$type=$assembly.GetType('Bootstrapper')
    $type.GetField('package',$flags).SetValue($dialog,$sample)
    $type.GetField('packageSize',$flags).SetValue($dialog,[long]4)
    $type.GetField('packageHash',$flags).SetValue($dialog,('a'*64))
    [void]$type.GetMethod('StartOrInstall',$flags).Invoke($dialog,@())
    if($type.GetField('status',$flags).GetValue($dialog).Text -notlike '*Hash do pacote mudou*'){throw 'Pacote alterado nao foi bloqueado antes de executar'}
}finally{$dialog.Dispose()}
'SMALL_BOOTSTRAPPER_RESOURCE_TRUST_KEY_UI_AND_NO_EMBEDDED_PAYLOAD_OK'
$job=Join-Path $project ('build\bootstrap-cancel-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($job)
foreach($name in @('BootstrapWorker.ps1','FrontendUpdate.ps1','Hashing.ps1','UpdateCache.ps1','UpdatePublicKey.xml')){
    $stream=$assembly.GetManifestResourceStream($name);$output=[IO.File]::Create((Join-Path $job $name))
    try{$stream.CopyTo($output)}finally{$output.Dispose();$stream.Dispose()}
}
[IO.File]::WriteAllText((Join-Path $job 'cancel'),'cancel')
$p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $job 'BootstrapWorker.ps1')+'" -Job "'+$job+'"') -WindowStyle Hidden -PassThru -Wait
$status=[IO.File]::ReadAllText((Join-Path $job 'status.json'))|ConvertFrom-Json
if($p.ExitCode -eq 0 -or $status.Phase -ne 'error' -or @(Get-ChildItem -LiteralPath $job -Filter '*.exe').Count){throw 'Cancelamento nao bloqueou download/instalacao'}
'BOOTSTRAP_CANCEL_BEFORE_DOWNLOAD_NO_PACKAGE_EXECUTED_OK'
