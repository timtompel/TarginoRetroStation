$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$setup=Join-Path $project 'dist\TarginoRetroStation-1.5.2-Setup.exe'
$fixture=Join-Path $project ('build\migration-'+[guid]::NewGuid().ToString('N'))
function Make-Old([string]$root){
    $old=Join-Path $root 'TarginoLauncher'
    foreach($dir in @('Dados','Midia','Marca','mp3')){[void][IO.Directory]::CreateDirectory((Join-Path $old $dir))}
    [IO.File]::WriteAllBytes((Join-Path $root 'hydra.exe'),[byte[]]@(77,90,0,0))
    foreach($name in @('Launcher.ps1','HydraLibrary.ps1')){[IO.File]::WriteAllText((Join-Path $old $name),'# fixture')}
    [IO.File]::WriteAllText((Join-Path $old 'Marca\avatar.png'),'personal-image')
    [IO.File]::WriteAllText((Join-Path $old 'Midia\capa.png'),'cover-fixture')
    [IO.File]::WriteAllText((Join-Path $old 'mp3\faixa.mp3'),'music-fixture')
    $prefs=@{MusicFolder=(Join-Path $old 'mp3');Background='TarginoLauncher\Midia\capa.png';External='D:\OutraPasta\TarginoLauncher\nao-alterar.png'}
    [IO.File]::WriteAllText((Join-Path $old 'Dados\preferencias.json'),($prefs|ConvertTo-Json))
    return $old
}
$old=Make-Old $fixture
[IO.File]::WriteAllText((Join-Path $fixture 'Abrir-TarginoLauncher.cmd'),'start powershell -File TarginoLauncher\Launcher.ps1')
$mediaHash=(Get-FileHash -LiteralPath (Join-Path $old 'Midia\capa.png')).Hash
$p=Start-Process -FilePath $setup -ArgumentList ('--test-migrate "'+$fixture+'"') -WindowStyle Hidden -PassThru -Wait
if($p.ExitCode -ne 0){throw 'Instalador falhou'}
$current=Join-Path $fixture 'TarginoRetroStation'
if(Test-Path -LiteralPath $old){throw 'Pasta antiga duplicada'}
if(Test-Path -LiteralPath (Join-Path $fixture 'Abrir-TarginoLauncher.cmd')){throw 'Comando antigo nao retirado'}
if(-not(Get-ChildItem -LiteralPath (Join-Path $current 'Backups\Migracao-1.4.2') -Recurse -Filter 'Abrir-TarginoLauncher.cmd')){throw 'Backup do comando ausente'}
if((Get-FileHash -LiteralPath (Join-Path $current 'Midia\capa.png')).Hash -ne $mediaHash){throw 'Midia modificada'}
if([IO.File]::ReadAllText((Join-Path $current 'Marca\avatar.png')) -cne 'personal-image'){throw 'Avatar pessoal substituido'}
$prefs=Get-Content -LiteralPath (Join-Path $current 'Dados\preferencias.json') -Raw|ConvertFrom-Json
if($prefs.MusicFolder -cne (Join-Path $current 'mp3') -or $prefs.Background -cne 'TarginoRetroStation\Midia\capa.png'){throw 'Caminhos nao reancorados'}
if($prefs.External -cne 'D:\OutraPasta\TarginoLauncher\nao-alterar.png'){throw 'Caminho externo alterado'}
Write-Output 'OLD_ONLY_DIRECTORY_REUSED_MEDIA_MUSIC_CUSTOM_AVATAR_AND_EXTERNAL_PATHS_OK'
$asm=[Reflection.Assembly]::LoadFile($setup)
$rollbackRoot=Join-Path $fixture 'Rollback';$rollbackOld=Make-Old $rollbackRoot
$original=[IO.File]::ReadAllText((Join-Path $rollbackOld 'Dados\preferencias.json'))
$migration=New-Object LegacyMigration -ArgumentList @([string]$rollbackRoot,$true)
$migration.Begin();$migration.MergeAndReanchor();$migration.RollbackChanges();$migration.UndoRename()
if([IO.File]::ReadAllText((Join-Path $rollbackOld 'Dados\preferencias.json')) -cne $original){throw 'Rollback perdeu configuracao'}
Write-Output 'MIGRATION_REANCHOR_AND_RENAME_ROLLBACK_OK'
$refuseRoot=Join-Path $fixture 'Refuse';[void][IO.Directory]::CreateDirectory((Join-Path $refuseRoot 'TarginoLauncher'))
$failed=$false;try{$m=New-Object LegacyMigration -ArgumentList @([string]$refuseRoot,$true)}catch{$failed=$true}
if(-not $failed){throw 'Instalacao nao Hydra aceita'}
Write-Output 'UNRELATED_LAUNCHER_MIGRATION_REFUSED_OK'
