$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
. (Join-Path $project 'src\HydraMetadata.ps1')
$dir=Join-Path $project ('build\media-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$script:calls=0
function NewHydraMetadataWebClient {
    $fake=[pscustomobject]@{Headers=@{}}
    $fake|Add-Member ScriptMethod DownloadFile {param($url,$path) $script:calls++;[IO.File]::WriteAllBytes($path,[byte[]]@(1,2,3,4))}
    $fake|Add-Member ScriptMethod Dispose {}
    return $fake
}
$path=Join-Path $dir 'media.png'
Receive-HydraMedia 'https://example.invalid/image.png' $path
Receive-HydraMedia 'https://example.invalid/image.png' $path
if($script:calls -ne 1 -or (Get-Item -LiteralPath $path).Length -ne 4){throw 'Cache local nao foi respeitado'}
$failed=$false;try{Receive-HydraMedia 'http://example.invalid/image.png' (Join-Path $dir 'invalid.png')}catch{$failed=$true};if(-not $failed){throw 'Midia HTTP aceita'}
foreach($name in @('HydraDetailsWorker.ps1','HydraArtwork.ps1')){
    $source=[IO.File]::ReadAllText((Join-Path $project ('src\'+$name)))
    if($source -match 'python|codex-runtimes|hydra-media-transport'){throw 'Dependencia de desenvolvimento ainda presente'}
    if($source -notmatch 'Receive-HydraMedia'){throw 'Transporte compartilhado nao conectado'}
}
'SHARED_NATIVE_MEDIA_TRANSPORT_LOCAL_CACHE_HTTPS_ONLY_AND_NO_PYTHON_OK'
