param([switch]$Initialize,[string]$SetupPath,[string]$Version,[string]$NotesPath,[string]$OutputDirectory,[switch]$TestMode,[string]$TestPrivateKeyPath,[string]$TestPublicKeyPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security
. (Join-Path $PSScriptRoot '..\src\FrontendUpdate.ps1')
$privateFolder=Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'work\retrostation-publisher-private'
$privatePath=Join-Path $privateFolder 'signing-key.dpapi'
$publicPath=Join-Path $PSScriptRoot '..\src\UpdatePublicKey.xml'
if($TestMode){
    if($Initialize -or -not $TestPrivateKeyPath -or -not $TestPublicKeyPath){throw 'Teste requer par de chaves isolado e nao permite Initialize.'}
    if([IO.Path]::GetFullPath($TestPublicKeyPath) -eq [IO.Path]::GetFullPath($publicPath)){throw 'Teste nao pode usar a chave publica de producao.'}
    if([IO.Path]::GetFullPath($TestPrivateKeyPath) -eq [IO.Path]::GetFullPath($privatePath)){throw 'Teste nao pode usar a chave privada de producao.'}
    $publicPath=$TestPublicKeyPath
}elseif($TestPrivateKeyPath -or $TestPublicKeyPath){throw 'Chaves de teste exigem TestMode.'}
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider 3072
$rsa.PersistKeyInCsp=$false
$secret=$null
try{
    if($Initialize){
        if(Test-Path -LiteralPath $privatePath){
            $secret=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($privatePath),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
            $rsa.FromXmlString([Text.Encoding]::UTF8.GetString($secret))
            if(-not(Test-Path -LiteralPath $publicPath) -or [IO.File]::ReadAllText($publicPath).Trim() -cne $rsa.ToXmlString($false)){throw 'Chave publica ausente ou diferente. Nao substitua a chave de confianca sem revisar as instalacoes existentes.'}
            Write-Output 'Chave existente preservada.';exit 0
        }
        if(Test-Path -LiteralPath $publicPath){throw 'Chave publica ja existe, mas a privada nao foi encontrada. Inicializacao bloqueada para evitar perder a confianca existente.'}
        New-Item -ItemType Directory -Force -Path $privateFolder|Out-Null
        $secret=[Text.Encoding]::UTF8.GetBytes($rsa.ToXmlString($true))
        $protected=[Security.Cryptography.ProtectedData]::Protect($secret,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes($privatePath,$protected)
        [IO.File]::WriteAllText($publicPath,$rsa.ToXmlString($false),[Text.UTF8Encoding]::new($false))
        Write-Output 'Chave criada. Privada protegida pelo Windows para este usuario, fora do projeto. Nao publique signing-key.dpapi.';exit 0
    }
    if((Get-FrontendVersionParts $Version).preview){throw 'Use somente versao estavel x.y.z.'}
    if(-not $OutputDirectory -or -not $NotesPath -or -not $SetupPath){throw 'Informe SetupPath, Version, NotesPath e OutputDirectory.'}
    $setup=Get-Item -LiteralPath $SetupPath
    if($setup.Name -cne ('TarginoRetroStation-'+$Version+'-Setup.exe')){throw 'Nome do instalador difere da versao.'}
    $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($setup.FullName)
    if($info.ProductVersion -cne $Version){throw 'Versao interna do instalador difere da release. Nao renomeie uma previa para estavel.'}
    $notes=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $NotesPath))
    if($notes.Length -gt 8000){throw 'Notas excedem limite.'}
    if($TestMode){$secret=[IO.File]::ReadAllBytes($TestPrivateKeyPath)}else{$secret=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($privatePath),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)}
    $rsa.FromXmlString([Text.Encoding]::UTF8.GetString($secret))
    if([IO.File]::ReadAllText($publicPath).Trim() -cne $rsa.ToXmlString($false)){throw 'Chave de publicacao difere da confianca do launcher.'}
    New-Item -ItemType Directory -Force -Path $OutputDirectory|Out-Null
    $manifest=@{schemaVersion=1;product='TarginoRetroStation.Hydra';channel='stable';version=$Version;fileName=$setup.Name;size=$setup.Length;sha256=(Get-FileHash -LiteralPath $setup.FullName -Algorithm SHA256).Hash;url=('https://github.com/timtompel/TarginoRetroStation/releases/download/v'+$Version+'/'+$setup.Name);notes=$notes}
    $bytes=[Text.Encoding]::UTF8.GetBytes(($manifest|ConvertTo-Json -Depth 5 -Compress))
    $envelope=@{algorithm='RSA-SHA256';payload=[Convert]::ToBase64String($bytes);signature=[Convert]::ToBase64String($rsa.SignData($bytes,'SHA256'))}
    $output=Join-Path $OutputDirectory 'update.json'
    if(Test-Path -LiteralPath $output){throw 'Manifesto ja existe. Use uma pasta nova para cada release.'}
    [IO.File]::WriteAllText($output,($envelope|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $m=Read-FrontendSignedManifest $output $publicPath;Assert-FrontendPackage $setup.FullName $m
    Write-Output ('Manifesto assinado: '+$output)
    if($TestMode){Write-Output 'TESTE ISOLADO: NAO PUBLICAR. Assinatura incompativel com instalacoes reais.'}else{Write-Output ('Publique manualmente uma release v'+$Version+' (nao rascunho/previa) com update.json e '+$setup.Name+'. Este script nao envia nada ao GitHub ou Telegram.')}
}finally{if($secret){[Array]::Clear($secret,0,$secret.Length)};$rsa.Dispose()}
