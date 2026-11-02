param([Parameter(Mandatory=$true)][string]$Job)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'FrontendUpdate.ps1')
. (Join-Path $PSScriptRoot 'UpdateCache.ps1')
function Set-BootstrapStatus([string]$phase,[string]$message,[int]$percent=0,[string]$package=''){
    $path=Join-Path $Job 'status.json'
    # Advisory UI status only. Readers tolerate an incomplete write; executable
    # trust is established separately by the signed manifest and package hash.
    [IO.File]::WriteAllText($path,(@{Phase=$phase;Message=$message;Percent=$percent;Package=$package;Sha256=$script:VerifiedSHA;Size=$script:VerifiedSize}|ConvertTo-Json -Compress),[Text.Encoding]::UTF8)
}
try{
    Clear-RetroStationUpdateCache (Split-Path $Job)
    $cancel=Join-Path $Job 'cancel'
    Set-BootstrapStatus 'download' 'Consultando a versao estavel...'
    $envelope=Join-Path $Job 'update.json'
    Receive-FrontendFile 'https://github.com/timtompel/TarginoRetroStation/releases/latest/download/update.json' $envelope 65536 $null $cancel
    $manifest=Read-FrontendSignedManifest $envelope (Join-Path $PSScriptRoot 'UpdatePublicKey.xml')
    $package=Join-Path $Job $manifest.fileName
    Receive-FrontendFile $manifest.url $package 512MB {
        param($received,$total)
        $percent=if($total -gt 0){[Math]::Min(99,[int](100*$received/$total))}else{0}
        Set-BootstrapStatus 'download' ('Baixando '+$manifest.version+' — '+[Math]::Round($received/1MB,1)+' MiB') $percent
    } $cancel
    Assert-FrontendPackage $package $manifest
    $script:VerifiedSHA=$manifest.sha256;$script:VerifiedSize=$manifest.size
    if([IO.File]::Exists($cancel)){throw [OperationCanceledException]::new('Cancelado.')}
    Set-BootstrapStatus 'ready' ('Versao '+$manifest.version+' verificada. Pronta para instalar.') 100 $package
}catch{
    Set-BootstrapStatus 'error' $_.Exception.Message
    exit 1
}finally{
    [IO.File]::WriteAllText((Join-Path $Job 'completed'),[datetime]::UtcNow.ToString('o'))
}
