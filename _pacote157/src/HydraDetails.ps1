# Lazy, persistent game metadata. This module never changes the ROM/catalogue.
$script:HydraDetailsProcesses=@{}
function HydraDetailsCachePath($game){Join-Path $DataDir ('Detalhes\'+(HydraMediaHash ($game.HydraSystemId+':'+$game.Id))+'.json')}
function HydraDetailsStart($game,[bool]$refresh=$false){
    $path=HydraDetailsCachePath $game
    if($script:HydraDetailsProcesses.ContainsKey($path) -and -not $script:HydraDetailsProcesses[$path].HasExited){return $script:HydraDetailsProcesses[$path]}
    $saved=ReadJson $path $false
    $repair=$false
    if($saved -and $saved.Snapshot -and $saved.SnapshotSource){$repair=(-not [IO.File]::Exists((Join-Path $Arq $saved.Snapshot)))}
    if($repair -and [IO.File]::Exists(($path+'.snapshot.failed')) -and ([datetime]::UtcNow-[IO.File]::GetLastWriteTimeUtc(($path+'.snapshot.failed'))).TotalMinutes -lt 30){$repair=$false}
    if($saved -and $saved.Status -ne 'loading' -and -not $refresh -and -not $repair){return $null}
    $folder=Split-Path $path;[void][IO.Directory]::CreateDirectory($folder)
    $requestFile=$path+'.request.json'
    $request=@{Addon=$Arq;Key=[IO.Path]::GetFileNameWithoutExtension($path);Id=$game.Id;Name=$game.Name;SystemId=$game.HydraSystemId;Repository=$script:HydraRepositories[$game.HydraSystemId]}
    if(-not (WriteJson $requestFile $request 3)){return $null}
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $PSHOME 'powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.WorkingDirectory=$Arq
    $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $Arq 'HydraDetailsWorker.ps1')+'" -RequestFile "'+$requestFile+'"'
    if($refresh -or ($saved -and $saved.Status -eq 'loading')){$psi.Arguments+=' -Force'}
    $process=[Diagnostics.Process]::Start($psi);$script:HydraDetailsProcesses[$path]=$process
    return $process
}
function HydraDetailsUpdate($dialog){
    $ui=$dialog.Tag;$game=$ui.Game
    $stamp=if([IO.File]::Exists($ui.Cache)){[IO.File]::GetLastWriteTimeUtc($ui.Cache).Ticks}else{0}
    $busy=($ui.Process -and -not $ui.Process.HasExited)
    if($stamp -eq $ui.Stamp -and $busy -eq $ui.Busy){return}
    $ui.Stamp=$stamp;$ui.Busy=$busy
    $data=ReadJson $ui.Cache $false
    $lines=New-Object Collections.Generic.List[string]
    $lines.Add('Sistema: '+$game.Version)
    $labels=[ordered]@{releaseyear='Ano';genre='Gênero';developer='Desenvolvedora';publisher='Publicadora';maxusers='Jogadores'}
    foreach($field in $labels.Keys){
        $value=if($data -and $data.Fields){$data.Fields.$field}else{''}
        if($field -eq 'genre' -and $value){$value=switch($value){'Platform'{'Plataforma'}'Action'{'Ação'}'Adventure'{'Aventura'}'Sports'{'Esportes'}'Racing'{'Corrida'}'Puzzle'{'Quebra-cabeça'}'Fighting'{'Luta'}'Shooter'{'Tiro'}default{$value}}}
        if($value){$lines.Add($labels[$field]+': '+$value)}
    }
    if($data -and $data.Overview){$lines.Add('');$lines.Add('Sobre o jogo:');$lines.Add([string]$data.Overview)}
    if($data -and $data.MatchedName){
        $lines.Add('');$lines.Add('Registro encontrado: '+$data.MatchedName)
        if($game.Name -match '\[|PTBR|FastROM|SA1|tradu'){$lines.Add('Os dados e a captura referem-se ao jogo original; hacks e traduções podem apresentar diferenças.')}
    }
    if(-not $data -or -not $data.Fields -or -not @($data.Fields.PSObject.Properties).Count){$lines.Add('');$lines.Add($(if($busy){'Buscando informações do jogo…'}else{'Informações adicionais não encontradas com segurança.'}))}
    $ui.Facts.Text=$lines -join "`r`n"
    $measure=[Windows.Forms.TextRenderer]::MeasureText($ui.Facts.Text,$ui.Facts.Font,(New-Object Drawing.Size(([Math]::Max(100,$ui.Facts.Parent.ClientSize.Width-28)),32767)),([Windows.Forms.TextFormatFlags]'WordBreak,NoPrefix'))
    $ui.Facts.Height=[Math]::Max(230,$measure.Height+28)
    if($ui.Source){$ui.Source.Text=if($data -and $data.TheGamesDBId){'Fontes: Libretro e TheGamesDB (dados complementares)'}else{'Fontes: Libretro Database e Libretro Thumbnails'}}
    $snapshot=''
    if($game.Shot){$manual=Full $game.Shot;if([IO.File]::Exists($manual)){$snapshot=$manual}}
    if(-not $snapshot -and $data -and $data.Snapshot){
        $candidate=[IO.Path]::GetFullPath((Join-Path $Arq $data.Snapshot))
        if($candidate.StartsWith(($Arq.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase) -and [IO.File]::Exists($candidate)){$snapshot=$candidate}
    }
    if($snapshot -ne $ui.ImagePath){
        $old=$ui.Picture.Image;$ui.Picture.Image=$null;if($old){$old.Dispose()}
        if($snapshot){try{$source=[Drawing.Image]::FromFile($snapshot);try{$ui.Picture.Image=New-Object Drawing.Bitmap($source)}finally{$source.Dispose()}}catch{LogEx 'AVISO' 'Captura de detalhes inválida' $_}}
        $ui.ImagePath=$snapshot
    }
    $ui.ImageHint.Visible=(-not $ui.Picture.Image)
    $ui.ImageHint.Text=if($busy){'Carregando captura real de gameplay…'}else{'Captura de gameplay não encontrada para este jogo.'}
    $ui.Status.Text=if($busy){'Buscando em segundo plano… Você já pode jogar ou fechar esta janela.'}elseif(-not $data -or $data.Status -eq 'error'){'Consulta indisponível. Use Atualizar dados para tentar novamente.'}else{'Dados salvos localmente · Sem nova consulta ao reabrir'}
    $ui.Refresh.Enabled=(-not $busy)
}
function ShowHydraDetails($game){
    $window=New-Object Windows.Forms.Form -Property @{Text=('Detalhes — '+$game.Name);StartPosition='CenterParent';ClientSize='900,760';MinimumSize='660,550';BackColor=[Drawing.Color]::FromArgb(13,21,33);ForeColor=[Drawing.Color]::White;KeyPreview=$true;Font=(New-Object Drawing.Font('Segoe UI',11))}
    $title=New-Object Windows.Forms.Label -Property @{Text=$game.Name;Dock='Top';Height=65;Padding='20,10,16,0';Font=(New-Object Drawing.Font('Segoe UI',20,[Drawing.FontStyle]::Bold));AutoEllipsis=$true}
    $actions=New-Object Windows.Forms.FlowLayoutPanel -Property @{Dock='Bottom';Height=56;Padding='16,10,0,0';BackColor=[Drawing.Color]::FromArgb(9,16,27)}
    $play=New-Object Windows.Forms.Button -Property @{Text='Jogar';Width=135;Height=34;DialogResult='OK';BackColor=[Drawing.Color]::FromArgb(0,124,190);FlatStyle='Flat'}
    $favorite=New-Object Windows.Forms.Button -Property @{Text=$(if($U.Fav -contains $game.Id){'★ Favorito'}else{'☆ Favoritar'});Width=135;Height=34;FlatStyle='Flat'}
    $refresh=New-Object Windows.Forms.Button -Property @{Text='Atualizar dados';Width=155;Height=34;FlatStyle='Flat'}
    $close=New-Object Windows.Forms.Button -Property @{Text='Fechar';Width=110;Height=34;DialogResult='Cancel';FlatStyle='Flat'}
    $actions.Controls.AddRange(@($play,$favorite,$refresh,$close))
    $status=New-Object Windows.Forms.Label -Property @{Dock='Bottom';Height=28;Padding='18,0,0,0';ForeColor=[Drawing.Color]::LightSkyBlue;AutoEllipsis=$true}
    $source=New-Object Windows.Forms.LinkLabel -Property @{Dock='Bottom';Height=27;Padding='18,0,0,0';Text='Fontes: Libretro Database e Libretro Thumbnails (capturas de gameplay)';LinkColor=[Drawing.Color]::LightSkyBlue}
    $source.Add_LinkClicked({param($sender,$eventArgs) $state=$sender.FindForm().Tag;$data=ReadJson $state.Cache $false;if($data -and $data.TheGamesDBId){[void][Diagnostics.Process]::Start('https://thegamesdb.net/game.php?id='+[int]$data.TheGamesDBId)}else{[void][Diagnostics.Process]::Start('https://github.com/libretro-thumbnails/libretro-thumbnails')}})
    $body=New-Object Windows.Forms.Panel -Property @{Dock='Fill';Padding='18,0,18,8'}
    $picture=New-Object Windows.Forms.PictureBox -Property @{Dock='Top';Height=290;SizeMode='Zoom';BackColor=[Drawing.Color]::FromArgb(5,10,17);TabStop=$false}
    $hint=New-Object Windows.Forms.Label -Property @{Dock='Fill';TextAlign='MiddleCenter';ForeColor=[Drawing.Color]::Silver}
    $picture.Controls.Add($hint)
    $factsPanel=New-Object Windows.Forms.Panel -Property @{Dock='Fill';AutoScroll=$true;Padding='0,12,0,0'}
    $facts=New-Object Windows.Forms.Label -Property @{Dock='Top';Height=280;BackColor=$window.BackColor;ForeColor=[Drawing.Color]::White;Font=(New-Object Drawing.Font('Segoe UI',11))}
    $factsPanel.Controls.Add($facts)
    $body.Controls.AddRange(@($factsPanel,$picture))
    $window.Controls.AddRange(@($body,$source,$status,$actions,$title));$window.AcceptButton=$play;$window.CancelButton=$close
    $window.Tag=@{Game=$game;Cache=(HydraDetailsCachePath $game);Stamp=-1;Busy=$null;Process=$null;Picture=$picture;ImageHint=$hint;ImagePath='';Facts=$facts;Status=$status;Refresh=$refresh;Source=$source}
    $favorite.Add_Click({param($sender,$eventArgs) $state=$sender.FindForm().Tag;ToggleFav $state.Game;$sender.Text=if($U.Fav -contains $state.Game.Id){'★ Favorito'}else{'☆ Favoritar'}})
    $refresh.Add_Click({param($sender,$eventArgs) $win=$sender.FindForm();$win.Tag.Process=HydraDetailsStart $win.Tag.Game $true;$win.Tag.Stamp=-1;HydraDetailsUpdate $win})
    $timer=New-Object Windows.Forms.Timer -Property @{Interval=350}
    $timer.Add_Tick(({try{HydraDetailsUpdate $window}catch{LogEx 'AVISO' 'Falha ao atualizar detalhes do jogo' $_}}.GetNewClosure()))
    $window.Tag.Process=HydraDetailsStart $game
    HydraDetailsUpdate $window;$timer.Start()
    $result='Cancel'
    try{$result=$window.ShowDialog($form)}finally{$timer.Stop();$timer.Dispose();if($picture.Image){$picture.Image.Dispose()};$window.Dispose();[void]$grid.Focus()}
    if($result -eq 'OK'){Launch $game}
}
