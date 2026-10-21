# Public presentation and help. No privileged settings or credentials here.
$script:TarginoWelcomeVersion=[string](Get-Variable -Name AppVer -ValueOnly -ErrorAction SilentlyContinue)
if(-not $script:TarginoWelcomeVersion){throw 'A apresentacao requer a versao AppVer do launcher.'}
$script:TarginoChannelUrl='https://www.youtube.com/@targino.socialmedia'
function TarginoWelcomeContent {
    @(
        @{Tab='Apresentação';Title='Sua biblioteca. Seu controle. Seu jeito de jogar.';Banner=$true;Body=@'
Bem-vindo ao Targino RetroStation {Version}!

Um complemento visual independente para organizar e iniciar os jogos da sua instalação do Hydra. Escolha o sistema, encontre o jogo e entre na diversão com teclado, mouse ou controle.

Biblioteca por sistemas • Capas e detalhes • Favoritos e busca • Músicas e personalização

Conheça o Targino.SocialMedia no YouTube: tecnologia, IA e jogos retro. Use o botão “Conhecer meu canal” abaixo — o navegador só abre quando você clicar.

Hydra, cores, ROMs e BIOS não acompanham este projeto. Não é o aplicativo comercial Hydra Launcher.
'@}
        @{Tab='Primeiros passos';Title='Da instalação ao primeiro jogo';Body=@'
1. PREPARE O HYDRA
Salve hydra.exe na pasta escolhida e abra-o para concluir a instalação inicial. O site oficial é https://hydrafrontend.com/ e o download é https://hydrafrontend.com/hydra.exe. Se ele faltar, o instalador e o launcher mostram esses endereços.

2. INSTALE O COMPLEMENTO
Selecione a pasta que contém hydra.exe. O complemento fica em TarginoRetroStation, dentro dela. Prefira uma pasta em que seu usuário possa gravar. Não mova apenas a subpasta do complemento para outro local.

3. ORGANIZE SEUS JOGOS
Use as pastas de ROMs correspondentes aos sistemas e os cores preparados pelo Hydra. Somente sistemas com jogos reconhecidos aparecem. No menu Sistemas, você pode informar outra pasta de ROMs e atualizar a biblioteca.

4. ESCOLHA E JOGUE
Abra um sistema, selecione o jogo e confirme. Em PS2, escolha Software, OpenGL ou Vulkan conforme seu computador. Em Neo Geo cartucho .neo, escolha AES ou MVS. Neo Geo CD não usa essa escolha.

5. VOLTE À SUA BIBLIOTECA
Use “Voltar para biblioteca” no Hydra. Nas versões reconhecidas, o launcher detecta o jogo descarregado, fecha o Hydra e recupera o foco. Salve sua partida antes de sair.

O usuário é responsável por obter jogos e BIOS com as permissões aplicáveis. O complemento não fornece esses arquivos nem altera suas ROMs.
'@}
        @{Tab='Controles';Title='No sofá ou na mesa: você escolhe';Body=@'
CONTROLE — MAPEAMENTO PADRÃO
Direcional: navegar entre sistemas e jogos.
A / Start: confirmar ou jogar. B: voltar ou cancelar.
X: detalhes do jogo. Y: filtros.
Select: ações. Select + Y: buscar.
L1 / R1: saltar blocos na lista atual.

Os botões e o tamanho dos saltos podem ser ajustados nas opções de controle disponíveis na interface. A leitura do controle só acontece com o launcher em primeiro plano; conexão e desconexão são reconhecidas.

TECLADO E MOUSE
Setas: navegar. Enter: confirmar. Esc: voltar.
D: detalhes. F: filtros. F1: menu lateral.
F11: alternar entre janela e tela cheia.
F2: reabrir esta apresentação e os tutoriais.
Personalizar ou Ctrl + Shift + F12: preferências do usuário.

MENU LATERAL E BUSCA
À esquerda do primeiro jogo, pressione Esquerda para abrir o menu. Dentro dele, Direita ou B / Esc volta à mesma lista e seleção. A busca oferece teclado virtual para uso com controle.

NESTA APRESENTAÇÃO
Esquerda / Direita: mudar de aba. Cima / Baixo: rolar o texto.
A / Start / B: fechar e ir para a biblioteca.
Com teclado, use Tab para os botões e a caixa de exibição inicial.
'@}
        @{Tab='Personalização';Title='Seu espaço, sem complicação';Body=@'
FUNDO E AVATAR
Abra Personalizar e use “Procurar…” para escolher suas imagens. As preferências ficam salvas. O nome do frontend permanece Targino RetroStation.

MÚSICA DE FUNDO
Escolha uma pasta com MP3 ou WAV e ative a reprodução. A primeira faixa e a sequência são aleatórias, sem repetição dentro da rodada. O nome aparece quando uma faixa começa.
A música continua ao trocar de aplicativo, monitor ou minimizar o launcher. Pausa durante o Hydra aberto pelo launcher e continua do mesmo ponto quando ele fecha.

JANELAS PARA LIVE
F11 permite ajustar a janela do launcher. Seu tamanho e modo de tela são lembrados. Em Personalizar > Janela para live…, você pode ativar a memória do tamanho manual da janela do Hydra. Deixe a opção de centralização marcada se quiser centralizar na próxima abertura; durante a sessão, mova a janela livremente.
As medidas do Hydra são da área cliente, sem bordas. A janela precisa caber no monitor. O enquadramento no OBS continua sendo configurado por você.

FORMATO DA JANELA
Em Janela para live…, marque “Aplicar tamanho e posição” e escolha Formato. Com altura 720, 4:3 usa 960×720, 16:9 usa 1280×720, 3:4 usa 540×720 e 9:16 usa 405×720. No Hydra, mantenha Proporção: Original e Janela: Janela.
A escolha é manual e vale para os próximos jogos. Ao trocar para um jogo de outro formato, altere a opção e salve. Não há detecção automática por jogo. Depois de abrir, o ajuste manual continua livre. Para desativar o formato fixo, escolha Livre — tamanho salvo ou desligue o perfil.
O ajuste reduz o espaço preto causado pela janela em proporção diferente; não remove margens internas do próprio jogo/core. Preencher um monitor largo com um jogo 4:3 exige barras, corte ou distorção.

CAPAS, DADOS E CAPTURAS
As imagens são carregadas em segundo plano e guardadas localmente. A ficha técnica e a captura real de gameplay são consultadas ao abrir Detalhes. A cobertura depende das fontes; traduções e hacks podem usar informações do jogo original, com aviso.
As opções de fontes de dados e cache estão em Personalizar e Filtros. Uma chave opcional de serviço fica local e não acompanha a distribuição.

ATUALIZAR O COMPLEMENTO
Use Filtros > Verificar atualizações do RetroStation. A consulta automática ocorre diariamente em segundo plano; você confirma antes de instalar. Só releases estáveis assinadas do repositório TarginoRetroStation são aceitas. Seus dados são preservados e os arquivos substituídos recebem backup.
'@}
        @{Tab='Novidades';Title='Novidades desta versão';Body=@'
CAPAS E ARTES DO SISTEMA
Correspondencia de nomes melhorada: artigos, conectores e titulos traduzidos ou regionais confirmados por plataforma. Ausencias antigas sao consultadas novamente, sem apagar capas validas.
Quando nao houver capa confirmada, o jogo recebe uma arte neutra da propria plataforma, identificada como ARTE DO SISTEMA, nunca como capa oficial. O contador distingue downloads, falhas e artes do sistema.
PacMan de 3DO pode usar uma captura do Archive3DO como imagem alternativa. Jogos, BIOS, saves e configuracoes sao preservados.


INSTALADOR WEB
Baixa somente a ultima versao estavel, confere assinatura e hash e oferece Instalar. Possui cancelamento e nova tentativa. O Setup offline permanece disponivel; nao e atualizacao diferencial.

INSTALACAO MAIS SEGURA
Arquivos sao gravados em temporarios e verificados antes da substituicao. Reinstalar nao duplica backups de arquivos identicos. Backups anteriores e dados pessoais sao preservados.

LIMPEZA DA BASE
Retirados UpdateWinPort, campos antigos de atualizacao, adicao em massa de recompilados e instalacao de runtimes de jogos. A biblioteca continua compartilhando componentes visuais da base original.

ARTES SEM PYTHON
Capas, capturas e metadados usam alternativas HTTPS nativas do Windows, sem depender de Python ou Codex.

FILTROS E CACHE
Instalados/Nao instalados foram retirados; configuracoes antigas retornam a Todos os jogos. A limpeza conserva tres sessoes de download recentes e so retira sessoes concluidas ha mais de 30 dias, sem processos ativos ou arquivos desconhecidos. Nao apaga artes, backups, ROMs, BIOS ou saves.

MANTIDO
Big Picture, retorno a biblioteca, musica, janela para OBS e modos PS2/Neo Geo. Limitações dos cores permanecem: esta versao nao promete corrigir PS2 Software ou suporte de hardware.
'@}
        @{Tab='Créditos';Title='Targino.SocialMedia — tecnologia e jogos retro';Banner=$true;Body=@'
TarginoRetroStation • Projeto e identidade: Targino.SocialMedia.
Conheça meu canal: https://www.youtube.com/@targino.socialmedia
Se este projeto ajudou você, acompanhe os vídeos e compartilhe o canal!

Complemento independente para o Hydra Frontend. Hydra e os emuladores pertencem aos seus respectivos desenvolvedores. Não há afiliação oficial presumida.

Dados: libretro/libretro-database e TheGamesDB quando configurado.
Capas e capturas: libretro-thumbnails. Logos: libretro/retroarch-assets.
Jogos, marcas e artes de terceiros pertencem aos respectivos titulares. Nenhuma ROM ou BIOS acompanha o pacote.

O instalador não possui assinatura de editor. Confira a origem antes de executar e não desative as proteções do Windows para contornar avisos.
'@}
    )
}
function TarginoWelcomeShouldShow($state,[string]$version){
    return (-not $state -or -not $state.PSObject.Properties['LastSeenVersion'] -or $state.LastSeenVersion -ne $version -or [bool]$state.ShowOnStartup)
}
function TarginoWelcomeInput([string]$key,$dialog){
    switch($key){
        'Left' {$dialog.Tag.Tabs.SelectedIndex=[Math]::Max(0,$dialog.Tag.Tabs.SelectedIndex-1)}
        'Right' {$dialog.Tag.Tabs.SelectedIndex=[Math]::Min($dialog.Tag.Tabs.TabCount-1,$dialog.Tag.Tabs.SelectedIndex+1)}
        {$_ -in @('Up','Down')} {
            $text=$dialog.Tag.Tabs.SelectedTab.Tag
            $position=[Math]::Abs($text.AutoScrollPosition.Y)+$(if($key -eq 'Down'){90}else{-90})
            $limit=[Math]::Max(0,$text.Tag.Text.Height-$text.ClientSize.Height)
            $text.AutoScrollPosition=New-Object Drawing.Point(0,([Math]::Max(0,[Math]::Min($limit,$position))))
        }
        'Escape' {$dialog.Close()}
        'Return' {$dialog.Close()}
    }
}
function New-TarginoWelcomeDialog($state){
    $dialog=New-Object Windows.Forms.Form -Property @{Text=('TarginoRetroStation '+$script:TarginoWelcomeVersion+' — Apresentação e ajuda');ClientSize='1000,740';MinimumSize='850,680';StartPosition='CenterParent';BackColor=[Drawing.Color]::FromArgb(10,18,31);ForeColor=[Drawing.Color]::White;Font=(New-Object Drawing.Font('Segoe UI',11));KeyPreview=$true;MinimizeBox=$false}
    $header=New-Object Windows.Forms.Panel -Property @{Dock='Top';Height=104;BackColor=[Drawing.Color]::FromArgb(17,34,56)}
    $avatar=New-Object Windows.Forms.PictureBox -Property @{Left=16;Top=7;Width=88;Height=88;SizeMode='Zoom'}
    $owned=New-Object 'Collections.Generic.List[Drawing.Image]'
    $avatarPath=Join-Path $Arq 'Marca\avatar.png'
    if([IO.File]::Exists($avatarPath)){$source=[Drawing.Image]::FromFile($avatarPath);try{$avatar.Image=New-Object Drawing.Bitmap($source);$owned.Add($avatar.Image)}finally{$source.Dispose()}}
    $title=New-Object Windows.Forms.Label -Property @{Text='TarginoRetroStation';Left=120;Top=17;Width=650;Height=40;Font=(New-Object Drawing.Font('Segoe UI',25,[Drawing.FontStyle]::Bold));ForeColor=[Drawing.Color]::FromArgb(100,195,255)}
    $subtitle=New-Object Windows.Forms.Label -Property @{Text=($script:TarginoWelcomeVersion+' ESTÁVEL   •   Complemento para o Hydra   •   Por Targino.SocialMedia');Left=122;Top=64;Width=830;Height=28;Font=(New-Object Drawing.Font('Segoe UI',10))}
    $header.Controls.AddRange(@($avatar,$title,$subtitle))
    $tabs=New-Object Windows.Forms.TabControl -Property @{Dock='Fill';Padding=(New-Object Drawing.Point(17,9))}
    foreach($content in @(TarginoWelcomeContent)){
        $page=New-Object Windows.Forms.TabPage -Property @{Text=$content.Tab;BackColor=[Drawing.Color]::FromArgb(13,24,40);ForeColor=[Drawing.Color]::White;Padding=(New-Object Windows.Forms.Padding(20,12,20,12))}
        $heading=New-Object Windows.Forms.Label -Property @{Text=$content.Title;Dock='Top';Height=46;AutoEllipsis=$true;Font=(New-Object Drawing.Font('Segoe UI',17,[Drawing.FontStyle]::Bold));ForeColor=[Drawing.Color]::FromArgb(121,204,255)}
        $body=New-Object Windows.Forms.Panel -Property @{Dock='Fill';AutoScroll=$true;TabStop=$true;BackColor=$page.BackColor}
        $paragraph=New-Object Windows.Forms.Label -Property @{Text=$content.Body.Replace('{Version}',$script:TarginoWelcomeVersion);AutoSize=$true;MaximumSize=(New-Object Drawing.Size(900,0));ForeColor=[Drawing.Color]::FromArgb(225,234,245);Font=(New-Object Drawing.Font('Segoe UI',11));UseMnemonic=$false}
        $body.Controls.Add($paragraph);$body.Tag=@{Text=$paragraph}
        $body.Add_SizeChanged({param($sender,$eventArgs) $sender.Tag.Text.MaximumSize=New-Object Drawing.Size(([Math]::Max(200,$sender.ClientSize.Width-24)),0)})
        $page.Controls.Add($body)
        if($content.Banner){
            $banner=New-Object Windows.Forms.PictureBox -Property @{Dock='Top';Height=230;SizeMode='Zoom';BackColor=$page.BackColor}
            $bannerPath=Join-Path $Arq 'Marca\banner.png'
            if([IO.File]::Exists($bannerPath)){$source=[Drawing.Image]::FromFile($bannerPath);try{$banner.Image=New-Object Drawing.Bitmap($source);$owned.Add($banner.Image)}finally{$source.Dispose()}}
            $page.Controls.Add($banner)
        }
        $page.Controls.Add($heading);$page.Tag=$body;[void]$tabs.TabPages.Add($page)
    }
    $footer=New-Object Windows.Forms.Panel -Property @{Dock='Bottom';Width=1000;Height=89;BackColor=$header.BackColor}
    $remember=New-Object Windows.Forms.CheckBox -Property @{Text='Mostrar ao abrir o launcher';Checked=($null -eq $state -or [bool]$state.ShowOnStartup);Left=20;Top=14;Width=290;Height=27}
    $channel=New-Object Windows.Forms.Button -Property @{Text='Conhecer meu canal';Left=500;Top=12;Width=215;Height=36;Anchor='Top,Right';FlatStyle='Flat';BackColor=[Drawing.Color]::FromArgb(160,31,48);ForeColor=[Drawing.Color]::White}
    $channel.Add_Click({try{[void][Diagnostics.Process]::Start((New-Object Diagnostics.ProcessStartInfo -Property @{FileName=$script:TarginoChannelUrl;UseShellExecute=$true}))}catch{[void][Windows.Forms.MessageBox]::Show($script:TarginoChannelUrl,'Meu canal no YouTube')}})
    $start=New-Object Windows.Forms.Button -Property @{Text='Ir para biblioteca';Left=735;Top=12;Width=245;Height=36;Anchor='Top,Right';FlatStyle='Flat';BackColor=[Drawing.Color]::FromArgb(0,109,180);ForeColor=[Drawing.Color]::White}
    $start.Add_Click({param($sender,$eventArgs) $sender.FindForm().Close()})
    $hint=New-Object Windows.Forms.Label -Property @{Text='Controle: ← → abas  •  ↑ ↓ texto  •  A / Start / B: biblioteca   |   Reabrir: menu Ajuda e novidades ou F2';Left=20;Top=59;Width=950;Height=22;Font=(New-Object Drawing.Font('Segoe UI',9));ForeColor=[Drawing.Color]::Silver}
    $footer.Controls.AddRange(@($remember,$channel,$start,$hint))
    $dialog.Controls.AddRange(@($tabs,$footer,$header))
    $dialog.Tag=@{Tabs=$tabs;Remember=$remember;OwnedImages=$owned}
    $dialog.Add_FormClosed({param($sender,$eventArgs) foreach($img in $sender.Tag.OwnedImages){$img.Dispose()}})
    $dialog.Add_KeyDown({param($sender,$key)
        if($key.KeyCode -eq 'Escape'){$key.Handled=$true;$key.SuppressKeyPress=$true;TarginoWelcomeInput 'Escape' $sender}
    })
    return $dialog
}
function ShowTarginoWelcome([switch]$Automatic){
    if($script:TarginoWelcomeDialog -and -not $script:TarginoWelcomeDialog.IsDisposed){return}
    $path=Join-Path $DataDir 'apresentacao.json';$state=ReadJson $path $false
    if($Automatic -and -not (TarginoWelcomeShouldShow $state $script:TarginoWelcomeVersion)){return}
    $dialog=New-TarginoWelcomeDialog $state;$script:TarginoWelcomeDialog=$dialog
    if($Automatic -and $state -and $state.LastSeenVersion -ne $script:TarginoWelcomeVersion){$dialog.Tag.Tabs.SelectedIndex=4}
    try{
        [void]$dialog.ShowDialog($form)
        [void](WriteJson $path @{ShowOnStartup=[bool]$dialog.Tag.Remember.Checked;LastSeenVersion=$script:TarginoWelcomeVersion} 3)
    }finally{$script:TarginoWelcomeDialog=$null;$dialog.Dispose();if(-not $form.IsDisposed){[void]$grid.Focus()}}
}
function InitializeTarginoWelcome {
    $form.Add_Shown({[void]$form.BeginInvoke([Action]{try{ShowTarginoWelcome -Automatic}catch{LogEx 'AVISO' 'Nao foi possivel abrir a apresentacao' $_}})})
    $form.Add_KeyDown({param($sender,$key) if($key.KeyCode -eq 'F2'){$key.Handled=$true;$key.SuppressKeyPress=$true;ShowTarginoWelcome}})
}
