param()
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$version='1.5.4'
$out=Join-Path $project 'dist'
$stage=Join-Path $project ('build\'+[guid]::NewGuid().ToString('N'))
$addon=Join-Path $stage 'TarginoRetroStation'
[void][IO.Directory]::CreateDirectory($addon);[void][IO.Directory]::CreateDirectory($out)
$csc=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
Copy-Item -Path (Join-Path $project 'src\*') -Destination $addon
[void][IO.Directory]::CreateDirectory((Join-Path $addon 'Dados'))
[void][IO.Directory]::CreateDirectory((Join-Path $addon 'Marca'))
foreach($name in @('avatar.png','banner.png','fundo.jpg')){Copy-Item -LiteralPath (Join-Path $project ('assets\'+$name)) -Destination (Join-Path $addon 'Marca')}
Copy-Item -LiteralPath (Join-Path $project 'assets\Launcher.ico') -Destination $addon
Copy-Item -LiteralPath (Join-Path $project 'assets\layout.template.json') -Destination (Join-Path $addon 'Dados')
Copy-Item -LiteralPath (Join-Path $project 'docs\Manual.html') -Destination $addon
Copy-Item -LiteralPath (Join-Path $project 'README.md') -Destination (Join-Path $addon 'LEIA-ME.txt')
& $csc /nologo /target:library /platform:x64 /optimize+ /r:System.Web.Extensions.dll ('/out:'+(Join-Path $addon 'HydraDirectBridge.dll')) (Join-Path $addon 'HydraDirectBridge.cs')
if($LASTEXITCODE -ne 0){throw 'Falha ao compilar adaptador'}
foreach($file in Get-ChildItem -LiteralPath $addon -Filter '*.ps1'){
    [IO.File]::WriteAllText($file.FullName,[IO.File]::ReadAllText($file.FullName),(New-Object Text.UTF8Encoding($true)))
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors|Out-String)}
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Abrir-TarginoRetroStation.cmd') -Destination $stage
$manifest=@{Product='TarginoRetroStation.Hydra';Version=$version;Files=@()}
foreach($f in Get-ChildItem -LiteralPath $stage -Recurse -File){
    $rel=$f.FullName.Substring($stage.Length+1).Replace('\','/')
    if($rel -match '(?i)(^|/)(hydra\.exe|cores|roms|bios|Saves|Logs|Cache|Backups|fontes-dados\.json|usuario\.json|preferencias\.json|layout\.json)(/|$)'){throw ('Arquivo privado/fora do escopo: '+$rel)}
    $manifest.Files+=@{Path=$rel;Sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash}
}
$manifestPath=Join-Path $stage 'manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 5),[Text.Encoding]::UTF8)
$zip=Join-Path $out ('TarginoRetroStation-'+$version+'-Arquivos.zip')
if(Test-Path -LiteralPath $zip){throw 'Build ja existe. Preserve a release anterior ou altere a versao.'}
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
# manifest.json is installer metadata, not an installed file.
$zipStream=[IO.File]::Create($zip);$archive=New-Object IO.Compression.ZipArchive($zipStream,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($f in Get-ChildItem -LiteralPath $stage -Recurse -File){if($f.FullName -eq $manifestPath){continue};$rel=$f.FullName.Substring($stage.Length+1).Replace('\','/');[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$f.FullName,$rel,[IO.Compression.CompressionLevel]::Optimal)}}finally{$archive.Dispose();$zipStream.Dispose()}
$setup=Join-Path $out ('TarginoRetroStation-'+$version+'-Setup.exe')
& $csc /nologo /target:winexe /platform:x64 /optimize+ ('/out:'+$setup) ('/win32icon:'+(Join-Path $project 'assets\Launcher.ico')) ('/win32manifest:'+(Join-Path $PSScriptRoot 'app.manifest')) /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /r:System.Web.Extensions.dll /r:Microsoft.CSharp.dll ('/resource:'+$zip+',hydra.payload.zip') ('/resource:'+$manifestPath+',hydra.manifest.json') (Join-Path $PSScriptRoot 'Setup.cs') (Join-Path $PSScriptRoot 'LegacyMigration.cs') (Join-Path $PSScriptRoot 'AtomicInstall.cs')
if($LASTEXITCODE -ne 0){throw 'Falha ao compilar instalador'}
$web=Join-Path $out ('TarginoRetroStation-'+$version+'-WebSetup.exe')
& $csc /nologo /target:winexe /platform:x64 /optimize+ ('/out:'+$web) ('/win32icon:'+(Join-Path $project 'assets\Launcher.ico')) ('/win32manifest:'+(Join-Path $PSScriptRoot 'app.manifest')) /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ('/resource:'+(Join-Path $PSScriptRoot 'BootstrapWorker.ps1')+',BootstrapWorker.ps1') ('/resource:'+(Join-Path $addon 'FrontendUpdate.ps1')+',FrontendUpdate.ps1') ('/resource:'+(Join-Path $addon 'Hashing.ps1')+',Hashing.ps1') ('/resource:'+(Join-Path $addon 'UpdateCache.ps1')+',UpdateCache.ps1') ('/resource:'+(Join-Path $addon 'UpdatePublicKey.xml')+',UpdatePublicKey.xml') (Join-Path $PSScriptRoot 'Bootstrapper.cs')
if($LASTEXITCODE -ne 0){throw 'Falha ao compilar instalador web'}
[pscustomobject]@{Installer=$setup;Stage=$stage;Files=$manifest.Files.Count}|ConvertTo-Json
