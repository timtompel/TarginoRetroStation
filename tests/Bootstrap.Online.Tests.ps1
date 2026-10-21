$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$job=Join-Path $project ('build\bootstrap-online-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($job)
# Test only download/verification; never executes the downloaded installer.
foreach($name in @('FrontendUpdate.ps1','Hashing.ps1','UpdateCache.ps1','UpdatePublicKey.xml')){Copy-Item -LiteralPath (Join-Path $project ('src\'+$name)) -Destination $job}
Copy-Item -LiteralPath (Join-Path $project 'installer\BootstrapWorker.ps1') -Destination $job
$worker=Join-Path $job 'BootstrapWorker.ps1'
$p=Start-Process -FilePath powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$worker+'" -Job "'+$job+'"') -WindowStyle Hidden -Wait -PassThru
$state=[IO.File]::ReadAllText((Join-Path $job 'status.json'))|ConvertFrom-Json
if($p.ExitCode -ne 0 -or $state.Phase -ne 'ready'){throw $state.Message}
. (Join-Path $job 'FrontendUpdate.ps1')
$manifest=Read-FrontendSignedManifest (Join-Path $job 'update.json') (Join-Path $job 'UpdatePublicKey.xml')
if($manifest.version -ne '1.5.4'){throw 'Bootstrap recebeu versao diferente da 1.5.4'}
Assert-FrontendPackage $state.Package $manifest
'BOOTSTRAP_PUBLIC_STABLE_DOWNLOAD_SIGNATURE_SIZE_HASH_VERIFIED_NO_INSTALLER_EXECUTED_OK version='+$manifest.version
