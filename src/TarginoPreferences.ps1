# User personalization and protected developer access for TarginoRetroStation.
$script:TarginoPreferencesFile=Join-Path $DataDir 'preferencias.json'
$script:TarginoPreferences=@{MusicFolder='';MusicEnabled=$false;MusicVolume=40}
$script:TarginoDeveloperAuthenticated=$false
$script:TarginoMusicLaunchPending=$false
$script:TarginoMusicCacheVersion=-1
$script:TarginoMusicPlayer=$null
$script:TarginoDefaultPasswordHash='' # No password or authentication hash is distributed.
function TarginoEnforceIdentity {
    $S.Title='Targino RetroStation';$S.HeaderText='Targino RetroStation'
    if(-not $S.PassHash){$S.PassHash=$script:TarginoDefaultPasswordHash}
}
TarginoEnforceIdentity
$Defaults.Title='Targino RetroStation';$Defaults.HeaderText='Targino RetroStation';$Defaults.PassHash=$script:TarginoDefaultPasswordHash
$savedPreferences=ReadJson $script:TarginoPreferencesFile $false
if($savedPreferences){foreach($name in @('MusicFolder','MusicEnabled','MusicVolume')){if($savedPreferences.PSObject.Properties[$name]){$script:TarginoPreferences[$name]=$savedPreferences.$name}}}
function TarginoMusicConfigure {
    if(-not $script:TarginoMusicPlayer){return}
    $prefs=$script:TarginoPreferences;$cache=ReadJson (Join-Path $DataDir 'musicas-cache.json') $false
    $tracks=[string[]]@()
    if($cache -and $cache.Folder -eq $prefs.MusicFolder){$tracks=[string[]]@($cache.Files | Where-Object {$_})}
    $script:TarginoMusicPlayer.Enabled=[bool]$prefs.MusicEnabled
    $script:TarginoMusicPlayer.Volume=[int]$prefs.MusicVolume
    $script:TarginoMusicPlayer.Configure([string]$prefs.MusicFolder,$tracks)
}
function TarginoMusicTick {
    if(-not $script:TarginoMusicPlayer){return}
    # Losing focus or minimizing the launcher must not interrupt background music.
    $hydraOpen=@($script:Play.Values | Where-Object {$_.Hydra}).Count -gt 0
    $allowed=(-not $script:TarginoMusicLaunchPending -and -not $hydraOpen)
    $script:TarginoMusicPlayer.Tick($allowed)
    TarginoNowPlayingTick $allowed
    if($script:TarginoMusicPlayer.PlaylistVersion -ne $script:TarginoMusicCacheVersion){
        $script:TarginoMusicCacheVersion=$script:TarginoMusicPlayer.PlaylistVersion
        [void](WriteJson (Join-Path $DataDir 'musicas-cache.json') @{Folder=$script:TarginoPreferences.MusicFolder;Files=$script:TarginoMusicPlayer.GetTracks()} 3)
    }
}
function TarginoNowPlayingTick([bool]$allowed){
    $toast=$script:TarginoNowPlaying
    if(-not $toast){return}
    $player=$script:TarginoMusicPlayer
    if(-not $allowed -or -not $player.IsOpen -or $player.IsPaused){$toast.Visible=$false;return}
    if($script:TarginoNowPlayingVersion -ne $player.PlaybackVersion){
        $script:TarginoNowPlayingVersion=$player.PlaybackVersion
        $name=[IO.Path]::GetFileNameWithoutExtension($player.CurrentTrack) -replace '_',' '
        $toast.Text="Tocando agora`r`n$name"
        $toast.AccessibleName='Tocando agora: '+$name
        $toast.Left=[Math]::Max(10,$form.ClientSize.Width-$toast.Width-20)
        $toast.Top=[Math]::Max(10,$form.ClientSize.Height-$toast.Height-65)
        $script:TarginoNowPlayingUntil=$script:TarginoClock.ElapsedMilliseconds+5500
        $toast.Visible=$true;$toast.BringToFront()
    }elseif($script:TarginoClock.ElapsedMilliseconds -ge $script:TarginoNowPlayingUntil){$toast.Visible=$false}
}
function TarginoPauseForGame {
    $script:TarginoMusicLaunchPending=$true
    if($script:TarginoNowPlaying){$script:TarginoNowPlaying.Visible=$false}
    if($script:TarginoMusicPlayer){$script:TarginoMusicPlayer.Pause()}
}
function TarginoGameLaunchFinished {$script:TarginoMusicLaunchPending=$false;TarginoMusicTick}
function TarginoDeveloperTick {
    if(-not $S.PassHash){return} # No shared developer credential in public builds.
    $focused=($form.Visible -and [TarginoMusicPlayer]::MainFocused($form.Handle))
    $trigger=$script:TarginoDeveloperGate.Update($focused,[TarginoMusicPlayer]::KeyDown(0x10),[TarginoMusicPlayer]::KeyDown(0x79),$script:TarginoClock.ElapsedMilliseconds)
    if(-not $trigger -or $script:TarginoDeveloperPrompt){return}
    $script:TarginoDeveloperPrompt=$true
    try {
        if(-not (Unlock)){return}
        $script:TarginoDeveloperAuthenticated=$true;$script:Dev=$true
        try{ApplyLayout;DevPanel}finally{$script:Dev=$false;$script:TarginoDeveloperAuthenticated=$false;ApplyLayout}
    } finally {$script:TarginoDeveloperPrompt=$false}
}
function TarginoCopyPersonalImage([string]$source,[string]$kind){
    if(-not [IO.File]::Exists($source)){throw 'A imagem selecionada nao foi encontrada.'}
    $image=[Drawing.Image]::FromFile($source)
    try {
        $directory=Join-Path $Arq 'Marca\Personalizacao';[void][IO.Directory]::CreateDirectory($directory)
        $path=Join-Path $directory ($kind+'-'+[Guid]::NewGuid().ToString('N')+'.png')
        $max=if($kind -eq 'avatar'){512}else{2560}
        $scale=[Math]::Min(1.0,$max/[double][Math]::Max($image.Width,$image.Height))
        $bitmap=New-Object Drawing.Bitmap([int][Math]::Max(1,($image.Width*$scale)),[int][Math]::Max(1,($image.Height*$scale)))
        try{$graphics=[Drawing.Graphics]::FromImage($bitmap);try{$graphics.InterpolationMode='HighQualityBicubic';$graphics.DrawImage($image,0,0,$bitmap.Width,$bitmap.Height)}finally{$graphics.Dispose()};$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
        return $path
    } finally {$image.Dispose()}
}
function TarginoSelectImage($dialog,[string]$kind){
    $picker=New-Object Windows.Forms.OpenFileDialog
    $picker.Title=if($kind -eq 'background'){'Escolher plano de fundo'}else{'Escolher avatar'}
    $picker.Filter='Imagens|*.png;*.jpg;*.jpeg;*.bmp;*.gif';$picker.CheckFileExists=$true
    try {
        if($picker.ShowDialog($dialog) -ne 'OK'){return}
        $source=[Drawing.Image]::FromFile($picker.FileName)
        try {$preview=New-Object Drawing.Bitmap($source)}finally{$source.Dispose()}
        $target=if($kind -eq 'background'){$dialog.Tag.BackgroundPreview}else{$dialog.Tag.AvatarPreview}
        $old=$target.Image;$target.Image=$preview;if($old){$old.Dispose()}
        if($kind -eq 'background'){$dialog.Tag.NewBackground=$picker.FileName}else{$dialog.Tag.NewAvatar=$picker.FileName}
    }catch{[void][Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Imagem invalida')}finally{$picker.Dispose()}
}
function ShowTarginoPreferences {
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Personalizar TarginoRetroStation';StartPosition='CenterParent';ClientSize='720,565';FormBorderStyle='FixedDialog';MaximizeBox=$false;MinimizeBox=$false;BackColor=[Drawing.Color]::FromArgb(13,18,28);ForeColor=[Drawing.Color]::White;Font=(New-Object Drawing.Font('Segoe UI',10));KeyPreview=$true}
    $name=New-Object Windows.Forms.Label -Property @{Text='TarginoRetroStation';Left=24;Top=16;Width=670;Height=34;Font=(New-Object Drawing.Font('Segoe UI',21,[Drawing.FontStyle]::Bold));ForeColor=[Drawing.Color]::FromArgb(77,179,255)}
    $backgroundLabel=New-Object Windows.Forms.Label -Property @{Text='Plano de fundo';Left=24;Top=66;Width=320;Height=24}
    $avatarLabel=New-Object Windows.Forms.Label -Property @{Text='Avatar';Left=380;Top=66;Width=300;Height=24}
    $background=New-Object Windows.Forms.PictureBox -Property @{Left=24;Top=94;Width=320;Height=152;SizeMode='Zoom';BackColor=[Drawing.Color]::FromArgb(24,31,45)}
    $avatar=New-Object Windows.Forms.PictureBox -Property @{Left=380;Top=94;Width=152;Height=152;SizeMode='Zoom';BackColor=[Drawing.Color]::FromArgb(24,31,45)}
    $backgroundButton=New-Object Windows.Forms.Button -Property @{Text='Procurar...';Left=24;Top=255;Width=132;Height=32}
    $avatarButton=New-Object Windows.Forms.Button -Property @{Text='Procurar...';Left=380;Top=255;Width=132;Height=32}
    $musicLabel=New-Object Windows.Forms.Label -Property @{Text='Pasta de musicas (MP3 e WAV, incluindo subpastas)';Left=24;Top=310;Width=670;Height=24}
    $folder=New-Object Windows.Forms.TextBox -Property @{Left=24;Top=340;Width=526;ReadOnly=$true;Text=$script:TarginoPreferences.MusicFolder}
    $folderButton=New-Object Windows.Forms.Button -Property @{Text='Procurar...';Left=560;Top=337;Width=132;Height=32}
    $enabled=New-Object Windows.Forms.CheckBox -Property @{Text='Tocar musica enquanto estiver no launcher';Left=24;Top=384;Width=525;Height=27;Checked=[bool]$script:TarginoPreferences.MusicEnabled}
    $volumeLabel=New-Object Windows.Forms.Label -Property @{Text='Volume';Left=24;Top=426;Width=75;Height=28}
    $volume=New-Object Windows.Forms.TrackBar -Property @{Left=99;Top=416;Width=325;Minimum=0;Maximum=100;TickFrequency=10;Value=[Math]::Max(0,[Math]::Min(100,[int]$script:TarginoPreferences.MusicVolume))}
    $hint=New-Object Windows.Forms.Label -Property @{Text='Ao jogar, a musica pausa. Quando o Hydra fechar, ela continua de onde parou.';Left=24;Top=466;Width=670;Height=35;ForeColor=[Drawing.Color]::Silver;Font=(New-Object Drawing.Font('Segoe UI',9))}
    $save=New-Object Windows.Forms.Button -Property @{Text='Salvar';Left=424;Top=516;Width=132;Height=32}
    $cancel=New-Object Windows.Forms.Button -Property @{Text='Cancelar';Left=560;Top=516;Width=132;Height=32;DialogResult='Cancel'}
    $dialog.Controls.AddRange(@($name,$backgroundLabel,$avatarLabel,$background,$avatar,$backgroundButton,$avatarButton,$musicLabel,$folder,$folderButton,$enabled,$volumeLabel,$volume,$hint,$save,$cancel))
    if(Get-Command ShowHydraLiveSettings -ErrorAction SilentlyContinue){
        $liveButton=New-Object Windows.Forms.Button -Property @{Text='Janela para live...';Left=230;Top=516;Width=184;Height=32;BackColor=[Drawing.Color]::FromArgb(28,43,63);ForeColor=[Drawing.Color]::White;FlatStyle='Flat'}
        $liveButton.Add_Click({param($sender,$eventArgs) ShowHydraLiveSettings -Owner $sender.FindForm()})
        $dialog.Controls.Add($liveButton)
    }
    if(Get-Command ShowHydraMetadataSettings -ErrorAction SilentlyContinue){
        $sourcesButton=New-Object Windows.Forms.Button -Property @{Text='Fontes de dados...';Left=24;Top=516;Width=200;Height=32;BackColor=[Drawing.Color]::FromArgb(28,43,63);ForeColor=[Drawing.Color]::White;FlatStyle='Flat'}
        $sourcesButton.Add_Click({param($sender,$eventArgs) ShowHydraMetadataSettings -Owner $sender.FindForm()})
        $dialog.Controls.Add($sourcesButton)
    }
    foreach($button in @($backgroundButton,$avatarButton,$folderButton,$save,$cancel)){$button.BackColor=[Drawing.Color]::FromArgb(28,43,63);$button.ForeColor=[Drawing.Color]::White;$button.FlatStyle='Flat'}
    $dialog.Tag=@{BackgroundPreview=$background;AvatarPreview=$avatar;NewBackground='';NewAvatar='';Folder=$folder;Enabled=$enabled;Volume=$volume}
    foreach($pair in @(@($background,$S.BackgroundImage),@($avatar,$S.AvatarImage))){if($pair[1] -and [IO.File]::Exists($pair[1])){$im=[Drawing.Image]::FromFile($pair[1]);try{$pair[0].Image=New-Object Drawing.Bitmap($im)}finally{$im.Dispose()}}}
    $backgroundButton.Add_Click({param($sender,$eventArgs) TarginoSelectImage $sender.FindForm() 'background'})
    $avatarButton.Add_Click({param($sender,$eventArgs) TarginoSelectImage $sender.FindForm() 'avatar'})
    $folderButton.Add_Click({param($sender,$eventArgs)
        $win=$sender.FindForm();$picker=New-Object Windows.Forms.FolderBrowserDialog
        $picker.Description='Escolha sua pasta de musicas';$picker.SelectedPath=$win.Tag.Folder.Text
        try{if($picker.ShowDialog($win) -eq 'OK'){$win.Tag.Folder.Text=$picker.SelectedPath;$win.Tag.Enabled.Checked=$true}}finally{$picker.Dispose()}
    })
    $save.Add_Click({param($sender,$eventArgs)
        $win=$sender.FindForm();$state=$win.Tag
        try{
            if($state.NewBackground){$S.BackgroundImage=TarginoCopyPersonalImage $state.NewBackground 'background'}
            if($state.NewAvatar){$S.AvatarImage=TarginoCopyPersonalImage $state.NewAvatar 'avatar'}
            $script:TarginoPreferences.MusicFolder=$state.Folder.Text
            $script:TarginoPreferences.MusicEnabled=[bool]$state.Enabled.Checked
            $script:TarginoPreferences.MusicVolume=[int]$state.Volume.Value
            if(-not (WriteJson $script:TarginoPreferencesFile $script:TarginoPreferences 3)){return}
            SaveSettings;ApplyBranding;ApplyLayout;TarginoMusicConfigure
            $win.DialogResult='OK';$win.Close()
        }catch{[void][Windows.Forms.MessageBox]::Show($win,$_.Exception.Message,'Nao foi possivel salvar')}
    })
    $dialog.CancelButton=$cancel;$dialog.AcceptButton=$save
    try{[void]$dialog.ShowDialog($form)}finally{foreach($picture in @($background,$avatar)){if($picture.Image){$picture.Image.Dispose()}};$dialog.Dispose();[void]$grid.Focus()}
}
function InitializeTarginoPreferences {
    $script:DevSchema=@($script:DevSchema | Where-Object {$_.Key -notin @('Title','HeaderText')})
    $script:TarginoMusicPlayer=New-Object TarginoMusicPlayer
    $script:TarginoDeveloperGate=New-Object TarginoDeveloperGate
    $script:TarginoClock=[Diagnostics.Stopwatch]::StartNew()
    $script:TarginoNowPlayingVersion=-1
    $script:TarginoNowPlaying=New-Object Windows.Forms.Label -Property @{Visible=$false;Width=410;Height=62;BackColor=[Drawing.Color]::FromArgb(18,33,52);ForeColor=[Drawing.Color]::FromArgb(130,211,255);BorderStyle='FixedSingle';Padding='12,5,12,5';AutoEllipsis=$true;TextAlign='MiddleLeft';Font=(New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold));Anchor='Bottom,Right';TabStop=$false}
    $form.Controls.Add($script:TarginoNowPlaying)
    TarginoMusicConfigure
    $script:TarginoPersonalizeButton=New-Object Windows.Forms.Button -Property @{Text='Personalizar';Width=140;Height=30;Top=14;FlatStyle='Flat';BackColor=[Drawing.Color]::FromArgb(24,36,54);ForeColor=[Drawing.Color]::White;Anchor='Top,Right'}
    $script:TarginoPersonalizeButton.Left=[Math]::Max(0,$hdr.Width-160)
    $hdr.Controls.Add($script:TarginoPersonalizeButton);$script:TarginoPersonalizeButton.BringToFront()
    $script:TarginoPersonalizeButton.Add_Click({ShowTarginoPreferences})
    $script:AvatarPic.Add_Click({ShowTarginoPreferences});$script:AvatarPic.Cursor='Hand'
    $hdr.Add_Resize({$script:TarginoPersonalizeButton.Left=[Math]::Max(0,$hdr.Width-160)})
    $form.Add_KeyDown({param($sender,$key)
        if($key.Shift -and $key.KeyCode -eq 'F10'){$key.Handled=$true;$key.SuppressKeyPress=$true}
    })
    $script:TarginoPreferencesTimer=New-Object Windows.Forms.Timer -Property @{Interval=100}
    $script:TarginoPreferencesTimer.Add_Tick({
        try{
            TarginoDeveloperTick
            if($script:TarginoClock.ElapsedMilliseconds-$script:TarginoLastMusicTick -ge 500){$script:TarginoLastMusicTick=$script:TarginoClock.ElapsedMilliseconds;TarginoMusicTick}
        }catch{LogEx 'AVISO' 'Falha na personalizacao ou musica' $_}
    })
    $script:TarginoPreferencesTimer.Start()
    $form.Add_Activated({TarginoMusicTick})
    $form.Add_Deactivate({TarginoMusicTick})
    $form.Add_FormClosed({
        if(Get-Command HydraLiveEnd -ErrorAction SilentlyContinue){foreach($entry in @($script:Play.Values)){if($entry.Hydra){try{HydraLiveEnd $entry}catch{ }}}}
        $script:TarginoPreferencesTimer.Stop();$script:TarginoPreferencesTimer.Dispose();$script:TarginoMusicPlayer.Dispose()
    })
}
