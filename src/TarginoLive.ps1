# Optional window geometry profile. Does not change Hydra settings or emulator resolution.
$script:HydraLivePrefs=@{Enabled=$false;Width=1280;Height=720;Center=$true;X=0;Y=0;AutoRemember=$true;AspectMode='manual'}
$script:HydraLiveRevision=0
$liveSaved=ReadJson (Join-Path $DataDir 'hydra-live.json') $false
if($liveSaved){foreach($key in @('Enabled','Width','Height','Center','X','Y','AutoRemember','AspectMode')){if($liveSaved.PSObject.Properties[$key]){$script:HydraLivePrefs[$key]=$liveSaved.$key}}}
function HydraLiveDimensions($prefs){
    $height=[int]$prefs.Height;$width=[int]$prefs.Width
    $ratio=switch([string]$prefs.AspectMode){'4:3'{4.0/3}'16:9'{16.0/9}'3:4'{3.0/4}'9:16'{9.0/16}default{0}}
    if($ratio -gt 0){$width=[int][Math]::Round($height*$ratio,0,[MidpointRounding]::AwayFromZero)}
    return @{Width=$width;Height=$height}
}
function HydraLiveLoad {
    if(-not ('TarginoLiveWindow' -as [type])){Add-Type -Path (Join-Path $Arq 'TarginoLiveWindow.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing}
}
function HydraLiveTick($entry){
    if(-not $entry.Hydra -or -not $entry.Proc){return}
    try{
        if(-not $script:HydraLivePrefs.Enabled){if('TarginoLiveWindow' -as [type]){[TarginoLiveWindow]::StopWatching($entry.Proc.Id)};return}
        HydraLiveLoad
        HydraLiveFlush $entry
        if($entry.ReturnRequested){return}
        $handle=$entry.Proc.MainWindowHandle
        if($handle -eq [IntPtr]::Zero){return}
        if($entry.LiveHandle -ne $handle -or $entry.LiveRevision -ne $script:HydraLiveRevision){$entry.LiveHandle=$handle;$entry.LiveRevision=$script:HydraLiveRevision;$entry.LiveAttempts=0;$entry.LiveStatus='';$entry.LiveInitialized=$false}
        if($script:HydraLivePrefs.AutoRemember){
            if(-not [TarginoLiveWindow]::StartWatching($handle,$entry.Proc.Id) -and -not $entry.LiveWatchError){Log 'AVISO' 'Windows nao permitiu observar o ajuste manual da janela do Hydra.';$entry.LiveWatchError=$true}
        }else{[TarginoLiveWindow]::StopWatching($entry.Proc.Id)}
        if($entry.LiveInitialized){HydraLiveObserve $entry;return}
        if((-not $entry.CoreSeen -and $entry.Start -and ((Get-Date)-$entry.Start).TotalSeconds -lt 2) -or [TarginoLiveWindow]::IsSizing($handle)){return}
        if($entry.LiveAttempts -ge 8){return}
        $p=$script:HydraLivePrefs
        $dimensions=HydraLiveDimensions $p
        $status=[TarginoLiveWindow]::Apply($handle,$entry.Proc.Id,[int]$dimensions.Width,[int]$dimensions.Height,[bool]$p.Center,[int]$p.X,[int]$p.Y)
        if($status -in @('applied','unchanged','does-not-fit-monitor','position-outside-monitor')){
            $entry.LiveInitialized=$true
            $entry.LiveObserved=[TarginoLiveWindow]::Measure($handle,$entry.Proc.Id)
            $entry.LiveCandidate=$null
            $entry.LiveLearnAfter=[Diagnostics.Stopwatch]::GetTimestamp()+[long]([Diagnostics.Stopwatch]::Frequency*2)
        }
        if($status -notin @('unchanged','not-visible')){
            $entry.LiveAttempts++
            if($entry.LiveStatus -ne $status){Log 'INFO' ('Perfil live do Hydra: '+$status+'; area cliente '+$dimensions.Width+'x'+$dimensions.Height+'; formato '+$p.AspectMode);$entry.LiveStatus=$status}
        }
    }catch{if(-not $entry.LiveError){Log 'AVISO' 'Nao foi possivel aplicar o perfil live; execucao do jogo preservada.';$entry.LiveError=$true}}
}
function HydraLiveObserve($entry){
    if(-not $script:HydraLivePrefs.AutoRemember -or -not [TarginoLiveWindow]::CanRemember($entry.LiveHandle,$entry.Proc.Id)){return}
    $geometry=[TarginoLiveWindow]::Measure($entry.LiveHandle,$entry.Proc.Id)
    if(-not $geometry){return}
    if(-not $entry.LiveObserved){$entry.LiveObserved=$geometry;return}
    $now=[Diagnostics.Stopwatch]::GetTimestamp()
    if($geometry.Width -eq $entry.LiveObserved.Width -and $geometry.Height -eq $entry.LiveObserved.Height){$entry.LiveCandidate=$null;return}
    if(-not $entry.LiveCandidate -or $geometry.Width -ne $entry.LiveCandidate.Width -or $geometry.Height -ne $entry.LiveCandidate.Height){
        $entry.LiveCandidate=$geometry;$entry.LiveCandidateSince=$now;return
    }
    if($now -lt $entry.LiveLearnAfter -or ($now-$entry.LiveCandidateSince)/[double][Diagnostics.Stopwatch]::Frequency -lt 0.8 -or [TarginoLiveWindow]::IsSizing($entry.LiveHandle)){return}
    HydraLiveRemember $entry $geometry
    $entry.LiveObserved=$geometry;$entry.LiveCandidate=$null
}
function HydraLiveRemember($entry,$geometry){
    if(-not $geometry -or -not $script:HydraLivePrefs.Enabled -or -not $script:HydraLivePrefs.AutoRemember){return}
    $entry.LiveInitialized=$true
    if($script:HydraLivePrefs.Width -eq $geometry.Width -and $script:HydraLivePrefs.Height -eq $geometry.Height){return}
    $prefs=$script:HydraLivePrefs.Clone();$prefs.Width=[int]$geometry.Width;$prefs.Height=[int]$geometry.Height
    if(WriteJson (Join-Path $DataDir 'hydra-live.json') $prefs 3){$script:HydraLivePrefs=$prefs;Log 'INFO' ('Tamanho manual do Hydra salvo: '+$prefs.Width+'x'+$prefs.Height)}
    $entry.LiveObserved=$geometry;$entry.LiveCandidate=$null
}
function HydraLiveFlush($entry){
    if($entry.Proc -and ('TarginoLiveWindow' -as [type])){HydraLiveRemember $entry ([TarginoLiveWindow]::TakePending($entry.Proc.Id))}
}
function HydraLiveEnd($entry){
    try{HydraLiveFlush $entry}finally{if($entry.Proc -and ('TarginoLiveWindow' -as [type])){[TarginoLiveWindow]::StopWatching($entry.Proc.Id)}}
}
function ShowHydraLiveSettings {
    param($Owner)
    if(-not $Owner){$Owner=$form}
    $p=$script:HydraLivePrefs
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Janela do Hydra para live';ClientSize='580,440';StartPosition='CenterParent';FormBorderStyle='FixedDialog';MaximizeBox=$false;MinimizeBox=$false;Font=(New-Object Drawing.Font('Segoe UI',10))}
    $enable=New-Object Windows.Forms.CheckBox -Property @{Text='Aplicar tamanho e posicao ao abrir jogos pelo launcher';Checked=[bool]$p.Enabled;Location='20,20';Size='540,30'}
    $hint=New-Object Windows.Forms.CheckBox -Property @{Text='Lembrar automaticamente o tamanho ajustado com o mouse';Checked=[bool]$p.AutoRemember;Location='20,60';Size='540,50'}
    $fields=@{};$specs=@(@('Width','Largura',160,7680,20,125),@('Height','Altura',120,4320,300,125),@('X','Posicao X',-32768,32768,20,202),@('Y','Posicao Y',-32768,32768,300,202))
    foreach($s in $specs){
        $label=New-Object Windows.Forms.Label -Property @{Text=$s[1];Location=(New-Object Drawing.Point($s[4],$s[5]));Size='95,26'}
        $number=New-Object Windows.Forms.NumericUpDown -Property @{Minimum=$s[2];Maximum=$s[3];Value=[Math]::Max($s[2],[Math]::Min($s[3],[int]$p[$s[0]]));Location=(New-Object Drawing.Point(($s[4]+100),$s[5]));Size='130,26'}
        $fields[$s[0]]=$number;$dialog.Controls.AddRange(@($label,$number))
    }
    $center=New-Object Windows.Forms.CheckBox -Property @{Text='Centralizar no monitor do Hydra (ignora X e Y)';Checked=[bool]$p.Center;Location='20,166';Size='540,28'}
    $aspectLabel=New-Object Windows.Forms.Label -Property @{Text='Formato';Location='20,247';Size='95,26'}
    $aspect=New-Object Windows.Forms.ComboBox -Property @{DropDownStyle='DropDownList';Location='120,244';Size='430,28'}
    [void]$aspect.Items.AddRange([object[]]@('Livre - tamanho salvo','4:3 - horizontal','16:9 - panoramico','3:4 - vertical','9:16 - vertical'))
    $modes=@('manual','4:3','16:9','3:4','9:16')
    $selected=[Array]::IndexOf($modes,[string]$p.AspectMode);if($selected -lt 0){$selected=0};$aspect.SelectedIndex=$selected
    $note=New-Object Windows.Forms.Label -Property @{Text="Em formato fixo, a largura e calculada a partir da altura ao abrir o jogo. No Hydra, mantenha Proporcao: Original. Nao detecta o formato do jogo automaticamente.`r`nDepois de abrir, mova e ajuste livremente. Nao remove bordas internas do jogo nem preenche um monitor largo sem esticar/cortar.";Location='20,285';Size='540,82'}
    $save=New-Object Windows.Forms.Button -Property @{Text='Salvar';Location='340,392';Size='100,32'}
    $cancel=New-Object Windows.Forms.Button -Property @{Text='Cancelar';Location='450,392';Size='100,32';DialogResult='Cancel'}
    $dialog.Controls.AddRange(@($enable,$hint,$center,$aspectLabel,$aspect,$note,$save,$cancel));$dialog.AcceptButton=$save;$dialog.CancelButton=$cancel
    $dialog.Tag=@{Enable=$enable;Center=$center;Fields=$fields;Remember=$hint;Aspect=$aspect;Modes=$modes;ManualWidth=[int]$fields.Width.Value}
    $aspect.Add_SelectedIndexChanged({param($sender,$eventArgs) HydraLivePreviewAspect $sender.FindForm()})
    $fields.Height.Add_ValueChanged({param($sender,$eventArgs) HydraLivePreviewAspect $sender.FindForm()})
    HydraLivePreviewAspect $dialog
    $save.Add_Click({param($sender,$eventArgs)
        $win=$sender.FindForm();$state=$win.Tag
        $prefs=@{Enabled=$state.Enable.Checked;Center=$state.Center.Checked;AutoRemember=$state.Remember.Checked;AspectMode=$state.Modes[$state.Aspect.SelectedIndex]}
        foreach($key in @('Width','Height','X','Y')){$prefs[$key]=[int]$state.Fields[$key].Value}
        $dimensions=HydraLiveDimensions $prefs
        if($dimensions.Width -lt 160 -or $dimensions.Width -gt 7680){[void][Windows.Forms.MessageBox]::Show($win,'Ajuste a altura: o formato escolhido deve produzir largura entre 160 e 7680 pixels.','Formato da janela');return}
        $prefs.Width=$dimensions.Width
        if(WriteJson (Join-Path $DataDir 'hydra-live.json') $prefs 3){$script:HydraLivePrefs=$prefs;$script:HydraLiveRevision++;$win.DialogResult='OK';$win.Close()}
    })
    try{[void]$dialog.ShowDialog($Owner)}finally{$dialog.Dispose();if($Owner -eq $form){[void]$grid.Focus()}else{[void]$Owner.Activate()}}
}
function HydraLivePreviewAspect($dialog){
    $state=$dialog.Tag;if(-not $state){return}
    $fixed=$state.Aspect.SelectedIndex -gt 0
    if($fixed){
        if($state.Fields.Width.Enabled){$state.ManualWidth=[int]$state.Fields.Width.Value}
        $state.Fields.Width.Enabled=$false
        $size=HydraLiveDimensions @{Height=[int]$state.Fields.Height.Value;Width=$state.ManualWidth;AspectMode=$state.Modes[$state.Aspect.SelectedIndex]}
        $state.Fields.Width.Value=[Math]::Max(160,[Math]::Min(7680,$size.Width))
    }elseif(-not $state.Fields.Width.Enabled){$state.Fields.Width.Enabled=$true;$state.Fields.Width.Value=$state.ManualWidth}
}
