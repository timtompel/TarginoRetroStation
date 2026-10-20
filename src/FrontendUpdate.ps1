# Atualizacao exclusiva do frontend. Sem tokens ou escrita na biblioteca/base.
. (Join-Path $PSScriptRoot 'Hashing.ps1')
function Read-FrontendStatus([string]$Path){
    $stream=$null;$reader=$null
    try{
        $sharing=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$sharing)
        $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true)
        return ($reader.ReadToEnd()|ConvertFrom-Json)
    }catch{
        if($_.Exception.GetBaseException() -is [IO.IOException]){return $null}
        throw
    }finally{if($reader){$reader.Dispose()}elseif($stream){$stream.Dispose()}}
}
function Get-FrontendVersionParts([string]$Version){
    if($Version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-preview\.[1-9][0-9]*)?$'){throw 'Versao invalida.'}
    [pscustomobject]@{number=[version]($Version.Split('-')[0]);preview=$Version.Contains('-')}
}
function Test-FrontendNewer([string]$Installed,[string]$Available){
    $local=Get-FrontendVersionParts $Installed;$remote=Get-FrontendVersionParts $Available
    return (-not $remote.preview -and ($remote.number -gt $local.number -or ($remote.number -eq $local.number -and $local.preview)))
}
function Assert-FrontendAssetUrl([string]$Url,[string]$Version,[string]$Name){
    $expected='https://github.com/timtompel/TarginoRetroStation/releases/download/v'+$Version+'/'+$Name
    if($Url -cne $expected){throw 'Origem do pacote nao autorizada.'}
}
function Read-FrontendSignedManifest([string]$EnvelopePath,[string]$PublicKeyPath){
    if((Get-Item -LiteralPath $EnvelopePath).Length -gt 65536){throw 'Manifesto excede limite.'}
    $envelope=[IO.File]::ReadAllText($EnvelopePath)|ConvertFrom-Json
    if($envelope.algorithm -cne 'RSA-SHA256'){throw 'Assinatura nao suportada.'}
    $bytes=[Convert]::FromBase64String($envelope.payload)
    $rsa=New-Object Security.Cryptography.RSACryptoServiceProvider
    $rsa.PersistKeyInCsp=$false
    try{
        $rsa.FromXmlString([IO.File]::ReadAllText($PublicKeyPath))
        if($rsa.KeySize -lt 3072 -or -not $rsa.VerifyData($bytes,'SHA256',[Convert]::FromBase64String($envelope.signature))){throw 'Assinatura do manifesto invalida.'}
    }finally{$rsa.Dispose()}
    $m=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
    $version=Get-FrontendVersionParts $m.version
    if($m.schemaVersion -ne 1 -or $m.product -cne 'TarginoRetroStation.Hydra' -or $m.channel -cne 'stable' -or $version.preview){throw 'Manifesto nao e uma versao estavel deste produto.'}
    if($m.fileName -cne ('TarginoRetroStation-'+$m.version+'-Setup.exe') -or $m.sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or $m.size -lt 1024 -or $m.size -gt 64MB){throw 'Dados de pacote invalidos.'}
    if($m.notes -isnot [string] -or $m.notes.Length -gt 8000){throw 'Notas invalidas.'}
    Assert-FrontendAssetUrl $m.url $m.version $m.fileName
    return $m
}
function Assert-FrontendPackage([string]$Path,$Manifest){
    $file=Get-Item -LiteralPath $Path
    if($file.Length -ne $Manifest.size -or (Get-TarginoFileSHA256 $Path) -ine $Manifest.sha256){throw 'Pacote incompleto ou adulterado. Instalacao bloqueada.'}
}
function Receive-FrontendFile([string]$Url,[string]$Destination,[long]$Limit,[scriptblock]$Progress,[string]$CancelPath){
    if($CancelPath -and [IO.File]::Exists($CancelPath)){throw [OperationCanceledException]::new('Atualizacao cancelada pelo usuario.')}
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $request=[Net.HttpWebRequest]::Create($Url);$request.UserAgent='TarginoRetroStation-Updater';$request.Timeout=20000;$request.ReadWriteTimeout=30000
    $request.CachePolicy=New-Object Net.Cache.RequestCachePolicy([Net.Cache.RequestCacheLevel]::NoCacheNoStore)
    $response=$null;$input=$null;$output=$null
    try{
        $response=$request.GetResponse()
        if($CancelPath -and [IO.File]::Exists($CancelPath)){throw [OperationCanceledException]::new('Atualizacao cancelada pelo usuario.')}
        if($response.ResponseUri.Scheme -ne 'https' -or $response.ResponseUri.Host -notin @('api.github.com','github.com','release-assets.githubusercontent.com','objects.githubusercontent.com')){throw 'Redirecionamento nao autorizado.'}
        if($response.ContentLength -gt $Limit){throw 'Download excede limite.'}
        $input=$response.GetResponseStream();$output=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew)
        $buffer=New-Object byte[] 65536;$received=0L;$last=[DateTime]::MinValue;$started=[DateTime]::UtcNow
        while(($count=$input.Read($buffer,0,$buffer.Length)) -gt 0){
            if($CancelPath -and [IO.File]::Exists($CancelPath)){throw [OperationCanceledException]::new('Atualizacao cancelada pelo usuario.')}
            $received+=$count;if($received -gt $Limit -or ([DateTime]::UtcNow-$started).TotalMinutes -gt 15){throw 'Limite do download excedido.'}
            $output.Write($buffer,0,$count)
            if($Progress -and ([DateTime]::UtcNow-$last).TotalMilliseconds -gt 250){& $Progress $received $response.ContentLength;$last=[DateTime]::UtcNow}
        }
        if($CancelPath -and [IO.File]::Exists($CancelPath)){throw [OperationCanceledException]::new('Atualizacao cancelada pelo usuario.')}
    }finally{if($output){$output.Dispose()};if($input){$input.Dispose()};if($response){$response.Dispose()}}
}
function Get-FrontendStableRelease($Release){
    if($Release.draft -or $Release.prerelease){throw 'Release nao estavel.'}
    $version=[string]$Release.tag_name
    if(-not $version.StartsWith('v')){throw 'Tag invalida.'};$version=$version.Substring(1)
    if((Get-FrontendVersionParts $version).preview){throw 'Previa recusada.'}
    $assets=@($Release.assets|Where-Object {$_.name -ceq 'update.json'})
    if($assets.Count -ne 1){throw 'Release sem manifesto de atualizacao assinado.'}
    Assert-FrontendAssetUrl $assets[0].browser_download_url $version 'update.json'
    [pscustomobject]@{version=$version;manifestUrl=$assets[0].browser_download_url}
}
