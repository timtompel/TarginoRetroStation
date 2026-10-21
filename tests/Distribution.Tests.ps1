$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$fixture=Join-Path $project ('build\test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$setup=Join-Path $project 'dist\TarginoRetroStation-1.5.3-Setup.exe'
[IO.File]::WriteAllBytes((Join-Path $fixture 'hydra.exe'),[byte[]]@(77,90,0,0))
foreach($dir in @('roms','bios','Saves')){[void][IO.Directory]::CreateDirectory((Join-Path $fixture $dir));[IO.File]::WriteAllText((Join-Path $fixture ($dir+'\preservar.txt')),'fixture-nao-e-jogo')}
$before=@{};Get-ChildItem -LiteralPath $fixture -File -Recurse|ForEach-Object {$before[$_.FullName]=(Get-FileHash -LiteralPath $_.FullName).Hash}
function Install-Fixture([string]$mode){$p=Start-Process -FilePath $setup -ArgumentList ($mode+' "'+$fixture+'"') -WindowStyle Hidden -PassThru -Wait;if($p.ExitCode -ne 0){throw ('Falha instalador '+$p.ExitCode)}}
Install-Fixture '--extract-only'
$addon=Join-Path $fixture 'TarginoRetroStation'
foreach($name in @('Launcher.ps1','RetroStationUpdateUI.ps1','RetroStationUpdateWorker.ps1','UpdatePublicKey.xml','Manual.html','Launcher.ico')){if(-not(Test-Path -LiteralPath (Join-Path $addon $name))){throw ('Ausente '+$name)}}
$user=Join-Path $addon 'Dados\usuario.json';[IO.File]::WriteAllText($user,'{"Fav":["fixture"]}')
Install-Fixture '--extract-only'
if([IO.File]::ReadAllText($user) -cne '{"Fav":["fixture"]}'){throw 'Favoritos sobrescritos'}
if(@(Get-ChildItem -LiteralPath (Join-Path $addon 'Backups\Instalador') -Recurse -File -ErrorAction SilentlyContinue).Count){throw 'Reinstalacao identica criou backup desnecessario'}
$installedSource=Join-Path $addon 'Launcher.ps1';$originalHash=(Get-FileHash -LiteralPath $installedSource).Hash
[IO.File]::AppendAllText($installedSource,"`r`n# OLD-VERSION-FIXTURE`r`n")
Install-Fixture '--extract-only'
if((Get-FileHash -LiteralPath $installedSource).Hash -ne $originalHash){throw 'Arquivo antigo nao foi substituido'}
$backups=@(Get-ChildItem -LiteralPath (Join-Path $addon 'Backups\Instalador') -Recurse -File)
if($backups.Count -ne 1 -or [IO.File]::ReadAllText($backups[0].FullName) -notmatch 'OLD-VERSION-FIXTURE'){throw 'Backup da versao anterior ausente ou duplicado'}
foreach($file in $before.Keys){if((Get-FileHash -LiteralPath $file).Hash -ne $before[$file]){throw ('Arquivo externo modificado '+$file)}}
Write-Output 'CLEAN_INSTALL_REINSTALL_BACKUP_USER_STATE_AND_EXTERNAL_FILES_OK'
# Isolated migration test using installer private entry, no shortcuts/registry.
$old=Join-Path $fixture 'TarginoLauncher';[void][IO.Directory]::CreateDirectory((Join-Path $old 'Dados'));[void][IO.Directory]::CreateDirectory((Join-Path $old 'Midia'))
[IO.File]::WriteAllText((Join-Path $old 'HydraLibrary.ps1'),'# fixture Hydra')
[IO.File]::WriteAllText((Join-Path $old 'Launcher.ps1'),'# fixture launcher')
[IO.File]::WriteAllText((Join-Path $old 'Dados\preferencias.json'),'{"Background":"TarginoLauncher\\Midia\\fundo.png"}')
[IO.File]::WriteAllText((Join-Path $old 'Midia\fundo.png'),'fixture-image')
Install-Fixture '--test-migrate'
$prefs=[IO.File]::ReadAllText((Join-Path $addon 'Dados\preferencias.json'))|ConvertFrom-Json
if($prefs.Background -cne 'TarginoRetroStation\Midia\fundo.png'){throw 'Migracao de caminhos falhou'}
if((Test-Path -LiteralPath $old) -or -not(Test-Path (Join-Path $addon 'Midia\fundo.png'))){throw 'Consolidacao de midia falhou'}
if(-not(Get-ChildItem -LiteralPath (Join-Path $addon 'Backups\Migracao-1.4.2') -Recurse -Filter '*.zip')){throw 'Backup das diferencas ausente'}
Write-Output 'TWO_FOLDERS_CONSOLIDATED_WITHOUT_DUPLICATING_MEDIA_AND_DIFFERENCES_BACKED_UP_OK'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[IO.Compression.ZipFile]::OpenRead((Join-Path $project 'dist\TarginoRetroStation-1.5.3-Arquivos.zip'))
try{foreach($e in $z.Entries){if($e.FullName -match '(?i)(^|/)(bios|roms|Saves|cores|Cache|Logs|hydra\.exe|usuario\.json|fontes-dados\.json|layout\.json)(/|$)'){throw ('Conteudo proibido '+$e.FullName)}}}finally{$z.Dispose()}
Write-Output 'NO_HYDRA_ROMS_BIOS_SAVES_OR_PERSONAL_DATA_IN_PAYLOAD_OK'
# Parse and initialize actual WinForms launcher without starting UI/network/game processes.
$source=[IO.File]::ReadAllText((Join-Path $addon 'Launcher.ps1'))
$assignment='$Arq = $PSScriptRoot.TrimEnd(''\''); $Root = [IO.Path]::GetDirectoryName($Arq).TrimEnd(''\'')'
$source=$source.Replace($assignment,('$Arq = '''+$addon+'''; $Root = '''+$fixture+''''))
$source=$source.Replace('Initialize-RetroStationUpdates','# network disabled only in fixture')
$source=$source.Replace('InitializeTarginoWelcome',"Write-Verbose 'welcome disabled only in fixture'")
$source=$source.Replace('[void]$form.ShowDialog()',@'
if($S.Title -ne 'Targino RetroStation' -or $S.HeaderText -ne 'Targino RetroStation'){throw 'Nome incorreto'}
if($script:TaskId -notlike 'TarginoRetroStation.Launcher.*'){throw 'AppID incorreto'}
if(Get-Command UpdRun -ErrorAction SilentlyContinue){throw 'Atualizador legado ainda presente'}
if($S.PassHash){throw 'Instalacao limpa contem credencial de desenvolvedor'}
if(Unlock){throw 'Area privilegiada sem senha local'}
if(-not (Get-Command Start-RetroStationUpdate -ErrorAction SilentlyContinue)){throw 'Menu update nao conectado'}
if(-not $script:TaskIcon){throw 'Icone ausente'}
InitFilter;CatRefresh;ApplyLayout;Populate
$S.SideItems='all,recent,fav,inst,notinst';$script:Filter='notinst';EnsureFilter
if($script:Filter -ne 'all' -or @((FilterKeys)|Where-Object {$_ -in @('inst','notinst')}).Count){throw 'Filtros legados nao migrados'}
$form.Show();[Windows.Forms.Application]::DoEvents()
$mouseEnter=[Windows.Forms.Control].GetMethod('OnMouseEnter',[Reflection.BindingFlags]'Instance,NonPublic')
for($cycle=0;$cycle -lt 5;$cycle++){
    if($script:BigPictureEnabled){BigPictureToggle}
    $script:BigPictureButton.PerformClick();[Windows.Forms.Application]::DoEvents()
    if(-not $script:BigPictureEnabled){throw 'Big Picture nao ativou'}
    $script:BigPictureButton.PerformClick();[Windows.Forms.Application]::DoEvents()
    [void]$mouseEnter.Invoke($grid,@([EventArgs]::Empty));[Windows.Forms.Application]::DoEvents()
    if(-not $script:BigPictureSidebar -or -not $script:BigPictureRail.Visible){throw 'Menu fechou ao entrar mouse na lista'}
    $script:BigPictureButtons[4].PerformClick();[Windows.Forms.Application]::DoEvents()
    if($script:BigPictureEnabled -or $script:BigPictureSidebar -or $script:BigPictureRail.Visible){throw 'Menu residual no classico'}
    if($top.Visible -ne [bool]($S.ShowSearch -or $S.ShowFilter -or $script:Dev)){throw 'Busca/filtros nao restaurados'}
    BigPictureFocusMenu
    if($script:BigPictureSidebar){throw 'Menu abriu no classico'}
}
'BIG_PICTURE_CLASSIC_TRANSITIONS_AND_MOUSE_FOCUS_REGRESSION_OK'
$form.Dispose()
'RETROSTATION_IDENTITY_ICON_UI_AND_LEGACY_UPDATER_DISABLED_OK'
'@)
. ([scriptblock]::Create($source))
