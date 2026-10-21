$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
. (Join-Path $project 'src\FrontendUpdate.ps1')
if(Test-FrontendNewer '1.5.0' '1.5.1-preview.1'){throw 'Previa aceita'}
if(Test-FrontendNewer '1.5.0' '1.4.2'){throw 'Downgrade aceito'}
if(-not(Test-FrontendNewer '1.5.0' '1.5.1')){throw 'Nova estavel recusada'}
function Must-Fail([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};if(-not $failed){throw 'Validacao deveria recusar'}}
Must-Fail {Assert-FrontendAssetUrl 'https://github.com/timtompel/TarginoLauncher/releases/download/v1.5.1/update.json' '1.5.1' 'update.json'}
Must-Fail {Get-FrontendStableRelease @{draft=$false;prerelease=$true;tag_name='v1.5.1';assets=@()}}
$dir=Join-Path $project ('build\crypto-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider 3072;$rsa.PersistKeyInCsp=$false
try{
    $key=Join-Path $dir 'public.xml';[IO.File]::WriteAllText($key,$rsa.ToXmlString($false))
    $payload=@{schemaVersion=1;product='TarginoRetroStation.Hydra';channel='stable';version='1.5.1';fileName='TarginoRetroStation-1.5.1-Setup.exe';size=2048;sha256=('a'*64);url='https://github.com/timtompel/TarginoRetroStation/releases/download/v1.5.1/TarginoRetroStation-1.5.1-Setup.exe';notes='teste'}
    function Sign-Payload($value){$bytes=[Text.Encoding]::UTF8.GetBytes(($value|ConvertTo-Json -Compress));$envelope=@{algorithm='RSA-SHA256';payload=[Convert]::ToBase64String($bytes);signature=[Convert]::ToBase64String($rsa.SignData($bytes,'SHA256'))};$path=Join-Path $dir 'update.json';[IO.File]::WriteAllText($path,($envelope|ConvertTo-Json));return $path}
    $path=Sign-Payload $payload;[void](Read-FrontendSignedManifest $path $key)
    $e=[IO.File]::ReadAllText($path)|ConvertFrom-Json;$bytes=[Convert]::FromBase64String($e.payload);$bytes[0]=$bytes[0] -bxor 1;$e.payload=[Convert]::ToBase64String($bytes);[IO.File]::WriteAllText($path,($e|ConvertTo-Json));Must-Fail {Read-FrontendSignedManifest $path $key}
    $payload.product='TarginoLauncher.Recompilados';$path=Sign-Payload $payload;Must-Fail {Read-FrontendSignedManifest $path $key}
    $payload.product='TarginoRetroStation.Hydra';$payload.size=65MB;$path=Sign-Payload $payload;[void](Read-FrontendSignedManifest $path $key)
    $payload.size=513MB;$path=Sign-Payload $payload;Must-Fail {Read-FrontendSignedManifest $path $key}
    Must-Fail {Assert-FrontendPackage (Join-Path $project 'README.md') @{size=1;sha256=('a'*64)}}
}finally{$rsa.Dispose()}
Write-Output 'STABLE_ONLY_NO_DOWNGRADE_WRONG_REPO_WRONG_PRODUCT_TAMPERED_SIGNATURE_AND_HASH_REJECTED_OK'
. (Join-Path $project 'src\RetroStationUpdateUI.ps1')
$script:Runs=@();$script:Play=@{'fixture'=@{Hydra=$true}};$script:TarginoMusicLaunchPending=$false
Start-RetroStationUpdate -Automatic
if($script:RetroUpdateProcess){throw 'Atualizacao iniciou com Hydra aberto'}
$script:Play=@{};$script:TarginoMusicLaunchPending=$true
Start-RetroStationUpdate -Automatic
if($script:RetroUpdateProcess){throw 'Atualizacao iniciou durante abertura do jogo'}
Write-Output 'UPDATER_BLOCKED_WHILE_GAME_OPEN_OR_LAUNCH_PENDING_OK'
