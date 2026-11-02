# Direct native launch; no simulated buttons or library-position-dependent sequences.
function HydraRendererInput([string]$key,$dialog){
    if(-not $dialog -or $dialog.IsDisposed){return}
    $state=$dialog.Tag
    switch($key){
        {$_ -in 'Up','Left'} {$state.Index=($state.Index+$state.Values.Count-1)%$state.Values.Count}
        {$_ -in 'Down','Right'} {$state.Index=($state.Index+1)%$state.Values.Count}
        'Return' {$state.Choice=$state.Values[$state.Index];$dialog.DialogResult='OK';$dialog.Close();return}
        'Escape' {$dialog.DialogResult='Cancel';$dialog.Close();return}
        default {return}
    }
    for($i=0;$i -lt $state.Values.Count;$i++){
        $state.Buttons[$i].BackColor=if($i -eq $state.Index){[Drawing.Color]::FromArgb(0,112,178)}else{[Drawing.Color]::FromArgb(28,35,49)}
    }
    [void]$state.Buttons[$state.Index].Focus()
}
function HydraCreateRendererDialog([string]$gameName,[string]$previous,[string]$system='ps2'){
    $dialog=New-Object Windows.Forms.Form -Property @{Text='PS2 - Como quer rodar?';StartPosition='CenterParent';ClientSize='600,370';FormBorderStyle='FixedDialog';MaximizeBox=$false;MinimizeBox=$false;ShowInTaskbar=$false;KeyPreview=$true;BackColor=[Drawing.Color]::FromArgb(13,18,28);ForeColor=[Drawing.Color]::White;Font=(New-Object Drawing.Font('Segoe UI',11))}
    $title=New-Object Windows.Forms.Label -Property @{Text='Como quer rodar este jogo de PS2?';Left=25;Top=20;Width=550;Height=35;Font=(New-Object Drawing.Font('Segoe UI',16,[Drawing.FontStyle]::Bold))}
    $name=New-Object Windows.Forms.Label -Property @{Text=$gameName;Left=27;Top=62;Width=545;Height=28;AutoEllipsis=$true}
    $hint=New-Object Windows.Forms.Label -Property @{Text='Direcional: escolher   A / Start / Enter: jogar   B / Esc: cancelar';Left=26;Top=326;Width=550;Height=30;ForeColor=[Drawing.Color]::Silver;Font=(New-Object Drawing.Font('Segoe UI',9))}
    $dialog.Controls.AddRange(@($title,$name,$hint))
    $values=@('software','hardware','opengl');$labels=@('Software','Vulkan','OpenGL')
    if($system -eq 'neogeo'){
        $values=@('aes','mvs');$labels=@('Console (AES)','Arcade (MVS)')
        $dialog.Text='Neo Geo - Como quer jogar?';$title.Text='Como quer jogar este jogo de Neo Geo?'
    }
    $dialog.ClientSize=New-Object Drawing.Size(600,(157+71*$values.Count))
    $hint.Top=113+71*$values.Count
    $index=[Array]::IndexOf($values,$previous);if($index -lt 0){$index=0}
    $state=@{Index=$index;Values=$values;Buttons=@();Choice=$null};$dialog.Tag=$state
    for($i=0;$i -lt $values.Count;$i++){
        $button=New-Object Windows.Forms.Button -Property @{Text=$labels[$i];Left=26;Top=(103+71*$i);Width=548;Height=58;FlatStyle='Flat';ForeColor=[Drawing.Color]::White;Tag=$i;TabIndex=$i}
        $button.BackColor=if($i -eq $index){[Drawing.Color]::FromArgb(0,112,178)}else{[Drawing.Color]::FromArgb(28,35,49)}
        $button.Add_Click({param($sender,$eventArgs) $win=$sender.FindForm();$win.Tag.Index=[int]$sender.Tag;HydraRendererInput 'Return' $win})
        $button.Add_Enter({param($sender,$eventArgs)
            $state=$sender.FindForm().Tag;$state.Index=[int]$sender.Tag
            for($n=0;$n -lt $state.Values.Count;$n++){$state.Buttons[$n].BackColor=if($n -eq $state.Index){[Drawing.Color]::FromArgb(0,112,178)}else{[Drawing.Color]::FromArgb(28,35,49)}}
        })
        $button.Add_PreviewKeyDown({param($sender,$eventArgs) if($eventArgs.KeyCode -in @('Left','Right','Up','Down')){$eventArgs.IsInputKey=$true}})
        $state.Buttons+= $button;$dialog.Controls.Add($button)
    }
    $dialog.Add_KeyDown({param($sender,$eventArgs) if($eventArgs.KeyCode.ToString() -in @('Up','Down','Left','Right','Return','Escape')){HydraRendererInput $eventArgs.KeyCode.ToString() $sender;$eventArgs.Handled=$true;$eventArgs.SuppressKeyPress=$true}})
    $dialog.Add_Shown({param($sender,$eventArgs) [void]$sender.Tag.Buttons[$sender.Tag.Index].Focus()})
    return $dialog
}
function HydraChooseStartupOption($game,[string]$system){
    $path=Join-Path $DataDir 'hydra-inicializacao.json'
    $saved=ReadJson $path $false
    $key=if($system -eq 'ps2'){'PS2Renderer'}else{'NeoGeoMode'}
    $previous=if($saved -and $saved.PSObject.Properties[$key]){[string]$saved.$key}else{''}
    $dialog=HydraCreateRendererDialog $game.Name $previous $system
    $script:HydraRendererDialog=$dialog
    try{
        if($dialog.ShowDialog($form) -ne 'OK'){return $null}
        $choice=[string]$dialog.Tag.Choice
        # Only remember focus, never skip the question or modify emulator settings.
        $preferences=@{}
        foreach($field in @('PS2Renderer','NeoGeoMode')){if($saved -and $saved.PSObject.Properties[$field]){$preferences[$field]=[string]$saved.$field}}
        $preferences[$key]=$choice
        [void](WriteJson $path $preferences 3)
        return $choice
    }finally{$script:HydraRendererDialog=$null;$dialog.Dispose();[void]$grid.Focus()}
}
function HydraGetLaunchPlan($game,[string]$exe) {
    $arguments=ArgsExpand $game.Args ([IO.Path]::GetDirectoryName($exe))
    if([IO.Path]::GetFileName($exe) -ine 'hydra.exe'){return @{Mode='direct';Arguments=$arguments}}
    $systemId=[string]$game.HydraSystemId
    if(-not $systemId -and $arguments -match '^--boot\s+([a-z0-9]+)\s+'){ $systemId=$Matches[1] }
    if($systemId -notin @('ps2','neogeo')){return @{Mode='direct';Arguments=$arguments}}
    if($arguments -notmatch '^--boot\s+(?<system>[a-z0-9]+)\s+"(?<rom>[^"\r\n]+)"\s*$'){throw 'Comando da ROM invalido para abertura direta.'}
    $rom=$Matches['rom'];$argumentSystem=$Matches['system']
    if($argumentSystem -ne $systemId){throw 'O sistema do jogo nao corresponde ao comando da ROM.'}
    # Neo Geo CD does not use cartridge AES/MVS options.
    if($systemId -eq 'neogeo' -and [IO.Path]::GetExtension($rom) -ine '.neo'){return @{Mode='direct';Arguments=$arguments}}
    return @{Mode='bridge-choice';Arguments=$arguments;System=$systemId;Rom=$rom}
}
function HydraLoadDirectBridge {
    if(-not ('HydraDirectBridge' -as [type])){
        $dll=Join-Path $Arq 'HydraDirectBridge.dll'
        if(-not [IO.File]::Exists($dll)){throw 'Adaptador de abertura direta ausente. Reinstale o TarginoRetroStation.'}
        Add-Type -Path $dll -ErrorAction Stop
    }
}
function HydraExitMessage($entry,[int]$code){
    $hex='0x'+([BitConverter]::ToUInt32([BitConverter]::GetBytes($code),0)).ToString('X8')
    $system=[string]$entry.Game.HydraSystemId
    $text="O Hydra encerrou com erro durante a execucao ou o fechamento de '$($entry.Name)'.`r`nCodigo: $code ($hex)."
    if($code -eq -1073741819){$text+="`r`nViolacao de acesso a memoria. Esse codigo, sozinho, nao identifica a causa nem comprova ROM ou BIOS defeituosa."}
    if($system -eq 'n64'){$text+="`r`nSistema: Nintendo 64. Esta configuracao usa Mupen64Plus-Next/ParaLLEl com Vulkan. Compare o mesmo jogo pelo menu original do Hydra e observe se o erro ocorre ao iniciar ou ao fechar."}
    elseif($system -eq 'ps2'){$text+="`r`nSistema: PlayStation 2. Confira a opcao de renderizacao escolhida e teste diretamente no Hydra."}
    $text+="`r`nConsulte TarginoRetroStation\Logs\launcher.log."
    return $text
}
function HydraPrepareLaunch($game,[string]$exe) {
    $plan=HydraGetLaunchPlan $game $exe
    if($plan.Mode -eq 'direct'){return $plan}
    HydraLoadDirectBridge
    $reason=[HydraDirectBridge]::GetCompatibilityReason($exe,[string]$plan.System)
    if($reason){return (HydraOfferNativeMenu $plan $reason)}
    $choice=HydraChooseStartupOption $game $plan.System
    if(-not $choice){return $null}
    $plan.Choice=$choice;$plan.Mode='bridge'
    return $plan
}
function HydraOfferNativeMenu($plan,[string]$reason){
    Log 'AVISO' ('Abertura direta indisponivel: '+$reason)
    $text="Este Hydra tem uma estrutura diferente da reconhecida para abertura direta. Nenhum ajuste sera aplicado.`r`n`r`nDeseja abrir o Hydra normalmente? Nesse modo, escolha o jogo e as opcoes dentro dele."
    $answer=[Windows.Forms.MessageBox]::Show($form,$text,'Abrir pelo Hydra',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Information)
    return (HydraNativeFallbackPlan $plan ($answer -eq [Windows.Forms.DialogResult]::Yes))
}
function HydraNativeFallbackPlan($plan,[bool]$accepted){
    if(-not $accepted){return $null}
    return @{Mode='direct';Arguments='';System=$plan.System;NativeMenu=$true}
}
function HydraStartDirectProcess([string]$exe,$plan){
    Log 'INFO' ("Abertura direta '$($plan.System)' / '$($plan.Choice)': $($plan.Arguments); sem navegacao simulada")
    return [HydraDirectBridge]::Start($exe,[string]$plan.System,[string]$plan.Rom,[string]$plan.Choice)
}
