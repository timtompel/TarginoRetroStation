<#
 Assina com Authenticode os scripts (.ps1) e executaveis (.exe/.dll) do RetroStation.
 Requer um certificado de assinatura de codigo REAL (emitido por uma autoridade confiavel).
 Certificado autoassinado NAO remove avisos do SmartScreen/antivirus em outros PCs.

 Exemplos:
   # certificado instalado no repositorio do Windows
   .\Assinar-RetroStation.ps1 -Path ..\src, ..\dist\Setup.exe -Thumbprint 0123ABCD...
   # certificado em arquivo .pfx
   .\Assinar-RetroStation.ps1 -Path ..\src -PfxPath C:\cert\codigo.pfx

 IMPORTANTE:
  - Assine ANTES de gerar o hash/manifesto (update.json) do instalador. Qualquer alteracao
    posterior no arquivo invalida a assinatura e o hash.
  - Scripts .ps1 assinados nao podem ser editados depois sem assinar de novo.
  - Guarde a chave privada fora do repositorio (nunca no GitHub).
#>
param(
    [Parameter(Mandatory)][string[]]$Path,
    [string]$Thumbprint,
    [string]$PfxPath,
    [string]$TimestampUrl='http://timestamp.digicert.com'
)
$ErrorActionPreference='Stop'
if($Thumbprint){
    $cert=Get-ChildItem Cert:\CurrentUser\My,Cert:\LocalMachine\My -CodeSigningCert|Where-Object {$_.Thumbprint -ieq $Thumbprint}|Select-Object -First 1
}elseif($PfxPath){
    $password=Read-Host 'Senha do PFX' -AsSecureString
    $cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2($PfxPath,$password)
}else{throw 'Informe -Thumbprint ou -PfxPath.'}
if(-not $cert){throw 'Certificado de assinatura de codigo nao encontrado.'}
if(-not $cert.HasPrivateKey){throw 'O certificado nao possui chave privada.'}
$files=foreach($p in $Path){
    if([IO.Directory]::Exists($p)){Get-ChildItem -LiteralPath $p -Recurse -File|Where-Object {$_.Extension -in '.ps1','.psm1','.exe','.dll'}}
    else{Get-Item -LiteralPath $p}
}
$failed=0
foreach($f in $files){
    $r=Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $cert -HashAlgorithm SHA256 -TimestampServer $TimestampUrl
    if($r.Status -ne 'Valid'){$failed++;Write-Warning ($f.Name+': '+$r.Status+' '+$r.StatusMessage)}else{Write-Host ('Assinado: '+$f.Name)}
}
if($failed){throw "$failed arquivo(s) nao foram assinados."}
