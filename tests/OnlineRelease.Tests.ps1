$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
. (Join-Path $project 'src\FrontendUpdate.ps1')
$job=Join-Path $project ('build\online-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($job)
$api=Join-Path $job 'release.json'
Receive-FrontendFile 'https://api.github.com/repos/timtompel/TarginoRetroStation/releases/latest' $api 1MB $null ''
$release=Get-FrontendStableRelease ([IO.File]::ReadAllText($api)|ConvertFrom-Json)
if($release.version -cne '1.5.1'){throw 'Release publicada diferente da esperada'}
$path=Join-Path $job 'update.json';Receive-FrontendFile $release.manifestUrl $path 65536 $null ''
$m=Read-FrontendSignedManifest $path (Join-Path $project 'src\UpdatePublicKey.xml')
if(-not(Test-FrontendNewer '1.4.2' $m.version)){throw 'Migracao de versao nao detectada'}
if(Test-FrontendNewer '1.5.1' $m.version){throw 'Reinstalacao automatica indevida'}
$setup=Join-Path $job $m.fileName;Receive-FrontendFile $m.url $setup 64MB $null '';Assert-FrontendPackage $setup $m
if((Get-FileHash -LiteralPath $setup).Hash -cne (Get-FileHash -LiteralPath (Join-Path $project ('dist\'+$m.fileName))).Hash){throw 'Pacote publicado difere do local'}
Write-Output 'PUBLIC_LATEST_RELEASE_SIGNED_MANIFEST_DOWNLOADED_SETUP_HASH_AND_VERSION_OK'
