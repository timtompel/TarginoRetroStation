# Perfis visuais do Targino RetroStation.
# Este módulo altera apenas preferências de aparência; catálogo, controles e integração Hydra permanecem intactos.
$script:ThemeProfiles = [ordered]@{
    'Moderno' = [ordered]@{
        Accent = '#00D9FF'; SelColor = '#00D9FF'; BgColor = '#08111F'; SideColor = '#111D2E'; TextColor = '#FFFFFF'; SubColor = '#9BA9B8'
        HeaderColor = '#00D9FF'; HeaderGlowColor = '#00D9FF'; HeaderLineColor = '#00D9FF'; DetailBg = '#0B1626'
        CinemaMode = $true; BackgroundImage = ''; HeaderFill = 'Degradê suave'; HeaderSize = 22; HeaderGlow = 35
        CoverFit = 'Preencher'; SelWidth = 3; SelGap = 3; SelBright = $true; GridCenter = $true
    }
    'Retrô Neon' = [ordered]@{
        Accent = '#FFB000'; SelColor = '#FFB000'; BgColor = '#0D0A12'; SideColor = '#21152A'; TextColor = '#FFF8E7'; SubColor = '#D2B8A3'
        HeaderColor = '#FF4D8D'; HeaderGlowColor = '#FF4D8D'; HeaderLineColor = '#FFB000'; DetailBg = '#160F1D'
        CinemaMode = $true; HeaderFill = 'Degradê suave'; HeaderSize = 22; HeaderGlow = 45
        CoverFit = 'Preencher'; SelWidth = 4; SelGap = 4; SelBright = $true; GridCenter = $true
    }
    'Clássico' = [ordered]@{
        Accent = '#4DA3FF'; SelColor = '#4DA3FF'; BgColor = '#0B0B0B'; SideColor = '#141414'; TextColor = '#FFFFFF'; SubColor = '#9A9A9A'
        HeaderColor = '#3BA4FF'; HeaderGlowColor = ''; HeaderLineColor = ''; DetailBg = '#0B0B0B'
        CinemaMode = $false; HeaderFill = 'Cor sólida'; HeaderSize = 20; HeaderGlow = 0
        CoverFit = 'Preencher'; SelWidth = 3; SelGap = 3; SelBright = $true; GridCenter = $false
    }
}
function SetThemeProfile([string]$name) {
    if (-not $script:ThemeProfiles.Contains($name)) { return $false }
    foreach ($key in $script:ThemeProfiles[$name].Keys) { $S[$key] = $script:ThemeProfiles[$name][$key] }
    $S.ThemeProfile = $name
    try { SaveSettings } catch { LogEx 'AVISO' "Não foi possível salvar o tema '$name'" $_ }
    try { ApplyLayout } catch { LogEx 'ERRO' "Não foi possível aplicar o tema '$name'" $_ }
    return $true
}
function AddThemeMenuItems($menu) {
    $menu.Items.Clear()
    foreach ($name in $script:ThemeProfiles.Keys) {
        $item = $menu.Items.Add($name)
        $item.Tag = $name
        $item.Add_Click({ param($sender,$eventArgs) SetThemeProfile "$($sender.Tag)" })
    }
    [void]$menu.Items.Add('-')
    $custom = $menu.Items.Add('Personalizado (manter ajustes)')
    $custom.Add_Click({ $S.ThemeProfile = 'Personalizado'; SaveSettings })
}
