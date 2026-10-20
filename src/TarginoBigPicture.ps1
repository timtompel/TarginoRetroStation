# Optional Big Picture test mode. No changes to Hydra, cores, ROMs or BIOS.
function BigPictureLayout {
    if(-not $script:BigPictureRail){return}
    $on=[bool]$script:BigPictureEnabled
    $script:BigPictureRail.Visible=($on -and $script:BigPictureSidebar)
    $script:BigPictureButton.Text=if($on){'Menu [F1]'}else{'Big Picture'}
    if($on){
        $railWidth=if($mainP.Width -lt 1100){190}else{230}
        $libP.Padding=New-Object Windows.Forms.Padding(0)
        $libP.Dock='Fill'
        $script:BackgroundPic.Visible=$false
        $script:BigPictureRail.Width=$railWidth
        foreach($button in $script:BigPictureButtons){$button.Width=$railWidth-24}
        $top.Visible=$false
    }else{
        $libP.Dock='Bottom';$script:BackgroundPic.Visible=$true
        $libP.Padding=New-Object Windows.Forms.Padding(0)
        $libP.Height=354
    }
    $script:BackgroundPic.Invalidate();$grid.Invalidate()
}
function BigPictureToggle {
    $script:BigPictureEnabled=-not $script:BigPictureEnabled
    $script:BigPictureSidebar=$false
    [void](WriteJson (Join-Path $DataDir 'bigpicture.json') @{Enabled=$script:BigPictureEnabled} 3)
    ApplyCinema;[void]$grid.Focus()
}
function BigPictureFocusMenu {
    $script:BigPictureSidebar=$true
    BigPictureLayout
    BigPictureHighlight
    [void]$script:BigPictureButtons[$script:BigPictureMenuIndex].Focus()
}
function BigPictureFocusLibrary {
    # Move focus before hiding its current owner. Otherwise WinForms can move
    # focus to another menu button while its panel is being collapsed.
    $script:BigPictureFocusChanging=$true
    try{
        $script:BigPictureSidebar=$false
        [void]$grid.Focus()
        BigPictureLayout
        BigPictureHighlight
        [void]$grid.Focus()
    }finally{$script:BigPictureFocusChanging=$false}
}
function BigPictureHighlight {
    for($i=0;$i -lt $script:BigPictureButtons.Count;$i++){
        $script:BigPictureButtons[$i].BackColor=if($script:BigPictureSidebar -and $i -eq $script:BigPictureMenuIndex){[Drawing.Color]::FromArgb(0,116,190)}else{[Drawing.Color]::FromArgb(20,29,43)}
    }
}
function BigPictureMenuAction([int]$index) {
    BigPictureFocusLibrary
    switch($index){
        0 {HydraShowSystems}
        1 {HydraRememberSelection;$script:HydraHome=$false;$script:HydraSystem='';$script:Filter='fav';$q.Clear();Populate;if($script:View.Count){SelectIdx 0 'single'}}
        2 {ShowSearchDialog}
        3 {ShowTarginoPreferences}
        4 {BigPictureToggle}
        5 {if(Get-Command ShowTarginoWelcome -ErrorAction SilentlyContinue){ShowTarginoWelcome}}
        6 {if([Windows.Forms.MessageBox]::Show($form,'Fechar o TarginoRetroStation?','Sair','YesNo','Question') -eq 'Yes'){$form.Close()}}
    }
}
function BigPictureInput([string]$key) {
    if(-not $script:BigPictureEnabled){return $false}
    if($key -eq 'F1'){BigPictureFocusMenu;return $true}
    if($script:BigPictureSidebar){
        switch($key){
            'Up' {$script:BigPictureMenuIndex=[Math]::Max(0,$script:BigPictureMenuIndex-1);BigPictureFocusMenu}
            'Down' {$script:BigPictureMenuIndex=[Math]::Min($script:BigPictureButtons.Count-1,$script:BigPictureMenuIndex+1);BigPictureFocusMenu}
            'Return' {BigPictureMenuAction $script:BigPictureMenuIndex}
            'Right' {BigPictureFocusLibrary}
            'Escape' {BigPictureFocusLibrary}
            'Left' { } # Keep a held left direction inside the menu.
            default {return $false}
        }
        return $true
    }
    if($key -in @('Left','Right','Up','Down','Home','End','PageUp','PageDown')){
        $geometry=BigPictureGeometry
        $index=[Math]::Max(0,$script:CurIdx);$columns=$geometry.Columns
        if($key -eq 'Left' -and $index -eq 0){BigPictureFocusMenu;return $true}
        $target=switch($key){'Left'{$index-1}'Right'{$index+1}'Up'{$index-$columns}'Down'{$index+$columns}'Home'{0}'End'{$script:View.Count-1}'PageUp'{$index-$geometry.PageSize}'PageDown'{$index+$geometry.PageSize}}
        if($script:View.Count){SelectIdx ([Math]::Max(0,[Math]::Min($script:View.Count-1,$target))) 'single'}
        return $true
    }
    if($key -eq 'Escape' -and $script:HydraHome){BigPictureFocusMenu;return $true}
    return $false
}
function BigPictureHero($gr) {
    if(-not $script:BigPictureEnabled){return}
    $left=36
    $height=$script:BackgroundPic.Height
    if($height -lt 100){return}
    $gm=Sel
    $eyebrow=if($script:HydraHome){'SUA BIBLIOTECA / SISTEMAS'}elseif($script:Filter -eq 'fav'){'SUA BIBLIOTECA / FAVORITOS'}else{'SUA BIBLIOTECA / '+(HydraSystemLabel $script:HydraSystem)}
    $title=if($gm){$gm.Name}else{'Pronto para jogar?'}
    $subtitle=if($gm -and $gm.HydraKind -eq 'system'){$gm.Version+' disponíveis · A / Enter para explorar'}elseif($gm){'A / Enter para jogar · X para detalhes'}else{'Escolha a pasta de ROMs no menu Sistemas.'}
    $small=New-Object Drawing.Font('Segoe UI',11)
    $large=New-Object Drawing.Font('Segoe UI',([single][Math]::Min(36,[Math]::Max(20,$height/6))),[Drawing.FontStyle]::Bold)
    $flags=[Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis,SingleLine,NoPrefix'
    $width=[Math]::Max(1,$script:BackgroundPic.Width-$left-36)
    try{
        [Windows.Forms.TextRenderer]::DrawText($gr,$eyebrow,$small,(New-Object Drawing.Rectangle($left,14,$width,26)),[Drawing.Color]::LightSkyBlue,$flags)
        [Windows.Forms.TextRenderer]::DrawText($gr,$title,$large,(New-Object Drawing.Rectangle($left,50,$width,([Math]::Max(40,$height-100)))),[Drawing.Color]::White,$flags)
        [Windows.Forms.TextRenderer]::DrawText($gr,$subtitle,$small,(New-Object Drawing.Rectangle($left,($height-35),$width,26)),[Drawing.Color]::Gainsboro,$flags)
    }finally{$small.Dispose();$large.Dispose()}
}
function InitializeBigPicture {
    $state=ReadJson (Join-Path $DataDir 'bigpicture.json') $false
    $script:BigPictureEnabled=if($state){[bool]$state.Enabled}else{[IO.File]::Exists((Join-Path $Arq 'BigPicture.enabled')) -or [IO.File]::Exists((Join-Path $Arq 'BigPicture.teste'))}
    $script:BigPictureSidebar=$false;$script:BigPictureMenuIndex=0
    $script:BigPictureContent=New-Object Windows.Forms.Panel -Property @{Dock='Fill';BackColor=[Drawing.Color]::FromArgb(9,12,19)}
    $mainP.Controls.Add($script:BigPictureContent);$mainP.Controls.SetChildIndex($script:BigPictureContent,0)
    $script:BigPictureRail=New-Object Windows.Forms.Panel -Property @{Dock='Left';BackColor=[Drawing.Color]::FromArgb(13,20,31);TabStop=$false;AutoScroll=$true}
    $script:BigPictureContent.Controls.AddRange(@($script:BackgroundPic,$libP,$script:BigPictureRail))
    $caption=New-Object Windows.Forms.Label -Property @{Text="BIG PICTURE`nTARGINO LAUNCHER";Left=16;Top=18;Width=170;Height=55;ForeColor=[Drawing.Color]::LightSkyBlue;Font=(New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold))}
    $script:BigPictureRail.Controls.Add($caption)
    $script:BigPictureButtons=@();$labels=@('Sistemas','Favoritos','Buscar','Personalizar','Visual clássico','Ajuda e novidades','Sair')
    for($i=0;$i -lt $labels.Count;$i++){
        $button=New-Object Windows.Forms.Button -Property @{Text=$labels[$i];Tag=$i;Left=12;Top=(88+$i*53);Width=200;Height=45;FlatStyle='Flat';ForeColor=[Drawing.Color]::White;BackColor=[Drawing.Color]::FromArgb(20,29,43);Font=(New-Object Drawing.Font('Segoe UI',12));TextAlign='MiddleLeft';Padding='12,0,0,0'}
        $button.FlatAppearance.BorderSize=0
        $button.Add_PreviewKeyDown({param($sender,$key)
            if($key.KeyCode -in @('Left','Right','Up','Down')){$key.IsInputKey=$true}
        })
        $button.Add_Click({param($sender,$eventArgs) BigPictureMenuAction ([int]$sender.Tag)})
        $button.Add_Enter({param($sender,$eventArgs) $script:BigPictureMenuIndex=[int]$sender.Tag;BigPictureHighlight})
        $script:BigPictureRail.Controls.Add($button);$script:BigPictureButtons+= $button
    }
    $script:BigPictureButton=New-Object Windows.Forms.Button -Property @{Width=125;Height=30;Top=14;FlatStyle='Flat';ForeColor=[Drawing.Color]::White;BackColor=[Drawing.Color]::FromArgb(24,36,54);Anchor='Top,Right'}
    $hdr.Controls.Add($script:BigPictureButton)
    $script:BigPictureButton.Add_Click({if($script:BigPictureEnabled){BigPictureFocusMenu}else{BigPictureToggle}})
    $hdr.Add_Resize({$script:BigPictureButton.Left=[Math]::Max(0,$hdr.Width-295)})
    $script:BigPictureButton.Left=[Math]::Max(0,$hdr.Width-295)
    $mainP.Add_Resize({BigPictureLayout})
    $script:BackgroundPic.Add_Paint({param($sender,$eventArgs) BigPictureHero $eventArgs.Graphics})
    $grid.Add_Enter({if($script:BigPictureSidebar -and -not $script:BigPictureFocusChanging){$script:BigPictureSidebar=$false;BigPictureLayout};BigPictureHighlight})
    BigPictureLayout
}

# Dedicated dashboard renderer: no dependence on the classic cinema carousel.
function BigPictureGeometry {
    $width=[Math]::Max(320,$grid.Width);$height=[Math]::Max(300,$grid.Height)
    $hero=[int][Math]::Min(265,[Math]::Max(220,$height*0.32))
    $systemPage=[bool]$script:HydraHome
    $columns=if($systemPage){[Math]::Max(1,[int][Math]::Floor(($width-64)/310))}else{[Math]::Max(1,[int][Math]::Floor(($width-64)/195))}
    $gap=18;$cellW=[int](($width-64-($columns-1)*$gap)/$columns)
    $available=$height-$hero-108
    $rows=if($systemPage){[Math]::Max(1,[int][Math]::Floor($available/155))}else{[Math]::Max(1,[int][Math]::Floor($available/275))}
    $cellH=[int][Math]::Min($(if($systemPage){170}else{290}),[Math]::Floor(($available-($rows-1)*$gap)/$rows))
    @{Columns=$columns;Rows=$rows;PageSize=($columns*$rows);Hero=$hero;CellW=$cellW;CellH=$cellH;Gap=$gap}
}
function BigPictureText($gr,[string]$text,[int]$size,[Drawing.Rectangle]$rect,[Drawing.Color]$color,[bool]$bold=$false){
    $font=New-Object Drawing.Font('Segoe UI',([single]$size),$(if($bold){[Drawing.FontStyle]::Bold}else{[Drawing.FontStyle]::Regular}))
    try{[Windows.Forms.TextRenderer]::DrawText($gr,$text,$font,$rect,$color,([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis,SingleLine,NoPrefix'))}finally{$font.Dispose()}
}
function BigPictureFill($gr,[Drawing.Rectangle]$rect,[Drawing.Color]$color){
    $brush=New-Object Drawing.SolidBrush($color)
    try{$gr.FillRectangle($brush,$rect)}finally{$brush.Dispose()}
}
function BigPictureImage($gr,$bitmap,[Drawing.Rectangle]$rect){
    if(-not $bitmap){return}
    $scale=[Math]::Min($rect.Width/[double]$bitmap.Width,$rect.Height/[double]$bitmap.Height)
    $w=[int]($bitmap.Width*$scale);$h=[int]($bitmap.Height*$scale)
    $dest=New-Object Drawing.Rectangle(($rect.X+[int](($rect.Width-$w)/2)),($rect.Y+[int](($rect.Height-$h)/2)),$w,$h)
    $gr.DrawImage($bitmap,$dest)
}
function BigPictureArtPath($game){
    if($game.HydraKind -ne 'system' -and $game.Cover){return (CoverPath $game)}
    if(-not $script:BigPictureOriginals -or $script:BigPictureOriginalStamp -ne $script:HydraMediaStamp){
        $script:BigPictureOriginals=@{};$script:BigPictureOriginalStamp=$script:HydraMediaStamp
        $index=ReadJson (Join-Path $DataDir 'hydra-midia-indice.json') $false
        if($index){foreach($entry in $index.PSObject.Properties){
            if($entry.Value.Status -ne 'downloaded' -or -not $entry.Value.Source){continue}
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($entry.Value.Source)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
            $path=Join-Path $Arq ('Midia\Originais\'+$hash+'.png')
            if([IO.File]::Exists($path)){$script:BigPictureOriginals[$entry.Name]=$path}
        }}
    }
    $key=if($game.HydraKind -eq 'system'){'system:'+$game.HydraSystemId}else{'game:'+$game.Id}
    if($script:BigPictureOriginals.ContainsKey($key)){return $script:BigPictureOriginals[$key]}
    return (CoverPath $game)
}
function PaintBigPicture($gr){
    DrawCinemaScene $gr $grid
    $script:CinemaHits=@();$script:CinemaFooterHits=@()
    $whole=New-Object Drawing.Rectangle(0,0,$grid.Width,$grid.Height)
    BigPictureFill $gr $whole ([Drawing.Color]::FromArgb(220,10,17,29))
    $layout=BigPictureGeometry;$n=$script:View.Count
    $selected=[Math]::Max(0,$script:CurIdx)
    $gm=if($n){$script:View[$selected]}else{$null}
    $accent=[Drawing.Color]::FromArgb(71,194,255);$white=[Drawing.Color]::White;$muted=[Drawing.Color]::FromArgb(170,190,213)
    $hero=New-Object Drawing.Rectangle(16,4,([Math]::Max(1,$grid.Width-32)),($layout.Hero-8))
    $gradient=New-Object Drawing.Drawing2D.LinearGradientBrush($hero,([Drawing.Color]::FromArgb(35,60,87)),([Drawing.Color]::FromArgb(13,25,42)),([single]0))
    try{$gr.FillRectangle($gradient,$hero)}finally{$gradient.Dispose()}
    $label=if($script:HydraHome){'EXPLORE SEUS SISTEMAS'}elseif($script:Filter -eq 'fav'){'SUA COLEÇÃO / FAVORITOS'}else{'BIBLIOTECA / '+(HydraSystemLabel $script:HydraSystem)}
    $textWidth=[int]($grid.Width*0.66)-50
    BigPictureText $gr $label 11 (New-Object Drawing.Rectangle(38,20,$textWidth,26)) $accent $true
    $title=if($gm){$gm.Name}else{'Sua próxima aventura começa aqui'}
    BigPictureText $gr $title 30 (New-Object Drawing.Rectangle(36,52,$textWidth,60)) $white $true
    $sub=if($script:HydraHome){"$($script:HydraSystemCards.Count) sistemas · $($script:Games.Count) jogos na sua biblioteca"}elseif($gm){(HydraSystemLabel $gm.Version)+' · Pronto para jogar no Hydra'}else{'Nenhum jogo neste filtro. Use Sistemas para escolher outra lista.'}
    BigPictureText $gr $sub 12 (New-Object Drawing.Rectangle(38,115,$textWidth,26)) $muted
    $play=New-Object Drawing.Rectangle(38,($layout.Hero-62),210,40)
    BigPictureFill $gr $play ([Drawing.Color]::FromArgb(0,132,198))
    BigPictureText $gr $(if($script:HydraHome){'A  EXPLORAR SISTEMA'}else{'A  JOGAR AGORA'}) 12 (New-Object Drawing.Rectangle(54,$play.Y,190,40)) $white $true
    $script:CinemaFooterHits+=@{Rect=$play;Action=0}
    if($gm){
        $art=CoverGet (BigPictureArtPath $gm) 320 'Ajustar'
        $artRect=New-Object Drawing.Rectangle(([int]($grid.Width*0.70)),16,([int]($grid.Width*0.26)),($layout.Hero-32))
        BigPictureImage $gr $art $artRect
    }
    $shelf=if($script:HydraHome){'Sistemas disponíveis'}elseif($script:Filter -eq 'fav'){'Seus favoritos'}else{'Todos os jogos'}
    BigPictureText $gr $shelf 17 (New-Object Drawing.Rectangle(32,($layout.Hero+6),($grid.Width-200),34)) $white $true
    $page=[int][Math]::Floor($selected/[double]$layout.PageSize)
    $start=$page*$layout.PageSize
    BigPictureText $gr $(if($n){"$($selected+1) / $n"}else{'0 jogos'}) 12 (New-Object Drawing.Rectangle(($grid.Width-145),($layout.Hero+6),110,34)) $muted
    for($slot=0;$slot -lt $layout.PageSize -and $start+$slot -lt $n;$slot++){
        $i=$start+$slot;$item=$script:View[$i];$focus=($i -eq $selected)
        $x=32+($slot % $layout.Columns)*($layout.CellW+$layout.Gap)
        $y=$layout.Hero+50+[int][Math]::Floor($slot/[double]$layout.Columns)*($layout.CellH+$layout.Gap)
        $rect=New-Object Drawing.Rectangle($x,$y,$layout.CellW,$layout.CellH)
        BigPictureFill $gr $rect $(if($focus){[Drawing.Color]::FromArgb(40,73,104)}else{[Drawing.Color]::FromArgb(22,35,53)})
        $image=CoverGet (BigPictureArtPath $item) 320 'Ajustar'
        if($script:HydraHome){
            $imageRect=New-Object Drawing.Rectangle(($x+10),($y+10),([int]($layout.CellW*0.37)),($layout.CellH-20))
            BigPictureImage $gr $image $imageRect
            $textX=$x+[int]($layout.CellW*0.42);$textW=$layout.CellW-($textX-$x)-10
            BigPictureText $gr $item.Name 15 (New-Object Drawing.Rectangle($textX,($y+26),$textW,34)) $white $true
            BigPictureText $gr $item.Version 12 (New-Object Drawing.Rectangle($textX,($y+65),$textW,26)) $accent
            BigPictureText $gr 'ABRIR BIBLIOTECA  ›' 9 (New-Object Drawing.Rectangle($textX,($y+$layout.CellH-38),$textW,24)) $muted $true
        }else{
            $imageRect=New-Object Drawing.Rectangle(($x+8),($y+8),($layout.CellW-16),($layout.CellH-89))
            BigPictureImage $gr $image $imageRect
            $titleRect=New-Object Drawing.Rectangle(($x+10),($y+$layout.CellH-78),($layout.CellW-20),43)
            $font=New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
            try{[Windows.Forms.TextRenderer]::DrawText($gr,$item.Name,$font,$titleRect,$white,([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,WordBreak,EndEllipsis,NoPrefix'))}finally{$font.Dispose()}
            $badge=New-Object Drawing.Rectangle(($x+12),($y+$layout.CellH-30),($layout.CellW-24),23)
            BigPictureFill $gr $badge ([Drawing.Color]::FromArgb(14,29,48))
            $pen=New-Object Drawing.Pen(([Drawing.Color]::FromArgb(42,91,134)))
            try{$gr.DrawRectangle($pen,$badge)}finally{$pen.Dispose()}
            $badgeFont=New-Object Drawing.Font('Segoe UI',8)
            try{[Windows.Forms.TextRenderer]::DrawText($gr,(HydraSystemLabel $item.Version),$badgeFont,$badge,$accent,([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,EndEllipsis,NoPrefix'))}finally{$badgeFont.Dispose()}
        }
        if(-not $image){BigPictureText $gr ($item.Name.Substring(0,[Math]::Min(2,$item.Name.Length)).ToUpperInvariant()) 28 $imageRect $accent $true}
        if($focus){$pen=New-Object Drawing.Pen($accent,3);try{$gr.DrawRectangle($pen,$rect)}finally{$pen.Dispose()}}
        $script:CinemaHits+=@{Index=$i;Rect=$rect}
    }
    if(-not $n){BigPictureText $gr 'Nenhum jogo encontrado. Abra Sistemas para escolher a pasta de ROMs.' 14 (New-Object Drawing.Rectangle(32,($layout.Hero+72),($grid.Width-64),60)) $muted}
    $footerY=$grid.Height-47
    BigPictureFill $gr (New-Object Drawing.Rectangle(0,($footerY-4),$grid.Width,51)) ([Drawing.Color]::FromArgb(11,20,33))
    $labels=@('A  Confirmar','X  Detalhes','Y  Filtros','Select  Ações','Select+Y  Buscar','B  Voltar')
    $itemW=[int](($grid.Width-32)/6)
    for($f=0;$f -lt 6;$f++){
        $rect=New-Object Drawing.Rectangle((16+$f*$itemW),$footerY,$itemW,42)
        BigPictureText $gr $labels[$f] 10 $rect $(if($f -eq 0){$accent}else{$muted}) $true
        $script:CinemaFooterHits+=@{Rect=$rect;Action=$f}
    }
}
