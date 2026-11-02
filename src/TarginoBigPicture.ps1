# Targino RetroStation v1.5.17 — Auto-Perspectiva Responsiva + Menu Rápido Corrigido
if (-not ('TarginoHeaderGfx' -as [type])) {
    $refs = @(
        [System.Drawing.Bitmap].Assembly.Location,
        [System.Windows.Forms.Form].Assembly.Location
    )
    Add-Type -ReferencedAssemblies $refs -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;

public static class TarginoHeaderGfx {
    public static GraphicsPath RoundedRect(Rectangle r, int radius) {
        GraphicsPath path = new GraphicsPath();
        int d = radius * 2;
        if (d <= 0 || r.Width <= 0 || r.Height <= 0) { path.AddRectangle(r); return path; }
        if (d > r.Width) d = r.Width;
        if (d > r.Height) d = r.Height;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    public static void FillRounded(Graphics g, Rectangle r, int radius, Color fill) {
        if (r.Width <= 0 || r.Height <= 0) return;
        SmoothingMode old = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (GraphicsPath p = RoundedRect(r, radius))
        using (SolidBrush b = new SolidBrush(fill)) { g.FillPath(b, p); }
        g.SmoothingMode = old;
    }

    public static void DrawRounded(Graphics g, Rectangle r, int radius, Color border, float width) {
        if (r.Width <= 0 || r.Height <= 0) return;
        SmoothingMode old = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (GraphicsPath p = RoundedRect(r, radius))
        using (Pen pen = new Pen(border, width)) { g.DrawPath(pen, p); }
        g.SmoothingMode = old;
    }

    public static void DrawGamepadBadge(Graphics g, int x, int y, float scale) {
        SmoothingMode old = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int w = Math.Max(24, (int)(34 * scale));
        int h = Math.Max(16, (int)(22 * scale));
        using (SolidBrush bodyBrush = new SolidBrush(Color.FromArgb(62, 74, 92)))
        using (Pen bodyPen = new Pen(Color.FromArgb(90, 106, 128), 1.3f))
        using (SolidBrush dpadBrush = new SolidBrush(Color.FromArgb(22, 28, 38))) {
            Rectangle body = new Rectangle(x, y + 2, w, h);
            using (GraphicsPath gp = RoundedRect(body, Math.Max(5, (int)(9 * scale)))) {
                g.FillPath(bodyBrush, gp);
                g.DrawPath(bodyPen, gp);
            }
            int gripW = Math.Max(8, (int)(12 * scale));
            int gripH = Math.Max(11, (int)(16 * scale));
            g.FillEllipse(bodyBrush, x - 2, y + (int)(10 * scale), gripW, gripH);
            g.FillEllipse(bodyBrush, x + w - gripW + 2, y + (int)(10 * scale), gripW, gripH);
            g.FillRectangle(dpadBrush, x + (int)(6 * scale), y + (int)(11 * scale), Math.Max(5, (int)(8 * scale)), Math.Max(2, (int)(3 * scale)));
            g.FillRectangle(dpadBrush, x + (int)(8 * scale), y + (int)(9 * scale), Math.Max(2, (int)(3 * scale)), Math.Max(5, (int)(8 * scale)));
            int dot = Math.Max(2, (int)(3 * scale));
            using (SolidBrush bY = new SolidBrush(Color.FromArgb(241, 196, 15)))
            using (SolidBrush bX = new SolidBrush(Color.FromArgb(52, 152, 219)))
            using (SolidBrush bB = new SolidBrush(Color.FromArgb(231, 76, 60)))
            using (SolidBrush bA = new SolidBrush(Color.FromArgb(46, 204, 113))) {
                g.FillEllipse(bY, x + (int)(23 * scale), y + (int)(7 * scale), dot, dot);
                g.FillEllipse(bX, x + (int)(20 * scale), y + (int)(10 * scale), dot, dot);
                g.FillEllipse(bB, x + (int)(26 * scale), y + (int)(10 * scale), dot, dot);
                g.FillEllipse(bA, x + (int)(23 * scale), y + (int)(13 * scale), dot, dot);
            }
        }
        g.SmoothingMode = old;
    }

    public static void DrawMusicBadge(Graphics g, int x, int y, int size) {
        SmoothingMode old = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle badge = new Rectangle(x, y, size, size);
        FillRounded(g, badge, 10, Color.FromArgb(20, 44, 68));
        DrawRounded(g, badge, 10, Color.FromArgb(45, 130, 185), 1.0f);
        using (SolidBrush cyan = new SolidBrush(Color.FromArgb(0, 212, 255)))
        using (SolidBrush softCyan = new SolidBrush(Color.FromArgb(90, 200, 255))) {
            g.FillRectangle(softCyan, x + 10, y + 20, 3, 10);
            g.FillRectangle(cyan,     x + 15, y + 12, 3, 18);
            g.FillRectangle(softCyan, x + 20, y + 16, 3, 14);
            g.FillRectangle(cyan,     x + 25, y + 10, 3, 20);
        }
        g.SmoothingMode = old;
    }
}
"@
}

$script:ShowEmbeddedDetails = $true
$script:EmbeddedLastGameId = ''
$script:EmbeddedLastStamp = -1
$script:EmbeddedHoldTicks = 0
$script:EmbeddedProcess = $null
$script:UiScale = 1.0

function Get-ResponsiveScale {
    $fw = [Math]::Max(640, $form.ClientSize.Width)
    $fh = [Math]::Max(460, $form.ClientSize.Height)
    $sw = $fw / 1520.0
    $sh = $fh / 880.0
    return [Math]::Max(0.62, [Math]::Min(1.20, [Math]::Min($sw, $sh)))
}

function Format-CleanGameTitle([string]$raw) {
    if (-not $raw) { return @{ Title = ''; Badge = ''; Color = $null } }
    $t = $raw.Trim()
    $badge = ''
    $badgeCol = [Drawing.Color]::FromArgb(0, 150, 215)

    if ($t -match '(?i)\b(?:pt-?br|traduzid|portugues)\b') {
        $badge = 'PT-BR'
        $badgeCol = [Drawing.Color]::FromArgb(39, 174, 96)
    } elseif ($t -match '(?i)\bfast\s*rom\b') {
        $badge = 'FastROM'
        $badgeCol = [Drawing.Color]::FromArgb(0, 168, 232)
    } elseif ($t -match '(?i)\bhack\b') {
        $badge = 'Hack'
        $badgeCol = [Drawing.Color]::FromArgb(230, 126, 34)
    } elseif ($t -match '(?i)\((France|Japan|Europe|Brazil|Spain|Germany)\)') {
        $reg = $Matches[1]
        if ($reg -ieq 'Brazil') { $badge = 'BR'; $badgeCol = [Drawing.Color]::FromArgb(39, 174, 96) }
        elseif ($reg -ieq 'Japan') { $badge = 'JP'; $badgeCol = [Drawing.Color]::FromArgb(192, 57, 43) }
        elseif ($reg -ieq 'France') { $badge = 'FR'; $badgeCol = [Drawing.Color]::FromArgb(52, 152, 219) }
    }

    $clean = $t -replace '\s*\[[^\]]*\]', ''
    $clean = $clean -replace '\s*\([^)]*\)', ''
    $clean = $clean -replace '(?i)\s+PT-?BR.*$', ''
    $clean = $clean -replace '(?i)^(.+),\s*(The|A|An)$', '$2 $1'
    $clean = ($clean -replace '\s+', ' ').Trim()
    if (-not $clean) { $clean = $t }
    return @{ Title = $clean; Badge = $badge; Color = $badgeCol }
}

function Format-CardSystemName([string]$name) {
    if ($name -ieq 'Nintendo Entertainment System') { return 'NES (Nintendinho)' }
    if ($name -ieq 'Super Nintendo Entertainment System') { return 'Super Nintendo' }
    return $name
}

function BigPictureLayout {
    $script:BigPictureEnabled = $false
    $script:BigPictureSidebar = $false

    $fw = [Math]::Max(640, $form.ClientSize.Width)
    $fh = [Math]::Max(460, $form.ClientSize.Height)
    $sc = Get-ResponsiveScale
    $script:UiScale = $sc

    $hdrH = [int][Math]::Max(54, [Math]::Min(72, [Math]::Round(70 * $sc)))
    $hdr.Height = $hdrH
    $hdr.BackColor = [Drawing.Color]::FromArgb(15, 21, 30)

    if ($top) { $top.Visible = $false }
    if ($btnTheme) { $btnTheme.Visible = $false }
    if ($script:TarginoPersonalizeButton) { $script:TarginoPersonalizeButton.Visible = $false }
    if ($script:BigPictureButton) { $script:BigPictureButton.Visible = $false }

    if ($script:AvatarPic) {
        $avSz = [int][Math]::Max(40, [Math]::Min(56, $hdrH - 14))
        $avX = [int][Math]::Max(205, [Math]::Round(256 * ([Math]::Max(0.82, $sc))))
        $avY = [int](($hdrH - $avSz) / 2)
        $hdr.Controls.Add($script:AvatarPic)
        $script:AvatarPic.SetBounds($avX, $avY, $avSz, $avSz)
        $gp = New-Object Drawing.Drawing2D.GraphicsPath
        $gp.AddEllipse(0, 0, $avSz, $avSz)
        $script:AvatarPic.Region = New-Object Drawing.Region($gp)
        $gp.Dispose()
        $script:AvatarPic.Visible = [bool]$script:AvatarPic.Image
        $script:AvatarPic.BringToFront()
    }

    $ctrlH = [int][Math]::Max(26, [Math]::Min(32, $hdrH - 28))
    $ctrlY = [int](($hdrH - $ctrlH) / 2)
    $searchW = [int][Math]::Max(150, [Math]::Min(214, [Math]::Round(214 * $sc)))
    $btnW = [int][Math]::Max(30, [Math]::Min(36, $ctrlH + 4))

    if ($script:HeaderGearBtn) {
        $script:HeaderGearBtn.Visible = $true
        $script:HeaderGearBtn.SetBounds(($fw - $btnW - 14), $ctrlY, $btnW, $ctrlH)
        $script:HeaderGearBtn.BringToFront()
    }
    if ($script:HeaderSearchPanel) {
        $script:HeaderSearchPanel.Visible = $true
        $script:HeaderSearchPanel.SetBounds(($fw - $btnW - $searchW - 22), $ctrlY, $searchW, $ctrlH)
        if ($script:HeaderSearchBox) {
            $script:HeaderSearchBox.Width = $searchW - 20
            $script:HeaderSearchBox.Top = [int][Math]::Max(3, (($ctrlH - $script:HeaderSearchBox.Height) / 2))
        }
        $script:HeaderSearchPanel.BringToFront()
    }
    if ($script:HeaderMusicBtn) {
        $script:HeaderMusicBtn.Visible = $true
        $script:HeaderMusicBtn.SetBounds(($fw - ($btnW * 2) - $searchW - 30), $ctrlY, $btnW, $ctrlH)
        $script:HeaderMusicBtn.BringToFront()
    }

    $carouselH = [int][Math]::Max(218, [Math]::Min(368, [Math]::Round($fh * 0.43)))
    $libP.Dock = 'Bottom'
    $libP.Height = $carouselH
    $script:BackgroundPic.Dock = 'Fill'
    $script:BackgroundPic.Visible = $true

    $upperTop = $hdrH
    $upperAvailH = [Math]::Max(120, ($fh - $hdrH - $carouselH))

    if ($script:EmbeddedDetailsCard) {
        $marginV = [int][Math]::Max(8, [Math]::Min(18, $upperAvailH * 0.06))
        $cardH = [int][Math]::Max(150, [Math]::Min(285, ($upperAvailH - ($marginV * 2))))
        $cardW = [int][Math]::Max(410, [Math]::Min(680, [Math]::Round($fw * 0.55)))
        $cardX = [Math]::Max(14, ($fw - $cardW - 18))
        $cardY = $upperTop + [int](($upperAvailH - $cardH) / 2)

        $script:EmbeddedDetailsCard.SetBounds($cardX, $cardY, $cardW, $cardH)
        $gpE = [TarginoHeaderGfx]::RoundedRect((New-Object Drawing.Rectangle(0, 0, $cardW, $cardH)), [int][Math]::Max(8, (12 * $sc)))
        $script:EmbeddedDetailsCard.Region = New-Object Drawing.Region($gpE)
        $gpE.Dispose()
        $script:EmbeddedDetailsCard.Invalidate()
    }

    if ($script:TarginoNowPlaying) {
        $npW = [int][Math]::Max(310, [Math]::Min(420, [Math]::Round(420 * $sc)))
        $npH = [int][Math]::Max(52, [Math]::Min(68, [Math]::Round(68 * $sc)))
        $script:TarginoNowPlaying.Width = $npW
        $script:TarginoNowPlaying.Height = $npH
        $script:TarginoNowPlaying.Left = [Math]::Max(14, $fw - $npW - 18)
        $script:TarginoNowPlaying.Top = $hdrH + 8
        $gpN = [TarginoHeaderGfx]::RoundedRect((New-Object Drawing.Rectangle(0, 0, $npW, $npH)), 10)
        $script:TarginoNowPlaying.Region = New-Object Drawing.Region($gpN)
        $gpN.Dispose()
    }

    if ($script:GearOverlayPanel -and $script:GearOverlayPanel.Visible) {
        $ovW = [Math]::Min(640, ($fw - 28))
        $ovH = [Math]::Min(456, ($fh - $hdrH - 20))
        $script:GearOverlayPanel.SetBounds([Math]::Max(14, $fw - $ovW - 16), ($hdrH + 6), $ovW, $ovH)
        $script:GearOverlayPanel.BringToFront()
    }

    $hdr.Invalidate()
    $grid.Invalidate()
}

function BigPictureToggle { }
function BigPictureFocusMenu { }
function BigPictureFocusLibrary { }
function BigPictureHighlight { }
function BigPictureHero($gr) { }
function BigPictureInput([string]$key) { return $false }
function PaintBigPicture($gr) { }

function PaintCinema($gr) {
    DrawCinemaScene $gr $grid
    $script:CinemaHits = @()
    $script:CinemaLetterHits = @()
    $n = $script:View.Count
    if (-not $script:Cfg) { return }
    $W = [Math]::Max(600, $grid.ClientSize.Width)
    $H = [Math]::Max(200, $grid.ClientSize.Height)

    $gr.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gr.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $topStripH = [int][Math]::Max(26, [Math]::Min(36, [Math]::Round($H * 0.10)))
    $footerH   = [int][Math]::Max(32, [Math]::Min(42, [Math]::Round($H * 0.115)))
    $titleH    = [int][Math]::Max(28, [Math]::Min(44, [Math]::Round($H * 0.125)))
    $availCardH = [Math]::Max(105, ($H - $topStripH - $footerH - $titleH - 12))
    $cScale    = [Math]::Max(0.54, [Math]::Min(1.08, ($availCardH / 212.0)))

    if (-not $n) {
        $emptyFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(9.5, 12 * $cScale)), [Drawing.FontStyle]::Regular)
        try {
            $message = "Nenhum item encontrado neste filtro.`nLimpe a pesquisa no topo ou escolha outra opção no menu ⚙."
            [Windows.Forms.TextRenderer]::DrawText($gr, $message, $emptyFont, (New-Object Drawing.Rectangle(30, ($topStripH + 20), ($W - 60), 120)), [Drawing.Color]::Silver, ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,WordBreak,NoPrefix'))
        } finally { $emptyFont.Dispose() }
        return
    }

    $selectedIndex = [Math]::Max(0, [Math]::Min($n - 1, $script:CurIdx))
    $selItem = $script:View[$selectedIndex]

    $topStripRect = New-Object Drawing.Rectangle(0, 0, $W, $topStripH)
    $stripBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(210, 11, 17, 26))
    $stripLine = New-Object Drawing.Pen([Drawing.Color]::FromArgb(80, 40, 62, 88), 1)
    try {
        $gr.FillRectangle($stripBrush, $topStripRect)
        $gr.DrawLine($stripLine, 0, $topStripH, $W, $topStripH)
    } finally { $stripBrush.Dispose(); $stripLine.Dispose() }

    $spotTitleFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(8.5, [Math]::Min(10.5, 10.5 * $cScale))), [Drawing.FontStyle]::Bold)
    $letFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(7.0, [Math]::Min(8.2, 8.0 * $cScale))), [Drawing.FontStyle]::Bold)
    $cyan = [Drawing.Color]::FromArgb(0, 212, 255)
    $white = [Drawing.Color]::White
    $muted = [Drawing.Color]::FromArgb(165, 185, 208)

    try {
        if ($script:HydraHome) {
            $sysInfo = "$($selItem.Name.ToUpperInvariant())   •   $($selItem.Version) disponíveis   •   Sistema $($selectedIndex + 1) de $n"
            [Windows.Forms.TextRenderer]::DrawText(
                $gr, $sysInfo, $spotTitleFont, (New-Object Drawing.Rectangle(18, 0, ($W - 36), $topStripH)), $cyan,
                ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,EndEllipsis,SingleLine,NoPrefix')
            )
        } else {
            $sysName = HydraSystemLabel $script:HydraSystem
            $parsedSel = Format-CleanGameTitle "$($selItem.Name)"
            $leftStatus = "$sysName  ›  $($selItem.Name)   ($($selectedIndex + 1) / $n)"
            $lw = [int][Math]::Max(14, [Math]::Min(19, [Math]::Floor(($W * 0.42) / 27.0)))
            $totalLetW = 27 * $lw
            $showLetters = ($n -gt 10 -and $W -ge 720)
            $maxLeftW = if ($showLetters) { [Math]::Max(200, ($W - $totalLetW - 36)) } else { $W - 36 }

            [Windows.Forms.TextRenderer]::DrawText(
                $gr, $leftStatus, $spotTitleFont, (New-Object Drawing.Rectangle(16, 0, $maxLeftW, $topStripH)), $white,
                ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis,SingleLine,NoPrefix')
            )

            if ($showLetters) {
                $letters = @('#','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z')
                $curFirst = if ($parsedSel.Title.Length -gt 0) { $parsedSel.Title.Substring(0, 1).ToUpperInvariant() } else { '#' }
                if ($curFirst -notmatch '^[A-Z]$') { $curFirst = '#' }
                $startX = $W - $totalLetW - 12
                $letH = [Math]::Max(18, ($topStripH - 8))
                $letY = [int](($topStripH - $letH) / 2)
                for ($li = 0; $li -lt $letters.Count; $li++) {
                    $ch = $letters[$li]
                    $lx = $startX + $li * $lw
                    $lRect = New-Object Drawing.Rectangle($lx, $letY, ($lw - 1), $letH)
                    $isCurLet = ($ch -eq $curFirst)
                    if ($isCurLet) {
                        [TarginoHeaderGfx]::FillRounded($gr, $lRect, 4, [Drawing.Color]::FromArgb(0, 130, 195))
                    }
                    [Windows.Forms.TextRenderer]::DrawText(
                        $gr, $ch, $letFont, $lRect, $(if ($isCurLet) { $white } else { $muted }),
                        ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix')
                    )
                    $script:CinemaLetterHits += @{ Letter = $ch; Rect = $lRect }
                }
            }
        }
    } finally {
        $spotTitleFont.Dispose(); $letFont.Dispose()
    }

    $step = [int][Math]::Max(94, [Math]::Round(166 * $cScale))
    $mid = [int]($W / 2)
    $reach = [int][Math]::Ceiling(($W - 70) / [double]$step / 2.0) + 1
    $maxScreenSlots = $reach * 2 + 1
    $slotsToDraw = [Math]::Min($n, $maxScreenSlots)
    $minOffset = -[int][Math]::Floor(($slotsToDraw - 1) / 2.0)
    $maxOffset = ($slotsToDraw - 1) + $minOffset

    $fontSz = [single][Math]::Max(7.8, [Math]::Min(9.5, 9.5 * ([Math]::Pow($cScale, 0.45))))
    $fontSelSz = [single][Math]::Max(8.2, [Math]::Min(10.0, 10.0 * ([Math]::Pow($cScale, 0.45))))
    $font = New-Object Drawing.Font('Segoe UI', $fontSz, [Drawing.FontStyle]::Bold)
    $fontSel = New-Object Drawing.Font('Segoe UI', $fontSelSz, [Drawing.FontStyle]::Bold)
    $badgeFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(6.8, 7.5 * ([Math]::Pow($cScale, 0.4)))), [Drawing.FontStyle]::Bold)
    $pen = New-Object Drawing.Pen($cyan, ([single][Math]::Max(2.0, 3.0 * $cScale)))

    try {
        for ($offset = $minOffset; $offset -le $maxOffset; $offset++) {
            $realIdx = (($selectedIndex + $offset) % $n + $n) % $n
            $selected = ($offset -eq 0)
            $focus = if ($selected) { 1.0 } else { 0.0 }
            $size   = [int][Math]::Round((138 + 22 * $focus) * $cScale)
            $height = [int][Math]::Round((188 + 24 * $focus) * $cScale)
            $y      = $topStripH + [int][Math]::Round((26 - 20 * $focus) * $cScale)
            $x      = $mid + ($offset * $step) - [int]($size / 2)
            if (($x + $size) -lt -10 -or $x -gt ($W + 10)) { continue }

            $rect = New-Object Drawing.Rectangle($x, $y, $size, $height)
            $gm = $script:View[$realIdx]

            $fit = if ($gm.HydraArt -or $gm.HydraKind -eq 'system') { 'Ajustar' } else { $script:Cfg.Fit }
            $bmp = CoverGet (CoverPath $gm) 176 $fit
            if ($bmp) {
                $sourceW = [single]($bmp.Height * $size / [double]$height)
                $sourceX = [single](($bmp.Width - $sourceW) / 2.0)
                $gr.DrawImage($bmp, $rect, $sourceX, ([single]0), $sourceW, ([single]$bmp.Height), [Drawing.GraphicsUnit]::Pixel)
            } else {
                $gr.FillRectangle($script:Gx.Ph, $rect)
            }

            $parsed = Format-CleanGameTitle "$($gm.Name)"
            if ($gm.HydraKind -ne 'system' -and $parsed.Badge) {
                $bSz = [Windows.Forms.TextRenderer]::MeasureText($parsed.Badge, $badgeFont)
                $bw = $bSz.Width + [int][Math]::Max(8, 12 * $cScale)
                $bh = [int][Math]::Max(14, 18 * $cScale)
                $bRect = New-Object Drawing.Rectangle(($x + $size - $bw - 4), ($y + 5), $bw, $bh)
                [TarginoHeaderGfx]::FillRounded($gr, $bRect, 4, $parsed.Color)
                [Windows.Forms.TextRenderer]::DrawText(
                    $gr, $parsed.Badge, $badgeFont, $bRect, $white,
                    ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix')
                )
            }

            if ($selected) {
                $glowPen = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(55, 0, 212, 255)), ([single][Math]::Max(4.0, 7.0 * $cScale)))
                try { $gr.DrawRectangle($glowPen, $rect) } finally { $glowPen.Dispose() }
                $gr.DrawRectangle($pen, $rect)
            }

            if ($gm.HydraKind -ne 'system' -and ($U.Fav -contains $gm.Id)) {
                $fhBand = [int][Math]::Max(18, 22 * $cScale)
                $badgeRect = New-Object Drawing.Rectangle($x, ($y + $height - $fhBand), $size, $fhBand)
                $badgeBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(220, 8, 16, 25))
                try { $gr.FillRectangle($badgeBrush, $badgeRect) } finally { $badgeBrush.Dispose() }
                [Windows.Forms.TextRenderer]::DrawText(
                    $gr, '★ Favorito', $badgeFont, $badgeRect, [Drawing.Color]::FromArgb(255, 215, 0),
                    ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,EndEllipsis,SingleLine,NoPrefix')
                )
            }

            $displayTitle = if ($gm.HydraKind -eq 'system') { Format-CardSystemName "$($gm.Name)" } else { $parsed.Title }
            $titleTop = $y + $height + [int][Math]::Max(3, 5 * $cScale)
            $titleBox = New-Object Drawing.Rectangle(($x - 6), $titleTop, ($size + 12), ($H - $footerH - $titleTop - 2))
            [Windows.Forms.TextRenderer]::DrawText(
                $gr, $displayTitle, $(if ($selected) { $fontSel } else { $font }), $titleBox,
                $(if ($selected) { $white } else { [Drawing.Color]::FromArgb(200, 214, 230) }),
                ([Windows.Forms.TextFormatFlags]'HorizontalCenter,Top,WordBreak,EndEllipsis,NoPrefix')
            )

            $script:CinemaHits += @{ Index = $realIdx; Rect = $rect }
        }

        $arrW = [int][Math]::Max(24, [Math]::Round(32 * $cScale))
        $arrH = [int][Math]::Max(40, [Math]::Round(56 * $cScale))
        $arrY = $topStripH + [int](($availCardH - $arrH) / 2)
        $arrowFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(13, 18 * $cScale)), [Drawing.FontStyle]::Bold)
        try {
            $navL = New-Object Drawing.Rectangle(6, $arrY, $arrW, $arrH)
            $navR = New-Object Drawing.Rectangle(($W - $arrW - 6), $arrY, $arrW, $arrH)
            [TarginoHeaderGfx]::FillRounded($gr, $navL, 7, [Drawing.Color]::FromArgb(195, 15, 24, 38))
            [TarginoHeaderGfx]::DrawRounded($gr, $navL, 7, [Drawing.Color]::FromArgb(55, 110, 160), 1.0)
            [TarginoHeaderGfx]::FillRounded($gr, $navR, 7, [Drawing.Color]::FromArgb(195, 15, 24, 38))
            [TarginoHeaderGfx]::DrawRounded($gr, $navR, 7, [Drawing.Color]::FromArgb(55, 110, 160), 1.0)
            [Windows.Forms.TextRenderer]::DrawText($gr, '‹', $arrowFont, $navL, $cyan, ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix'))
            [Windows.Forms.TextRenderer]::DrawText($gr, '›', $arrowFont, $navR, $cyan, ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix'))
            $script:CinemaNavArrows = @(@{ Dir = -1; Rect = $navL }, @{ Dir = 1; Rect = $navR })
        } finally { $arrowFont.Dispose() }
    } finally {
        $font.Dispose(); $fontSel.Dispose(); $badgeFont.Dispose(); $pen.Dispose()
    }
}

function ShowCinemaDetails {
    if ($script:HydraHome) { return }
    $script:ShowEmbeddedDetails = -not [bool]$script:ShowEmbeddedDetails
    Update-EmbeddedDetails $true
}

function ShowHydraDetails($game) {
    ShowCinemaDetails
}

function Initialize-EmbeddedDetailsPanel {
    if ($script:EmbeddedDetailsCard) {
        try { $form.Controls.Remove($script:EmbeddedDetailsCard); $script:EmbeddedDetailsCard.Dispose() } catch {}
    }

    $panel = New-Object Windows.Forms.Panel -Property @{
        Visible = $false; Width = 620; Height = 250;
        BackColor = [Drawing.Color]::FromArgb(13, 20, 32);
        TabStop = $false
    }
    $hdMi = [Windows.Forms.Control].GetMethod('SetStyle', [Reflection.BindingFlags]'Instance,NonPublic')
    foreach ($st in 'UserPaint', 'AllPaintingInWmPaint', 'OptimizedDoubleBuffer', 'ResizeRedraw') {
        [void]$hdMi.Invoke($panel, @([Windows.Forms.ControlStyles]$st, $true))
    }

    $coverPic = New-Object Windows.Forms.PictureBox -Property @{
        SizeMode = 'Zoom'; BackColor = [Drawing.Color]::FromArgb(19, 28, 42); TabStop = $false
    }
    $snapPic = New-Object Windows.Forms.PictureBox -Property @{
        SizeMode = 'Zoom'; BackColor = [Drawing.Color]::FromArgb(19, 28, 42); TabStop = $false
    }
    $snapHint = New-Object Windows.Forms.Label -Property @{
        Dock = 'Fill'; TextAlign = 'MiddleCenter';
        ForeColor = [Drawing.Color]::FromArgb(140, 162, 188);
        Font = (New-Object Drawing.Font('Segoe UI', 8.0));
        Text = 'Prévia de gameplay'
    }
    $snapPic.Controls.Add($snapHint)

    $btnPlay = New-Object Windows.Forms.Button -Property @{
        Text = '▶ Jogar'; Width = 84; Height = 24;
        FlatStyle = 'Flat'; BackColor = [Drawing.Color]::FromArgb(0, 128, 198);
        ForeColor = [Drawing.Color]::White; Cursor = 'Hand'; TabStop = $false;
        Font = (New-Object Drawing.Font('Segoe UI', 8.0, [Drawing.FontStyle]::Bold))
    }
    $btnPlay.FlatAppearance.BorderSize = 0
    $btnPlay.Add_Click({ $gm = Sel; if ($gm) { Launch $gm }; [void]$grid.Focus() })

    $btnFav = New-Object Windows.Forms.Button -Property @{
        Text = '☆ Favoritar'; Width = 92; Height = 24;
        FlatStyle = 'Flat'; BackColor = [Drawing.Color]::FromArgb(24, 36, 52);
        ForeColor = [Drawing.Color]::White; Cursor = 'Hand'; TabStop = $false;
        Font = (New-Object Drawing.Font('Segoe UI', 8.0))
    }
    $btnFav.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(48, 72, 102)
    $btnFav.FlatAppearance.BorderSize = 1
    $btnFav.Add_Click({
        $gm = Sel
        if ($gm) { ToggleFav $gm; Update-EmbeddedDetails $true; $grid.Invalidate() }
        [void]$grid.Focus()
    })

    $panel.Controls.AddRange(@($coverPic, $snapPic, $btnPlay, $btnFav))
    $panel.Tag = @{
        Cover = $coverPic; CoverPath = '';
        Snap = $snapPic; SnapPath = ''; SnapHint = $snapHint;
        PlayBtn = $btnPlay; FavBtn = $btnFav;
        Title = ''; Console = ''; Genre = ''; Year = ''; Players = ''; Studio = ''
    }

    $panel.Add_Paint({
        param($snd, $pe)
        $g = $pe.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $W = [Math]::Max(320, $snd.Width)
        $H = [Math]::Max(140, $snd.Height)
        $st = $snd.Tag
        $pScale = [Math]::Max(0.65, [Math]::Min(1.05, ($H / 260.0)))

        $g.Clear([Drawing.Color]::FromArgb(13, 20, 32))

        $hdrBarH = [int][Math]::Max(32, [Math]::Min(44, [Math]::Round($H * 0.165)))
        $hdrBr = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(18, 28, 44))
        $sepPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(32, 48, 70), 1)
        try {
            $g.FillRectangle($hdrBr, 0, 0, $W, $hdrBarH)
            $g.DrawLine($sepPen, 0, $hdrBarH, $W, $hdrBarH)
        } finally { $hdrBr.Dispose(); $sepPen.Dispose() }

        $accentBr = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0, 212, 255))
        try { $g.FillRectangle($accentBr, 0, 0, 4, $H) } finally { $accentBr.Dispose() }

        $btnH = [int][Math]::Max(22, ($hdrBarH - 12))
        $btnY = [int](($hdrBarH - $btnH) / 2)
        $st.FavBtn.SetBounds(($W - 96 - 12), $btnY, 96, $btnH)
        $st.PlayBtn.SetBounds(($st.FavBtn.Left - 86 - 6), $btnY, 86, $btnH)

        $pad = [int][Math]::Max(8, [Math]::Round(12 * $pScale))
        $contentY = $hdrBarH + $pad
        $contentH = [Math]::Max(90, ($H - $contentY - $pad))

        $coverW = [int][Math]::Round($contentH * 0.70)
        $snapX  = 12 + $coverW + $pad
        $snapW  = [int][Math]::Round($contentH * 1.26)
        $infoX  = $snapX + $snapW + $pad
        $infoW  = [Math]::Max(115, ($W - $infoX - 10))
        if ($infoW -lt 130) {
            $infoW = 135
            $infoX = $W - $infoW - 10
            $snapW = [Math]::Max(110, ($infoX - $snapX - $pad))
        }

        $st.Cover.SetBounds(12, $contentY, $coverW, $contentH)
        $st.Snap.SetBounds($snapX, $contentY, $snapW, $contentH)

        $tFont   = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(9.5, 12.5 * $pScale)), [Drawing.FontStyle]::Bold)
        $lblFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(6.5, 7.2 * $pScale)), [Drawing.FontStyle]::Bold)
        $valFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(7.8, 9.0 * $pScale)), [Drawing.FontStyle]::Bold)
        $cyan = [Drawing.Color]::FromArgb(0, 212, 255)
        $white = [Drawing.Color]::White

        try {
            [Windows.Forms.TextRenderer]::DrawText(
                $g, $st.Title, $tFont, (New-Object Drawing.Rectangle(14, 0, ($st.PlayBtn.Left - 20), $hdrBarH)), $white,
                ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis,SingleLine,NoPrefix')
            )

            $fields = @(
                @{ L = 'CONSOLE';    V = $st.Console },
                @{ L = 'GÊNERO';     V = $st.Genre },
                @{ L = 'LANÇAMENTO'; V = $st.Year },
                @{ L = 'JOGADORES';  V = $st.Players },
                @{ L = 'ESTÚDIO';    V = $st.Studio }
            )
            $gapF = [int][Math]::Max(3, [Math]::Round(4 * $pScale))
            $pillH = [int][Math]::Floor(($contentH - ($gapF * 4)) / 5.0)
            $fy = $contentY
            foreach ($f in $fields) {
                $fRect = New-Object Drawing.Rectangle($infoX, $fy, $infoW, $pillH)
                [TarginoHeaderGfx]::FillRounded($g, $fRect, 5, [Drawing.Color]::FromArgb(19, 29, 44))
                [TarginoHeaderGfx]::DrawRounded($g, $fRect, 5, [Drawing.Color]::FromArgb(34, 50, 72), 1.0)
                $lblH = [int][Math]::Max(10, ($pillH * 0.42))
                [Windows.Forms.TextRenderer]::DrawText($g, $f.L, $lblFont, (New-Object Drawing.Rectangle(($infoX + 8), ($fy + 1), ($infoW - 14), $lblH)), $cyan, ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix'))
                [Windows.Forms.TextRenderer]::DrawText($g, $f.V, $valFont, (New-Object Drawing.Rectangle(($infoX + 8), ($fy + $lblH - 1), ($infoW - 14), ($pillH - $lblH))), $white, ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis,SingleLine,NoPrefix'))
                $fy += ($pillH + $gapF)
            }
        } finally {
            $tFont.Dispose(); $lblFont.Dispose(); $valFont.Dispose()
        }

        [TarginoHeaderGfx]::DrawRounded($g, (New-Object Drawing.Rectangle(0, 0, ($W - 1), ($H - 1))), [int][Math]::Max(8, (12 * $script:UiScale)), [Drawing.Color]::FromArgb(45, 110, 160), 1.5)
    })

    $form.Controls.Add($panel)
    $panel.BringToFront()
    $script:EmbeddedDetailsCard = $panel
}

function Update-EmbeddedDetails([bool]$force = $false) {
    $card = $script:EmbeddedDetailsCard
    if (-not $card) { return }

    if ($script:HydraHome -or -not $script:ShowEmbeddedDetails -or $script:View.Count -eq 0) {
        if ($card.Visible) { $card.Visible = $false }
        return
    }

    $gm = Sel
    if (-not $gm -or $gm.HydraKind -eq 'system') {
        if ($card.Visible) { $card.Visible = $false }
        return
    }

    if (-not $card.Visible) {
        BigPictureLayout
        $card.Visible = $true
        $card.BringToFront()
        if ($script:GearOverlayPanel -and $script:GearOverlayPanel.Visible) { $script:GearOverlayPanel.BringToFront() }
    }

    $cacheFile = HydraDetailsCachePath $gm
    $stamp = if ([IO.File]::Exists($cacheFile)) { [IO.File]::GetLastWriteTimeUtc($cacheFile).Ticks } else { 0 }
    $gameChanged = ("$($gm.Id)" -ne $script:EmbeddedLastGameId)

    if ($gameChanged) {
        $script:EmbeddedLastGameId = "$($gm.Id)"
        $script:EmbeddedHoldTicks = 0
    } else {
        $script:EmbeddedHoldTicks++
        if ($script:EmbeddedHoldTicks -eq 2) {
            try { $script:EmbeddedProcess = HydraDetailsStart $gm $false } catch {}
        }
    }

    if (-not $force -and -not $gameChanged -and $stamp -eq $script:EmbeddedLastStamp) { return }
    $script:EmbeddedLastStamp = $stamp

    $st = $card.Tag
    $parsed = Format-CleanGameTitle "$($gm.Name)"
    $st.Title = $parsed.Title
    $st.Console = HydraSystemLabel $gm.Version
    $st.FavBtn.Text = if ($U.Fav -contains $gm.Id) { '★ Favorito' } else { '☆ Favoritar' }

    $cPath = CoverPath $gm
    if ($cPath -ne $st.CoverPath) {
        $oldC = $st.Cover.Image; $st.Cover.Image = $null; if ($oldC) { $oldC.Dispose() }
        if ($cPath -and [IO.File]::Exists($cPath)) {
            try { $src = [Drawing.Image]::FromFile($cPath); try { $st.Cover.Image = New-Object Drawing.Bitmap($src) } finally { $src.Dispose() } } catch {}
        }
        $st.CoverPath = $cPath
    }

    $data = ReadJson $cacheFile $false
    $st.Genre = if ($data -and $data.Fields -and $data.Fields.genre) {
        switch ("$($data.Fields.genre)") {
            'Platform' { 'Plataforma' } 'Action' { 'Ação' } 'Adventure' { 'Aventura' }
            'Role-playing (RPG)' { 'RPG' } 'Sports' { 'Esportes' } 'Racing' { 'Corrida' }
            'Fighting' { 'Luta' } 'Shooter' { 'Tiro / Arcade' } default { "$($data.Fields.genre)" }
        }
    } else { 'Clássico Retrô' }

    $st.Year = if ($data -and $data.Fields -and $data.Fields.releaseyear) { "$($data.Fields.releaseyear)" } else { '—' }
    $pCnt = if ($data -and $data.Fields -and $data.Fields.maxusers) { "$($data.Fields.maxusers)" } else { '' }
    $st.Players = if ($pCnt) { "$pCnt " + $(if ($pCnt -eq '1') { 'Jogador' } else { 'Jogadores' }) } else { '1-2 Jogadores' }
    $st.Studio = if ($data -and $data.Fields -and $data.Fields.developer) { "$($data.Fields.developer)" }
                 elseif ($data -and $data.Fields -and $data.Fields.publisher) { "$($data.Fields.publisher)" } else { 'Original' }

    $snapPath = ''
    if ($gm.Shot) { $m = Full $gm.Shot; if ([IO.File]::Exists($m)) { $snapPath = $m } }
    if (-not $snapPath -and $data -and $data.Snapshot) {
        $cand = [IO.Path]::GetFullPath((Join-Path $Arq $data.Snapshot))
        if ([IO.File]::Exists($cand)) { $snapPath = $cand }
    }
    if ($snapPath -ne $st.SnapPath) {
        $oldS = $st.Snap.Image; $st.Snap.Image = $null; if ($oldS) { $oldS.Dispose() }
        if ($snapPath) {
            try { $srcS = [Drawing.Image]::FromFile($snapPath); try { $st.Snap.Image = New-Object Drawing.Bitmap($srcS) } finally { $srcS.Dispose() } } catch {}
        }
        $st.SnapPath = $snapPath
    }
    $st.SnapHint.Visible = (-not $st.Snap.Image)
    $busy = ($script:EmbeddedProcess -and -not $script:EmbeddedProcess.HasExited)
    $st.SnapHint.Text = if ($busy) { 'Sincronizando gameplay...' } else { 'Prévia de gameplay' }

    $card.Invalidate()
}

function Invoke-GearMenuAction([string]$code) {
    if ($script:GearOverlayPanel) { $script:GearOverlayPanel.Visible = $false }
    [void]$grid.Focus()
    if (-not $code) { return }
    if ($code.StartsWith('sys:')) {
        $folder = $code.Substring(4)
        HydraOpenSystem $folder
        return
    }
    switch ($code) {
        'nav:home'    { HydraShowSystems }
        'filter:all'  { if ($script:HydraHome) { $script:HydraHome = $false; $script:HydraSystem = '' }; SetFilter 'all'; Populate }
        'filter:fav'  { HydraRememberSelection; $script:HydraHome = $false; $script:HydraSystem = ''; SetFilter 'fav'; Populate }
        'filter:rec'  { if ($script:HydraHome) { $script:HydraHome = $false; $script:HydraSystem = '' }; SetFilter 'recent'; Populate }
        'tool:prefs'  { ShowTarginoPreferences }
        'tool:roms'   { HydraChooseRoms }
        'tool:art'    { HydraRetryArtwork }
        'tool:meta'   { if (Get-Command ShowHydraMetadataSettings -ErrorAction SilentlyContinue) { ShowHydraMetadataSettings } }
        'tool:reload' { HydraRestartFrontend }
        'tool:help'   { if (Get-Command ShowTarginoWelcome -ErrorAction SilentlyContinue) { ShowTarginoWelcome } else { Start-Process (Join-Path $Arq 'Manual.html') } }
        'tool:update' {
            $upCmd = Get-Command Check-RetroStationUpdate*, Show-RetroStationUpdate*, Start-RetroStationUpdate*, Invoke-RetroStationUpdate*, ShowRetroStationUpdate*, Update-HydraSystem -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($upCmd) { & $upCmd }
        }
    }
}

function Invoke-GearMenuAction([string]$code) {
    if ($script:GearOverlayPanel) { $script:GearOverlayPanel.Visible = $false }
    [void]$grid.Focus()
    if (-not $code) { return }
    if ($code.StartsWith('sys:')) {
        $folder = $code.Substring(4)
        HydraOpenSystem $folder
        return
    }
    switch ($code) {
        'nav:home'    { HydraShowSystems }
        'filter:all'  { if ($script:HydraHome) { $script:HydraHome = $false; $script:HydraSystem = '' }; SetFilter 'all'; Populate }
        'filter:fav'  { HydraRememberSelection; $script:HydraHome = $false; $script:HydraSystem = ''; SetFilter 'fav'; Populate }
        'filter:rec'  { if ($script:HydraHome) { $script:HydraHome = $false; $script:HydraSystem = '' }; SetFilter 'recent'; Populate }
        'tool:prefs'  { ShowTarginoPreferences }
        'tool:roms'   { HydraChooseRoms }
        'tool:art'    { HydraRetryArtwork }
        'tool:meta'   { if (Get-Command ShowHydraMetadataSettings -ErrorAction SilentlyContinue) { ShowHydraMetadataSettings } }
        'tool:reload' { HydraRestartFrontend }
        'tool:help'   { if (Get-Command ShowTarginoWelcome -ErrorAction SilentlyContinue) { ShowTarginoWelcome } else { Start-Process (Join-Path $Arq 'Manual.html') } }
        'tool:update' {
            $upCmd = Get-Command Check-RetroStationUpdate*, Show-RetroStationUpdate*, Start-RetroStationUpdate*, Invoke-RetroStationUpdate*, ShowRetroStationUpdate*, Update-HydraSystem -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($upCmd) { & $upCmd }
        }
    }
}

function FilterMenuShow { Show-ModernGearOverlay }
function Show-CompleteGearMenu { Show-ModernGearOverlay }

function Show-ModernGearOverlay {
    if ($script:GearOverlayPanel -and -not $script:GearOverlayPanel.IsDisposed) {
        if ($script:GearOverlayPanel.Visible) {
            $script:GearOverlayPanel.Visible = $false
            [void]$grid.Focus()
            return
        }
        $script:GearOverlayPanel.Dispose()
        $script:GearOverlayPanel = $null
    }

    $ovW = [Math]::Min(640, ($form.ClientSize.Width - 28))
    $ovH = [Math]::Min(456, ($form.ClientSize.Height - $hdr.Height - 20))
    $ov = New-Object Windows.Forms.Panel -Property @{
        Width = $ovW; Height = $ovH;
        Left = [Math]::Max(14, $form.ClientSize.Width - $ovW - 16);
        Top = ($hdr.Height + 6);
        BackColor = [Drawing.Color]::FromArgb(13, 20, 32);
        TabStop = $false; Anchor = 'Top,Right'
    }
    $hdMi = [Windows.Forms.Control].GetMethod('SetStyle', [Reflection.BindingFlags]'Instance,NonPublic')
    foreach ($st in 'UserPaint', 'AllPaintingInWmPaint', 'OptimizedDoubleBuffer', 'ResizeRedraw') {
        [void]$hdMi.Invoke($ov, @([Windows.Forms.ControlStyles]$st, $true))
    }

    $gpOv = [TarginoHeaderGfx]::RoundedRect((New-Object Drawing.Rectangle(0, 0, $ovW, $ovH)), 12)
    $ov.Region = New-Object Drawing.Region($gpOv)
    $gpOv.Dispose()

    $ov.Add_Paint({
        param($snd, $pe)
        $g = $pe.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $W = $snd.Width; $H = $snd.Height
        $g.Clear([Drawing.Color]::FromArgb(13, 20, 32))

        $hdrBr = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(18, 28, 44))
        $sepPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(30, 46, 68), 1)
        try {
            $g.FillRectangle($hdrBr, 0, 0, $W, 44)
            $g.DrawLine($sepPen, 0, 44, $W, 44)
            $g.DrawLine($sepPen, 318, 54, 318, ($H - 14))
        } finally { $hdrBr.Dispose(); $sepPen.Dispose() }

        $hFont = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
        $secFont = New-Object Drawing.Font('Segoe UI', 8.5, [Drawing.FontStyle]::Bold)
        $cyan = [Drawing.Color]::FromArgb(0, 212, 255)
        try {
            [Windows.Forms.TextRenderer]::DrawText($g, 'Menu Rápido  •  Sistemas, Filtros e Ajustes', $hFont, (New-Object Drawing.Rectangle(18, 8, 450, 28)), [Drawing.Color]::White, ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix'))
            [Windows.Forms.TextRenderer]::DrawText($g, 'FILTROS E CONSOLES', $secFont, (New-Object Drawing.Rectangle(18, 52, 280, 18)), $cyan, ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix'))
            [Windows.Forms.TextRenderer]::DrawText($g, 'FERRAMENTAS E OPÇÕES', $secFont, (New-Object Drawing.Rectangle(334, 52, 280, 18)), $cyan, ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix'))
        } finally { $hFont.Dispose(); $secFont.Dispose() }

        [TarginoHeaderGfx]::DrawRounded($g, (New-Object Drawing.Rectangle(0, 0, ($W - 1), ($H - 1))), 12, [Drawing.Color]::FromArgb(50, 130, 190), 1.6)
    })

    $btnClose = New-Object Windows.Forms.Button -Property @{
        Text = '✕'; Width = 32; Height = 28; Left = ($ovW - 42); Top = 8;
        FlatStyle = 'Flat'; BackColor = [Drawing.Color]::FromArgb(26, 38, 56);
        ForeColor = [Drawing.Color]::White; Cursor = 'Hand'; TabStop = $false
    }
    $btnClose.FlatAppearance.BorderSize = 0
    $btnClose.Add_Click({ $script:GearOverlayPanel.Visible = $false; [void]$grid.Focus() })
    $ov.Controls.Add($btnClose)

    # Filtros Rápidos com chamadas diretas via Invoke-GearMenuAction
    $quickFilters = @(
        @{ Text = '❖ Menu de Sistemas'; Code = 'nav:home' },
        @{ Text = "◈ Todos ($($script:FilCounts['all']))"; Code = 'filter:all' },
        @{ Text = "★ Favoritos ($($script:FilCounts['fav']))"; Code = 'filter:fav' },
        @{ Text = "◷ Recentes ($($script:FilCounts['recent']))"; Code = 'filter:rec' }
    )
    for ($qf = 0; $qf -lt $quickFilters.Count; $qf++) {
        $col = $qf % 2
        $row = [int][Math]::Floor($qf / 2.0)
        $b = New-Object Windows.Forms.Button -Property @{
            Text = $quickFilters[$qf].Text; Left = (18 + $col * 144); Top = (74 + $row * 34);
            Width = 138; Height = 29; FlatStyle = 'Flat'; Cursor = 'Hand'; TabStop = $false;
            BackColor = [Drawing.Color]::FromArgb(20, 31, 46); ForeColor = [Drawing.Color]::White;
            Font = (New-Object Drawing.Font('Segoe UI', 8.5, [Drawing.FontStyle]::Bold));
            TextAlign = 'MiddleLeft'; Padding = '6,0,0,0'; Tag = $quickFilters[$qf].Code
        }
        $b.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(38, 58, 84)
        $b.FlatAppearance.BorderSize = 1
        $b.Add_Click({ param($senderCtrl, $evtArgs) Invoke-GearMenuAction "$($senderCtrl.Tag)" })
        $ov.Controls.Add($b)
    }

    $sysListPanel = New-Object Windows.Forms.Panel -Property @{
        Left = 18; Top = 148; Width = 284; Height = ($ovH - 164);
        AutoScroll = $true; BackColor = [Drawing.Color]::FromArgb(13, 20, 32)
    }
    $sy = 0
    foreach ($card in $script:HydraSystemCards) {
        $isCurSys = (-not $script:HydraHome -and $script:HydraSystem -eq $card.HydraSystem)
        $sysBtn = New-Object Windows.Forms.Button -Property @{
            Text = "$(Format-CardSystemName $card.Name)   •   $($card.Version)";
            Left = 0; Top = $sy; Width = 264; Height = 32;
            FlatStyle = 'Flat'; Cursor = 'Hand'; TabStop = $false;
            BackColor = $(if ($isCurSys) { [Drawing.Color]::FromArgb(0, 108, 168) } else { [Drawing.Color]::FromArgb(19, 29, 44) });
            ForeColor = [Drawing.Color]::White;
            Font = (New-Object Drawing.Font('Segoe UI', 9, $(if ($isCurSys) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular })));
            TextAlign = 'MiddleLeft'; Padding = '12,0,0,0'; Tag = ("sys:" + $card.HydraSystem)
        }
        $sysBtn.FlatAppearance.BorderColor = if ($isCurSys) { [Drawing.Color]::FromArgb(0, 212, 255) } else { [Drawing.Color]::FromArgb(30, 44, 64) }
        $sysBtn.FlatAppearance.BorderSize = 1
        $sysBtn.Add_Click({ param($senderCtrl, $evtArgs) Invoke-GearMenuAction "$($senderCtrl.Tag)" })
        $sysListPanel.Controls.Add($sysBtn)
        $sy += 36
    }
    $ov.Controls.Add($sysListPanel)

    $tools = @(
        @{ Title = '❖  Personalizar Launcher';       Sub = 'Avatar, papel de parede e música MP3'; Code = 'tool:prefs' },
        @{ Title = '▸  Escolher Pasta de ROMs';      Sub = 'Alterar diretório de jogos do Hydra';  Code = 'tool:roms' },
        @{ Title = '↻  Sincronizar Artes Pendentes'; Sub = 'Baixar capas e capturas faltantes';     Code = 'tool:art' },
        @{ Title = '◈  Fontes de Dados e Cache';     Sub = 'Configurar Libretro e TheGamesDB';      Code = 'tool:meta' },
        @{ Title = '↻  Atualizar Biblioteca';        Sub = 'Recarregar catálogo de sistemas e ROMs'; Code = 'tool:reload' },
        @{ Title = '★  Apresentação e Ajuda (F2)';   Sub = 'Guia de controles, dicas e novidades';  Code = 'tool:help' },
        @{ Title = '▲  Verificar Atualizações';      Sub = 'Checar nova versão do RetroStation';    Code = 'tool:update' }
    )
    $ty = 74
    $btnH = [int][Math]::Max(38, [Math]::Min(48, [Math]::Floor(($ovH - 86) / 7.2)))
    foreach ($tl in $tools) {
        $tBtn = New-Object Windows.Forms.Button -Property @{
            Text = "$($tl.Title)`r`n      $($tl.Sub)";
            Left = 334; Top = $ty; Width = ($ovW - 348); Height = $btnH;
            FlatStyle = 'Flat'; Cursor = 'Hand'; TabStop = $false;
            BackColor = [Drawing.Color]::FromArgb(19, 29, 44);
            ForeColor = [Drawing.Color]::White;
            Font = (New-Object Drawing.Font('Segoe UI', 8.5, [Drawing.FontStyle]::Bold));
            TextAlign = 'MiddleLeft'; Padding = '10,2,6,2'; Tag = $tl.Code
        }
        $tBtn.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(36, 54, 78)
        $tBtn.FlatAppearance.BorderSize = 1
        $tBtn.Add_Click({ param($senderCtrl, $evtArgs) Invoke-GearMenuAction "$($senderCtrl.Tag)" })
        $ov.Controls.Add($tBtn)
        $ty += ($btnH + 4)
    }

    $form.Controls.Add($ov)
    $ov.BringToFront()
    $script:GearOverlayPanel = $ov
}

function TarginoNowPlayingTick([bool]$allowed) {
    $toast = $script:TarginoNowPlaying
    if (-not $toast) { return }
    $player = $script:TarginoMusicPlayer
    if (-not $allowed -or -not $player.IsOpen -or $player.IsPaused) {
        $toast.Visible = $false
        return
    }
    if ($script:TarginoNowPlayingVersion -ne $player.PlaybackVersion) {
        $script:TarginoNowPlayingVersion = $player.PlaybackVersion
        $rawName = [IO.Path]::GetFileNameWithoutExtension($player.CurrentTrack) -replace '_', ' '
        $script:TarginoCurrentTrackTitle = $rawName
        $toast.AccessibleName = 'Tocando agora: ' + $rawName
        $toast.Left = [Math]::Max(14, $form.ClientSize.Width - $toast.Width - 18)
        $toast.Top = $hdr.Height + 8
        $script:TarginoNowPlayingUntil = $script:TarginoClock.ElapsedMilliseconds + 5500
        $toast.Visible = $true
        $toast.BringToFront()
        $toast.Invalidate()
    } elseif ($script:TarginoClock.ElapsedMilliseconds -ge $script:TarginoNowPlayingUntil) {
        $toast.Visible = $false
    }
}

function PaintOrganizedHeader($gr, $snd) {
    $W = [Math]::Max(1, $snd.ClientSize.Width)
    $H = [Math]::Max(1, $snd.ClientSize.Height)
    $sc = Get-ResponsiveScale
    $gr.Clear([Drawing.Color]::FromArgb(15, 21, 30))
    $gr.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gr.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $linePen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(30, 42, 58), 1)
    try { $gr.DrawLine($linePen, 0, ($H - 1), $W, ($H - 1)) } finally { $linePen.Dispose() }

    $padScale = [single][Math]::Max(0.80, $sc)
    [TarginoHeaderGfx]::DrawGamepadBadge($gr, 16, ([int](($H - 26 * $padScale) / 2)), $padScale)

    $tx = [int][Math]::Max(52, (62 * $padScale))
    $titleFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(11.0, [Math]::Min(13.5, 13.5 * $padScale))), [Drawing.FontStyle]::Bold)
    try {
        [Windows.Forms.TextRenderer]::DrawText(
            $gr, 'Targino RetroStation', $titleFont,
            (New-Object Drawing.Rectangle($tx, ([int]($H * 0.12)), 195, ([int]($H * 0.42)))),
            [Drawing.Color]::White,
            ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix')
        )
    } finally { $titleFont.Dispose() }

    $pillW = [int][Math]::Max(108, (124 * $padScale))
    $pillH = [int][Math]::Max(17, (21 * $padScale))
    $pillY = [int]($H * 0.55)
    $pillRect = New-Object Drawing.Rectangle(($tx + 2), $pillY, $pillW, $pillH)
    [TarginoHeaderGfx]::FillRounded($gr, $pillRect, 6, [Drawing.Color]::FromArgb(28, 37, 50))
    [TarginoHeaderGfx]::DrawRounded($gr, $pillRect, 6, [Drawing.Color]::FromArgb(48, 62, 82), 1.0)
    $pillFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(7.0, 8.0 * $padScale)), [Drawing.FontStyle]::Regular)
    try {
        [Windows.Forms.TextRenderer]::DrawText(
            $gr, 'Controle Conectado', $pillFont, $pillRect,
            [Drawing.Color]::FromArgb(190, 204, 220),
            ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix')
        )
    } finally { $pillFont.Dispose() }

    if ($script:AvatarPic -and $script:AvatarPic.Visible) {
        $ax = $script:AvatarPic.Left; $ay = $script:AvatarPic.Top
        $aw = $script:AvatarPic.Width; $ah = $script:AvatarPic.Height
        $glowPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(70, 0, 210, 255), 3.5)
        $ringPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(120, 195, 235), 1.6)
        try {
            $gr.DrawEllipse($glowPen, ($ax - 2), ($ay - 2), ($aw + 4), ($ah + 4))
            $gr.DrawEllipse($ringPen, ($ax - 1), ($ay - 1), ($aw + 2), ($ah + 2))
        } finally { $glowPen.Dispose(); $ringPen.Dispose() }
    }
}

function PaintOrganizedFooter($gr, $snd) {
    if (-not $S.CinemaMode) { return }
    $W = [Math]::Max(1, $snd.ClientSize.Width)
    $H = [Math]::Max(1, $snd.ClientSize.Height)
    if ($H -lt 100) { return }

    $gr.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gr.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $footH = [int][Math]::Max(32, [Math]::Min(42, [Math]::Round($H * 0.115)))
    $footerY = $H - $footH
    $fScale = [Math]::Max(0.76, [Math]::Min(1.0, ($footH / 42.0)))

    $barBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(245, 15, 21, 30))
    $linePen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(30, 42, 58), 1)
    try {
        $gr.FillRectangle($barBrush, 0, $footerY, $W, $footH)
        $gr.DrawLine($linePen, 0, $footerY, $W, $footerY)
    } finally { $barBrush.Dispose(); $linePen.Dispose() }

    $script:CinemaFooterHits = @()
    $fichaLabel = if ($script:ShowEmbeddedDetails) { 'Ocultar Ficha' } else { 'Mostrar Ficha' }
    $items = @(
        @{ Key = 'A';      IsPill = $false; Label = $(if ($script:HydraHome) { 'Abrir' } else { 'Jogar' }); Color = [Drawing.Color]::FromArgb(39, 174, 96);  Action = 0; Width = [int](96 * $fScale) },
        @{ Key = 'X';      IsPill = $false; Label = $(if ($script:HydraHome) { 'Ficha' } else { $fichaLabel }); Color = [Drawing.Color]::FromArgb(41, 128, 185); Action = 1; Width = [int](122 * $fScale) },
        @{ Key = 'Y';      IsPill = $false; Label = 'Menu / Filtros'; Color = [Drawing.Color]::FromArgb(243, 156, 18); Action = 2; Width = [int](126 * $fScale) },
        @{ Key = 'Select'; IsPill = $true;  Label = 'Ações';    Color = [Drawing.Color]::FromArgb(52, 73, 94);   Action = 3; Width = [int](106 * $fScale) },
        @{ Key = 'B';      IsPill = $false; Label = $(if ($script:HydraHome) { 'Sistemas' } else { 'Voltar' }); Color = [Drawing.Color]::FromArgb(192, 57, 43); Action = 5; Width = [int](100 * $fScale) }
    )

    $totalW = 0
    foreach ($it in $items) { $totalW += $it.Width }
    $statusMaxW = [int][Math]::Min(290, ($W * 0.30))
    $centerX = [int](($W - $totalW) / 2)
    if ($script:HydraArtStatus -and ($centerX + $totalW) -gt ($W - $statusMaxW - 16)) {
        $centerX = [Math]::Max(12, ($W - $statusMaxW - $totalW - 20))
    }

    $keyFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(7.5, 8.5 * $fScale)), [Drawing.FontStyle]::Bold)
    $pillKeyFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(6.8, 7.5 * $fScale)), [Drawing.FontStyle]::Bold)
    $lblFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(8.0, 9.5 * $fScale)), [Drawing.FontStyle]::Regular)
    $white = [Drawing.Color]::White
    $lblColor = [Drawing.Color]::FromArgb(215, 225, 238)
    $cirSz = [int][Math]::Max(16, [Math]::Round(20 * $fScale))
    $by = $footerY + [int](($footH - $cirSz) / 2)

    try {
        $curX = $centerX
        foreach ($it in $items) {
            if ($it.IsPill) {
                $pw = [int][Math]::Max(34, (42 * $fScale))
                $pRect = New-Object Drawing.Rectangle($curX, $by, $pw, $cirSz)
                [TarginoHeaderGfx]::FillRounded($gr, $pRect, 5, $it.Color)
                [TarginoHeaderGfx]::DrawRounded($gr, $pRect, 5, [Drawing.Color]::FromArgb(90, 115, 140), 1.0)
                [Windows.Forms.TextRenderer]::DrawText($gr, $it.Key, $pillKeyFont, $pRect, $white, ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix'))
                $txtRect = New-Object Drawing.Rectangle(($curX + $pw + 5), $footerY, ($it.Width - $pw - 6), $footH)
            } else {
                $cBrush = New-Object Drawing.SolidBrush($it.Color)
                try { $gr.FillEllipse($cBrush, $curX, $by, $cirSz, $cirSz) } finally { $cBrush.Dispose() }
                [Windows.Forms.TextRenderer]::DrawText($gr, $it.Key, $keyFont, (New-Object Drawing.Rectangle($curX, $by, $cirSz, $cirSz)), $white, ([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix'))
                $txtRect = New-Object Drawing.Rectangle(($curX + $cirSz + 5), $footerY, ($it.Width - $cirSz - 6), $footH)
            }
            [Windows.Forms.TextRenderer]::DrawText($gr, $it.Label, $lblFont, $txtRect, $lblColor, ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix'))
            $hitRect = New-Object Drawing.Rectangle($curX, $footerY, $it.Width, $footH)
            $script:CinemaFooterHits += @{ Rect = $hitRect; Action = $it.Action }
            $curX += $it.Width
        }

        if ($script:HydraArtStatus) {
            $stFont = New-Object Drawing.Font('Segoe UI', ([single][Math]::Max(7.5, 8.5 * $fScale)), [Drawing.FontStyle]::Regular)
            try {
                $stRect = New-Object Drawing.Rectangle(($W - $statusMaxW - 12), $footerY, $statusMaxW, $footH)
                [Windows.Forms.TextRenderer]::DrawText($gr, $script:HydraArtStatus, $stFont, $stRect, [Drawing.Color]::FromArgb(140, 160, 184), ([Windows.Forms.TextFormatFlags]'Right,VerticalCenter,EndEllipsis,SingleLine,NoPrefix'))
            } finally { $stFont.Dispose() }
        }
    } finally {
        $keyFont.Dispose(); $pillKeyFont.Dispose(); $lblFont.Dispose()
    }
}

function Initialize-ModernNowPlayingCard {
    if ($script:TarginoNowPlaying) {
        try { $form.Controls.Remove($script:TarginoNowPlaying); $script:TarginoNowPlaying.Dispose() } catch {}
    }

    $card = New-Object Windows.Forms.Panel -Property @{
        Visible = $false; Width = 420; Height = 68;
        BackColor = [Drawing.Color]::FromArgb(14, 22, 34);
        Cursor = 'Hand'; TabStop = $false; Anchor = 'Top,Right'
    }
    $hdMi = [Windows.Forms.Control].GetMethod('SetStyle', [Reflection.BindingFlags]'Instance,NonPublic')
    foreach ($st in 'UserPaint', 'AllPaintingInWmPaint', 'OptimizedDoubleBuffer', 'ResizeRedraw') {
        [void]$hdMi.Invoke($card, @([Windows.Forms.ControlStyles]$st, $true))
    }

    $gp = [TarginoHeaderGfx]::RoundedRect((New-Object Drawing.Rectangle(0, 0, 420, 68)), 10)
    $card.Region = New-Object Drawing.Region($gp)
    $gp.Dispose()

    $card.Add_Paint({
        param($snd, $pe)
        $g = $pe.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $W = $snd.Width; $H = $snd.Height
        $g.Clear([Drawing.Color]::FromArgb(14, 22, 34))

        $accentBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0, 212, 255))
        try { $g.FillRectangle($accentBrush, 0, 0, 4, $H) } finally { $accentBrush.Dispose() }

        $bSz = [Math]::Max(28, ($H - 26))
        [TarginoHeaderGfx]::DrawMusicBadge($g, 14, ([int](($H - $bSz) / 2)), $bSz)

        $eyebrowFont = New-Object Drawing.Font('Segoe UI', 8, [Drawing.FontStyle]::Bold)
        $hintFont = New-Object Drawing.Font('Segoe UI', 7.5, [Drawing.FontStyle]::Regular)
        $songFont = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
        try {
            $tx = 22 + $bSz
            [Windows.Forms.TextRenderer]::DrawText($g, 'TOCANDO AGORA', $eyebrowFont, (New-Object Drawing.Rectangle($tx, 8, 150, 18)), [Drawing.Color]::FromArgb(0, 212, 255), ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,SingleLine,NoPrefix'))
            [Windows.Forms.TextRenderer]::DrawText($g, '» Próxima', $hintFont, (New-Object Drawing.Rectangle(($W - 95), 8, 82, 18)), [Drawing.Color]::FromArgb(120, 145, 175), ([Windows.Forms.TextFormatFlags]'Right,VerticalCenter,SingleLine,NoPrefix'))
            $title = if ($script:TarginoCurrentTrackTitle) { "$script:TarginoCurrentTrackTitle" } else { 'Reproduzindo música...' }
            [Windows.Forms.TextRenderer]::DrawText($g, $title, $songFont, (New-Object Drawing.Rectangle($tx, ([int]($H * 0.45)), ($W - $tx - 12), 24)), [Drawing.Color]::White, ([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis,SingleLine,NoPrefix'))
        } finally { $eyebrowFont.Dispose(); $hintFont.Dispose(); $songFont.Dispose() }

        [TarginoHeaderGfx]::DrawRounded($g, (New-Object Drawing.Rectangle(0, 0, ($W - 1), ($H - 1))), 10, [Drawing.Color]::FromArgb(45, 110, 160), 1.4)
    })

    $card.Add_Click({
        if ($script:TarginoMusicPlayer) {
            $script:TarginoMusicPlayer.Next()
            $script:TarginoNowPlayingVersion = -1
            TarginoMusicTick
        }
    })

    $form.Controls.Add($card)
    $card.BringToFront()
    $script:TarginoNowPlaying = $card
}

function InitializeBigPicture {
    $script:BigPictureEnabled = $false
    $script:BigPictureSidebar = $false

    Initialize-ModernNowPlayingCard
    Initialize-EmbeddedDetailsPanel

    $script:EmbeddedDetailsTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 160 }
    $script:EmbeddedDetailsTimer.Add_Tick({
        try { Update-EmbeddedDetails $false } catch {}
    })
    $script:EmbeddedDetailsTimer.Start()
    $form.Add_FormClosed({
        if ($script:EmbeddedDetailsTimer) { $script:EmbeddedDetailsTimer.Stop(); $script:EmbeddedDetailsTimer.Dispose() }
    })

    $script:HeaderMusicBtn = New-Object Windows.Forms.Button -Property @{
        Text = '♪'; Width = 36; Height = 32; Top = 20; FlatStyle = 'Flat';
        ForeColor = [Drawing.Color]::FromArgb(0, 212, 255);
        BackColor = [Drawing.Color]::FromArgb(20, 29, 42);
        Font = (New-Object Drawing.Font('Segoe UI', 10.5, [Drawing.FontStyle]::Bold));
        Cursor = 'Hand'; TabStop = $false
    }
    $script:HeaderMusicBtn.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(45, 65, 90)
    $script:HeaderMusicBtn.FlatAppearance.BorderSize = 1
    $script:HeaderMusicBtn.Add_Click({
        if ($script:TarginoMusicPlayer) {
            if (-not $script:TarginoMusicPlayer.Enabled) { ShowTarginoPreferences }
            else { $script:TarginoMusicPlayer.Next(); $script:TarginoNowPlayingVersion = -1; TarginoMusicTick }
        }
    })
    $hdr.Controls.Add($script:HeaderMusicBtn)

    $script:HeaderSearchPanel = New-Object Windows.Forms.Panel -Property @{
        Width = 214; Height = 32; Top = 20; BackColor = [Drawing.Color]::FromArgb(20, 27, 38)
    }
    $script:HeaderSearchPanel.Add_Paint({
        param($snd, $pe)
        $p = New-Object Drawing.Pen([Drawing.Color]::FromArgb(45, 60, 82), 1)
        try { $pe.Graphics.DrawRectangle($p, 0, 0, ($snd.Width - 1), ($snd.Height - 1)) } finally { $p.Dispose() }
    })
    $script:HeaderSearchBox = New-Object Windows.Forms.TextBox -Property @{
        Left = 10; Top = 7; Width = 194; BorderStyle = 'None';
        BackColor = [Drawing.Color]::FromArgb(20, 27, 38); ForeColor = [Drawing.Color]::White;
        Font = (New-Object Drawing.Font('Segoe UI', 9.0))
    }
    $script:HeaderSearchBox.Add_HandleCreated({ try { [CaCue]::Set($script:HeaderSearchBox.Handle, 'Pesquisar...') } catch {} })
    $script:HeaderSearchBox.Add_TextChanged({
        if ($q.Text -ne $script:HeaderSearchBox.Text) {
            $q.Text = $script:HeaderSearchBox.Text; Populate; $grid.Invalidate()
        }
    })
    $script:HeaderSearchBox.Add_KeyDown({
        param($snd, $ke)
        if ($ke.KeyCode -in @('Return', 'Down')) { $ke.SuppressKeyPress = $true; [void]$grid.Focus() }
        elseif ($ke.KeyCode -eq 'Escape') { $ke.SuppressKeyPress = $true; $script:HeaderSearchBox.Clear(); [void]$grid.Focus() }
    })
    $script:HeaderSearchPanel.Controls.Add($script:HeaderSearchBox)
    $hdr.Controls.Add($script:HeaderSearchPanel)

    $script:HeaderGearBtn = New-Object Windows.Forms.Button -Property @{
        Text = '⚙'; Width = 36; Height = 32; Top = 20; FlatStyle = 'Flat';
        ForeColor = [Drawing.Color]::FromArgb(220, 230, 242);
        BackColor = [Drawing.Color]::FromArgb(28, 38, 52);
        Font = (New-Object Drawing.Font('Segoe UI', 11.0));
        Cursor = 'Hand'; TabStop = $false
    }
    $script:HeaderGearBtn.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(70, 145, 190)
    $script:HeaderGearBtn.FlatAppearance.BorderSize = 1
    $script:HeaderGearBtn.Add_Click({ Show-ModernGearOverlay })
    $hdr.Controls.Add($script:HeaderGearBtn)

    $hdr.Add_Paint({ param($snd, $pe) PaintOrganizedHeader $pe.Graphics $snd })
    $grid.Add_Paint({ param($snd, $pe) PaintOrganizedFooter $pe.Graphics $snd })

    $form.Add_KeyDown({
        param($senderCtrl, $ke)
        if ($ke.KeyCode -eq 'Escape' -and $script:GearOverlayPanel -and $script:GearOverlayPanel.Visible) {
            $script:GearOverlayPanel.Visible = $false
            $ke.Handled = $true
            $ke.SuppressKeyPress = $true
            [void]$grid.Focus()
        }
    })

    $grid.Add_MouseDown({
        param($snd, $me)
        if ($script:GearOverlayPanel -and $script:GearOverlayPanel.Visible) {
            $script:GearOverlayPanel.Visible = $false
        }
        if (-not $S.CinemaMode -or $me.Button -ne 'Left') { return }
        if ($script:CinemaLetterHits) {
            foreach ($lh in $script:CinemaLetterHits) {
                if ($lh.Rect.Contains($me.Location)) {
                    $targetLet = $lh.Letter
                    for ($idx = 0; $idx -lt $script:View.Count; $idx++) {
                        $tClean = (Format-CleanGameTitle "$($script:View[$idx].Name)").Title
                        $firstCh = if ($tClean.Length -gt 0) { $tClean.Substring(0, 1).ToUpperInvariant() } else { '#' }
                        if ($targetLet -eq '#' -and $firstCh -notmatch '^[A-Z]$') { SelectIdx $idx 'single'; return }
                        elseif ($firstCh -ge $targetLet) { SelectIdx $idx 'single'; return }
                    }
                    return
                }
            }
        }
        if ($script:CinemaNavArrows -and $script:View.Count -gt 0) {
            foreach ($na in $script:CinemaNavArrows) {
                if ($na.Rect.Contains($me.Location)) {
                    $nCount = $script:View.Count
                    $nextIdx = (($script:CurIdx + $na.Dir) % $nCount + $nCount) % $nCount
                    SelectIdx $nextIdx 'single'
                    return
                }
            }
        }
    })

    $script:BackgroundPic.Add_MouseDown({
        if ($script:GearOverlayPanel -and $script:GearOverlayPanel.Visible) {
            $script:GearOverlayPanel.Visible = $false
            [void]$grid.Focus()
        }
    })

    $form.Add_Resize({ BigPictureLayout })
    $hdr.Add_Resize({ BigPictureLayout })
    $mainP.Add_Resize({ BigPictureLayout })
    BigPictureLayout
}