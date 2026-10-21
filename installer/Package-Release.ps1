$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot;$out=Join-Path $project 'dist'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zipPath=Join-Path $out 'TarginoRetroStation-1.5.2-Fontes.zip'
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew)
$zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
try{
    $list=@((Get-Item (Join-Path $project 'README.md')),(Get-Item (Join-Path $project '.gitignore')))
    $list+=@(Get-ChildItem -LiteralPath (Join-Path $project 'src'),(Join-Path $project 'installer'),(Join-Path $project 'assets'),(Join-Path $project 'tests'),(Join-Path $project 'docs') -Recurse -File)
    foreach($f in $list){
        $rel=$f.FullName.Substring($project.Length+1).Replace('\','/')
        if($rel -match '(?i)(\.dpapi$|signing-key|/Dados/|/Cache/|/Logs/|/roms/|/bios/|/Saves/)'){throw 'Arquivo privado no pacote de fontes'}
        if($f.Extension -in @('.ps1','.json','.xml','.cs','.py')){
            $text=[IO.File]::ReadAllText($f.FullName)
            if($text -match 'TarginoDefaultPasswordHash=''[A-Fa-f0-9]{32,}''|PassHash\s*[:=]\s*"[A-Fa-f0-9]{32,}"'){throw ('Credencial publica proibida: '+$rel)}
        }
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$f.FullName,$rel)
    }
}finally{$zip.Dispose();$stream.Dispose()}
Copy-Item -LiteralPath (Join-Path $project 'docs\Manual.html') -Destination (Join-Path $out 'Manual.html')
foreach($name in @('banner.png','avatar.png')){Copy-Item -LiteralPath (Join-Path $project ('assets\'+$name)) -Destination (Join-Path $out $name)}
$sums=Get-ChildItem -LiteralPath $out -File|Where-Object {$_.Name -ne 'SHA256SUMS.txt'}|ForEach-Object {((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_.Name)}
[IO.File]::WriteAllLines((Join-Path $out 'SHA256SUMS.txt'),$sums,(New-Object Text.UTF8Encoding($false)))
Write-Output 'PACOTES_PUBLICOS_SEM_CREDENCIAL_PADRAO_OK'
