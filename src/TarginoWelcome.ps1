# TarginoWelcome.ps1 — Tela de Apresentação e Ajuda Modernizada (v1.5.14)
$script:TarginoChannelUrl = 'https://www.youtube.com/@targino.socialmedia'
$script:TarginoWelcomeDialog = $null
$script:TarginoWelcomeTabIndex = 0

function Get-TarginoWelcomeStatePath {
    return (Join-Path $DataDir 'boas-vindas.json')
}

function Get-TarginoWelcomeShowOnStartup {
    $p = Get-TarginoWelcomeStatePath
    $st = ReadJson $p $false
    if ($null -ne $st -and $null -ne $st.ShowOnStartup) {
        return [bool]$st.ShowOnStartup
    }
    return $true
}

function Set-TarginoWelcomeShowOnStartup([bool]$show) {
    $p = Get-TarginoWelcomeStatePath
    [void](WriteJson $p @{ ShowOnStartup = $show; Version = '1.5.14' } 3)
}

function TarginoWelcomeInput([string]$key, $dialog) {
    if (-not $dialog -or $dialog.IsDisposed) { return }
    switch ($key) {
        'Left' {
            $next = [Math]::Max(0, $script:TarginoWelcomeTabIndex - 1)
            if ($dialog.Tag -and $dialog.Tag.SelectTab) { & $dialog.Tag.SelectTab $next }
        }
        'Right' {
            $next = [Math]::Min(5, $script:TarginoWelcomeTabIndex + 1)
            if ($dialog.Tag -and $dialog.Tag.SelectTab) { & $dialog.Tag.SelectTab $next }
        }
        'Escape' { $dialog.DialogResult = 'Cancel'; $dialog.Close() }
        'Return' { $dialog.DialogResult = 'OK'; $dialog.Close() }
    }
}

function ShowTarginoWelcome {
    if ($script:TarginoWelcomeDialog -and -not $script:TarginoWelcomeDialog.IsDisposed) {
        $script:TarginoWelcomeDialog.Activate()
        return
    }

    $verText = if ($AppVer) { "$AppVer" } else { '1.5.14' }
    $dlg = New-Object Windows.Forms.Form -Property @{
        Text = "TarginoRetroStation $verText — Apresentação e ajuda"
        ClientSize = New-Object Drawing.Size(1020, 670)
        MinimumSize = New-Object Drawing.Size(960, 640)
        StartPosition = 'CenterParent'
        FormBorderStyle = 'FixedDialog'
        MaximizeBox = $false
        MinimizeBox = $false
        BackColor = [Drawing.Color]::FromArgb(11, 17, 26)
        ForeColor = [Drawing.Color]::White
        KeyPreview = $true
        ShowIcon = $true
    }
    if ($form -and $form.Icon) { $dlg.Icon = $form.Icon }
    $script:TarginoWelcomeDialog = $dlg

    # Carrega imagens de Marca (Avatar e Banner grande)
    $avatarBmp = $null
    $avatarCandidates = @("$($S.AvatarImage)", (Join-Path $Arq 'Marca\avatar.png'))
    foreach ($ac in $avatarCandidates) {
        if ($ac -and [IO.File]::Exists($ac)) {
            try { $src = [Drawing.Image]::FromFile($ac); try { $avatarBmp = New-Object Drawing.Bitmap($src) } finally { $src.Dispose() }; break } catch {}
        }
    }

    $bannerBmp = $null
    $bannerCandidates = @((Join-Path $Arq 'Marca\banner.png'), (Join-Path $Arq 'Marca\fundo.jpg'), "$($S.BackgroundImage)")
    foreach ($bc in $bannerCandidates) {
        if ($bc -and [IO.File]::Exists($bc)) {
            try { $src = [Drawing.Image]::FromFile($bc); try { $bannerBmp = New-Object Drawing.Bitmap($src) } finally { $src.Dispose() }; break } catch {}
        }
    }

    # === 1. CABEÇALHO SUPERIOR ESCURO (86px) ===
    $topHdr = New-Object Windows.Forms.Panel -Property @{
        Dock = 'Top'; Height = 86; BackColor = [Drawing.Color]::FromArgb(15, 22, 34)
    }
    $hdMi = [Windows.Forms.Control].GetMethod('SetStyle', [Reflection.BindingFlags]'Instance,NonPublic')
    foreach ($st in 'UserPaint', 'AllPaintingInWmPaint', 'OptimizedDoubleBuffer', 'ResizeRedraw') {
        [void]$hdMi.Invoke($topHdr, @([Windows.Forms.ControlStyles]$st, $true))
    }

    if ($avatarBmp) {
        $avPic = New-Object Windows.Forms.PictureBox -Property @{
            Left = 24; Top = 12; Width = 62; Height = 62; SizeMode = 'Zoom';
            Image = $avatarBmp; BackColor = [Drawing.Color]::Transparent
        }
        $gp = New-Object Drawing.Drawing2D.GraphicsPath
        $gp.AddEllipse(0, 0, 62, 62)
        $avPic.Region = New-Object Drawing.Region($gp)
        $gp.Dispose()
        $topHdr.Controls.Add($avPic)
    }

    $topHdr.Add_Paint({
        param($snd, $pe)
        $g = $pe.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $linePen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(30, 44, 64), 1)
        try { $g.DrawLine($linePen, 0, ($snd.Height - 1), $snd.Width, ($snd.Height - 1)) } finally { $linePen.Dispose() }

        # Aro iluminado ao redor do Avatar
        $glowPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(75, 0, 210, 255), 4.0)
        $ringPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(0, 210, 255), 2.0)
        try {
            $g.DrawEllipse($glowPen, 22, 10, 66, 66)
            $g.DrawEllipse($ringPen, 23, 11, 64, 64)
        } finally { $glowPen.Dispose(); $ringPen.Dispose() }

        $tFont = New-Object Drawing.Font('Segoe UI', 19, [Drawing.FontStyle]::Bold)
        $bFont = New-Object Drawing.Font('Segoe UI', 8.5, [Drawing.FontStyle]::Bold)
        $sFont = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Regular)
        try {
            [Windows.Forms.TextRenderer]::DrawText(
                $g, 'Targino RetroStation', $tFont, (New-Object Drawing.Rectangle(102, 12, 310, 36)),
                [Drawing.Color]::FromArgb(115, 205, 255), ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix')
            )
            # Pílula de versão estável
            $pillRect = New-Object Drawing.Rectangle(408, 18, 112, 24)
            if ('TarginoHeaderGfx' -as [type]) {
                [TarginoHeaderGfx]::FillRounded($g, $pillRect, 6, [Drawing.Color]::FromArgb(20, 100, 138))
                [TarginoHeaderGfx]::DrawRounded($g, $pillRect, 6, [Drawing.Color]::FromArgb(45, 165, 215), 1.0)
            }
            [Windows.Forms.TextRenderer]::DrawText(
                $g, "$verText ESTÁVEL", $bFont, $pillRect, [Drawing.Color]::White,
                ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix')
            )
            [Windows.Forms.TextRenderer]::DrawText(
                $g, 'Complemento visual para o Hydra   •   Por Targino.SocialMedia', $sFont,
                (New-Object Drawing.Rectangle(104, 49, 520, 24)), [Drawing.Color]::FromArgb(175, 192, 212),
                ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix')
            )
        } finally {
            $tFont.Dispose(); $bFont.Dispose(); $sFont.Dispose()
        }
    })

    # === 2. BARRA DE ABAS 100% ESCURA (Sem bordas brancas do Windows) ===
    $tabBar = New-Object Windows.Forms.Panel -Property @{
        Dock = 'Top'; Height = 44; BackColor = [Drawing.Color]::FromArgb(12, 18, 28)
    }
    $tabBar.Add_Paint({
        param($snd, $pe)
        $p = New-Object Drawing.Pen([Drawing.Color]::FromArgb(28, 40, 58), 1)
        try { $pe.Graphics.DrawLine($p, 0, ($snd.Height - 1), $snd.Width, ($snd.Height - 1)) } finally { $p.Dispose() }
    })

    $tabNames = @('Apresentação', 'Primeiros passos', 'Controles', 'Personalização', 'Novidades', 'Créditos')
    $tabButtons = @()
    $tabX = 20
    for ($i = 0; $i -lt $tabNames.Count; $i++) {
        $btn = New-Object Windows.Forms.Button -Property @{
            Text = $tabNames[$i]; Tag = $i; Left = $tabX; Top = 4; Width = 148; Height = 39;
            FlatStyle = 'Flat'; Cursor = 'Hand'; TabStop = $false;
            Font = (New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold))
        }
        $btn.FlatAppearance.BorderSize = 0
        $btn.Add_Paint({
            param($snd, $pe)
            if ([int]$snd.Tag -eq $script:TarginoWelcomeTabIndex) {
                $barBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0, 212, 255))
                try { $pe.Graphics.FillRectangle($barBrush, 8, ($snd.Height - 3), ($snd.Width - 16), 3) } finally { $barBrush.Dispose() }
            }
        })
        $tabBar.Controls.Add($btn)
        $tabButtons += $btn
        $tabX += 152
    }

    # === 3. RODAPÉ INFERIOR ESCURO (66px) ===
    $footer = New-Object Windows.Forms.Panel -Property @{
        Dock = 'Bottom'; Height = 66; BackColor = [Drawing.Color]::FromArgb(15, 22, 34)
    }
    $footer.Add_Paint({
        param($snd, $pe)
        $p = New-Object Drawing.Pen([Drawing.Color]::FromArgb(30, 44, 64), 1)
        try { $pe.Graphics.DrawLine($p, 0, 0, $snd.Width, 0) } finally { $p.Dispose() }
    })

    $chkShow = New-Object Windows.Forms.CheckBox -Property @{
        Text = 'Mostrar ao abrir o launcher'; Left = 24; Top = 11; Width = 260; Height = 24;
        Checked = (Get-TarginoWelcomeShowOnStartup);
        ForeColor = [Drawing.Color]::FromArgb(225, 235, 245);
        Font = (New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Regular))
    }
    $chkShow.Add_CheckedChanged({ Set-TarginoWelcomeShowOnStartup $chkShow.Checked })

    $lblHint = New-Object Windows.Forms.Label -Property @{
        Text = 'Controle:  ← → alterna abas   •   A / Start / B: ir para biblioteca   |   Atalho para reabrir: F2 ou menu ⚙';
        Left = 24; Top = 38; Width = 540; Height = 20;
        ForeColor = [Drawing.Color]::FromArgb(135, 155, 180);
        Font = (New-Object Drawing.Font('Segoe UI', 8.5, [Drawing.FontStyle]::Regular))
    }

    $btnChannel = New-Object Windows.Forms.Button -Property @{
        Text = '▶  Conhecer meu canal'; Left = 576; Top = 14; Width = 200; Height = 38;
        FlatStyle = 'Flat'; Cursor = 'Hand';
        BackColor = [Drawing.Color]::FromArgb(172, 38, 56);
        ForeColor = [Drawing.Color]::White;
        Font = (New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold))
    }
    $btnChannel.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(225, 75, 95)
    $btnChannel.FlatAppearance.BorderSize = 1
    $btnChannel.Add_Click({
        try { [void][Diagnostics.Process]::Start((New-Object Diagnostics.ProcessStartInfo -Property @{ FileName = $script:TarginoChannelUrl; UseShellExecute = $true })) } catch {}
    })

    $btnLibrary = New-Object Windows.Forms.Button -Property @{
        Text = 'Ir para biblioteca'; Left = 792; Top = 14; Width = 204; Height = 38;
        FlatStyle = 'Flat'; Cursor = 'Hand'; DialogResult = 'OK';
        BackColor = [Drawing.Color]::FromArgb(0, 122, 195);
        ForeColor = [Drawing.Color]::White;
        Font = (New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold))
    }
    $btnLibrary.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(45, 185, 255)
    $btnLibrary.FlatAppearance.BorderSize = 1
    $btnLibrary.Add_Click({ $dlg.Close() })

    $footer.Controls.AddRange(@($chkShow, $lblHint, $btnChannel, $btnLibrary))

    # === 4. PAINEL CENTRAL DE CONTEÚDO (100% customizado em GDI+ sem barras brancas) ===
    $bodyPanel = New-Object Windows.Forms.Panel -Property @{
        Dock = 'Fill'; BackColor = [Drawing.Color]::FromArgb(11, 17, 26)
    }
    foreach ($st in 'UserPaint', 'AllPaintingInWmPaint', 'OptimizedDoubleBuffer', 'ResizeRedraw') {
        [void]$hdMi.Invoke($bodyPanel, @([Windows.Forms.ControlStyles]$st, $true))
    }

    $bodyPanel.Add_Paint({
        param($snd, $pe)
        $g = $pe.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $W = $snd.ClientSize.Width
        $H = $snd.ClientSize.Height
        $cyan = [Drawing.Color]::FromArgb(56, 189, 248)
        $white = [Drawing.Color]::White
        $soft = [Drawing.Color]::FromArgb(205, 218, 232)
        $muted = [Drawing.Color]::FromArgb(148, 168, 190)
        $cardBg = [Drawing.Color]::FromArgb(17, 26, 39)
        $cardBorder = [Drawing.Color]::FromArgb(34, 52, 76)

        $h1Font = New-Object Drawing.Font('Segoe UI', 16, [Drawing.FontStyle]::Bold)
        $h2Font = New-Object Drawing.Font('Segoe UI', 11.5, [Drawing.FontStyle]::Bold)
        $bodyFont = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Regular)
        $smallFont = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Regular)

        try {
            if ($script:TarginoWelcomeTabIndex -eq 0) {
                # === ABA 0: APRESENTAÇÃO (BANNER GRANDE 16:9 EM DESTAQUE + CARDS DE RECURSOS) ===
                [Windows.Forms.TextRenderer]::DrawText(
                    $g, 'Sua biblioteca. Seu controle. Seu jeito de jogar.', $h1Font,
                    (New-Object Drawing.Rectangle(24, 14, ($W - 48), 34)), $cyan,
                    ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix')
                )

                # Moldura panorâmica 16:9 grande para o Banner (540 x 304) à esquerda
                $banRect = New-Object Drawing.Rectangle(26, 58, 540, 304)
                if ('TarginoHeaderGfx' -as [type]) {
                    [TarginoHeaderGfx]::FillRounded($g, (New-Object Drawing.Rectangle(30, 63, 540, 304)), 10, [Drawing.Color]::FromArgb(140, 0, 0, 0))
                    [TarginoHeaderGfx]::FillRounded($g, $banRect, 10, $cardBg)
                }
                if ($bannerBmp) {
                    if ('TarginoHeaderGfx' -as [type]) {
                        $clipPath = [TarginoHeaderGfx]::RoundedRect($banRect, 10)
                        $oldClip = $g.Clip
                        $g.SetClip($clipPath, [Drawing.Drawing2D.CombineMode]::Intersect)
                        $g.DrawImage($bannerBmp, $banRect)
                        $g.Clip = $oldClip
                        $clipPath.Dispose()
                    } else {
                        $g.DrawImage($bannerBmp, $banRect)
                    }
                }
                if ('TarginoHeaderGfx' -as [type]) {
                    [TarginoHeaderGfx]::DrawRounded($g, $banRect, 10, [Drawing.Color]::FromArgb(95, 0, 210, 255), 1.6)
                }

                # Coluna da Direita: Boas-vindas + 4 Cards de Destaques
                $rx = 586
                $rw = $W - $rx - 26
                $introCard = New-Object Drawing.Rectangle($rx, 58, $rw, 114)
                if ('TarginoHeaderGfx' -as [type]) {
                    [TarginoHeaderGfx]::FillRounded($g, $introCard, 8, $cardBg)
                    [TarginoHeaderGfx]::DrawRounded($g, $introCard, 8, $cardBorder, 1.0)
                }
                [Windows.Forms.TextRenderer]::DrawText(
                    $g, "Bem-vindo ao Targino RetroStation $verText!", $h2Font,
                    (New-Object Drawing.Rectangle(($rx + 16), 68, ($rw - 32), 26)), $white,
                    ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix')
                )
                [Windows.Forms.TextRenderer]::DrawText(
                    $g, "Um complemento visual independente para organizar e iniciar os jogos da sua instalação do Hydra. Escolha o sistema, encontre o jogo e entre na diversão com teclado, mouse ou controle.",
                    $bodyFont, (New-Object Drawing.Rectangle(($rx + 16), 96, ($rw - 32), 70)), $soft,
                    ([Windows.Forms.TextFormatFlags]'Left,Top,WordBreak,NoPrefix')
                )

                # 4 Mini-Cards de Funcionalidades em Grade 2x2
                $feats = @(
                    @{ Title = 'Biblioteca por Sistemas'; Sub = 'Navegação rápida por cada console instalado' },
                    @{ Title = 'Capas e Detalhes';        Sub = '771 artes sincronizadas automaticamente' },
                    @{ Title = 'Favoritos e Busca';       Sub = 'Pesquisa instantânea no cabeçalho superior' },
                    @{ Title = 'Músicas e Visual';        Sub = 'Avatar iluminado, papel de parede e áudio' }
                )
                $fw = [int](($rw - 12) / 2)
                $fh = 84
                for ($f = 0; $f -lt 4; $f++) {
                    $col = $f % 2
                    $row = [int][Math]::Floor($f / 2.0)
                    $fx = $rx + $col * ($fw + 12)
                    $fy = 184 + $row * ($fh + 10)
                    $fRect = New-Object Drawing.Rectangle($fx, $fy, $fw, $fh)
                    if ('TarginoHeaderGfx' -as [type]) {
                        [TarginoHeaderGfx]::FillRounded($g, $fRect, 8, $cardBg)
                        [TarginoHeaderGfx]::DrawRounded($g, $fRect, 8, $cardBorder, 1.0)
                    }
                    $accentBar = New-Object Drawing.SolidBrush($cyan)
                    try { $g.FillRectangle($accentBar, $fx, ($fy + 14), 3, 22) } finally { $accentBar.Dispose() }
                    [Windows.Forms.TextRenderer]::DrawText(
                        $g, $feats[$f].Title, $h2Font, (New-Object Drawing.Rectangle(($fx + 12), ($fy + 10), ($fw - 20), 26)), $white,
                        ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis,SingleLine,NoPrefix')
                    )
                    [Windows.Forms.TextRenderer]::DrawText(
                        $g, $feats[$f].Sub, $smallFont, (New-Object Drawing.Rectangle(($fx + 12), ($fy + 38), ($fw - 20), 38)), $muted,
                        ([Windows.Forms.TextFormatFlags]'Left,Top,WordBreak,NoPrefix')
                    )
                }

                # Faixa Inferior de Canal e Segurança da Instalação (Largura Total)
                $botCard = New-Object Drawing.Rectangle(26, 378, ($W - 52), 82)
                if ('TarginoHeaderGfx' -as [type]) {
                    [TarginoHeaderGfx]::FillRounded($g, $botCard, 8, [Drawing.Color]::FromArgb(16, 25, 38))
                    [TarginoHeaderGfx]::DrawRounded($g, $botCard, 8, [Drawing.Color]::FromArgb(38, 60, 88), 1.0)
                }
                [Windows.Forms.TextRenderer]::DrawText(
                    $g, 'Conheça o Targino.SocialMedia no YouTube: tecnologia, IA e jogos retrô!', $h2Font,
                    (New-Object Drawing.Rectangle(44, 388, ($W - 88), 24)), $cyan,
                    ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix')
                )
                [Windows.Forms.TextRenderer]::DrawText(
                    $g, "Use o botão ""Conhecer meu canal"" abaixo — o navegador só abre quando você clicar.`r`nSeus arquivos do Hydra, cores, ROMs e BIOS permanecem 100% preservados na sua pasta original.",
                    $smallFont, (New-Object Drawing.Rectangle(44, 414, ($W - 88), 40)), $soft,
                    ([Windows.Forms.TextFormatFlags]'Left,Top,WordBreak,NoPrefix')
                )
            } else {
                # === ABAS 1 A 5: LAYOUT DE CARDS LIMPOS E ORGANIZADOS ===
                $tabInfo = switch ($script:TarginoWelcomeTabIndex) {
                    1 {
                        @{
                            Header = 'Primeiros passos para jogar'
                            Cards = @(
                                @{ T = '1. Escolha o seu Console no Carrossel'; D = 'Ao abrir o Targino RetroStation, navegue horizontalmente pelos sistemas disponíveis usando as setas do teclado, a roda do mouse ou o direcional do seu controle USB.' },
                                @{ T = '2. Explore as Capas da Biblioteca'; D = 'Pressione Enter (ou botão A no controle) sobre um sistema para exibir todos os jogos daquele console com suas respectivas capas sincronizadas.' },
                                @{ T = '3. Inicie o Jogo Imediatamente'; D = 'Pressione Enter / botão A (ou dê duplo clique na capa) para abrir o jogo diretamente no motor do Hydra. Ao fechar o jogo, o foco retorna automaticamente ao launcher.' },
                                @{ T = '4. Pesquisa Rápida e Menu ⚙ no Cabeçalho'; D = 'Use o campo "Pesquisar..." no topo direito para filtrar qualquer jogo pelo nome em tempo real, ou clique no botão ⚙ para trocar de sistema, atualizar a biblioteca e abrir opções.' }
                            )
                        }
                    }
                    2 {
                        @{
                            Header = 'Comandos do Controle USB, Teclado e Mouse'
                            Cards = @(
                                @{ T = 'Botão A  /  Tecla Enter  /  Duplo Clique'; D = 'Abre a lista de jogos do console selecionado ou inicia imediatamente o jogo em destaque no Hydra.' },
                                @{ T = 'Botão X  /  Tecla D'; D = 'Abre a janela de Detalhes do jogo selecionado (sinopse, sistema, capa ampliada e informações técnicas).' },
                                @{ T = 'Botão Y  /  Tecla F  /  Botão ⚙'; D = 'Abre o menu completo de Sistemas, Filtros (Favoritos, Recentes, Instalados) e Ferramentas do RetroStation.' },
                                @{ T = 'Botão B  /  Tecla Esc  |  F11 e F2'; D = 'Volta da lista de jogos para o carrossel de Sistemas. Pressione F11 para alternar Tela Cheia sem bordas e F2 para reabrir esta tela de ajuda.' }
                            )
                        }
                    }
                    3 {
                        @{
                            Header = 'Personalização Visual e Áudio Ambiente'
                            Cards = @(
                                @{ T = 'Avatar Circular Iluminado no Cabeçalho'; D = 'Clique diretamente sobre o seu Avatar no topo (ou acesse ⚙ > Personalizar launcher...) para escolher sua própria foto ou logotipo.' },
                                @{ T = 'Papel de Parede Personalizado'; D = 'Em ⚙ > Personalizar launcher..., você pode selecionar qualquer imagem Full HD / 4K para compor o fundo do modo cinema.' },
                                @{ T = 'Música Ambiente da Biblioteca'; D = 'Configure suas trilhas sonoras favoritas no painel de personalização; a música pausa sozinha quando um jogo é iniciado no Hydra e retoma ao voltar.' },
                                @{ T = 'Sincronização Automática de Capas'; D = 'O sincronizador busca capas oficiais em segundo plano e mantém 771+ artes salvas localmente em cache para carregamento instantâneo.' }
                            )
                        }
                    }
                    4 {
                        @{
                            Header = "Novidades da Versão $verText Estável"
                            Cards = @(
                                @{ T = 'Novo Cabeçalho Unificado e Organizado'; D = 'Ícone de controle colorido, indicador "Controle Conectado", Avatar circular com aro duplo ciano, busca integrada e botão rápido de configurações ⚙.' },
                                @{ T = 'Novo Rodapé com Botões Coloridos do Controle'; D = 'Barra inferior escura alinhada ao cabeçalho com ícones coloridos (A, X, Y, Select, B) clicáveis e contador de artes integrado à direita.' },
                                @{ T = 'Tela de Apresentação Reformulada'; D = 'Banner Targino.SocialMedia em formato widescreen de alta definição, abas 100% escuras sem bordas brancas e leitura direta sem barras de rolagem.' },
                                @{ T = 'Estabilidade Aprimorada com o Motor Hydra'; D = 'Encerramento automático de processos anteriores travados e permanência estável da janela do jogo após o redimensionamento.' }
                            )
                        }
                    }
                    5 {
                        @{
                            Header = 'Créditos e Projeto Targino.SocialMedia'
                            Cards = @(
                                @{ T = 'Idealização e Desenvolvimento — Emmanuel Targino'; D = 'Criado por Targino.SocialMedia para proporcionar uma experiência de console moderna, rápida e prática sobre a sua coleção no Hydra.' },
                                @{ T = 'Conteúdo sobre Tecnologia, IA e Jogos Retrô'; D = 'Acompanhe tutoriais, lives, dicas de emulação e inteligência artificial no canal oficial Targino.SocialMedia no YouTube.' },
                                @{ T = 'Respeito Total à sua Instalação'; D = 'O Targino RetroStation atua como um frontend visual limpo: não altera executáveis do emulador, não modifica suas ROMs e preserva suas configurações.' },
                                @{ T = 'Apoie e Compartilhe'; D = 'Clique no botão vermelho "▶ Conhecer meu canal" no rodapé desta janela para visitar o canal oficial no seu navegador.' }
                            )
                        }
                    }
                }

                [Windows.Forms.TextRenderer]::DrawText(
                    $g, $tabInfo.Header, $h1Font, (New-Object Drawing.Rectangle(28, 16, ($W - 56), 34)), $cyan,
                    ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix')
                )

                $cy = 64
                foreach ($c in $tabInfo.Cards) {
                    $cRect = New-Object Drawing.Rectangle(28, $cy, ($W - 56), 92)
                    if ('TarginoHeaderGfx' -as [type]) {
                        [TarginoHeaderGfx]::FillRounded($g, $cRect, 8, $cardBg)
                        [TarginoHeaderGfx]::DrawRounded($g, $cRect, 8, $cardBorder, 1.0)
                    }
                    $bar = New-Object Drawing.SolidBrush($cyan)
                    try { $g.FillRectangle($bar, 28, ($cy + 16), 4, 24) } finally { $bar.Dispose() }
                    [Windows.Forms.TextRenderer]::DrawText(
                        $g, $c.T, $h2Font, (New-Object Drawing.Rectangle(46, ($cy + 12), ($W - 92), 26)), $white,
                        ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix')
                    )
                    [Windows.Forms.TextRenderer]::DrawText(
                        $g, $c.D, $bodyFont, (New-Object Drawing.Rectangle(46, ($cy + 42), ($W - 92), 44)), $soft,
                        ([Windows.Forms.TextFormatFlags]'Left,Top,WordBreak,NoPrefix')
                    )
                    $cy += 102
                }
            }
        } finally {
            $h1Font.Dispose(); $h2Font.Dispose(); $bodyFont.Dispose(); $smallFont.Dispose()
        }
    })

    $selectTabFn = {
        param([int]$idx)
        $script:TarginoWelcomeTabIndex = [Math]::Max(0, [Math]::Min(5, $idx))
        for ($i = 0; $i -lt $tabButtons.Count; $i++) {
            $active = ($i -eq $script:TarginoWelcomeTabIndex)
            $tabButtons[$i].BackColor = if ($active) { [Drawing.Color]::FromArgb(24, 36, 54) } else { [Drawing.Color]::FromArgb(12, 18, 28) }
            $tabButtons[$i].ForeColor = if ($active) { [Drawing.Color]::White } else { [Drawing.Color]::FromArgb(155, 175, 198) }
            $tabButtons[$i].Invalidate()
        }
        $bodyPanel.Invalidate()
    }

    foreach ($btn in $tabButtons) {
        $btn.Add_Click({ param($s, $e) & $selectTabFn ([int]$s.Tag) })
    }

    $dlg.Tag = @{ SelectTab = $selectTabFn }
    & $selectTabFn 0

    $dlg.Add_KeyDown({
        param($s, $ke)
        if ($ke.KeyCode -in @('Left', 'Right', 'Escape', 'Return', 'F2')) {
            $ke.Handled = $true
            $ke.SuppressKeyPress = $true
            if ($ke.KeyCode -eq 'F2') { $dlg.Close(); return }
            TarginoWelcomeInput ([string]$ke.KeyCode) $dlg
        }
    })

    $dlg.Controls.Add($bodyPanel)
    $dlg.Controls.Add($tabBar)
    $dlg.Controls.Add($topHdr)
    $dlg.Controls.Add($footer)

    Log 'INFO' 'Apresentacao aberta'
    try {
        $res = $dlg.ShowDialog($form)
        Log 'INFO' "Apresentacao fechada (resultado: $res; janela principal ainda existe: $([bool]($form -and -not $form.IsDisposed)))"
    } finally {
        if ($avatarBmp) { $avatarBmp.Dispose() }
        if ($bannerBmp) { $bannerBmp.Dispose() }
        $script:TarginoWelcomeDialog = $null
        $dlg.Dispose()
        if ($form -and -not $form.IsDisposed) { [void]$grid.Focus() }
    }
}

function InitializeTarginoWelcome {
    $form.Add_KeyDown({
        param($s, $ke)
        if ($ke.KeyCode -eq 'F2' -and -not $ke.Control -and -not $ke.Alt) {
            $ke.Handled = $true
            $ke.SuppressKeyPress = $true
            ShowTarginoWelcome
        }
    })
    $form.Add_Shown({
        if (Get-TarginoWelcomeShowOnStartup) {
            $form.BeginInvoke([Action]{ ShowTarginoWelcome }) | Out-Null
        }
    })
}