# System navigation and persistent artwork integration for TarginoRetroStation.
$metadataModule=Join-Path $PSScriptRoot 'HydraMetadata.ps1'
if([IO.File]::Exists($metadataModule)){. $metadataModule}
$liveModule=Join-Path $PSScriptRoot 'TarginoLive.ps1'
if([IO.File]::Exists($liveModule) -and $DataDir -and (Get-Command ReadJson -ErrorAction SilentlyContinue)){. $liveModule}
$script:HydraHome=$true
$script:HydraNavigationEnabled=$true
$script:HydraSystem=''
$script:HydraLastSelection=@{}
$script:HydraSystemCards=@()
$script:HydraArtItems=@()
$script:HydraArtStatus=''
$script:HydraArtworkProcess=$null
$script:HydraMediaStamp=0
$script:HydraRepositories=@{
 '3do'='The 3DO Company - 3DO';'arcade'='MAME';'atari2600'='Atari - 2600';'dreamcast'='Sega - Dreamcast'
 'gba'='Nintendo - Game Boy Advance';'gameboy'='Nintendo - Game Boy';'gameboycolor'='Nintendo - Game Boy Color'
 'gamecube'='Nintendo - GameCube';'gamegear'='Sega - Game Gear';'genesis'='Sega - Mega Drive - Genesis'
 'sms'='Sega - Master System - Mark III';'megacd'='Sega - Mega-CD - Sega CD';'n64'='Nintendo - Nintendo 64'
 'nes'='Nintendo - Nintendo Entertainment System';'neogeo'='SNK - Neo Geo';'ps2'='Sony - PlayStation 2'
 'psx'='Sony - PlayStation';'snes'='Nintendo - Super Nintendo Entertainment System';'saturn'='Sega - Saturn'
 'pce'='NEC - PC Engine - TurboGrafx 16'
}
function HydraMediaHash([string]$value){
    $hash=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($value)))).Replace('-','').ToLowerInvariant().Substring(0,24) }
    finally {$hash.Dispose()}
}
function HydraDisplayTitle([string]$name){
    # Presentation only: never rename ROMs or rebuild launch arguments.
    $title=$name -replace '_',' '
    $title=$title -creplace '(?<=[a-z])(?=[A-Z])',' '
    $title=$title -replace '(?i)\s*\((?:USA|Europe|Japan|World|Brazil|En|Fr|De|Es|It|Pt)(?:[, +/-]+(?:USA|Europe|Japan|World|Brazil|En|Fr|De|Es|It|Pt))*\)',''
    $title=$title -replace '(?i)\s*\[(?:!|b\d*|o\d*|h\d*|a\d*)\]',''
    $title=($title -replace '\s+',' ').Trim()
    if($title -cmatch '^[^a-z]+$' -and $title -match '[A-Z]'){
        $title=[Globalization.CultureInfo]::GetCultureInfo('en-US').TextInfo.ToTitleCase($title.ToLowerInvariant())
        $title=[regex]::Replace($title,'\b(?:Ii|Iii|Iv|Vi|Vii|Viii|Ix|Xi|Xii|Xiii|Rpg|Usa|Snes|Nes|Dmx)\b',{param($m) $m.Value.ToUpperInvariant()})
    }
    if(-not $title){return $name};return $title
}
function HydraSystemLabel([string]$folder){
    if($script:HydraSystemLookup -and $script:HydraSystemLookup.ContainsKey($folder)){return $script:HydraSystemLookup[$folder].Name}
    return $folder
}
function HydraInitializeLibrary {
    $script:HydraSystemCards=@();$script:HydraArtItems=@();$script:HydraArtGames=@()
    $titleIndex=$null
    if($DataDir -and (Get-Command ReadJson -ErrorAction SilentlyContinue)){$titleIndex=ReadJson (Join-Path $DataDir 'hydra-midia-indice.json') $false}
    foreach($manifest in $HydraManifests){
        $folder=Split-Path ($manifest.directories.games.Replace('/','\')) -Leaf
        $systemGames=@($script:Games | Where-Object {$_.Version -eq $folder})
        if(-not $systemGames.Count){continue}
        $color=switch($manifest.id){'snes'{'#AB85FF'}'genesis'{'#3289FF'}'sms'{'#EF584C'}'gamegear'{'#52B6FF'}'n64'{'#4DC98B'}default{'#49C4E5'}}
        $systemName=switch($manifest.id){'ps2'{'PlayStation 2'}'psx'{'PlayStation'}'snes'{'Super Nintendo'}'nes'{'Nintendo Entertainment System'}'n64'{'Nintendo 64'}'gba'{'Game Boy Advance'}'gameboy'{'Game Boy'}'gameboycolor'{'Game Boy Color'}'gamegear'{'Game Gear'}'sms'{'Master System'}'neogeo'{'Neo Geo'}'pce'{'PC Engine'}'megacd'{'Mega-CD / Sega CD'}'3do'{'3DO'}default{HydraDisplayTitle $manifest.name}}
        $path='TarginoRetroStation\Midia\Sistemas\'+$manifest.id+'.png'
        $script:HydraSystemCards += [pscustomobject]@{
            Id=('system-'+$manifest.id);Name=$systemName;Exe='hydra.exe';Args='';Cover=$path;Shot='';Version=($systemGames.Count.ToString()+' jogos')
            Link='';Desc=("$($manifest.name)`n$($systemGames.Count) jogos disponiveis`nCore: $($manifest.library)`n`nPressione A / Enter para abrir este sistema.")
            ImgName='';Archive='';Added='';HydraKind='system';HydraSystem=$folder;HydraSystemId=$manifest.id
        }
        $script:HydraArtItems += [pscustomobject]@{Key=('system:'+$manifest.id);Kind='system';SystemId=$manifest.id;SystemName=$manifest.name;Name=$manifest.name;Count=$systemGames.Count;Color=$color;Path=$path;Repository=$script:HydraRepositories[$manifest.id]}
        foreach($game in $systemGames){
            if(-not $game.PSObject.Properties['HydraRawName']){$game | Add-Member NoteProperty HydraRawName $game.Name}
            $game.Name=HydraDisplayTitle $game.HydraRawName
            # Recover spacing from already cached cover names only on exact
            # normalized equality; never guess a different title or variant.
            $entry=if($titleIndex){$titleIndex.PSObject.Properties['game:'+$game.Id]}else{$null}
            if($entry -and $entry.Value.Source -match '/Named_Boxarts/([^/?]+)'){
                $cachedTitle=HydraDisplayTitle ([IO.Path]::GetFileNameWithoutExtension([Uri]::UnescapeDataString($Matches[1])))
                $plain=$game.Name.ToLowerInvariant() -replace '[^\p{L}\p{N}]',''
                $cachedPlain=$cachedTitle.ToLowerInvariant() -replace '[^\p{L}\p{N}]',''
                if($plain -eq $cachedPlain){$game.Name=$cachedTitle}
            }
            $artPath='TarginoRetroStation\Midia\Capas\'+(HydraMediaHash $game.Id)+'.png'
            $game | Add-Member NoteProperty HydraArt $artPath -Force
            $game | Add-Member NoteProperty HydraSystemId $manifest.id -Force
            $script:HydraArtGames += [pscustomobject]@{Key=('game:'+$game.Id);Kind='game';SystemId=$manifest.id;SystemName=$systemName;Name=$game.HydraRawName;Color=$color;Path=$artPath;Repository=$script:HydraRepositories[$manifest.id]}
        }
    }
    $script:HydraSystemCards=@($script:HydraSystemCards | Sort-Object Name)
    $script:HydraSystemLookup=@{}
    foreach($card in $script:HydraSystemCards){$script:HydraSystemLookup[$card.HydraSystem]=$card}
    $script:HydraArtAll=@($script:HydraArtItems)+@($script:HydraArtGames)
}
function HydraGetCover($game){
    if($game.HydraKind -eq 'system'){return (Full $game.Cover)}
    # A manually assigned cover takes precedence over automatic media.
    if($game.Cover){$manual=Full $game.Cover;if([IO.File]::Exists($manual)){return $manual}}
    if($game.HydraArt){$path=Full $game.HydraArt;if([IO.File]::Exists($path)){return $path}}
    return ''
}
function HydraRememberSelection {
    if($script:Cur){$key=if($script:HydraHome){'home'}else{$script:HydraSystem};$script:HydraLastSelection[$key]=$script:Cur.Id}
}
function HydraOpenSystem([string]$folder){
    HydraRememberSelection
    $script:HydraSystem=$folder;$script:HydraHome=$false
    $script:SelIds.Clear();$script:Cur=$null;$script:CurIdx=-1;$script:Anchor=-1
    $script:Filter='all';$q.Clear();$searchTm.Stop();$vsb.Value=0
    Populate
    if($script:BigPictureEnabled){$script:BackgroundPic.Invalidate()}
    $saved=$script:HydraLastSelection[$folder];$idx=[Array]::IndexOf([string[]]$script:ViewIds,[string]$saved)
    if($idx -lt 0){$idx=0};if($script:View.Count){SelectIdx $idx 'single'}
    [void]$grid.Focus()
}
function HydraShowSystems {
    HydraRememberSelection
    $script:HydraHome=$true;$script:HydraSystem=''
    $script:SelIds.Clear();$script:Cur=$null;$script:CurIdx=-1;$script:Anchor=-1
    $script:Filter='all';$q.Clear();$searchTm.Stop();$vsb.Value=0
    Populate
    if($script:BigPictureEnabled){$script:BackgroundPic.Invalidate()}
    $saved=$script:HydraLastSelection['home'];$idx=[Array]::IndexOf([string[]]$script:ViewIds,[string]$saved)
    if($idx -lt 0){$idx=0};if($script:View.Count){SelectIdx $idx 'single'}
    [void]$grid.Focus()
}
function HydraScopedIndex {
    if(-not $script:HydraSystem){return $script:Ix}
    if(-not $script:HydraScopeIx -or -not [object]::ReferenceEquals($script:HydraScopeIx.Source,$script:Ix.Games) -or $script:HydraScopeIx.System -ne $script:HydraSystem){
        $positions=New-Object Collections.Generic.List[int]
        for($i=0;$i -lt $script:Ix.Games.Length;$i++){if($script:Ix.Games[$i].Version -eq $script:HydraSystem){$positions.Add($i)}}
        $script:HydraScopeIx=@{Source=$script:Ix.Games;System=$script:HydraSystem;Games=[object[]]@($positions | ForEach-Object {$script:Ix.Games[$_]});Ids=[string[]]@($positions | ForEach-Object {$script:Ix.Ids[$_]});Names=[string[]]@($positions | ForEach-Object {$script:Ix.Names[$_]});Added=[long[]]@($positions | ForEach-Object {$script:Ix.Added[$_]})}
    }
    return $script:HydraScopeIx
}
function HydraAddSystemMenu {
    [void]$fm.Items.Add('Verificar atualizacoes do RetroStation...', $null, {Start-RetroStationUpdate})
    [void]$fm.Items.Add('Manual do RetroStation...', $null, {Start-Process (Join-Path $Arq 'Manual.html')})
    if(Get-Command ShowHydraMetadataSettings -ErrorAction SilentlyContinue){[void]$fm.Items.Add('Fontes de dados e cache...', $null, {ShowHydraMetadataSettings})}
    [void]$fm.Items.Add('Personalizar launcher...', $null, {ShowTarginoPreferences})
    [void]$fm.Items.Add('Escolher pasta de ROMs...', $null, {HydraChooseRoms})
    [void]$fm.Items.Add('Atualizar biblioteca', $null, {HydraRestartFrontend})
    [void]$fm.Items.Add('← Menu de sistemas', $null, {HydraShowSystems})
    [void]$fm.Items.Add('-')
    foreach($card in $script:HydraSystemCards){
        $mi=$fm.Items.Add(($card.Name+'  ('+$card.Version+')'),$null,{param($sender,$eventArgs) HydraOpenSystem $sender.Tag})
        $mi.Tag=$card.HydraSystem;$mi.Checked=(-not $script:HydraHome -and $script:HydraSystem -eq $card.HydraSystem)
    }
    [void]$fm.Items.Add('-')
    [void]$fm.Items.Add('Tentar novamente artes pendentes', $null, {HydraRetryArtwork})
    [void]$fm.Items.Add('-')
}
function HydraRestartFrontend {
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$script:SelfPath+'"'
    $psi.WorkingDirectory=$Root;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    [void][Diagnostics.Process]::Start($psi)
    $form.Close()
}
function HydraChooseRoms {
    $dialog=New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description='Escolha a pasta roms que contem as subpastas de cada sistema.'
    $dialog.SelectedPath=$HydraRoms
    try {
        if($dialog.ShowDialog($form) -ne 'OK'){return}
        if(WriteJson (Join-Path $DataDir 'hydra-biblioteca.json') @{RomsPath=$dialog.SelectedPath} 3){HydraRestartFrontend}
    } finally {$dialog.Dispose()}
}
function HydraArtworkSummary([int]$saved,[int]$failed,[int]$notFound){
    if($failed -gt 0 -or $notFound -gt 0){return "Artes: $saved salvas · $failed falhas · $notFound sem correspondência"}
    return "Artes salvas: $saved · cache local"
}
function HydraArtworkRetryDue($entry){
    if(-not $entry -or $entry.Status -ne 'error'){return $false}
    if($entry.TransportVersion -ne 2){return $true}
    $checked=[datetime]::MinValue
    return (-not [datetime]::TryParse([string]$entry.Checked,[ref]$checked) -or ([datetime]::UtcNow-$checked.ToUniversalTime()).TotalMinutes -ge 30)
}
function HydraStartArtwork {
    if($script:HydraArtworkProcess -and -not $script:HydraArtworkProcess.HasExited){return}
    $items=@($script:HydraArtAll | Where-Object {$_})
    $indexPath=Join-Path $DataDir 'hydra-midia-indice.json';$known=ReadJson $indexPath $false
    $complete=$true
    $savedCount=0;$failedCount=0;$notFoundCount=0
    foreach($item in $items){
        $entry=if($known -and $known.PSObject.Properties[$item.Key]){$known.($item.Key)}else{$null}
        if(-not $entry -or $entry.StyleVersion -ne 2 -or -not [IO.File]::Exists((Full $item.Path)) -or (HydraArtworkRetryDue $entry)){$complete=$false;break}
        switch($entry.Status){'downloaded'{$savedCount++}'error'{$failedCount++}default{$notFoundCount++}}
    }
    if($complete){$script:HydraArtStatus=HydraArtworkSummary $savedCount $failedCount $notFoundCount;return}
    $worker=Join-Path $Arq 'HydraArtwork.ps1'
    if(-not [IO.File]::Exists($worker)){Log 'AVISO' 'HydraArtwork.ps1 ausente';return}
    [void](WriteJson (Join-Path $DataDir 'hydra-midia-pedidos.json') @{RootKey=(HydraMediaHash $Arq);Systems=$script:HydraArtItems;Games=$script:HydraArtGames} 6)
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $PSHOME 'powershell.exe'
    if(-not [IO.File]::Exists($psi.FileName)){$psi.FileName='powershell.exe'}
    $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$worker+'" -Root "'+$Root+'"'
    $psi.WorkingDirectory=$Root;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $script:HydraArtworkProcess=[Diagnostics.Process]::Start($psi)
    $script:HydraArtStatus='Preparando capas e logos...'
    Log 'INFO' 'Processo de artes iniciado em segundo plano'
}
function HydraRetryArtwork {
    if($script:HydraArtworkProcess -and -not $script:HydraArtworkProcess.HasExited){return}
    $path=Join-Path $DataDir 'hydra-midia-indice.json';$saved=ReadJson $path $false;$keep=@{}
    if($saved){foreach($property in $saved.PSObject.Properties){if($property.Value.Status -eq 'downloaded'){$keep[$property.Name]=$property.Value}}}
    [void](WriteJson $path $keep 6)
    HydraStartArtwork
}
function HydraArtworkTick {
    $progress=Join-Path $DataDir 'hydra-midia-progresso.json'
    if(-not [IO.File]::Exists($progress)){return}
    $stamp=[IO.File]::GetLastWriteTimeUtc($progress).Ticks
    if($stamp -eq $script:HydraMediaStamp){return}
    $script:HydraMediaStamp=$stamp
    try {
        $state=Get-Content -LiteralPath $progress -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $script:HydraArtStatus=if($state.Phase -eq 'Concluido'){HydraArtworkSummary ([int]$state.Saved) ([int]$state.Failed) ([int]$state.NotFound)}else{"Artes: $($state.Done)/$($state.Total) · $($state.Phase)"}
        if($state.Phase -eq 'Concluido' -and [int]$state.Failed -gt 0){Log 'AVISO' "Artes concluidas com $($state.Failed) falha(s); detalhes em Dados\hydra-midia-indice.json. Use Tentar novamente artes pendentes."}
        $script:CoverFail.Clear()
        $grid.Invalidate()
    } catch { }
}
HydraInitializeLibrary
