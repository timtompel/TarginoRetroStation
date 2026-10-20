Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$AppVer = '1.5.0'
$script:T0 = [Diagnostics.Stopwatch]::StartNew()      # tempo de abertura (vai para o log e para o diagnóstico)
# O Launcher.ps1 fica em TarginoRetroStation\; a pasta do launcher ($Root) é a de cima (onde ficam só o executável e Jogos\).
#  Tudo é relativo a $Root: a pasta pode ser copiada para outro HD ou renomeada.
$ArqName = 'TarginoRetroStation'
$Arq = $PSScriptRoot.TrimEnd('\'); $Root = [IO.Path]::GetDirectoryName($Arq).TrimEnd('\')
$script:SelfPath = $PSCommandPath
$hydraHelpModule=Join-Path $Arq 'HydraInstallHelp.ps1'
if(-not [IO.File]::Exists((Join-Path $Root 'hydra.exe')) -and [IO.File]::Exists($hydraHelpModule)){
    . $hydraHelpModule
    if(-not (Show-HydraInstallHelp $Root)){return}
}
function ArqDir($nm) { [IO.Path]::Combine($Arq, $nm) }
# Executável do launcher na raiz. Pode ter sido renomeado (ex.: "TarginoRetroStation - WinPort.exe"), então vale:
#  Launcher.exe, se existir; senão o .exe da raiz cujo nome original (OriginalFilename) é Launcher.exe. Vazio = não achou.
function LauncherExe {
    $p = [IO.Path]::Combine($Root, 'Launcher.exe'); if ([IO.File]::Exists($p)) { return $p }
    try {
        foreach ($f in [IO.Directory]::GetFiles($Root, '*.exe')) {
            try { if ([Diagnostics.FileVersionInfo]::GetVersionInfo($f).OriginalFilename -ieq 'Launcher.exe') { return $f } } catch { $Error.Clear() }
        }
    } catch { $Error.Clear() }
    return ''
}
# Pasta TarginoRetroStation sempre oculta (só a pasta; o conteúdo não é tocado). O launcher lê tudo normalmente com ela oculta.
function ArqHide {
    if (-not [IO.Directory]::Exists($Arq)) { return }
    $di = New-Object IO.DirectoryInfo $Arq
    if (($di.Attributes -band [IO.FileAttributes]::Hidden) -eq 0) {
        $di.Attributes = $di.Attributes -bor [IO.FileAttributes]::Hidden
        Log 'INFO' "Pasta $ArqName marcada como oculta"
    }
}


# ===== Log (TarginoRetroStation\Logs\launcher.log) =====
#  Níveis: INFO, AVISO, ERRO. Gira ao passar de 1 MB (mantém launcher.1.log ... launcher.5.log).
#  Mensagens idênticas seguidas em menos de 30 s viram uma linha "repetida Nx". Limite de 120 linhas por minuto.
$LogDir = ArqDir 'Logs'; $LogFile = [IO.Path]::Combine($LogDir, 'launcher.log')
$LogMaxBytes = 1MB; $LogKeep = 5
$script:LogLast = ''; $script:LogLastT = [datetime]::MinValue; $script:LogRep = 0; $script:LogMin = -1; $script:LogMinCount = 0
function RotateLog {
    $fi = New-Object IO.FileInfo $LogFile
    if (-not $fi.Exists -or $fi.Length -lt $LogMaxBytes) { return }
    for ($i = $LogKeep; $i -ge 1; $i--) {
        $src = if ($i -eq 1) { $LogFile } else { [IO.Path]::Combine($LogDir, "launcher.$($i - 1).log") }
        $dst = [IO.Path]::Combine($LogDir, "launcher.$i.log")
        if ([IO.File]::Exists($src)) { if ([IO.File]::Exists($dst)) { [IO.File]::Delete($dst) }; [IO.File]::Move($src, $dst) }
    }
}
function Log($lvl, $msg) {
    try {
        $msg = ("$msg" -replace '\s*\r?\n\s*', ' | ').Trim()
        $now = Get-Date; $key = "$lvl|$msg"
        if ($key -eq $script:LogLast -and ($now - $script:LogLastT).TotalSeconds -lt 30) { $script:LogRep++; return }
        $min = [int]($now.Ticks / 600000000)
        if ($min -ne $script:LogMin) { $script:LogMin = $min; $script:LogMinCount = 0 }
        $script:LogMinCount++
        if ($script:LogMinCount -gt 120) { return }
        if (-not [IO.Directory]::Exists($LogDir)) { [void][IO.Directory]::CreateDirectory($LogDir) }
        RotateLog
        $txt = ''
        if ($script:LogRep) { $txt = "{0:yyyy-MM-dd HH:mm:ss} [INFO ] (mensagem anterior repetida mais {1}x)`r`n" -f $now, $script:LogRep; $script:LogRep = 0 }
        if ($script:LogMinCount -eq 120) { $msg += '  (limite de mensagens por minuto atingido; as próximas deste minuto serão ignoradas)' }
        $txt += "{0:yyyy-MM-dd HH:mm:ss} [{1,-5}] {2}`r`n" -f $now, $lvl, $msg
        $script:LogLast = $key; $script:LogLastT = $now
        [IO.File]::AppendAllText($LogFile, $txt, (New-Object Text.UTF8Encoding $false))
    } catch { try { if ($Error.Count) { $Error.RemoveAt(0) } } catch {} }
}
# Registra um erro já tratado e o tira de $Error (para não ser registrado de novo por FlushErrors)
function LogEx($lvl, $msg, $rec) { Log $lvl $msg; if ($rec) { try { $Error.Remove($rec) } catch {} } }
# Erros não tratados dentro de eventos da interface vão para $Error; isto os envia ao log periodicamente
function FlushErrors {
    if (-not $Error.Count) { return }
    $list = @($Error); $Error.Clear(); [array]::Reverse($list)
    foreach ($e in $list) {
        if ($e -is [Management.Automation.ErrorRecord]) {
            $ln = if ($e.InvocationInfo) { " (linha $($e.InvocationInfo.ScriptLineNumber))" } else { '' }
            Log 'ERRO' "$($e.Exception.Message)$ln"
        } elseif ($e -is [Exception]) { Log 'ERRO' $e.Message }
    }
}
# Erro fatal antes da janela abrir: registra e avisa uma vez (a janela do PowerShell é oculta, senão ninguém veria)
trap {
    Log 'ERRO' ("Erro: $($_.Exception.Message) (linha $($_.InvocationInfo.ScriptLineNumber))")
    try { $Error.Remove($_) } catch {}
    if ($script:Ready) { continue }
    try { [void][Windows.Forms.MessageBox]::Show("O launcher não conseguiu abrir.`n`n$($_.Exception.Message)`n`nDetalhes em TarginoRetroStation\Logs\launcher.log", 'Erro') } catch {}
    break
}
try { [Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::CatchException) } catch {}
[Windows.Forms.Application]::add_ThreadException({ param($snd, $e) Log 'ERRO' "Exceção não tratada: $($e.Exception.Message)" })
[Windows.Forms.Application]::EnableVisualStyles()
Log 'INFO' ("Launcher iniciado - v$AppVer (PowerShell $($PSVersionTable.PSVersion), Windows $([Environment]::OSVersion.Version))")
try { ArqHide } catch { LogEx 'AVISO' "Não foi possível ocultar a pasta $ArqName ($($_.Exception.Message)); será tentado na próxima abertura" $_ }

# ===== Arquivos de dados (cada coisa separada; atualizar uma não mexe nas outras) =====
#  TarginoRetroStation\Dados\catalogo.json    -> lista de jogos (vem de você, recebe atualizações)
#  TarginoRetroStation\Dados\usuario.json     -> SÓ os favoritos (da pessoa, nunca é sobrescrito)
#  TarginoRetroStation\Dados\janelas.json     -> tamanho das janelas do modo dev (seu; vai nas atualizações)
#  TarginoRetroStation\Dados\layout.json      -> layout/aparência/senha do modo dev (seu)
#  TarginoRetroStation\Dados\Backups\         -> cópias automáticas antes de operações importantes
#  TarginoRetroStation\Dados\atualizacao.json -> ETag do último UpdateWinPort aplicado neste launcher
$DataDir = ArqDir 'Dados'
if (-not [IO.Directory]::Exists($DataDir)) { [void][IO.Directory]::CreateDirectory($DataDir) }
$Db = "$DataDir\catalogo.json"; $SetFile = "$DataDir\layout.json"; $UserFile = "$DataDir\usuario.json"
$script:MassUndo = ''; $script:MassUndoInfo = ''; $script:MassUndoStamp = 0; $script:MassRows = @(); $script:MassGames = @()
$script:Dev = $false; $script:Ready = $false; $script:Inst = @{}; $script:CatBroken = $false; $script:StartMsg = @()
$Utf8Bom = New-Object Text.UTF8Encoding $true

# ===== JSON seguro =====
# Grava em .tmp e só depois troca pelo arquivo real (o anterior vira .bak). Uma queda no meio não corrompe o arquivo.
function WriteText($path, $text) {
    $tmp = "$path.tmp"; $bak = "$path.bak"
    [IO.File]::WriteAllText($tmp, $text, $Utf8Bom)
    if ([IO.File]::Exists($path)) {
        try { [IO.File]::Replace($tmp, $path, $bak) }
        catch {   # unidades FAT/exFAT ou rede podem não suportar Replace
            $Error.Remove($_)
            [IO.File]::Copy($path, $bak, $true); [IO.File]::Copy($tmp, $path, $true); [IO.File]::Delete($tmp)
        }
    } else { [IO.File]::Move($tmp, $path) }
}
function WriteJson($path, $obj, $depth = 4) {
    try { WriteText $path (ConvertTo-Json -InputObject $obj -Depth $depth); $true }
    catch { LogEx 'ERRO' "Falha ao salvar $(Split-Path $path -Leaf): $($_.Exception.Message)" $_; $false }
}
# Lê um JSON. Se estiver corrompido: guarda uma cópia (.corrompido_data), tenta o .bak e, sem saída, devolve $null.
function ReadJson($path, [bool]$keepCopy = $true) {
    $name = Split-Path $path -Leaf
    if (-not [IO.File]::Exists($path)) { return $null }
    foreach ($p in @($path, "$path.bak")) {
        if (-not [IO.File]::Exists($p)) { continue }
        $n0 = $Error.Count
        try {
            $stream=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            try{$reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true);try{$txt=$reader.ReadToEnd()}finally{$reader.Dispose()}}finally{$stream.Dispose()}
            if (-not $txt.Trim()) { throw 'arquivo vazio' }
            $o = ConvertFrom-Json $txt
            if ($p -ne $path) { Log 'AVISO' "$name estava danificado; usando a cópia $name.bak"; $script:StartMsg += "$name estava danificado e foi recuperado da cópia de segurança." }
            return , $o   # a vírgula impede o PowerShell de desmontar listas de 1 item
        } catch {
            $baseError=$_.Exception.GetBaseException()
            if($baseError -is [IO.IOException] -or $baseError -is [UnauthorizedAccessException]){
                LogEx 'AVISO' "Arquivo temporariamente indisponivel para leitura: $name. Nao foi considerado corrompido." $_
                return $null
            }
            LogEx 'ERRO' "Falha ao ler $(Split-Path $p -Leaf): $($_.Exception.Message)" $_
            while ($Error.Count -gt $n0) { $Error.RemoveAt(0) }   # já registrado; não repetir no log
            if ($keepCopy -and $p -eq $path) { try { [IO.File]::Copy($path, "$path.corrompido_$(Get-Date -Format 'yyyyMMdd_HHmmss')", $true) } catch { $Error.Remove($_) } }
        }
    }
    $null
}
# Cópia de segurança datada em TarginoRetroStation\Dados\Backups (mantém as 20 mais recentes de cada arquivo)
function Backup($path, $tag) {
    if (-not [IO.File]::Exists($path)) { return $null }
    try {
        $bd = [IO.Path]::Combine($DataDir, 'Backups'); [void][IO.Directory]::CreateDirectory($bd)
        $n = [IO.Path]::GetFileNameWithoutExtension($path)
        $dst = [IO.Path]::Combine($bd, "${n}_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$tag.json")
        [IO.File]::Copy($path, $dst, $true)
        [IO.Directory]::GetFiles($bd, "${n}_*.json") | Sort-Object -Descending | Select-Object -Skip 20 | ForEach-Object { [IO.File]::Delete($_) }
        Log 'INFO' "Backup criado: TarginoRetroStation\Dados\Backups\$(Split-Path $dst -Leaf)"
        $dst
    } catch { LogEx 'ERRO' "Falha ao criar backup de $(Split-Path $path -Leaf): $($_.Exception.Message)" $_; $null }
}

function Hash($t) { $h = [Security.Cryptography.SHA256]::Create(); try { $b = $h.ComputeHash([Text.Encoding]::UTF8.GetBytes($t)) } finally { $h.Dispose() }; -join ($b | ForEach-Object { $_.ToString('x2') }) }
function Save {
    # Se o catálogo não pôde ser lido, não grava por cima (o original continua no disco para recuperação)
    if ($script:CatBroken) { Log 'AVISO' 'Catálogo não foi salvo: ele não pôde ser lido ao abrir o launcher.'; return }
    [void](WriteJson $Db @($script:Games) 3)
}
function NewId($name) {
    $b = ("$name".ToLower() -replace '[^a-z0-9]+', '-').Trim('-'); if (-not $b) { $b = 'jogo' }
    $id = $b; $i = 2
    while ($script:Games | Where-Object { $_.Id -eq $id }) { $id = "$b-$i"; $i++ }
    $id
}

# ---- Catálogo ----
$Games = @()
if ([IO.File]::Exists($Db)) {
    $d = ReadJson $Db
    if ($null -eq $d) { $script:CatBroken = $true; $script:StartMsg += "Não foi possível ler TarginoRetroStation\Dados\catalogo.json. Uma cópia foi guardada como catalogo.json.corrompido_* e nada será gravado por cima até o problema ser resolvido." }
    else { $Games = @($d | Where-Object { $_ }) }

}

# ===== Catálogo Hydra automático =====
# Mantém todo o frontend do TarginoRetroStation e troca somente a origem dos jogos.
$HydraRoot = $Root
$HydraRoms = Join-Path $HydraRoot 'roms'
$HydraLibraryConfig = ReadJson (Join-Path $Arq 'Dados\hydra-biblioteca.json') $false
if ($HydraLibraryConfig -and $HydraLibraryConfig.RomsPath -and [IO.Directory]::Exists($HydraLibraryConfig.RomsPath)) {
    $HydraRoms = [IO.Path]::GetFullPath($HydraLibraryConfig.RomsPath)
}
$HydraCores = Join-Path $HydraRoot 'cores'
$HydraExe = Join-Path $HydraRoot 'hydra.exe'
$HydraManifests = @()
if ([IO.File]::Exists($HydraExe)) {
    $manifestText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($HydraExe))
    foreach ($match in [regex]::Matches($manifestText, '(?s)\{\s*"manifest_version"[^\x00]+')) {
        try { $HydraManifests += ($match.Value | ConvertFrom-Json -ErrorAction Stop) } catch { }
    }
    $manifestText = $null
}
function HydraRel([string]$base,[string]$path) {
    $b = New-Object Uri(([IO.Path]::GetFullPath($base)).TrimEnd('\') + '\')
    $p = New-Object Uri([IO.Path]::GetFullPath($path))
    [Uri]::UnescapeDataString($b.MakeRelativeUri($p).ToString()).Replace('/','\')
}
if ([IO.Directory]::Exists($HydraRoms) -and [IO.Directory]::Exists($HydraCores) -and [IO.File]::Exists($HydraExe)) {
    $HydraGames = @(); $HydraIds = @{}
    foreach ($manifest in $HydraManifests) {
        $systemFolder = Split-Path ($manifest.directories.games.Replace('/','\')) -Leaf
        $systemPath = Join-Path $HydraRoms $systemFolder
        if (-not [IO.Directory]::Exists($systemPath)) { continue }
        $hs = Get-Item -LiteralPath $systemPath
        $corePath = Join-Path (Join-Path $HydraCores $hs.Name) $manifest.library
        if (-not [IO.File]::Exists($corePath)) {
            $corePath = Join-Path (Join-Path $HydraCores $manifest.id) $manifest.library
        }
        $hc = Get-Item -LiteralPath $corePath -ErrorAction SilentlyContinue
        if (-not $hc) { continue }
        $HydraExts = @($manifest.extensions | ForEach-Object { '.' + $_.ToLowerInvariant() })
        foreach ($hr in Get-ChildItem $hs.FullName -Recurse -File -ErrorAction SilentlyContinue) {
            if ($HydraExts -notcontains $hr.Extension.ToLowerInvariant()) { continue }
            $hid = ((HydraRel $HydraRoms $hr.FullName).ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-')
            if ($HydraIds.ContainsKey($hid)) { $hid += '-2' }; $HydraIds[$hid] = $true
            $hcore = HydraRel $HydraRoot $hc.FullName; $hrom = HydraRel $HydraRoot $hr.FullName
            $HydraGames += [pscustomobject]@{ Id=$hid; Name=$hr.BaseName; Exe='hydra.exe'; Args="--boot $($manifest.id) `"$($hr.FullName)`""; Cover=''; Shot=''; Version=$hs.Name; Link=''; Desc="Sistema: $($hs.Name)`nCore: $($hc.Name)`nROM: $hrom"; ImgName=''; Archive=''; Added=$hr.CreationTime.ToString('yyyy-MM-dd') }
        }
    }
    $Games = @($HydraGames)
}
$hydraLibrary = Join-Path $Arq 'HydraLibrary.ps1'
if ([IO.File]::Exists($hydraLibrary)) { . $hydraLibrary }
$hydraStartup = Join-Path $Arq 'HydraStartup.ps1'
if ([IO.File]::Exists($hydraStartup)) { . $hydraStartup }
$dirty = $false
foreach ($g in $Games) { if (-not $g.Id) { $g | Add-Member NoteProperty Id (NewId $g.Name) -Force; $dirty = $true } }
if ($dirty) { Save }

# ---- Layout (seu) ----
$S = @{ Title = 'Launcher'; Accent = '#1E90FF'; Zoom = 2; Maximized = $false; PassHash = ''
        CoverCacheMB = 96; CoverThreads = 2; CoverPrefetchRows = 2; LoadScreen = $true; ThumbCache = $true
        ShowSearch = $true; ShowFilter = $true; ShowZoom = $true; ShowPanel = $true
        ShowTitle = $true; ShowFav = $true; ShowVersion = $true; ShowLink = $true; ShowDesc = $true; ShowShot = $true
        # Biblioteca (grade de capas)
        CoverS1 = 128; CoverS2 = 180; CoverS3 = 256; GapH = 20; GapV = 14; PadX = 24; PadY = 20; GridCenter = $false; CoverFit = 'Preencher'
        NameLines = 2; NameSize = 9; NameGap = 6; NotInstalled = 'Preto e branco'; DimNotInst = 60; DimInstalled = 0; SelBright = $true; SmoothScroll = $true; InstRecheckSec = 60
        CoverDir = ''; ShotDir = ''; CoverPattern = '{Alt}|{Nome}|{Id}'; ShotPattern = '{Alt}|{Nome}|{Id}'; ImgExts = 'png,jpg,jpeg,bmp,gif'; ImgLoose = $true
        UpdUrl = ''; UpdPass = ''
        ArchivePass = ''; UnrarPath = 'TarginoRetroStation\Ferramentas\UnRar\UnRAR.exe'; TdlPath = 'TarginoRetroStation\Ferramentas\Tdl\tdl.exe'; TelegramPath = 'TarginoRetroStation\Ferramentas\Telegram\Telegram.exe'; ArchiveDirs = ''; T_Archived = 'Compactado: será extraído ao jogar'
        DetailWidth = 400; DescFont = ''; FontFamily = ''; TextWeight = 'Médio'; TextContrast = 6; TextRender = 'ClearType'; DescSize = 10; DescTitleSize = 18; DescSubSize = 13; DescLinkColor = '#4DA3FF'
        DetailPad = 15; DetailBg = ''; TitleFont = ''; TitleSize = 18; TitleStyle = 'Normal'; TitleColor = ''; TitleLines = 2; TitleAlign = 'Esquerda'
        StatusSize = 9; StatusColor = '#E07B7B'; StatusStyle = 'Normal'; StatusAlign = 'Centro'; StatusGapTop = 6; StatusGapBottom = 10; VersionSize = 9; VersionColor = ''; DescColor = ''; DescTitleColor = ''; DescAlign = 'Esquerda'
        SelColor = '#1E90FF'; SelWidth = 3; SelGap = 3; SelStyle = 'Sólida'
        # Cores gerais
        BgColor = '#0B0B0B'; SideColor = '#141414'; TextColor = '#FFFFFF'; SubColor = '#9A9A9A'
        # Personalização visual: caminhos opcionais escolhidos manualmente no painel de configurações
        BackgroundImage = ''; AvatarImage = ''; CinemaMode = $true; CinemaAnimate = $false
        JoystickEnabled = $true; JoyConfirm = 3; JoyBack = 2; JoyDetails = 4; JoyFilters = 1; JoyStart = 10
        JoyPageLeft = 5; JoyPageRight = 6; JoyPageSize = 8
        JoyActions = 9; JoySearchModifier = 9
        Fullscreen = $true
        # Menu de filtros ao lado da busca (ShowFilter = mostrar o menu)
        SideItems = 'all,recent,fav,inst,notinst'; RecentDays = 30; ShowSideCount = $true
        T_Fav = 'Favoritar'; T_Faved = 'Favorito'; T_Link = 'Baixar Jogo'; T_Version = 'Versão'; T_Zoom = 'Ampliar/Reduzir'; T_Offline = 'Unidade desconectada'
        T_All = 'Todos os Jogos'; T_Recent = 'Últimas atualizações'; T_Favs = 'Favoritos'; T_Inst = 'Instalados'; T_NotInst = 'Não instalados'
        T_Empty = 'Nenhum jogo nesta lista'
        DeleteColor = '#E5484D'; T_CtxDelete = 'Deletar jogo'
        NameStrip = '(WinPort)'
        T_CtxPlay = 'Jogar'; T_CtxFav = 'Favoritar'; T_CtxUnfav = 'Remover dos favoritos'
        T_Starting = 'Iniciando...'; T_Running = 'Em execução'; T_Extracting = 'Extraindo seu jogo'; T_CtxStop = 'Fechar jogo'; T_Downloading = 'Baixando seu jogo'; T_CtxCancelDl = 'Cancelar download'
        # Topo (v2.50.0): nome do launcher com brilho, linha decorativa e dica na busca
        HeaderShow = $true; HeaderText = 'Targino RetroStation'; HeaderFont = ''; HeaderSize = 22; HeaderStyle = 'Negrito'; HeaderCaps = $false; HeaderSpacing = 1
        HeaderColor = '#3BA4FF'; HeaderFill = 'Degradê suave'; HeaderGlow = 35; HeaderGlowSize = 10; HeaderGlowColor = ''; HeaderPadTop = 10; HeaderPadBottom = 0
        HeaderLine = $true; HeaderLineColor = ''; HeaderLineWidth = 50; SearchHint = 'Pesquisar jogos...'
        HeaderArea = 'Área dos jogos'; HeaderAlign = 'Centro'; HeaderOffsetX = 0; TopJoin = $true
        SearchArea = 'Área dos jogos'; SearchAlign = 'Centro'; SearchOffsetX = 0; FilterArea = 'Área dos jogos'; FilterAlign = 'Centro'; FilterOffsetX = 0
        PlayPulse = 70; PlayBorderColor = ''; PlayDotColor = ''; PlayDotSize = 9; PlayTextColor = ''; PlayTextSize = 0; PlayBold = $true; PlayItalic = $false; PlayCheckSec = 3 }
$Defaults = $S.Clone()      # valores de fábrica (para "Restaurar padrões" no modo dev)
# Só valem as chaves que o launcher conhece: chaves de opções que já saíram ficam para trás e somem na próxima gravação
$o = ReadJson $SetFile
if ($o) { foreach ($p in $o.PSObject.Properties) { if ($Defaults.ContainsKey($p.Name)) { $S[$p.Name] = $p.Value } } }
$targinoPreferencesSource=Join-Path $Arq 'TarginoPreferences.ps1'
if([IO.File]::Exists($targinoPreferencesSource)){. $targinoPreferencesSource}
function SaveSettings {
    if(Get-Command TarginoEnforceIdentity -ErrorAction SilentlyContinue){TarginoEnforceIdentity}
    [void](WriteJson $SetFile $S 4)
}

# ---- Dados da pessoa ----
#  v2.52.0: usuario.json guarda SÓ os favoritos (é o único arquivo da pessoa; as atualizações nunca o substituem).
#  Último filtro usado: Dados\ultimo_filtro.txt (da pessoa, também nunca é substituído). Zoom ao abrir: o do layout.json.
#  Tamanho das janelas do modo dev: Dados\janelas.json. Campos antigos (FilterKey, Zoom, Win) são limpos na abertura;
#  o Win antigo é levado para janelas.json.
$U = @{ Fav = @() }
$JanFile = "$DataDir\janelas.json"; $DevWin = @{}
$o = ReadJson $JanFile $false
if ($o) { foreach ($p in $o.PSObject.Properties) { $DevWin[$p.Name] = "$($p.Value)" } }
function SaveWin { [void](WriteJson $JanFile $DevWin 2) }
function SaveUser { [void](WriteJson $UserFile $U 2) }
$FilFile = "$DataDir\ultimo_filtro.txt"
function FilSave($fk) { try { WriteText $FilFile "$fk" } catch { LogEx 'AVISO' "Não foi possível guardar o último filtro: $($_.Exception.Message)" $_ } }
function FilLoad { try { if ([IO.File]::Exists($FilFile)) { return "$([IO.File]::ReadAllText($FilFile))".Trim() } } catch { $Error.Clear() }; '' }
$o = ReadJson $UserFile
if ($o) {
    $U.Fav = @($o.Fav | Where-Object { $_ })
    $old = @($o.PSObject.Properties | Where-Object { $_.Name -ne 'Fav' })
    if ($old.Count) {
        if ($o.FilterKey -and -not [IO.File]::Exists($FilFile)) { FilSave "$($o.FilterKey)" }      # leva o filtro antigo para o arquivo novo
        if ($o.Win -and -not $DevWin.Count) { foreach ($p in $o.Win.PSObject.Properties) { $DevWin[$p.Name] = "$($p.Value)" }; SaveWin }
        SaveUser; Log 'INFO' "usuario.json: campos antigos removidos ($(($old | ForEach-Object { $_.Name }) -join ', ')); ficam só os favoritos"
    }
}
function ToggleFav($g) {
    if ($U.Fav -contains $g.Id) { $U.Fav = @($U.Fav | Where-Object { $_ -ne $g.Id }) } else { $U.Fav = @($U.Fav) + $g.Id }
    SaveUser
}


# ---- Caminhos: sempre relativos à pasta do launcher. Variáveis: {LauncherDir} {JogosDir} {TarginoRetroStationDir} ----
#  Nada fora da pasta do launcher: caminho completo que aponte para fora dela é recusado (Full devolve '' e avisa uma vez no log).
function Expand($txt) {
    if (-not $txt) { return '' }
    $txt.Replace('{LauncherDir}', $Root).Replace('{JogosDir}', "$Root\Jogos").Replace('{TarginoRetroStationDir}', $Arq)
}
$script:RootSlash = $Root + '\'
function InRoot($pth) { [bool]("$pth" -and ("$pth" -ieq $Root -or "$pth".StartsWith($script:RootSlash, 'OrdinalIgnoreCase'))) }
$script:OutWarned = @{}
$script:FullMemo = @{}      # Full() é pura: guarda o resultado de cada texto (evita refazer o caminho de milhares de jogos)
function Full($p) {
    $fk = "$p"
    if ($script:FullMemo.ContainsKey($fk)) { return $script:FullMemo[$fk] }
    $fr = FullCalc $p; $script:FullMemo[$fk] = $fr; $fr
}
function FullCalc($p) {
    $p = Expand $p; if (-not $p) { return '' }
    try {
        if (-not [IO.Path]::IsPathRooted($p)) { $p = [IO.Path]::Combine($Root, $p) }
        $p = [IO.Path]::GetFullPath($p)
        if (-not (InRoot $p)) {
            if (-not $script:OutWarned[$p]) { $script:OutWarned[$p] = 1; Log 'AVISO' "Caminho fora da pasta do launcher recusado: '$p'" }
            return ''
        }
        $p
    } catch { LogEx 'AVISO' "Caminho inválido: '$p' ($($_.Exception.Message))" $_; '' }
}
# Argumentos (do jogo e dos .exe do Link/extras): cada trecho que é um caminho RELATIVO de arquivo/pasta que existe a partir da
#  pasta do launcher (ex.: "Jogos\X\rom.z64") vira o caminho completo entre aspas. Necessário porque o programa roda com a pasta
#  DELE como pasta atual ($wd): lá "Jogos\X\rom.z64" não existiria. Trecho que já existe a partir de $wd, caminho completo, opção
#  (-x, --x, /x), site/protocolo ou caminho que não existe ficam como estão.
function ArgsExpand($txt, $wd) {
    $txt = Expand $txt; if (-not $txt) { return '' }
    $sb = New-Object Text.StringBuilder; $last = 0
    foreach ($m in [regex]::Matches($txt, '"[^"]*"|[^\s"]+')) {
        [void]$sb.Append($txt.Substring($last, $m.Index - $last)); $last = $m.Index + $m.Length
        $tok = $m.Value; $raw = $tok.Trim('"'); $new = $tok
        if ($raw -and $raw -match '[\\/.]' -and $raw -notmatch '^[-/]' -and $raw -notmatch '^[a-zA-Z][a-zA-Z0-9+.\-]+:' -and $raw.IndexOfAny([IO.Path]::GetInvalidPathChars()) -lt 0) {
            try {
                if (-not [IO.Path]::IsPathRooted($raw)) {
                    $inWd = $wd -and ([IO.File]::Exists([IO.Path]::Combine($wd, $raw)) -or [IO.Directory]::Exists([IO.Path]::Combine($wd, $raw)))
                    if (-not $inWd) {
                        $f = [IO.Path]::GetFullPath([IO.Path]::Combine($Root, $raw))
                        if ([IO.File]::Exists($f) -or [IO.Directory]::Exists($f)) { $new = '"' + $f + '"' }
                    }
                }
            } catch { $Error.Clear() }
        }
        [void]$sb.Append($new)
    }
    [void]$sb.Append($txt.Substring($last)); $sb.ToString()
}
function Short($p) {
    if ($p -and $p.StartsWith("$Root\", 'OrdinalIgnoreCase')) { return $p.Substring($Root.Length + 1) }
    $p
}
function ExePath($g) { Full $g.Exe }   # o jogo sempre fica em Jogos\ : vale só o executável do catálogo
# ---- Estado de instalação (jogo instalado / não instalado / unidade desconectada) ----
#  Só verifica se o executável existe ([IO.File]::Exists): nunca varre pastas.
#  Cada unidade (C:\, H:\, \\servidor\pasta) é consultada UMA vez por verificação. Se a unidade não responde, os jogos dela
#  ficam com o ÚLTIMO estado conhecido (estado 'offline'): unidade desconectada NÃO significa jogo removido.
#  O último resultado fica em Dados\cache_instalacao.json, então a tela abre já com o estado certo e a verificação
#  completa roda em lotes pequenos (timer), sem travar a janela. Dois jogos com o mesmo executável são checados uma vez só.
$InstFile = [IO.Path]::Combine($DataDir, 'cache_instalacao.json')
$script:InstState = @{}; $script:InstCache = @{}; $script:InstDirty = $false
$script:Drive = @{}; $script:DriveSeen = @{}; $script:PathSeen = @{}
$script:InstQ = @(); $script:InstIdx = 0; $script:InstRun = $false; $script:InstChanged = $false; $script:InstLast = [datetime]::MinValue; $script:InstSw = $null
function InstSig($gm) { "|$($gm.Exe)|$($gm.Archive)" }
function DriveOf($pth) { try { "$([IO.Path]::GetPathRoot($pth))" } catch { '' } }
function DriveOnline($rt) {
    if (-not $rt) { return $true }
    if ($script:Drive.ContainsKey($rt)) { return [bool]$script:Drive[$rt] }
    $swd = [Diagnostics.Stopwatch]::StartNew(); $on = $false
    try { $on = [IO.Directory]::Exists($rt) } catch { $on = $false }
    if ($swd.ElapsedMilliseconds -gt 1000) { Log 'AVISO' "Unidade '$rt' demorou $($swd.ElapsedMilliseconds) ms para responder" }
    $script:Drive[$rt] = $on
    if ($script:DriveSeen[$rt] -ne $on) {
        $script:DriveSeen[$rt] = $on
        Log 'INFO' ("Unidade '$rt' " + $(if ($on) { 'disponível' } else { 'indisponível: os jogos dela mantêm o último estado conhecido' }))
    }
    $on
}
# ---- Jogo compactado: sem a pasta do jogo, mas com NomeDaPasta.rar ao lado dela => estado 'archived' (conta como instalado;
#  o launcher extrai sozinho quando a pessoa manda jogar). Campo opcional Archive do jogo e pastas extras em ArchiveDirs (separadas por ;).
$script:ArcPath = @{}
# Índice dos .rar de uma pasta: durante a verificação completa lista cada pasta UMA vez (em vez de até 5 testes por jogo sem .exe)
$script:DirIdx = $null
function ArcIndex($dir) {
    if ($null -eq $script:DirIdx) { return $null }
    if ($script:DirIdx.ContainsKey($dir)) { $hv = $script:DirIdx[$dir]; if ($null -eq $hv) { return $null }; return ,$hv }
    $hs = $null
    try {
        $hs = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($f0 in [IO.Directory]::EnumerateFiles($dir, '*.rar')) { [void]$hs.Add([IO.Path]::GetFileName($f0)) }
    } catch { $hs = $null; $Error.Clear() }
    $script:DirIdx[$dir] = $hs
    if ($null -eq $hs) { return $null }
    return ,$hs
}
function GameFolder($gm) {   # pasta do jogo = 1º nível dentro de Jogos\ (ou a pasta do executável, se estiver fora de Jogos)
    $pc = Full $gm.Exe; if (-not $pc) { return $null }
    $sep = [string][IO.Path]::DirectorySeparatorChar; $jd = [IO.Path]::Combine($Root, 'Jogos'); $folder = ''; $parent = ''
    if ($pc.StartsWith($jd + $sep, 'OrdinalIgnoreCase')) {
        $first = $pc.Substring($jd.Length + 1).Split($sep)[0]
        if ($pc.Length -gt ($jd.Length + 1 + $first.Length)) { $folder = $jd + $sep + $first; $parent = $jd }
    }
    if (-not $folder) { $folder = [IO.Path]::GetDirectoryName($pc); if ($folder) { $parent = [IO.Path]::GetDirectoryName($folder) } }
    if (-not $folder -or -not $parent) { return $null }
    @{ Folder = $folder; Parent = $parent; Name = [IO.Path]::GetFileName($folder); Exe = $pc }
}
function FindArchive($gm) {   # devolve @{ Path; Offline }
    $res = @{ Path = ''; Offline = $false }
    $ex = "$($gm.Archive)".Trim()
    if ($ex) {
        $pa = Full $ex
        if ($pa) { if (-not (DriveOnline (DriveOf $pa))) { $res.Offline = $true; return $res } elseif ([IO.File]::Exists($pa)) { $res.Path = $pa; return $res } }
    }
    $gf = GameFolder $gm; if (-not $gf) { return $res }
    $dirs = @($gf.Parent)
    foreach ($ad in ("$($S.ArchiveDirs)" -split ';')) { $ad = $ad.Trim(); if ($ad) { $fd = Full $ad; if ($fd -and $dirs -notcontains $fd) { $dirs += $fd } } }
    foreach ($dd in $dirs) {
        if (-not (DriveOnline (DriveOf $dd))) { $res.Offline = $true; continue }
        $ix = ArcIndex $dd
        foreach ($sf in '.part1.rar', '.part01.rar', '.part001.rar', '.part0001.rar', '.rar') {
            $ap = [IO.Path]::Combine($dd, $gf.Name + $sf)
            if ($null -ne $ix) { if ($ix.Contains($gf.Name + $sf)) { $res.Path = $ap; return $res } }
            elseif ([IO.File]::Exists($ap)) { $res.Path = $ap; return $res }
        }
    }
    $res
}
# Partes de um arquivo (só nomes de arquivo, sem abrir nenhuma): Nome.part1.rar..partN.rar ou Nome.rar + Nome.r00, r01...
# Devolve @{ Files; Missing } ; Missing = $true se faltar alguma parte no meio da sequência.
function ArcVolumes($first) {
    $res = @{ Files = @($first); Missing = $false }
    try {
        $dir = [IO.Path]::GetDirectoryName($first); $fn = [IO.Path]::GetFileName($first)
        $m = [regex]::Match($fn, '^(?<b>.+)\.part(?<n>\d+)\.rar$', 'IgnoreCase')
        if ($m.Success) { $b0 = $m.Groups['b'].Value; $rx = '^' + [regex]::Escape($b0) + '\.part(?<n>\d+)\.rar$'; $gl = $b0 + '.part*.rar' }
        elseif ($fn -match '(?i)\.rar$') { $b0 = $fn.Substring(0, $fn.Length - 4); $rx = '^' + [regex]::Escape($b0) + '\.(?<e>rar|[r-z]\d{2})$'; $gl = $b0 + '.*' }
        else { return $res }
        $files = @(); $nums = @()
        foreach ($f0 in [IO.Directory]::EnumerateFiles($dir, $gl)) {
            $mm = [regex]::Match([IO.Path]::GetFileName($f0), $rx, 'IgnoreCase')
            if (-not $mm.Success) { continue }
            $files += $f0
            if ($mm.Groups['n'].Success) { $nums += [int]$mm.Groups['n'].Value }
            elseif ($mm.Groups['e'].Value -match '^[r-z](\d{2})$') { $nums += (([int][char]$mm.Groups['e'].Value.Substring(0, 1).ToLower() - [int][char]'r') * 100 + [int]$Matches[1] + 1) }
            else { $nums += 0 }
        }
        if ($files.Count) { $res.Files = $files }
        $first_n = if ($m.Success) { 1 } else { 0 }
        $nums = @($nums | Sort-Object)
        for ($k = 0; $k -lt $nums.Count; $k++) { if ($nums[$k] -ne ($first_n + $k)) { $res.Missing = $true; break } }
    } catch { $Error.Clear() }
    $res
}
# Verifica um jogo. Devolve $true se algo mudou (estado ou instalado/não).
function CheckGame($gm) {
    $id = "$($gm.Id)"
    $pc = Full $gm.Exe
    $stt = 'missing'; $arc = ''
    $key = "$pc".ToLower()
    if ($key -and $script:PathSeen.ContainsKey($key)) { $pv = $script:PathSeen[$key]; $stt = $pv.S; $arc = $pv.A }
    else {
        $offl = $false; $found = $false
        if ($pc) {
            if (-not (DriveOnline (DriveOf $pc))) { $offl = $true }
            elseif ([IO.File]::Exists($pc)) { $found = $true }
        }
        if ($found) { $stt = 'ok' }
        elseif ($offl) { $stt = 'offline' }
        else { $fa = FindArchive $gm; if ($fa.Path) { $stt = 'archived'; $arc = $fa.Path } elseif ($fa.Offline) { $stt = 'offline' } }
        if ($key) { $script:PathSeen[$key] = @{ S = $stt; A = $arc } }
    }
    if ($stt -eq 'archived') { $script:ArcPath[$id] = $arc }
    $old = $script:InstState[$id]; $ch = ($old -ne $stt)
    $script:InstState[$id] = $stt
    if ($stt -ne 'offline') {
        $v = ($stt -eq 'ok')      # instalado somente após extrair e localizar o executável
        if ($script:Inst[$id] -ne $v) { $script:Inst[$id] = $v; $ch = $true }
        $sig = InstSig $gm; $ce = $script:InstCache[$id]
        if (-not $ce -or $ce.S -ne $stt -or $ce.P -ne $sig) { $script:InstCache[$id] = @{ S = $stt; P = $sig }; $script:InstDirty = $true }
    } elseif ($null -eq $script:Inst[$id]) { $script:Inst[$id] = $false }   # unidade fora e sem histórico: mostra como não instalado
    $ch
}
function InstSave {
    if (-not $script:InstDirty) { return }
    $ids = @{}; foreach ($gm in $script:Games) { $ids["$($gm.Id)"] = 1 }
    $out = [ordered]@{}
    foreach ($k in @($script:InstCache.Keys | Sort-Object)) { if ($ids.ContainsKey($k)) { $out[$k] = $script:InstCache[$k] } }
    if (WriteJson $InstFile ([ordered]@{ Ver = 1; Games = $out }) 4) { $script:InstDirty = $false }
}
# Lê o cache do disco (uma vez, na abertura). Só vale para jogos cujo caminho não mudou desde a última verificação.
function InstLoadCache {
    $o = ReadJson $InstFile $false
    if (-not $o -or -not $o.Games) { return }
    foreach ($p in $o.Games.PSObject.Properties) {
        $s1 = "$($p.Value.S)"; if ($s1 -ne 'ok' -and $s1 -ne 'missing' -and $s1 -ne 'archived') { continue }
        $script:InstCache[$p.Name] = @{ S = $s1; P = "$($p.Value.P)" }
    }
    foreach ($gm in $script:Games) {
        $id = "$($gm.Id)"; $ce = $script:InstCache[$id]
        if ($ce -and $ce.P -eq (InstSig $gm)) { $script:Inst[$id] = ($ce.S -eq 'ok'); $script:InstState[$id] = $ce.S }
    }
}
# Verifica na hora (sem timer) os jogos que ainda não têm estado válido: novos, editados.
function InstCheckStale {
    $stale = @($script:Games | Where-Object { $ce = $script:InstCache["$($_.Id)"]; -not $ce -or $ce.P -ne (InstSig $_) })
    if ($stale.Count -eq 0) { return $false }
    $script:Drive = @{}; $script:PathSeen = @{}
    if ($stale.Count -gt 20) { $script:DirIdx = @{} }
    try { foreach ($gm in $stale) { [void](CheckGame $gm) } } finally { $script:DirIdx = $null }
    InstSave; $true
}
function InstCounts {
    $n = 0; $nOff = 0
    foreach ($gm in $script:Games) { $id = "$($gm.Id)"; if (-not $script:Inst[$id]) { $n++ }; if ($script:InstState[$id] -eq 'offline') { $nOff++ } }
    @($n, $nOff)
}
# Passada completa em lotes. force = descarta o resultado das unidades (reconsulta tudo).
function InstStart {
    $script:Drive = @{}; $script:PathSeen = @{}; $script:DirIdx = @{}
    $script:InstQ = @($script:Games); $script:InstIdx = 0; $script:InstChanged = $false; $script:InstRun = $true
    $script:InstSw = [Diagnostics.Stopwatch]::StartNew()
    if ($instTm) { $instTm.Start() }
}
# Processa jogos até esgotar o orçamento (ms). Devolve $true quando a passada terminou.
function InstStep($budgetMs) {
    if (-not $script:InstRun) { return $true }
    $swb = [Diagnostics.Stopwatch]::StartNew()
    while ($script:InstIdx -lt $script:InstQ.Count) {
        if (CheckGame $script:InstQ[$script:InstIdx]) { $script:InstChanged = $true }
        $script:InstIdx++
        if ($swb.ElapsedMilliseconds -ge $budgetMs) { break }
    }
    if ($script:InstIdx -lt $script:InstQ.Count) { return $false }
    $script:InstRun = $false; $script:InstLast = Get-Date; $script:DirIdx = $null
    $cn = InstCounts
    Log 'INFO' ("Verificação de instalação: $($script:InstQ.Count) jogo(s), $($cn[0]) não instalado(s), $($cn[1]) em unidade desconectada, $($script:Drive.Count) unidade(s) consultada(s), $($script:InstSw.ElapsedMilliseconds) ms")
    InstSave
    $true
}
# ---- Imagens automáticas (capas e capturas) ----
#  Duas pastas configuráveis no modo dev. O nome do arquivo é montado por padrões ({Alt}|{Nome}|{Id}) e as extensões têm prioridade
#  pela ordem da lista. A pasta é lida UMA vez para um índice em memória (nome -> arquivo); o índice também fica em
#  Dados\cache_imagens.json e só é refeito quando a data da pasta muda ou no botão do modo dev. Nenhuma varredura por jogo.
#  Capa/captura cadastrada à mão no jogo (campos Capa/Captura) continua valendo primeiro. Sem imagem: placeholder, como antes.
$ImgFile = [IO.Path]::Combine($DataDir, 'cache_imagens.json')
$script:Img = @{ Cover = $null; Shot = $null }; $script:ImgDisk = $null; $script:ImgDirty = $false; $script:ImgGen = 0; $script:ImgMemo = @{}; $script:ImgWarned = @{}
$script:ImgMemoDirty = $false; $script:ImgDM = @{}; $script:ImgDMGen = @{}; $script:ImgDMOff = $false      # capa de cada jogo guardada em disco (D152)
$script:ImgExtMemo = $null; $script:ImgPatMemo = @{}; $script:ImgHit = 0; $script:ImgMiss = 0
function ImgNorm($t) {
    $n = "$t".Normalize([Text.NormalizationForm]::FormD)
    $n = [regex]::Replace($n, '\p{Mn}', ''); $n = [regex]::Replace($n, '[^\p{L}\p{N}]', ''); $n.ToLowerInvariant()
}
function ImgExtList {
    $ekey = "$($S.ImgExts)"; if ($script:ImgExtMemo -and $script:ImgExtMemo.K -ceq $ekey) { return $script:ImgExtMemo.V }      # calculado uma vez (antes: a cada jogo)
    $r = @()
    foreach ($e in ("$($S.ImgExts)" -split '[,; ]+')) {
        $e = $e.Trim().TrimStart('.').ToLowerInvariant(); if (-not $e -or $e -notmatch '^[a-z0-9]{1,5}$' -or $r -contains $e) { continue }
        if ($e -eq 'webp' -or $e -eq 'avif') { if (-not $script:ImgWarned[$e]) { $script:ImgWarned[$e] = 1; Log 'AVISO' "Extensão '$e' ignorada: o componente de imagem do Windows usado pelo launcher não abre esse formato" }; continue }
        $r += $e
    }
    if (-not $r) { $r = @('png', 'jpg', 'jpeg') }
    $script:ImgExtMemo = @{ K = $ekey; V = $r }
    $r
}
function ImgPatterns($kind) {
    $p = "$($S["${kind}Pattern"])".Trim(); if (-not $p) { $p = '{Alt}|{Nome}|{Id}' }
    $pm = $script:ImgPatMemo[$kind]; if ($pm -and $pm.K -ceq $p) { return $pm.V }      # calculado uma vez por padrão
    $pv = @($p -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $script:ImgPatMemo[$kind] = @{ K = $p; V = $pv }
    $pv
}
function ImgLoadDisk {
    $o = ReadJson $ImgFile $false
    if ($o) { $script:ImgDisk = $o }
}
function ImgSaveDisk {
    if (-not $script:ImgDirty -and -not $script:ImgMemoDirty) { return }
    $out = [ordered]@{ Ver = 3 }
    foreach ($k in 'Cover', 'Shot') {
        $ix = $script:Img[$k]; if (-not $ix) { continue }
        # capa achada de cada jogo, como NOME de arquivo dentro da pasta de imagens (nunca caminho completo: a pasta do launcher pode mudar de lugar/nome)
        $mm = @{}; $dm = ImgDiskMemo $k
        if ($dm) { foreach ($dk in $dm.Keys) { $mm[$dk] = "$($dm[$dk][0])`t$($dm[$dk][1])" } }
        foreach ($me in $script:ImgMemo.Values) { if ($me.Kind -eq $k -and $me.Gen -eq $script:ImgGen -and $null -ne $me.Rel) { $mm[$me.Id] = "$($me.Sd)`t$($me.Rel)" } }
        $out[$k] = [ordered]@{ Cfg = $ix.Cfg; Stamp = $ix.Stamp; Files = @($ix.Files); Memo = $mm }
    }
    if (WriteJson $ImgFile $out 4) { $script:ImgDirty = $false; $script:ImgMemoDirty = $false }
}
# Capa/captura de cada jogo, guardada em cache_imagens.json. Só vale se a pasta é a mesma (configuração) e não mudou
# (data da pasta igual à do índice atual). Desligada até fechar depois de "Reconstruir índice" (procura tudo de novo).
function ImgDiskMemo($kind) {
    if ($script:ImgDMGen.ContainsKey($kind) -and $script:ImgDMGen[$kind] -eq $script:ImgGen) { return $script:ImgDM[$kind] }
    $t = $null; $cur = $script:Img[$kind]; $de = $null; if ($script:ImgDisk) { $de = $script:ImgDisk.$kind }
    if (-not $script:ImgDMOff -and $cur -and $de -and $de.Memo -and [int]$script:ImgDisk.Ver -ge 3 -and "$($cur.Stamp)" -and "$($de.Cfg)" -eq "$($cur.Cfg)" -and "$($de.Stamp)" -eq "$($cur.Stamp)") {
        $t = @{}
        foreach ($pp in $de.Memo.PSObject.Properties) { $v = "$($pp.Value)"; $ti = $v.LastIndexOf("`t"); if ($ti -ge 0) { $t[$pp.Name] = @($v.Substring(0, $ti), $v.Substring($ti + 1)) } }
    }
    $script:ImgDM[$kind] = $t; $script:ImgDMGen[$kind] = $script:ImgGen
    $t
}
function ImgMake($dir, $cfg, $stamp, $files) {
    $ix = @{ Dir = $dir; Cfg = $cfg; Stamp = $stamp; Files = @($files); Exact = @{}; Loose = @{} }
    $loose = [bool]$S.ImgLoose
    foreach ($fn in $ix.Files) {
        $b = [IO.Path]::GetFileNameWithoutExtension($fn); $e = [IO.Path]::GetExtension($fn).TrimStart('.').ToLowerInvariant()
        $k = $b.ToLowerInvariant(); if (-not $ix.Exact.ContainsKey($k)) { $ix.Exact[$k] = @{} }; if (-not $ix.Exact[$k].ContainsKey($e)) { $ix.Exact[$k][$e] = $fn }
        if ($loose) {
            $k = ImgNorm $b; if ($k) { if (-not $ix.Loose.ContainsKey($k)) { $ix.Loose[$k] = @{} }; if (-not $ix.Loose[$k].ContainsKey($e)) { $ix.Loose[$k][$e] = $fn } }
        }
    }
    $ix
}
# Garante o índice de 'Cover' ou 'Shot'. Devolve $true se o índice mudou (então capas/memória precisam ser recalculadas).
function ImgEnsure($kind, $force) {
    $dcfg = "$($S["${kind}Dir"])".Trim(); $cur = $script:Img[$kind]
    if (-not $dcfg) { if ($cur) { $script:Img[$kind] = $null; $script:ImgGen++; return $true }; return $false }
    $exts = ImgExtList
    $cfg = "$dcfg|$($exts -join ',')|$([bool]$S.ImgLoose)|$((ImgPatterns $kind) -join '|')"
    $dir = Full $dcfg; $avail = $false; $stamp = ''
    try { if ($dir -and [IO.Directory]::Exists($dir)) { $avail = $true; $stamp = "$([IO.Directory]::GetLastWriteTimeUtc($dir).Ticks)" } } catch { $avail = $false }
    if ($cur -and $cur.Cfg -eq $cfg -and -not $force -and (-not $avail -or $cur.Stamp -eq $stamp)) { return $false }
    $swi = [Diagnostics.Stopwatch]::StartNew(); $files = $null; $how = ''
    $de = $null; if ($script:ImgDisk) { $de = $script:ImgDisk.$kind }
    if (-not $avail) {
        if ($cur -and $cur.Cfg -eq $cfg) { return $false }
        if ($de -and "$($de.Cfg)" -eq $cfg) { $files = @($de.Files); $stamp = "$($de.Stamp)"; $how = 'pasta indisponível, usando o último índice' }
        else { $files = @(); $how = 'pasta indisponível, sem índice anterior' }
        if (-not $script:ImgWarned["dir$kind"]) { $script:ImgWarned["dir$kind"] = 1; Log 'AVISO' "Pasta de imagens ($kind) indisponível: '$(Short $dir)' ($how)" }
    } elseif (-not $force -and -not $cur -and $de -and "$($de.Cfg)" -eq $cfg -and "$($de.Stamp)" -eq $stamp) {
        $files = @($de.Files); $how = 'cache'
    } else {
        $files = New-Object 'System.Collections.Generic.List[string]'
        try {
            foreach ($fp in [IO.Directory]::EnumerateFiles($dir)) {
                $e = [IO.Path]::GetExtension($fp).TrimStart('.').ToLowerInvariant()
                if ($exts -contains $e) { $files.Add([IO.Path]::GetFileName($fp)) }
            }
        } catch { LogEx 'AVISO' "Falha ao listar a pasta de imagens ($kind): $($_.Exception.Message)" $_ }
        $files = $files.ToArray(); $how = 'lida do disco'
    }
    $script:Img[$kind] = ImgMake $dir $cfg $stamp $files
    $script:ImgDirty = $true; $script:ImgGen++
    Log 'INFO' "Índice de imagens ($kind): $($files.Count) arquivo(s), $how, $($swi.ElapsedMilliseconds) ms"
    $true
}
function ImgEnsureAll($force) {
    $ch = $false
    foreach ($k in 'Cover', 'Shot') { if (ImgEnsure $k $force) { $ch = $true } }
    if ($ch) { ImgSaveDisk }
    $ch
}
# Procura a imagem do jogo no índice. '' se não achar.
function ImgFind($kind, $gm) {
    $ix = $script:Img[$kind]; if (-not $ix) { return '' }
    $alt = "$($gm.ImgName)".Trim(); $exts = ImgExtList; $bad = [IO.Path]::GetInvalidFileNameChars()
    foreach ($pt in (ImgPatterns $kind)) {
        if ($pt.Contains('{Alt}') -and -not $alt) { continue }
        $nm = $pt.Replace('{Alt}', $alt).Replace('{Nome}', "$($gm.Name)".Trim()).Replace('{Id}', "$($gm.Id)")
        $nm = ($nm.Split($bad) -join '').Trim()      # tira os caracteres proibidos do Windows (sem pipeline por letra)
        if (-not $nm) { continue }
        $hit = $ix.Exact[$nm.ToLowerInvariant()]
        if (-not $hit -and $ix.Loose.Count) { $k = ImgNorm $nm; if ($k) { $hit = $ix.Loose[$k] } }
        if ($hit) { foreach ($e in $exts) { if ($hit.ContainsKey($e)) { return [IO.Path]::Combine($ix.Dir, $hit[$e]) } } }
    }
    ''
}
# Caminho final da imagem do jogo: a cadastrada à mão (se o arquivo existe) -> a achada na pasta -> a cadastrada (ausente, para o aviso) -> ''.
function ImgPath($kind, $field, $gm) {
    $gid = "$($gm.Id)"; $mk = "$kind$gid"; $sd = "$($gm.$field)|$($gm.ImgName)|$($gm.Name)"; $sig = "$sd|$script:ImgGen"
    $m = $script:ImgMemo[$mk]; if ($m -and $m.Sig -eq $sig) { return $m.Path }
    $ex = Full $gm.$field; $res = $null; $rel = $null
    if ($ex -and [IO.File]::Exists($ex)) { $res = $ex }      # cadastrada à mão e existe: tem prioridade (nada a guardar)
    else {
        $ix = $script:Img[$kind]; $dm = ImgDiskMemo $kind
        if ($dm -and $ix) {      # já achada numa abertura anterior (pasta sem mudança e jogo com os mesmos dados)? O caminho é montado com a pasta de agora.
            $hit = $dm[$gid]
            if ($hit -and $hit[0] -ceq $sd) {
                if (-not $hit[1]) { $res = $ex; $rel = ''; $script:ImgHit++ }
                else { $pp = [IO.Path]::Combine($ix.Dir, $hit[1]); if ([IO.File]::Exists($pp)) { $res = $pp; $rel = $hit[1]; $script:ImgHit++ } }
            }
        }
        if ($null -eq $res) {
            $res = ImgFind $kind $gm; $script:ImgMiss++
            if ($res) { $rel = [IO.Path]::GetFileName($res) } else { $res = $ex; $rel = '' }
            $script:ImgMemoDirty = $true
        }
    }
    $script:ImgMemo[$mk] = @{ Sig = $sig; Path = $res; Kind = $kind; Id = $gid; Sd = $sd; Gen = $script:ImgGen; Rel = $rel }
    $res
}
function CoverPath($gm) {
    if ($script:HydraSystemCards) { $automatic=HydraGetCover $gm; if($automatic){return $automatic} }
    ImgPath 'Cover' 'Cover' $gm
}
function ShotPath($gm) { ImgPath 'Shot' 'Shot' $gm }
# Botão do modo dev: refaz os índices agora e mostra um resumo
function ImgRebuildReport {
    $ch = ImgEnsureAll $true; $script:ImgGen++; $script:ImgMemo = @{}; $script:ImgDMOff = $true; $script:ImgMemoDirty = $true
    CacheClear; $grid.Invalidate(); ShowGame (Sel)
    $nc = 0; $ns = 0; $sc = 0; $ss = 0
    foreach ($gm in $script:Games) {
        $p = CoverPath $gm; if ($p -and [IO.File]::Exists($p)) { $nc++ }
        $p = ShotPath $gm; if ($p -and [IO.File]::Exists($p)) { $ns++ }
    }
    $tot = $script:Games.Count
    $ci = $script:Img.Cover; $si = $script:Img.Shot
    $msg = "Capas: " + $(if ($ci) { "$($ci.Files.Count) arquivo(s) na pasta, $nc de $tot jogo(s) com capa" } else { 'pasta não configurada' }) + "`n" +
           "Capturas: " + $(if ($si) { "$($si.Files.Count) arquivo(s) na pasta, $ns de $tot jogo(s) com captura" } else { 'pasta não configurada' })
    [void][Windows.Forms.MessageBox]::Show($msg, 'Índice de imagens')
}

# ---- Execuções em andamento (extração de jogo compactado e extração de extras .rar) e início do jogo ----
$script:Runs = @()
function RunFind($id) { foreach ($r0 in $script:Runs) { if ($r0.Id -eq $id) { return $r0 } }; $null }
function RunRemove($run) { $script:Runs = @($script:Runs | Where-Object { $_ -ne $run }); RunStatus }
# v2.53.1: nada de status no título da janela (baixando/extraindo/apagando já aparece na capa e no nome do jogo)
function RunStatus { }
function GameStart($gm) {
    $exe = ExePath $gm
    $launchArguments=ArgsExpand $gm.Args ([IO.Path]::GetDirectoryName($exe))
    $launchPlan=@{Mode='direct';Arguments=$launchArguments}
    if(Get-Command HydraPrepareLaunch -ErrorAction SilentlyContinue){
        try {$launchPlan=HydraPrepareLaunch $gm $exe}
        catch {LogEx 'ERRO' 'Falha ao preparar abertura nativa do Hydra' $_;[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Erro');return}
        if($null -eq $launchPlan){return}
        $launchArguments=[string]$launchPlan.Arguments
    }
    if ([IO.Path]::GetFileName($exe) -ine 'hydra.exe') { UnblockGame $gm }
    if($script:TarginoMusicPlayer){TarginoPauseForGame}
    try {
        if ([IO.Path]::GetFileName($exe) -ieq 'hydra.exe') {
            foreach ($existingHydra in @([Diagnostics.Process]::GetProcessesByName('hydra'))) {
                if ($existingHydra.MainModule.FileName -ine $exe) { continue }
                [void]$existingHydra.CloseMainWindow()
                if (-not $existingHydra.WaitForExit(3000)) {
                    throw 'O Hydra anterior continua aberto. Feche-o para iniciar outro jogo.'
                }
            }
        }
        # ProcessStartInfo usa o caminho literal (Start-Process trataria [ ] no nome como curinga)
        $psi = New-Object Diagnostics.ProcessStartInfo $exe
        $psi.WorkingDirectory = [IO.Path]::GetDirectoryName($exe); $psi.UseShellExecute = $true
        $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
        $a = $launchArguments; if ($a) { $psi.Arguments = $a; Log 'INFO' "Argumentos de '$($gm.Name)': $a" }
        $pr = if($launchPlan.Mode -eq 'bridge'){HydraStartDirectProcess $exe $launchPlan}else{[Diagnostics.Process]::Start($psi)}
        Log 'INFO' ("Jogo '$($gm.Name)' iniciado" + $(if ($pr) { " (processo $($pr.Id))" }))
        try { PlayBegin $gm $pr } catch { LogEx 'AVISO' "Não foi possível acompanhar '$($gm.Name)': $($_.Exception.Message)" $_; if ($pr) { $pr.Dispose() } }   # capa mostra que está abrindo/rodando (v2.36.0)
    } catch {
        LogEx 'ERRO' "Falha ao iniciar '$($gm.Name)': $($_.Exception.Message)" $_
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Erro')
    } finally {
        if($script:TarginoMusicPlayer){TarginoGameLaunchFinished}
    }
}
# ---- Jogo em execução (v2.36.0): o launcher acompanha o processo que abriu e mostra isso na capa ----
#  Acompanhados: o processo iniciado + todos os processos filhos dele + qualquer processo cujo executável esteja dentro da
#  pasta do jogo (pega jogos que abrem por um "lançador" que fecha logo em seguida). A verificação é feita a cada 3 s (PlayCheckSec),
#  em C# (lista de processos do Windows), sem custo perceptível.
#  Fases: 'start' (aberto, a janela do jogo ainda não apareceu: capa escurecida + anel girando + "Iniciando...") e
#  'run' (já há uma janela visível do jogo: borda "respirando" + faixa "Em execução"). O jogo é considerado fechado
#  quando nenhum processo acompanhado existe por 2 verificações seguidas (e passaram ao menos 4 s da abertura).
#  Duplo clique / Enter / "Fechar jogo" num jogo em execução = encerra à força todos os processos acompanhados. Se mesmo
#  assim algum não fechar em ~2 s, o launcher considera encerrado e abre o jogo de novo.
#  A animação só é redesenhada com o launcher em primeiro plano (durante o jogo não gasta nada).
$script:GpSrc = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class GameProc
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct PE32
    {
        public uint dwSize; public uint cntUsage; public uint th32ProcessID; public IntPtr th32DefaultHeapID; public uint th32ModuleID;
        public uint cntThreads; public uint th32ParentProcessID; public int pcPriClassBase; public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32FirstW(IntPtr h, ref PE32 e);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32NextW(IntPtr h, ref PE32 e);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageNameW(IntPtr h, int flags, StringBuilder sb, ref int size);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    public static bool FocusLauncher(IntPtr h) { return SetForegroundWindow(h); }

    // pid -> pai, de todos os processos que existem agora
    static Dictionary<int, int> Snapshot()
    {
        Dictionary<int, int> all = new Dictionary<int, int>();
        IntPtr h = CreateToolhelp32Snapshot(2, 0);
        if (h == IntPtr.Zero || h == new IntPtr(-1)) return all;
        try
        {
            PE32 e = new PE32(); e.dwSize = (uint)Marshal.SizeOf(typeof(PE32));
            if (Process32FirstW(h, ref e))
            {
                do { all[(int)e.th32ProcessID] = (int)e.th32ParentProcessID; } while (Process32NextW(h, ref e));
            }
        }
        finally { CloseHandle(h); }
        return all;
    }
    static string ImagePath(int pid)
    {
        IntPtr h = OpenProcess(0x1000, false, pid);      // PROCESS_QUERY_LIMITED_INFORMATION
        if (h == IntPtr.Zero) return null;
        try
        {
            StringBuilder sb = new StringBuilder(1024); int n = sb.Capacity;
            return QueryFullProcessImageNameW(h, 0, sb, ref n) ? sb.ToString(0, n) : null;
        }
        finally { CloseHandle(h); }
    }
    // Processos do jogo agora: os conhecidos que ainda existem + os filhos deles + os que rodam de dentro da pasta do jogo
    public static int[] Track(int[] known, string dir, int self)
    {
        Dictionary<int, int> all = Snapshot();
        HashSet<int> set = new HashSet<int>();
        if (known != null) foreach (int p in known) if (p > 4 && p != self && all.ContainsKey(p)) set.Add(p);
        if (!string.IsNullOrEmpty(dir))
        {
            string d = dir.TrimEnd('\\') + "\\";
            foreach (int p in all.Keys)
            {
                if (p <= 4 || p == self || set.Contains(p)) continue;
                string img = ImagePath(p);
                if (img != null && img.StartsWith(d, StringComparison.OrdinalIgnoreCase)) set.Add(p);
            }
        }
        bool grew = true;
        while (grew)
        {
            grew = false;
            foreach (KeyValuePair<int, int> kv in all)
            {
                if (kv.Key <= 4 || kv.Key == self || set.Contains(kv.Key)) continue;
                if (kv.Value != kv.Key && set.Contains(kv.Value)) { set.Add(kv.Key); grew = true; }
            }
        }
        int[] r = new int[set.Count]; set.CopyTo(r); return r;
    }
    // Algum desses processos já tem uma janela visível de verdade (a do jogo)?
    public static bool HasWindow(int[] pids)
    {
        if (pids == null || pids.Length == 0) return false;
        HashSet<uint> set = new HashSet<uint>(); foreach (int p in pids) set.Add((uint)p);
        bool found = false;
        EnumProc cb = delegate (IntPtr w, IntPtr l)
        {
            if (!IsWindowVisible(w) || GetWindow(w, 4) != IntPtr.Zero) return true;      // invisível ou com dono (diálogo)
            uint pid; GetWindowThreadProcessId(w, out pid);
            if (set.Contains(pid)) { found = true; return false; }
            return true;
        };
        EnumWindows(cb, IntPtr.Zero); GC.KeepAlive(cb);
        return found;
    }
    // Encerra à força; devolve quantos foram encerrados
    public static int Kill(int[] pids)
    {
        int n = 0; if (pids == null) return 0;
        foreach (int p in pids)
        {
            if (p <= 4) continue;
            IntPtr h = OpenProcess(0x0001, false, p);      // PROCESS_TERMINATE
            if (h == IntPtr.Zero) continue;
            try { if (TerminateProcess(h, 1)) n++; } finally { CloseHandle(h); }
        }
        return n;
    }
}
'@
$script:Play = @{}
function PlayDir($gm) {   # pasta do jogo para procurar processos ('' se for ampla demais: a própria Jogos\ ou a raiz de uma unidade)
    $d = "$(XeGameDir $gm)".TrimEnd('\'); if (-not $d -or $d.Length -le 3) { return '' }
    if ($d -ieq ([IO.Path]::Combine($Root, 'Jogos')).TrimEnd('\') -or $d -ieq $Root.TrimEnd('\')) { return '' }
    $d
}
function PlayPids($p) {   # processos do jogo agora
    , ([GameProc]::Track([int[]]@($p.Pids), "$($p.Dir)", $PID))
}
function PlayBegin($gm, $pr) {
    $id = "$($gm.Id)"
    $pids = @(); if ($pr) { try { $pids = @([int]$pr.Id) } catch { $Error.Clear() } }
    $script:Play[$id] = @{ Id = $id; Name = "$($gm.Name)"; Game = $gm; Pids = [int[]]$pids; Dir = (PlayDir $gm); Start = (Get-Date); Phase = 'start'; Empty = 0; Idx = -1; Proc = $pr }
    if ($pr -and [IO.Path]::GetFileName((ExePath $gm)) -ieq 'hydra.exe') {
        $entry = $script:Play[$id]
        $entry.Hydra = $true
        $entry.CoreSeen = $false
        $entry.CoreMissing = 0
        $entry.ReturnRequested = $null
        $entry.ModuleErrorLogged = $false
        $entry.GameSeen = $false
        $entry.ReturnObserver = $null
        try {
            HydraLoadDirectBridge
            $entry.ReturnObserver = New-Object HydraDirectBridge+ReturnObserver($pr,(ExePath $gm))
        } catch { Log 'AVISO' 'Estado nativo de retorno indisponivel; usando acompanhamento do core.' }
        $entry.WindowState = $form.WindowState
        if ($hydraReturnTm) { $hydraReturnTm.Start() }
    }
    TileInvalidate $script:Play[$id] $id
    if ($playTm) { $iv = 1000 * [int]$script:Cfg.PlayCheck; if ($iv -ge 1000) { $playTm.Interval = $iv }; $playTm.Start() }; if ($playAnim) { $playAnim.Start() }
}
function PlayEnd($id, $why) {
    $p = $script:Play[$id]; if (-not $p) { return }
    if($p.Hydra -and (Get-Command HydraLiveEnd -ErrorAction SilentlyContinue)){try{HydraLiveEnd $p}catch{Log 'AVISO' 'Nao foi possivel concluir a memoria do tamanho da janela.'}}
    $nativeExit=$null
    TileInvalidate $script:Play[$id] $id
    $script:Play.Remove($id)
    try {
        if ($p.Proc) {
            if($p.Hydra -and $p.Proc.HasExited){
                $exitCode=$p.Proc.ExitCode
                $nativeExit=$exitCode
                Log $(if($exitCode -eq 0){'INFO'}else{'ERRO'}) ("Hydra encerrou com codigo $exitCode para '$($p.Name)'")
            }
            $p.Proc.Dispose()
        }
    } catch { $Error.Clear() }
    $min = [int]((Get-Date) - $p.Start).TotalMinutes
    Log 'INFO' "Jogo '$($p.Name)' $why (aberto por $min min)"
    if (-not $script:Play.Count) { if ($playTm) { $playTm.Stop() }; if ($playAnim) { $playAnim.Stop() } }
    $grid.Invalidate()
    if ($p.Hydra -and -not $form.IsDisposed -and $form.Visible) {
        if ($form.WindowState -eq 'Minimized') { $form.WindowState = $p.WindowState }
        $form.Show(); $form.BringToFront(); $form.Activate()
        [void][GameProc]::FocusLauncher($form.Handle)
        [void]$grid.Focus()
        Log 'INFO' 'Hydra encerrado; foco devolvido ao launcher'
    }
    if($script:TarginoMusicPlayer){TarginoMusicTick}
    if($null -ne $nativeExit -and $nativeExit -ne 0 -and -not $p.ReturnForced -and -not $form.IsDisposed -and $form.Visible){
        $message=HydraExitMessage $p $nativeExit
        [void][Windows.Forms.MessageBox]::Show($form,$message,'Hydra encerrou com erro',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)
    }
}
function HydraReturnTick {
    $active = $false
    foreach ($id in @($script:Play.Keys)) {
        $entry = $script:Play[$id]
        if (-not $entry -or -not $entry.Hydra -or -not $entry.Proc) { continue }
        $active = $true
        try {
            $entry.Proc.Refresh()
            if ($entry.Proc.HasExited) { PlayEnd $id 'fechou'; continue }
            if(Get-Command HydraLiveTick -ErrorAction SilentlyContinue){HydraLiveTick $entry}
            if ($null -ne $entry.ReturnRequested) {
                # Fecha de forma normal para o Hydra concluir a gravação de saves.
                $closingSeconds=((Get-Date) - $entry.ReturnRequested).TotalSeconds
                if ($closingSeconds -ge 15 -and -not $entry.ReturnForced) {
                    Log 'AVISO' 'Hydra sem jogo ativo nao concluiu o fechamento em 15 s; encerrando somente o processo acompanhado.'
                    $entry.Proc.Kill();$entry.ReturnForced=$true
                } elseif ($closingSeconds -ge 5 -and -not $entry.ReturnRetried) {
                    $entry.ReturnRetried = $true
                    [void]$entry.Proc.CloseMainWindow()
                }
                continue
            }
            $nativeState=-1
            if($entry.ReturnObserver){$nativeState=$entry.ReturnObserver.ReadGameState()}
            if($nativeState -ge 0){
                if($nativeState -eq 1){$entry.GameSeen=$true;$entry.CoreMissing=0}
                elseif($entry.GameSeen){
                    $entry.CoreMissing++
                    if($entry.CoreMissing -ge 2){
                        Log 'INFO' "Hydra voltou a biblioteca apos '$($entry.Name)' (jogo descarregado, mesmo com DLL presente); solicitando fechamento"
                        $entry.ReturnRequested=Get-Date
                        [void]$entry.Proc.CloseMainWindow()
                    }
                }
                continue
            }
            $coreLoaded = $false
            foreach ($module in $entry.Proc.Modules) {
                if ($module.ModuleName -like '*_libretro.dll') { $coreLoaded = $true; break }
            }
            if ($coreLoaded) {
                $entry.CoreSeen = $true; $entry.CoreMissing = 0
            } elseif ($entry.CoreSeen) {
                $entry.CoreMissing++
                if ($entry.CoreMissing -ge 2) {
                    Log 'INFO' "Hydra voltou à biblioteca após '$($entry.Name)'; solicitando fechamento"
                    $entry.ReturnRequested = Get-Date
                    [void]$entry.Proc.CloseMainWindow()
                }
            }
        } catch {
            if (-not $entry.ModuleErrorLogged) {
                LogEx 'AVISO' 'Falha ao verificar retorno do Hydra à biblioteca' $_
                $entry.ModuleErrorLogged = $true
            }
        }
    }
    if (-not $active) { $hydraReturnTm.Stop() }
}
function PlayTick {
    $iv = 1000 * [int]$script:Cfg.PlayCheck; if ($iv -ge 1000 -and $playTm.Interval -ne $iv) { $playTm.Interval = $iv }   # padrão 3 s (painel dev)
    foreach ($id in @($script:Play.Keys)) {
        $p = $script:Play[$id]; if (-not $p) { continue }
        try {
            $now = PlayPids $p
            $age = ((Get-Date) - $p.Start).TotalSeconds
            if ($now.Length) {
                $p.Pids = $now; $p.Empty = 0
                if ($p.Phase -eq 'start') {
                    $win = [GameProc]::HasWindow($now)
                    if ($win -or $age -ge 90) { $p.Phase = 'run'; Log 'INFO' "Jogo '$($p.Name)' em execução ($([int]$age) s para abrir a janela; processos: $($now -join ', '))"; TileInvalidate $script:Play[$id] $id }
                }
            } else {
                $p.Empty++
                if ($p.Empty -ge 2 -and $age -ge 4) { PlayEnd $id 'fechou' }
            }
        } catch { LogEx 'AVISO' "Falha ao acompanhar o jogo '$($p.Name)': $($_.Exception.Message)" $_; PlayEnd $id 'deixou de ser acompanhado (erro)' }
    }
}
# Duplo clique / Enter / "Fechar jogo" com o jogo aberto: encerra à força
function PlayStop($gm) {
    $id = "$($gm.Id)"; $p = $script:Play[$id]; if (-not $p) { return }
    $pids = PlayPids $p
    Log 'INFO' "Encerrando à força '$($p.Name)' (processos: $(if ($pids.Length) { $pids -join ', ' } else { 'nenhum' }))"
    [void][GameProc]::Kill($pids)
    $left = $pids
    for ($k = 0; $k -lt 20 -and $left.Length; $k++) { Start-Sleep -Milliseconds 100; $left = PlayPids $p }
    if (-not $left.Length) { PlayEnd $id 'encerrado pelo launcher'; return }
    Log 'AVISO' "'$($p.Name)': processo(s) $($left -join ', ') não fecharam; considerado encerrado, abrindo o jogo de novo"
    PlayEnd $id 'considerado encerrado (não fechou)'
    if ($p.Extra) { ExtraRun $gm $p.Extra } else { Launch $gm }      # reabre o que estava aberto: o extra ou o jogo (v2.40.0)
}
# Redesenha só o quadrado do jogo $id; $e = entrada de $script:Play ou $script:Ext (guarda a última posição na lista em Idx)
function TileInvalidate($e, $id) {
    $met = $script:Met; if (-not $e -or -not $met) { return }
    $i = [int]$e.Idx
    if ($i -lt 0 -or $i -ge $script:View.Count -or "$($script:View[$i].Id)" -ne $id) {
        $i = -1; for ($k = 0; $k -lt $script:View.Count; $k++) { if ("$($script:View[$k].Id)" -eq $id) { $i = $k; break } }
        $e.Idx = $i
    }
    if ($i -lt 0) { return }
    $xy = TileXY $met $i; $ry = $xy[1] - [int]$vsb.Value
    if ($ry + $met.CellH -lt 0 -or $ry -gt $grid.ClientSize.Height) { return }
    $grid.Invalidate((New-Object Drawing.Rectangle ([int]$xy[0]), ([int]$ry), ([int]$met.CellW), ([int]$met.CellH)))
}
$script:PlayLastRun = [DateTime]::MinValue
function PlayAnim {   # ~14 quadros/s no "Iniciando..."; ~10/s no pulso de "Em execução"; nada com o launcher em segundo plano
    if ($form.WindowState -eq 'Minimized' -or [Windows.Forms.Form]::ActiveForm -ne $form) { return }
    $now = Get-Date; $slow = (($now - $script:PlayLastRun).TotalMilliseconds -ge 100); if ($slow) { $script:PlayLastRun = $now }
    foreach ($id in @($script:Play.Keys)) { $p = $script:Play[$id]; if ($p -and ($p.Phase -eq 'start' -or $slow)) { TileInvalidate $script:Play[$id] $id } }
}
function PlayText($key, $def) { $t = "$($S[$key])"; if ($t.Trim()) { $t } else { $def } }
# Por cima da capa: pulso (véu na cor da borda + borda forte "respirando"); no "Iniciando" também capa escurecida + anel girando.
# O texto com a bolinha vai no lugar do nome do jogo (PaintPlayLabel); sem nomes na grade, vai numa faixa sobre a capa.
function PaintPlaying($gr, $c, $gx, $p, $rect, $met) {
    $t = [double](Get-Date).Ticks / 1e7; $ac = $c.Accent; $bc = $c.PlayBorder; $k = [double]$c.PlayPulse / 100.0
    $oldS = $gr.SmoothingMode; $gr.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $res = New-Object System.Collections.ArrayList
    try {
        $br = (1 + [Math]::Sin($t * $(if ($p.Phase -eq 'start') { 4.2 } else { 2.6 }))) / 2.0      # 0..1, "respiração"
        if ($p.Phase -eq 'start') {
            $veil = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(120, 0, 0, 0)); [void]$res.Add($veil); $gr.FillRectangle($veil, $rect)
            $rad = [single][Math]::Max(12, [Math]::Min(26, $rect.Width * 0.14)); $cx = [single]($rect.X + $rect.Width / 2.0); $cy = [single]($rect.Y + $rect.Height / 2.0)
            $disc = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(150, 0, 0, 0)); [void]$res.Add($disc)
            $gr.FillEllipse($disc, $cx - $rad - 8, $cy - $rad - 8, 2 * $rad + 16, 2 * $rad + 16)
            $trk = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(55, 255, 255, 255)), ([single]3); [void]$res.Add($trk)
            $gr.DrawEllipse($trk, $cx - $rad, $cy - $rad, 2 * $rad, 2 * $rad)
            $arc = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(245, $ac.R, $ac.G, $ac.B)), ([single]3); $arc.StartCap = 'Round'; $arc.EndCap = 'Round'; [void]$res.Add($arc)
            $a0 = [single](($t * 330) % 360); $sw = [single](70 + 50 * [Math]::Sin($t * 3.2))
            $gr.DrawArc($arc, $cx - $rad, $cy - $rad, 2 * $rad, 2 * $rad, $a0, $sw)
        }
        if ($k -gt 0) {
            # véu na cor da borda que acende e apaga sobre a capa inteira
            $tint = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int](70 * $k * $br), $bc.R, $bc.G, $bc.B)); [void]$res.Add($tint)
            $gr.FillRectangle($tint, $rect)
            # brilho largo por dentro + borda forte
            $gw = [single](4 + 8 * $k)
            $glow = New-Object Drawing.Pen ([Drawing.Color]::FromArgb([int]([Math]::Min(255, (30 + 140 * $br) * $k)), $bc.R, $bc.G, $bc.B)), $gw; [void]$res.Add($glow)
            $gr.DrawRectangle($glow, [single]($rect.X + $gw / 2), [single]($rect.Y + $gw / 2), [single]($rect.Width - $gw - 1), [single]($rect.Height - $gw - 1))
            $edge = New-Object Drawing.Pen ([Drawing.Color]::FromArgb([int](110 + 145 * $br), $bc.R, $bc.G, $bc.B)), ([single]3); [void]$res.Add($edge)
            $gr.DrawRectangle($edge, [single]($rect.X + 1.5), [single]($rect.Y + 1.5), [single]($rect.Width - 4), [single]($rect.Height - 4))
        }
        if ($met.NameH -le 0) {      # grade sem nomes: o texto vai numa faixa escura sobre a capa
            $bh = [int][Math]::Min(30, [Math]::Max(22, $rect.Height * 0.16))
            $band = New-Object Drawing.Rectangle $rect.X, ($rect.Bottom - $bh), $rect.Width, $bh
            $gb = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.Rectangle $band.X, ($band.Y - 1), $band.Width, ($band.Height + 1))), ([Drawing.Color]::FromArgb(0, 0, 0, 0)), ([Drawing.Color]::FromArgb(210, 0, 0, 0)), ([single]90); [void]$res.Add($gb)
            $gr.FillRectangle($gb, $band)
            PaintPlayLabel $gr $c $gx $p (New-Object Drawing.RectangleF ([single]$band.X), ([single]$band.Y), ([single]$band.Width), ([single]$bh)) $true
        }
    } finally {
        foreach ($o in $res) { try { $o.Dispose() } catch { $Error.Clear() } }
        $gr.SmoothingMode = $oldS
    }
}
# Bolinha pulsando + "Iniciando..."/"Em execução", centralizados na 1ª linha do nome (ou no meio da faixa)
function PaintPlayLabel($gr, $c, $gx, $p, $tr, $mid, $lbl = '') {      # $lbl: texto próprio (ex.: "Extraindo seu jogo", v2.48.0)
    $t = [double](Get-Date).Ticks / 1e7; $dc = $c.PlayDot; $fnt = $gx.PlayFont
    $txt = if ($lbl) { $lbl } elseif ($p.Phase -eq 'start') { PlayText 'T_Starting' 'Iniciando...' } else { PlayText 'T_Running' 'Em execução' }
    $oldS = $gr.SmoothingMode; $gr.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $res = New-Object System.Collections.ArrayList
    try {
        $lh = [single]$fnt.GetHeight($gr); $ym = if ($mid) { [single]($tr.Y + $tr.Height / 2.0) } else { [single]($tr.Y + $lh / 2.0) }
        $dot = [single]$c.PlayDotSize; $gap = [single][Math]::Max(5, $dot * 0.7)
        $tw = [single]$gr.MeasureString($txt, $fnt).Width; $tw = [single][Math]::Min($tw, [Math]::Max(10, $tr.Width - $dot - $gap - 8))
        $x0 = [single]($tr.X + ($tr.Width - ($dot + $gap + $tw)) / 2.0)
        $pul = (1 + [Math]::Sin($t * 3.4)) / 2.0
        $halo = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int](50 + 90 * $pul), $dc.R, $dc.G, $dc.B)); [void]$res.Add($halo)
        $hr = [single]($dot / 2 + 1 + ($dot * 0.45) * $pul); $dcx = [single]($x0 + $dot / 2)
        $gr.FillEllipse($halo, $dcx - $hr, $ym - $hr, 2 * $hr, 2 * $hr)
        $db = New-Object Drawing.SolidBrush ($dc); [void]$res.Add($db)
        $gr.FillEllipse($db, $x0, $ym - $dot / 2, $dot, $dot)
        $tb = New-Object Drawing.SolidBrush ($c.PlayTxt); [void]$res.Add($tb)
        $gr.DrawString($txt, $fnt, $tb, (New-Object Drawing.RectangleF ($x0 + $dot + $gap), ([single]($ym - $lh / 2.0 - 1)), ([single]($tw + 6)), ([single]($lh + 2))), $gx.FmtL)
    } finally {
        foreach ($o in $res) { try { $o.Dispose() } catch { $Error.Clear() } }
        $gr.SmoothingMode = $oldS
    }
}
# Texto da capa durante a extração (v2.48.0): jogo = "Extraindo seu jogo" (T_Extracting); extra .rar = "Extraindo <nome do extra>"
function ExtLabel($id) {
    $elR = RunFind $id
    if ($elR -and $elR.Stage -eq 'extra' -and $elR.UP) { return "Extraindo $($elR.UP.Label)" }
    if ($elR -and $elR.Stage -eq 'dl') { return (PlayText 'T_Downloading' 'Baixando seu jogo') }      # v2.53.0: download pelo Telegram
    PlayText 'T_Extracting' 'Extraindo seu jogo'
}
# Grade sem nomes: o texto vai numa faixa escura sobre a capa (como no "Em execução")
function PaintBandLabel($gr, $c, $gx, $rect, $lbl) {
    $bh = [int][Math]::Min(30, [Math]::Max(22, $rect.Height * 0.16))
    $band = New-Object Drawing.Rectangle $rect.X, ($rect.Bottom - $bh), $rect.Width, $bh
    $gb = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.Rectangle $band.X, ($band.Y - 1), $band.Width, ($band.Height + 1))), ([Drawing.Color]::FromArgb(0, 0, 0, 0)), ([Drawing.Color]::FromArgb(210, 0, 0, 0)), ([single]90)
    try { $gr.FillRectangle($gb, $band) } finally { $gb.Dispose() }
    PaintPlayLabel $gr $c $gx $null (New-Object Drawing.RectangleF ([single]$band.X), ([single]$band.Y), ([single]$band.Width), ([single]$bh)) $true $lbl
}
# ---- Desbloqueio de arquivos vindos da internet (marca "Zone.Identifier" / Mark-of-the-Web) ----
#  Toda vez que um jogo (ou um extra que é programa) é executado, o launcher apaga antes a marca dos .exe, .bat e .cmd da pasta do jogo
#  (inclusive subpastas), para o Windows não bloquear / perguntar "deseja executar?" / SmartScreen (v2.47.0). Também roda depois de
#  extrair um extra .rar. É o mesmo efeito de Propriedades > Desbloquear. Arquivo já desbloqueado é só pulado (custo baixo).
#  Núcleo em C# (DeleteFileW no fluxo ":Zone.Identifier"), compilado junto com os outros componentes (CoreLoad).
#  Sistemas de arquivos sem fluxos (FAT/exFAT) não têm a marca: não é erro. Falha nunca impede o jogo de abrir.
$script:UbSrc = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
// Arquivos e pastas com caminho longo (v2.49.0): o PowerShell 5.1 (.NET no modo antigo) não passa de 260 caracteres.
// Aqui tudo vai direto ao Windows com o prefixo \\?\ (sem limite prático), sem custo extra.
public static class CaFs
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct FIND_DATA
    {
        public uint attr; public System.Runtime.InteropServices.ComTypes.FILETIME c, a, w;
        public uint sizeHigh, sizeLow, res0, res1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string alt;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr FindFirstFileExW(string p, int level, out FIND_DATA d, int op, IntPtr f, int flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool FindNextFileW(IntPtr h, out FIND_DATA d);
    [DllImport("kernel32.dll")] static extern bool FindClose(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool DeleteFileW(string p);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool RemoveDirectoryW(string p);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool SetFileAttributesW(string p, uint a);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern uint GetFileAttributesW(string p);
    public static string LastError = "";
    public static string L(string p)      // caminho com o prefixo de caminho longo
    {
        if (string.IsNullOrEmpty(p)) return p;
        p = p.Replace('/', '\\');
        if (p.StartsWith("\\\\?\\")) return p;
        if (p.StartsWith("\\\\")) return "\\\\?\\UNC\\" + p.Substring(2);
        return "\\\\?\\" + p;
    }
    // Conteúdo de UMA pasta: arquivos (com tamanho), subpastas normais e atalhos/junções (nunca seguidos). false = não deu para ler.
    public static bool Scan(string dir, List<string> files, List<long> sizes, List<string> subs, List<string> links)
    {
        FIND_DATA d; string bs = dir.TrimEnd('\\') + "\\";
        IntPtr h = FindFirstFileExW(L(bs + "*"), 1, out d, 0, IntPtr.Zero, 2);      // FindExInfoBasic, FIND_FIRST_EX_LARGE_FETCH
        if (h == new IntPtr(-1)) { int e = Marshal.GetLastWin32Error(); if (e == 2 || e == 18) return true; LastError = dir + " (erro " + e + ")"; return false; }
        try
        {
            do
            {
                if (d.name == "." || d.name == "..") continue;
                string full = bs + d.name;
                if ((d.attr & 0x10) != 0)
                {
                    if ((d.attr & 0x400) != 0) { if (links != null) links.Add(full); }
                    else if (subs != null) subs.Add(full);
                }
                else
                {
                    if (files != null) files.Add(full);
                    if (sizes != null) sizes.Add(((long)d.sizeHigh << 32) | d.sizeLow);
                }
            } while (FindNextFileW(h, out d));
        }
        finally { FindClose(h); }
        return true;
    }
    public static bool DelFile(string f)      // tira o "somente leitura" e apaga
    {
        string lp = L(f); uint a = GetFileAttributesW(lp);
        if (a != 0xFFFFFFFF && (a & 1) != 0) SetFileAttributesW(lp, 0x80);
        if (DeleteFileW(lp)) return true;
        LastError = f + " (erro " + Marshal.GetLastWin32Error() + ")"; return false;
    }
    public static bool DelDir(string d)      // pasta vazia (ou atalho/junção: remove só o atalho)
    {
        string lp = L(d); uint a = GetFileAttributesW(lp);
        if (a != 0xFFFFFFFF && (a & 1) != 0) SetFileAttributesW(lp, a & ~1u);
        if (RemoveDirectoryW(lp)) return true;
        LastError = d + " (erro " + Marshal.GetLastWin32Error() + ")"; return false;
    }
    public static bool Exists(string d) { uint a = GetFileAttributesW(L(d)); return a != 0xFFFFFFFF && (a & 0x10) != 0; }
    public static long Bytes(string dir)      // soma dos tamanhos (progresso da extração)
    {
        long sum = 0; Stack<string> st = new Stack<string>(); st.Push(dir);
        List<string> subs = new List<string>(); List<long> sizes = new List<long>();
        while (st.Count > 0)
        {
            subs.Clear(); sizes.Clear();
            Scan(st.Pop(), null, sizes, subs, null);
            foreach (long z in sizes) sum += z;
            foreach (string sd in subs) st.Push(sd);
        }
        return sum;
    }
    public static bool DeleteTree(string dir)      // apaga a pasta inteira; atalhos/junções dentro dela são removidos sem tocar no destino
    {
        if (!Exists(dir)) return true;
        bool ok = true;
        List<string> files = new List<string>(), subs = new List<string>(), links = new List<string>();
        if (!Scan(dir, files, null, subs, links)) return false;
        foreach (string f in files) if (!DelFile(f)) ok = false;
        foreach (string lk in links) if (!DelDir(lk)) ok = false;
        foreach (string sd in subs) if (!DeleteTree(sd)) ok = false;
        if (ok && !DelDir(dir)) ok = false;
        return ok;
    }
}
public static class CaUnblock
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool DeleteFileW(string lpFileName);
    public static int Scanned, Cleared, Failed;
    public static string LastError = "";
    static bool Wanted(string file, string[] exts)
    {
        string x = Path.GetExtension(file);
        if (string.IsNullOrEmpty(x)) return false;
        for (int i = 0; i < exts.Length; i++) { if (string.Equals(x, exts[i], StringComparison.OrdinalIgnoreCase)) return true; }
        return false;
    }
    public static void Run(string root, string[] exts)
    {
        Scanned = 0; Cleared = 0; Failed = 0; LastError = "";
        Stack<string> pending = new Stack<string>();
        pending.Push(root);
        List<string> files = new List<string>(), subs = new List<string>();
        while (pending.Count > 0)
        {
            string dir = pending.Pop();
            files.Clear(); subs.Clear();
            if (!CaFs.Scan(dir, files, null, subs, null)) { Failed++; LastError = CaFs.LastError; continue; }      // atalhos/junções não são seguidos
            foreach (string f in files)
            {
                if (!Wanted(f, exts)) continue;
                Scanned++;
                if (DeleteFileW(CaFs.L(f) + ":Zone.Identifier")) { Cleared++; continue; }
                int err = Marshal.GetLastWin32Error();
                if (err == 2 || err == 3 || err == 87 || err == 123) continue;      // sem marca (ou sistema de arquivos sem fluxos)
                Failed++; LastError = f + " (erro " + err + ")";
            }
            foreach (string sd in subs) pending.Push(sd);
        }
    }
}
'@
$script:UbExts = @('.exe', '.bat', '.cmd')
function UnblockTree($ubDir, $ubName) {
    if (-not $ubDir -or -not [IO.Directory]::Exists($ubDir)) { return }
    $ubSw = [Diagnostics.Stopwatch]::StartNew(); $ubFound = 0; $ubClear = 0; $ubBad = 0; $ubLast = ''
    try {
        [CaUnblock]::Run($ubDir, [string[]]$script:UbExts)
        $ubFound = [CaUnblock]::Scanned; $ubClear = [CaUnblock]::Cleared; $ubBad = [CaUnblock]::Failed; $ubLast = [CaUnblock]::LastError
    } catch { $ubBad++; $ubLast = $_.Exception.Message; $Error.Clear() }
    Log 'INFO' "Desbloqueio de '$ubName': $ubFound arquivo(s) .exe/.bat/.cmd verificado(s), $ubClear liberado(s) em $($ubSw.ElapsedMilliseconds) ms"
    if ($ubBad) { Log 'AVISO' "Desbloqueio de '$ubName': $ubBad falha(s); última: $ubLast" }
}
function UnblockGame($gm) {   # pasta do jogo (1º nível de Jogos\); nunca a própria Jogos\, a pasta do launcher ou a raiz de uma unidade
    try {
        $ubG = GameFolder $gm; if (-not $ubG) { return }
        $ubD = "$($ubG.Folder)".TrimEnd('\')
        if ($ubD.Length -le 3 -or $ubD -ieq $Root.TrimEnd('\') -or $ubD -ieq ([IO.Path]::Combine($Root, 'Jogos')).TrimEnd('\')) { return }
        UnblockTree $ubD "$($gm.Name)"
    } catch { LogEx 'AVISO' "Desbloqueio de '$($gm.Name)' falhou: $($_.Exception.Message)" $_ }      # nunca impede o jogo de abrir
}
# ---- Deletar jogo (menu do botão direito; só jogo instalado) ----
#  Apaga a PASTA do jogo inteira, mas SÓ se ela for uma pasta de 1º nível dentro de Jogos\ (nunca o próprio Jogos\, nunca algo fora dele,
#  nunca pasta que seja atalho/junção). O jogo continua no catálogo e passa a "não instalado". Sem threads e sem cmd.exe: um timer apaga
#  em fatias de ~40 ms (a janela não trava), tira o "somente leitura" de cada arquivo, e relata o que não deu para apagar (jogo aberto, antivírus...).
$script:Del = @{}
function JogosSub($dsPath) {   # texto puro (sem acessar o disco): devolve Jogos\<pasta> se o caminho estiver dentro de uma pasta de 1º nível de Jogos\, senão ''
    if (-not $dsPath) { return '' }
    $dsSep = [string][IO.Path]::DirectorySeparatorChar; $dsJd = [IO.Path]::Combine($Root, 'Jogos')
    if (-not $dsPath.StartsWith($dsJd + $dsSep, 'OrdinalIgnoreCase')) { return '' }
    $dsFirst = $dsPath.Substring($dsJd.Length + 1).Split($dsSep)[0]
    if (-not $dsFirst -or $dsPath.Length -le ($dsJd.Length + 1 + $dsFirst.Length)) { return '' }      # executável solto direto em Jogos\
    $dsJd + $dsSep + $dsFirst
}
function DeleteFolderOf($gm) {   # pasta que "Deletar jogo" apagaria ou '' se não puder (fora de Jogos\, ausente ou atalho)
    $dfp = JogosSub (ExePath $gm); if (-not $dfp) { return '' }
    try {
        if (-not [IO.Directory]::Exists($dfp)) { return '' }
        if (([int][IO.File]::GetAttributes($dfp) -band 1024) -ne 0) { return '' }      # 1024 = ReparsePoint (atalho/junção)
    } catch { $Error.Clear(); return '' }
    $dfp
}
function DeleteGame($gm) {
    if (-not $gm) { return }
    $dgId = "$($gm.Id)"
    if ($script:Del.ContainsKey($dgId)) { return }
    if (RunFind $dgId) { return }
    if ($script:Play.ContainsKey($dgId)) { [void][Windows.Forms.MessageBox]::Show("'$($gm.Name)' está aberto. Feche o jogo antes de deletar.", 'Deletar jogo'); return }
    $dgFolder = DeleteFolderOf $gm
    if (-not $dgFolder) {
        Log 'AVISO' "Deletar '$($gm.Name)' recusado: a pasta do jogo não está diretamente dentro de Jogos\ (ou não existe mais)"
        [void][Windows.Forms.MessageBox]::Show("Por segurança, o launcher só apaga pastas que estejam diretamente dentro de 'Jogos'.`nEste jogo está em outro lugar (ou a pasta não existe mais).", 'Deletar jogo', 'OK', 'Information'); return
    }
    $dgOthers = @()
    foreach ($og in $script:Games) { if ("$($og.Id)" -ne $dgId -and (JogosSub (ExePath $og)) -ieq $dgFolder) { $dgOthers += "$($og.Name)" } }
    $dgMsg = "Deletar o jogo '$($gm.Name)' do disco?`n`nPasta: $(Short $dgFolder)`n`nTudo o que está dentro dessa pasta (inclusive saves e configurações guardados nela) será apagado DEFINITIVAMENTE, sem passar pela Lixeira. O jogo continua na lista, como não instalado."
    if ($dgOthers.Count) {
        $dgShow = @($dgOthers | Select-Object -First 5)
        $dgMsg += "`n`nATENÇÃO: esta mesma pasta também é usada por: " + ($dgShow -join ', ') + $(if ($dgOthers.Count -gt 5) { " e mais $($dgOthers.Count - 5)" } else { '' }) + '.'
    }
    $dgMsg += "`n`nFeche o jogo antes de continuar."
    if ([Windows.Forms.MessageBox]::Show($dgMsg, 'Deletar jogo', 'YesNo', 'Warning', 'Button2') -ne 'Yes') { return }
    $script:Del[$dgId] = @{ Id = $dgId; Name = "$($gm.Name)"; Game = $gm; Folder = $dgFolder; Phase = 'scan'; Dirs = $null; Links = $null; Idx = -1
                            FileList = $null; FPos = 0; DirBad = $false; Files = 0; Fail = 0; Last = ''; Sw = [Diagnostics.Stopwatch]::StartNew() }
    Log 'INFO' "Deletando o jogo '$($gm.Name)': $(Short $dgFolder)"
    RunStatus; $delTm.Start()
}
function DelStep($dl) {
    $dlSw = [Diagnostics.Stopwatch]::StartNew()
    if ($dl.Phase -eq 'scan') {
        $dl.Dirs = New-Object 'Collections.Generic.List[string]'; $dl.Links = New-Object 'Collections.Generic.List[string]'
        $dlStack = New-Object 'Collections.Generic.Stack[string]'; $dlStack.Push($dl.Folder)
        while ($dlStack.Count -gt 0) {
            $dlD = $dlStack.Pop(); $dl.Dirs.Add($dlD)
            $dlSubs = New-Object 'Collections.Generic.List[string]'      # v2.49.0: varredura com caminho longo (CaFs)
            if ([CaFs]::Scan($dlD, $null, $null, $dlSubs, $dl.Links)) { foreach ($dlSub in $dlSubs) { $dlStack.Push($dlSub) } } else { $dl.Fail++; $dl.Last = [CaFs]::LastError }
        }
        foreach ($dlLk in $dl.Links) {      # atalho/junção dentro do jogo: remove só o atalho, nunca o conteúdo para onde ele aponta
            if (-not [CaFs]::DelDir($dlLk)) { $dl.Fail++; $dl.Last = [CaFs]::LastError }
        }
        $dl.Idx = $dl.Dirs.Count - 1; $dl.Phase = 'run'; return
    }
    # fase 'run': pastas na ordem inversa da varredura (filhas antes das mães); em cada uma apaga os arquivos e depois a pasta vazia
    while ($dl.Idx -ge 0) {
        $dlD = $dl.Dirs[$dl.Idx]
        if ($null -eq $dl.FileList) {
            $dlFl = New-Object 'Collections.Generic.List[string]'
            if (-not [CaFs]::Scan($dlD, $dlFl, $null, $null, $null)) { $dl.Fail++; $dl.Last = [CaFs]::LastError; $dl.DirBad = $true }
            $dl.FileList = $dlFl.ToArray()
            $dl.FPos = 0
        }
        while ($dl.FPos -lt $dl.FileList.Length) {
            $dlF = $dl.FileList[$dl.FPos]; $dl.FPos++
            if ([CaFs]::DelFile($dlF)) { $dl.Files++ } else { $dl.Fail++; $dl.Last = [CaFs]::LastError; $dl.DirBad = $true }      # tira o "somente leitura" e apaga
            if ($dlSw.ElapsedMilliseconds -ge 40) { return }
        }
        if (-not $dl.DirBad) {
            if (-not [CaFs]::DelDir($dlD)) { $dl.Fail++; $dl.Last = [CaFs]::LastError }
        }
        $dl.FileList = $null; $dl.DirBad = $false; $dl.Idx--
        if ($dlSw.ElapsedMilliseconds -ge 40) { return }
    }
    $dl.Phase = 'end'
}
function DelFinish($dl) {
    $script:Del.Remove($dl.Id)
    $dlLeft = [IO.Directory]::Exists($dl.Folder)
    $dlSecs = [Math]::Round($dl.Sw.Elapsed.TotalSeconds, 1)
    if ($dl.Fail -or $dlLeft) { Log 'AVISO' "Jogo '$($dl.Name)' apagado parcialmente: $($dl.Files) arquivo(s) apagado(s), $($dl.Fail) falha(s); última: $($dl.Last)" }
    else { Log 'INFO' "Jogo '$($dl.Name)' deletado: $($dl.Files) arquivo(s) em $dlSecs s ($(Short $dl.Folder))" }
    $script:Drive = @{}; $script:PathSeen = @{}
    try { [void](CheckGame $dl.Game); InstSave; Populate; ShowGame (Sel) } catch { LogEx 'AVISO' "Falha ao atualizar a lista depois de deletar: $($_.Exception.Message)" $_ }
    RunStatus
    if ($dl.Fail -or $dlLeft) {
        [void][Windows.Forms.MessageBox]::Show("Não foi possível apagar tudo de '$($dl.Name)'.`n$($dl.Fail) item(ns) não puderam ser apagados (o jogo ou algum arquivo dele pode estar aberto).`nÚltimo: $(Short $dl.Last)`n`nFeche o jogo e tente de novo.", 'Deletar jogo', 'OK', 'Warning')
    }
}
function DelTick {
    foreach ($dlId in @($script:Del.Keys)) {
        $dl = $script:Del[$dlId]
        try { DelStep $dl }
        catch { LogEx 'ERRO' "Falha ao deletar '$($dl.Name)': $($_.Exception.Message)" $_; $dl.Fail++; $dl.Last = "$($_.Exception.Message)"; $dl.Phase = 'end' }
        if ($dl.Phase -eq 'end') { DelFinish $dl }
    }
    if (-not $script:Del.Count) { $delTm.Stop() }
}
# ---- Extração automática de jogo compactado (UnRAR) ----
#  Só roda quando a pessoa manda jogar um jogo no estado 'archived'. Fluxo: lista o arquivo (tamanho total) -> confere espaço livre ->
#  extrai para uma pasta temporária ao lado (.ca_ + código curto do nome, para não estourar o limite de caminho do Windows) -> move para a pasta final -> depois abre o jogo. Senha: ArchivePass (painel dev). Várias partes: só a primeira é passada ao UnRAR; só após sucesso confirmado todas as partes são apagadas.
#  O progresso é desenhado na própria capa (ela vai ganhando cor de baixo para cima) e termina com um sinal discreto (sem números/letras).
#  UnrarPath (relativo ao launcher) aponta para o UnRAR.exe do WinRAR. Senha: ArchivePass (vazio = -p-: arquivo protegido falha em vez de travar).
$script:Ext = @{}
function UnrarExe { $ur = "$($S.UnrarPath)".Trim(); if (-not $ur) { $ur = $Defaults.UnrarPath }; Full $ur }
function ProcRedirect($file, $argText) {
    $psi = New-Object Diagnostics.ProcessStartInfo; $psi.FileName = $file; $psi.Arguments = $argText
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $pr = [Diagnostics.Process]::Start($psi)
    try { $pr.StandardInput.Close() } catch { $Error.Clear() }
    @{ Proc = $pr; Out = $pr.StandardOutput.ReadToEndAsync(); Err = $pr.StandardError.ReadToEndAsync() }
}
# Argumento de senha do UnRAR: -p-  (sem senha) ou "-pSENHA" (aspas escapadas). Nunca vai para o log.
#  Sem parâmetro = senha dos jogos (ArchivePass); a atualização passa a própria (UpdPass, v2.52.0).
function PassArg($pw = "$($S.ArchivePass)") {
    $pw = "$pw"
    if (-not $pw) { return '-p-' }
    $pw = $pw -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1'
    '"-p' + $pw + '"'
}
function ProcDone($pp) { $pp.Proc.HasExited -and $pp.Out.IsCompleted -and $pp.Err.IsCompleted }
function DirBytes($dir) { try { [CaFs]::Bytes($dir) } catch { $Error.Clear(); [long]0 } }      # v2.49.0: caminho longo e mais rápido (tamanho vem da própria listagem)
function UnpackFail($run, $why) {
    $id = "$($run.Id)"; $up = $run.UP
    Log 'ERRO' "Extração de '$($run.Name)' falhou: $why"
    if ($up -and $up.Proc) { try { if (-not $up.Proc.Proc.HasExited) { $up.Proc.Proc.Kill() } } catch { $Error.Clear() } }
    if ($up -and $up.Temp -and -not [CaFs]::DeleteTree($up.Temp)) { Log 'AVISO' "Não foi possível limpar a pasta temporária: $([CaFs]::LastError)" }
    $script:Ext[$id] = @{ Phase = 'fail'; P = 0.0; T = 0.0; Since = (Get-Date); End = (Get-Date); Idx = -1 }
    RunRemove $run; if ($extTm) { $extTm.Start() }
    [void][Windows.Forms.MessageBox]::Show("Não foi possível extrair '$($run.Name)'.`n$why`n`nDetalhes em TarginoRetroStation\Logs\launcher.log", 'Extração', 'OK', 'Warning')
}
function UnpackStart($run) {
    $gm = $run.Game; $id = "$($run.Id)"; $exe = UnrarExe
    $arc = $script:ArcPath[$id]; $gf = GameFolder $gm
    if (-not [IO.File]::Exists($exe)) { UnpackFail $run "UnRAR.exe não foi encontrado em: $(Short $exe)`nAjuste o caminho no modo desenvolvedor (aba Compactados)."; return $false }
    if (-not $arc -or -not [IO.File]::Exists($arc)) { UnpackFail $run 'O arquivo compactado não foi encontrado.'; return $false }
    if (-not $gf) { UnpackFail $run 'Não foi possível descobrir a pasta do jogo.'; return $false }
    $up = @{ Arc = $arc; Folder = $gf.Folder; Parent = $gf.Parent; Name = $gf.Name; Exe = $exe; Phase = 'list'; Total = [long]0; Proc = $null
             Temp = [IO.Path]::Combine($gf.Parent, ".ca_$((Hash $gf.Name).Substring(0, 10))"); Legacy = [IO.Path]::Combine($gf.Parent, ".ca_unpack_$($gf.Name)"); Poll = (Get-Date); PollEvery = 700; Rel = $gf.Exe.Substring($gf.Folder.Length).TrimStart('\', '/') }
    $vol = ArcVolumes $arc
    if ($vol.Missing) { UnpackFail $run 'Faltam partes do arquivo compactado (a sequência de partes está incompleta).'; return $false }
    $up.Vols = @($vol.Files); $up.ExeFull = $gf.Exe
    $run.UP = $up; $run.Stage = 'unpack'
    try { $up.Proc = ProcRedirect $exe "l $(PassArg) -idc -- `"$arc`"" } catch { UnpackFail $run "Não foi possível iniciar o UnRAR: $($_.Exception.Message)"; return $false }
    $script:Ext[$id] = @{ Phase = 'list'; P = 0.0; T = -1.0; Since = (Get-Date); End = $null; Idx = -1 }
    Log 'INFO' "Extraindo '$($run.Name)' de $(Short $arc) ($($up.Vols.Count) parte(s))"
    $true
}
function UnpackTick($run) {
    $up = $run.UP; $id = "$($run.Id)"; $e = $script:Ext[$id]
    if ($up.Phase -eq 'list') {
        if (-not (ProcDone $up.Proc)) { return }
        $out = "$($up.Proc.Out.Result)"; $code = $up.Proc.Proc.ExitCode; $up.Proc.Proc.Dispose()
        if ($code -ne 0) { UnpackFail $run $(if ($code -eq 11) { 'Senha incorreta ou ausente. Defina a senha no modo desenvolvedor (aba Compactados).' } else { "O arquivo não pôde ser lido (código $code). Ele pode estar corrompido, incompleto ou protegido por senha." }); return }
        $lines = @($out -split "`r?`n"); $last = -1
        for ($k = 0; $k -lt $lines.Count; $k++) { if ($lines[$k] -match '^\s*-{5,}') { $last = $k } }
        if ($last -ge 0 -and $last + 1 -lt $lines.Count) { $mm = [regex]::Match($lines[$last + 1], '^\s*(\d{1,15})\s'); if ($mm.Success) { $up.Total = [long]$mm.Groups[1].Value } }
        if ($up.Total -gt 0) {
            try {
                $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($up.Parent))).AvailableFreeSpace
                if ($free -lt ($up.Total * 1.02 + 50MB)) { UnpackFail $run 'Não há espaço livre suficiente no disco para extrair o jogo.'; return }
            } catch { $Error.Clear() }
        } else { Log 'AVISO' "Tamanho total de '$($run.Name)' não identificado; o progresso será estimado" }
        try {
            if (-not [CaFs]::DeleteTree($up.Temp)) { throw "a pasta temporária de uma extração anterior não pôde ser apagada ($([CaFs]::LastError))" }
            if (-not [CaFs]::DeleteTree($up.Legacy)) { Log 'AVISO' "Sobra de extração antiga não pôde ser apagada: $([CaFs]::LastError)" }      # nome antigo (até v2.47)
            [void][IO.Directory]::CreateDirectory($up.Temp)
            $dest = $up.Temp.TrimEnd('\', '/') + '\'      # UMA barra no fim (v2.48.0: com '\\' o caminho saía com barra dupla e o UnRAR falhava em caminhos longos)
            $up.Proc = ProcRedirect $up.Exe "x -y -o+ $(PassArg) -idq -- `"$($up.Arc)`" `"$dest`""
        } catch { UnpackFail $run "Não foi possível iniciar a extração: $($_.Exception.Message)"; return }
        $up.Phase = 'run'; $up.Poll = Get-Date
        $e.Phase = 'run'; if ($up.Total -gt 0) { $e.T = 0.0 }
        return
    }
    # fase 'run': mede o que já foi extraído (intervalo adaptativo: a medição nunca passa de ~10% do tempo da interface)
    if (((Get-Date) - $up.Poll).TotalMilliseconds -ge $up.PollEvery -and -not (ProcDone $up.Proc)) {
        $swp = [Diagnostics.Stopwatch]::StartNew(); $b = DirBytes $up.Temp; $up.PollEvery = [Math]::Max(700, 10 * $swp.ElapsedMilliseconds); $up.Poll = Get-Date
        if ($up.Total -gt 0) { $e.T = [Math]::Min(0.985, $b / [double]$up.Total) }
    }
    if (-not (ProcDone $up.Proc)) { return }
    $code = $up.Proc.Proc.ExitCode; $txt = ("$($up.Proc.Err.Result) $($up.Proc.Out.Result)").Trim(); $up.Proc.Proc.Dispose()
    if ($code -gt 1) {
        if ($txt.Length -gt 300) { $txt = $txt.Substring(0, 300) }
        UnpackFail $run $(if ($code -eq 11) { 'Senha incorreta ou ausente. Defina a senha no modo desenvolvedor (aba Compactados).' } else { "O UnRAR terminou com erro (código $code). $txt" }); return
    }
    if ($code -eq 1) { Log 'AVISO' "UnRAR terminou com aviso (código 1) ao extrair '$($run.Name)': as partes .rar serão mantidas" }
    UnpackFinish $run ($code -eq 0)
}
function UnpackFinish($run, $clean) {
    $up = $run.UP; $id = "$($run.Id)"
    try {
        $items = @([IO.Directory]::GetFileSystemEntries($up.Temp)); $src = $up.Temp
        if ($items.Count -eq 1 -and [IO.Directory]::Exists($items[0])) {      # o arquivo trazia uma pasta só: ela é a pasta do jogo (qualquer nome)
            $one = $items[0]
            if ([IO.File]::Exists([IO.Path]::Combine($one, $up.Rel)) -or -not [IO.File]::Exists([IO.Path]::Combine($up.Temp, $up.Rel))) { $src = $one }
        }
        if ([IO.Directory]::Exists($up.Folder)) {      # pasta incompleta de antes: guarda de lado em vez de apagar
            $aside = "$($up.Folder).anterior"; if ([IO.Directory]::Exists($aside)) { $aside = "${aside}_$(Get-Date -Format 'yyyyMMdd_HHmmss')" }
            [IO.Directory]::Move($up.Folder, $aside); Log 'AVISO' "Pasta existente de '$($run.Name)' guardada como $(Short $aside)"
        }
        [IO.Directory]::Move($src, $up.Folder)
        if ($src -ne $up.Temp) { [void][CaFs]::DeleteTree($up.Temp) }
    } catch { UnpackFail $run "Não foi possível concluir a extração: $($_.Exception.Message)"; return }
    # (o desbloqueio dos .exe/.bat/.cmd é feito pelo GameStart, logo abaixo, como em toda execução)
    # Confirmação: UnRAR terminou sem nenhum aviso (código 0), a pasta foi movida e o executável do jogo existe. Só então apaga as partes.
    $conf = ($clean -and $up.ExeFull -and [IO.File]::Exists($up.ExeFull))
    if ($conf -and -not $run.KeepSource) {
        $del = 0; $bad = 0
        foreach ($vf in $up.Vols) {
            if ($vf.StartsWith($up.Folder + [IO.Path]::DirectorySeparatorChar, 'OrdinalIgnoreCase')) { continue }
            try { [IO.File]::Delete($vf); $del++ } catch { $bad++; LogEx 'AVISO' "Não foi possível apagar $(Short $vf): $($_.Exception.Message)" $_ }
        }
        Log 'INFO' ("Extração de '$($run.Name)' confirmada: $del parte(s) .rar apagada(s)" + $(if ($bad) { " ($bad não puderam ser apagadas)" } else { '' }))
    } elseif ($conf -and $run.KeepSource) { Log 'INFO' "Arquivo original de '$($run.Name)' preservado após extração" }
    else { Log 'AVISO' "Extração de '$($run.Name)' não pôde ser confirmada (aviso do UnRAR ou executável não encontrado): os arquivos .rar foram mantidos" }
    $script:Drive = @{}; $script:PathSeen = @{}; [void](CheckGame $run.Game); InstSave
    Log 'INFO' "Extração de '$($run.Name)' concluída (estado: $($script:InstState[$id]))"
    $script:Ext[$id] = @{ Phase = 'done'; P = 1.0; T = 1.0; Since = (Get-Date); End = (Get-Date); Idx = -1 }
    $run.Stage = ''; $run.UP = $null; RunRemove $run
    if ($conf -or ($up.ExeFull -and [IO.File]::Exists($up.ExeFull))) { GameStart $run.Game }
    else { [void][Windows.Forms.MessageBox]::Show("A extração de '$($run.Name)' terminou, mas o executável do jogo não foi encontrado.`nOs arquivos .rar foram mantidos. Confira o caminho do executável.", 'Extração', 'OK', 'Warning') }
}
# ---- animação da capa (só o quadrado do jogo é redesenhado, ~14 quadros por segundo) ----
function ExtAnim {
    $now = Get-Date; $dead = @()
    foreach ($id in @($script:Ext.Keys)) {
        $e = $script:Ext[$id]
        if ($e.Phase -eq 'list' -or $e.Phase -eq 'run') {
            if ($e.T -ge 0) { $d = $e.T - $e.P; if ($d -gt 0) { $e.P = [Math]::Min($e.T, $e.P + [Math]::Max($d * 0.2, 0.002)) } }
            else { $e.P += (0.92 - $e.P) * 0.012 }      # sem tamanho total: avança devagar até ~90%
        } else {
            $life = 2.6; if ($e.Phase -eq 'fail') { $life = 3.2 }
            if (($now - $e.End).TotalSeconds -gt $life) { $dead += $id }
        }
        TileInvalidate $e $id
    }
    foreach ($id in $dead) { $script:Ext.Remove($id); $grid.Invalidate() }
    if (-not $script:Ext.Count) { $extTm.Stop() }
}
function PaintProgress($gr, $gx, $ex, $rect, $bmp) {
    $p = [Math]::Max(0.0, [Math]::Min(1.0, [double]$ex.P)); $fh = [int][Math]::Round($rect.Height * $p); $ty = $rect.Bottom - $fh
    if ($fh -gt 0) {
        $st = $gr.Save()
        try {
            $gr.SetClip((New-Object Drawing.Rectangle $rect.X, $ty, $rect.Width, $fh), [Drawing.Drawing2D.CombineMode]::Intersect)
            if ($bmp) { $gr.DrawImage($bmp, $rect) } else { $gr.FillRectangle($gx.PhOn, $rect) }
        } finally { $gr.Restore($st) }
    }
    $t = [double](Get-Date).Ticks / 1e7; $al = [int](170 + 80 * [Math]::Sin($t * 5)); $wy = [Math]::Min($rect.Bottom - 1, $ty)
    $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb($al, 255, 255, 255)), ([single]2)
    try { $gr.DrawLine($pen, [single]$rect.X, [single]$wy, [single]($rect.Right - 1), [single]$wy) } finally { $pen.Dispose() }
    $bh = [Math]::Min(16, $fh)
    if ($bh -gt 2) {
        $band = New-Object Drawing.Rectangle $rect.X, $wy, $rect.Width, $bh
        $gb = New-Object Drawing.Drawing2D.LinearGradientBrush $band, ([Drawing.Color]::FromArgb(90, 255, 255, 255)), ([Drawing.Color]::FromArgb(0, 255, 255, 255)), ([single]90)
        try { $gr.FillRectangle($gb, $band) } finally { $gb.Dispose() }
    }
}
function PaintExtMark($gr, $c, $ex, $rect) {   # sinal discreto no canto: V (extraído) ou X (falhou), some em ~3 s
    $life = 2.6; if ($ex.Phase -eq 'fail') { $life = 3.2 }
    $k = 1.0 - (((Get-Date) - $ex.End).TotalSeconds / $life); if ($k -le 0) { return }
    $al = [int](235 * [Math]::Min(1.0, $k * 1.6)); $cx = $rect.Right - 20; $cy = $rect.Y + 20
    $bb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int]($al * 0.7), 0, 0, 0))
    $col = [Drawing.Color]::FromArgb($al, 255, 255, 255); if ($ex.Phase -eq 'fail') { $col = [Drawing.Color]::FromArgb($al, 235, 120, 95) }
    $pen = New-Object Drawing.Pen $col, ([single]2); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    try {
        $gr.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gr.FillEllipse($bb, [single]($cx - 12), [single]($cy - 12), [single]24, [single]24)
        $gr.DrawEllipse($pen, [single]($cx - 12), [single]($cy - 12), [single]24, [single]24)
        if ($ex.Phase -eq 'fail') {
            $gr.DrawLine($pen, [single]($cx - 4), [single]($cy - 4), [single]($cx + 4), [single]($cy + 4)); $gr.DrawLine($pen, [single]($cx + 4), [single]($cy - 4), [single]($cx - 4), [single]($cy + 4))
        } else {
            $gr.DrawLines($pen, [Drawing.PointF[]]@((New-Object Drawing.PointF ([single]($cx - 5)), ([single]$cy)), (New-Object Drawing.PointF ([single]($cx - 1)), ([single]($cy + 4))), (New-Object Drawing.PointF ([single]($cx + 5)), ([single]($cy - 4)))))
            $glow = New-Object Drawing.Pen ([Drawing.Color]::FromArgb([int]($al * 0.8), $c.Accent.R, $c.Accent.G, $c.Accent.B)), ([single]2)
            try { $gr.DrawRectangle($glow, [single]($rect.X + 1), [single]($rect.Y + 1), [single]($rect.Width - 3), [single]($rect.Height - 3)) } finally { $glow.Dispose() }
        }
    } finally { $gr.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::Default; $bb.Dispose(); $pen.Dispose() }
}
function Launch($g) {
    if ($g.HydraKind -eq 'system') { HydraOpenSystem $g.HydraSystem; return }
    if (-not $g) { return }
    if ($g -and (RunFind "$($g.Id)")) { return }      # extraindo (v2.48.0): duplo clique / Enter não fazem nada até terminar ou falhar
    if ($g -and $script:Play.ContainsKey("$($g.Id)")) { PlayStop $g; return }   # já está aberto: duplo clique/Enter encerra (v2.36.0)
    $exe = ExePath $g
    Log 'INFO' "Iniciando jogo '$($g.Name)' ($(Short $exe))"
    if (RunFind "$($g.Id)") { Log 'AVISO' "Jogo '$($g.Name)' está sendo extraído"; return }
    if ($script:Del.ContainsKey("$($g.Id)")) { Log 'AVISO' "Jogo '$($g.Name)' está sendo apagado"; [void][Windows.Forms.MessageBox]::Show("'$($g.Name)' está sendo apagado do disco. Aguarde terminar.", 'Deletar jogo'); return }
    $script:Drive = @{}; $script:PathSeen = @{}      # nova verificação ao iniciar: reconsulta a unidade deste jogo
    $script:DirIdx = $null      # Jogar sempre consulta os .rar atuais, sem índice antigo da varredura
    $chg = CheckGame $g
    if ($chg) { InstSave; Populate }
    if ($script:InstState["$($g.Id)"] -eq 'offline') {
        $dr = DriveOf $exe
        Log 'AVISO' "Jogo '$($g.Name)': unidade '$dr' não está disponível"
        [void][Windows.Forms.MessageBox]::Show("A unidade $dr não está conectada.`nConecte-a e tente novamente.", 'Unidade desconectada'); return
    }
    if ($script:InstState["$($g.Id)"] -ne 'archived' -and (-not $exe -or -not [IO.File]::Exists($exe))) {
        Log 'AVISO' "Jogo '$($g.Name)' não encontrado: $(Short $exe)"
        OfferMissingGameDownload $g
        return
    }
    $run = @{ Id = "$($g.Id)"; Name = "$($g.Name)"; Game = $g; Stage = ''; UP = $null; KeepSource = $false }
    if ($script:InstState["$($g.Id)"] -eq 'archived') {      # só existe o arquivo compactado: extrai primeiro (capa mostra o progresso)
        if (UnpackStart $run) { $script:Runs += $run; RunStatus; if ($runTm) { $runTm.Start() }; if ($extTm) { $extTm.Start() } }
        return
    }
    GameStart $g
}
function ConfirmMissingGameDownload($g) {
    [Windows.Forms.MessageBox]::Show($form,"Jogo não instalado, prosseguir com download?`n`n$($g.Name)",'Baixar jogo',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question,[Windows.Forms.MessageBoxDefaultButton]::Button2) -eq [Windows.Forms.DialogResult]::Yes
}
function OfferMissingGameDownload($g) {
    if (-not "$($g.Link)".Trim()) {
        [void][Windows.Forms.MessageBox]::Show($form,"Jogo não instalado.`n`nNão há link de download cadastrado para '$($g.Name)'.",'Download indisponível',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    if (ConfirmMissingGameDownload $g) {
        Log 'INFO' "Download solicitado ao jogar '$($g.Name)' ausente"
        GameLinkOpen $g
    }
}
# Acompanha a extração em andamento (timer de 500 ms; não bloqueia a janela)
function RunTick {
    foreach ($run in @($script:Runs)) {
        try { if ($run.Stage -eq 'unpack') { UnpackTick $run } elseif ($run.Stage -eq 'extra') { ExtraTick $run } elseif ($run.Stage -eq 'dl') { TgTick $run } else { RunRemove $run } }
        catch {
            LogEx 'ERRO' "Falha ao acompanhar '$($run.Name)': $($_.Exception.Message)" $_
            if ($run.Stage -eq 'unpack') { UnpackFail $run "erro inesperado: $($_.Exception.Message)" } elseif ($run.Stage -eq 'extra') { ExtraFail $run "erro inesperado: $($_.Exception.Message)" } elseif ($run.Stage -eq 'dl') { TgFail $run "erro inesperado: $($_.Exception.Message)" $true } else { RunRemove $run }
        }
    }
    if (-not $script:Runs.Count) { $runTm.Stop() }
}

# ---- Abrir destinos do campo Link: URL, protocolo registrado no Windows ou arquivo/programa local ----
#  https://site, www.site.com      -> navegador padrão
#  tg://resolve?domain=canal       -> aplicativo registrado para o protocolo (Telegram, Steam, mailto: ...)
#  Pasta\Programa.exe argumentos   -> caminho relativo à pasta do launcher (aceita {LauncherDir}, {JogosDir}, {TarginoRetroStationDir}); nada fora dela
#  "Pasta com espaço\App.exe" arg  -> aspas quando o caminho tem espaços e há argumentos
#  Um caminho local nunca é tratado como URL e uma URL nunca é executada como programa.
$BlockedSchemes = 'javascript', 'vbscript', 'data', 'ms-msdt', 'search-ms', 'search', 'ms-officecmd'
function TargetInfo($txt) {
    $txt = "$txt".Trim(); if (-not $txt) { return $null }
    if ($txt -match '^www\.') { $txt = "https://$txt" }
    if ($txt -match '^https?://') { return @{ Kind = 'URL'; Target = $txt; Arg = '' } }
    # esquema com 2+ letras (tg:, steam:, mailto:). "C:\..." tem 1 letra e é caminho local.
    if ($txt -match '^([a-zA-Z][a-zA-Z0-9+.\-]+):' -and $Matches[1].Length -gt 1) { return @{ Kind = 'Protocolo'; Scheme = $Matches[1].ToLower(); Target = $txt; Arg = '' } }
    $path = $txt; $arg = ''
    if ($txt -match '^"([^"]+)"\s*(.*)$') { $path = $Matches[1]; $arg = $Matches[2] }
    elseif ($txt -match '^(.+?\.(?:exe|bat|cmd|com|lnk|ps1))(?:\s+(.*))?$') { $path = $Matches[1]; $arg = "$($Matches[2])" }
    $tg = Full $path; $twd = $(if ($tg) { try { [IO.Path]::GetDirectoryName($tg) } catch { $Error.Clear(); '' } } else { '' })
    @{ Kind = 'Local'; Target = $tg; Raw = $path; Arg = (ArgsExpand $arg $twd) }
}
function ShellOpen($file, $arg, $wd) {
    $psi = New-Object Diagnostics.ProcessStartInfo $file; $psi.UseShellExecute = $true
    if ($arg) { $psi.Arguments = $arg }; if ($wd) { $psi.WorkingDirectory = $wd }
    [Diagnostics.Process]::Start($psi)
}
# $what descreve a origem para o log; $allowLocal = $false para links que não devem abrir arquivos/programas (ex.: links da descrição)
function OpenTarget($text, $what, [bool]$allowLocal = $true) {
    $script:OpenProc = $null      # processo do último destino local aberto (usado pelos extras para acompanhar como o Jogar, v2.40.0)
    $t = TargetInfo $text; if (-not $t) { return $false }
    try {
        switch ($t.Kind) {
            'URL' { Log 'INFO' "Abrindo URL ($what): $($t.Target)"; [void](ShellOpen $t.Target '' '') }
            'Protocolo' {
                if ($BlockedSchemes -contains $t.Scheme) {
                    Log 'AVISO' "Protocolo bloqueado ($what): $($t.Scheme):"
                    [void][Windows.Forms.MessageBox]::Show("Este tipo de link ($($t.Scheme):) não é permitido.", 'Link bloqueado'); return $false
                }
                Log 'INFO' "Abrindo link de protocolo ($what): $($t.Scheme):"; [void](ShellOpen $t.Target '' '')
            }
            'Local' {
                if (-not $allowLocal) { Log 'AVISO' "Destino local ignorado ($what): $($t.Raw)"; return $false }
                $p = $t.Target
                $isDir = $p -and [IO.Directory]::Exists($p)
                if (-not $p -or -not ($isDir -or [IO.File]::Exists($p))) {
                    Log 'AVISO' "Destino local não encontrado ($what): $(if ($p) { Short $p } else { $t.Raw })"
                    [void][Windows.Forms.MessageBox]::Show("Não foi encontrado:`n$(if ($p) { $p } else { $t.Raw })", 'Link'); return $false
                }
                Log 'INFO' "Abrindo destino local ($what): $(Short $p)"
                if ($isDir) { [void](ShellOpen $p '' '') }
                elseif ([IO.Path]::GetExtension($p) -eq '.ps1') { $script:OpenProc = ShellOpen 'powershell.exe' ("-NoProfile -ExecutionPolicy Bypass -File `"$p`" $($t.Arg)").Trim() ([IO.Path]::GetDirectoryName($p)) }
                else { $script:OpenProc = ShellOpen $p $t.Arg ([IO.Path]::GetDirectoryName($p)) }
            }
        }
        $true
    } catch {
        LogEx 'ERRO' "Falha ao abrir ($what) '$text': $($_.Exception.Message)" $_
        [void][Windows.Forms.MessageBox]::Show("Não foi possível abrir:`n$text`n`n$($_.Exception.Message)", 'Link'); $false
    }
}

# ---- Baixar Jogo pelo Telegram (v2.53.0) ----
#  O "Baixar Jogo" do menu do botão direito: se o Link do jogo tem um ou mais links https://t.me/..., o launcher baixa os arquivos
#  dessas mensagens direto para a pasta Jogos (com o progresso na capa, como na extração). Sem link do Telegram ou sem o tdl.exe,
#  continua abrindo o Link como antes.
#  Quem baixa é o tdl.exe (Ferramentas\Tdl, programa livre: github.com/iyear/tdl), sem janela, usando a conta do Telegram da pessoa.
#  Conexão: na primeira vez o launcher abre o Telegram portátil (Ferramentas\Telegram) para a pessoa entrar na conta dela (QR code ou
#  número) e depois lê esse login da pasta tdata do Telegram portátil e guarda a sessão em TarginoRetroStation\Cache\Telegram\sessao.json.
#  Nada vai para o C:: o tdl roda com a "pasta do usuário" apontando para TarginoRetroStation\Cache\Telegram\tdl (log, temporários).
#  NUNCA distribua Ferramentas\Telegram\tdata nem TarginoRetroStation\Cache\Telegram: dão acesso à conta do Telegram de quem conectou.
#  Download: vai para uma pasta oculta Jogos\.ca_dl_<código> e, só quando TODOS os arquivos terminam, eles são movidos para Jogos\.
#  Se falhar ou for cancelado, o que já terminou fica guardado e a próxima tentativa continua de onde parou.
#  Conta desconectada (sessão encerrada pelo celular, por exemplo): a sessão é apagada e a janela de conectar aparece de novo.
function TgPaths {
    $tc = [IO.Path]::Combine((ArqDir 'Cache'), 'Telegram')
    $tdl = "$($S.TdlPath)".Trim(); if (-not $tdl) { $tdl = $Defaults.TdlPath }
    $tge = "$($S.TelegramPath)".Trim(); if (-not $tge) { $tge = $Defaults.TelegramPath }
    @{ Tdl = (Full $tdl); TgExe = (Full $tge); Dir = $tc; Sess = [IO.Path]::Combine($tc, 'sessao.json'); Home = [IO.Path]::Combine($tc, 'tdl') }
}
function TgUrls($txt) {
    $out = @()
    foreach ($m in [regex]::Matches("$txt", 'https?://(?:www\.)?t(?:elegram)?\.me/[^\s"''<>]+', 'IgnoreCase')) { $u = $m.Value.TrimEnd('.', ',', ';', ')'); if ($out -notcontains $u) { $out += $u } }
    $out
}
function TgSessionOk { $p = TgPaths; try { return ([IO.File]::Exists($p.Sess) -and (New-Object IO.FileInfo $p.Sess).Length -gt 100) } catch { $Error.Clear(); $false } }
function GameLinkOpen($g) {
    if (-not $g -or -not $g.Link) { return }
    $urls = @(TgUrls $g.Link); $p = TgPaths
    if ($urls.Count -or "$($g.Link)" -match '^tg://') {
        if (-not $p.TgExe -or -not [IO.File]::Exists($p.TgExe)) {
            [void][Windows.Forms.MessageBox]::Show($form,"Telegram não encontrado em:`n$($p.TgExe)`nAjuste o caminho em Personalizar > Compactados.",'Telegram'); return
        }
        $targets=@($urls); if (-not $targets.Count) { $targets=@("$($g.Link)") }
        try {
            $arguments='-- '+(($targets | ForEach-Object { TgQuote $_ }) -join ' ')
            [void](ShellOpen $p.TgExe $arguments ([IO.Path]::GetDirectoryName($p.TgExe)))
            Log 'INFO' "Telegram aberto para '$($g.Name)'. Após baixar em Jogos, pressione Jogar novamente para extrair e executar."
        } catch {
            LogEx 'ERRO' 'Não foi possível abrir o Telegram' $_
            [void][Windows.Forms.MessageBox]::Show($form,"Não foi possível abrir o Telegram: $($_.Exception.Message)",'Telegram')
        }
        return
    }
    [void](OpenTarget $g.Link "link de '$($g.Name)'")
}
function TgDownload($g, $urls) {
    $id = "$($g.Id)"
    if (RunFind $id) { return }
    if ($script:Del.ContainsKey($id)) { [void][Windows.Forms.MessageBox]::Show("'$($g.Name)' está sendo apagado do disco. Aguarde terminar.", 'Baixar jogo'); return }
    $st = $script:InstState[$id]
    if ($st -eq 'ok' -or $st -eq 'archived') {
        $r = [Windows.Forms.MessageBox]::Show("'$($g.Name)' já está na pasta Jogos.`nBaixar de novo?", 'Baixar jogo', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
    }
    if (-not (TgSessionOk)) { if (-not (TgConnect)) { return } }
    TgStart $g $urls
}
# Argumento de linha de comando com aspas quando precisa (mesma regra do Windows usada no PassArg)
function TgQuote($a) {
    $a = "$a"
    if ($a -and $a -notmatch '[\s"]') { return $a }
    '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}
# Fecha o Telegram PORTÁTIL do launcher (só o executável de TelegramPath; o Telegram instalado da pessoa nunca é tocado).
#  Ele e o tdl usam o mesmo login: abertos juntos, o Telegram fica lento até ser reaberto (v2.54.1).
function TgCloseDesktop($p) {
    if (-not $p.TgExe) { return }
    foreach ($tp in @(Get-Process -Name 'Telegram' -ErrorAction SilentlyContinue)) {
        try {
            $fn = ''; try { $fn = "$($tp.MainModule.FileName)" } catch { $Error.Clear() }
            if ($fn -and $fn -ieq $p.TgExe -and -not $tp.HasExited) {
                $tp.Kill(); [void]$tp.WaitForExit(5000)
                Log 'INFO' "Telegram portátil fechado para o download (processo $($tp.Id))"
            }
        } catch { LogEx 'AVISO' "Não foi possível fechar o Telegram portátil: $($_.Exception.Message)" $_ } finally { $tp.Dispose() }
    }
    $Error.Clear()
}
function TgStart($g, $urls) {
    $p = TgPaths; $id = "$($g.Id)"
    TgCloseDesktop $p
    $run = @{ Id = $id; Name = "$($g.Name)"; Game = $g; Stage = 'dl'; UP = $null }
    try {
        $jd = [IO.Path]::Combine($Root, 'Jogos'); [void][IO.Directory]::CreateDirectory($jd)
        $tmp = [IO.Path]::Combine($jd, ".ca_dl_$((Hash $id).Substring(0, 10))")
        [void][IO.Directory]::CreateDirectory($tmp)
        try { $di = New-Object IO.DirectoryInfo $tmp; $di.Attributes = $di.Attributes -bor [IO.FileAttributes]::Hidden } catch { $Error.Clear() }
        foreach ($tf in [IO.Directory]::GetFiles($tmp, '*.tmp')) { try { [IO.File]::Delete($tf) } catch { $Error.Clear() } }      # pedaço incompleto de antes: o tdl baixa esse arquivo de novo
        $ttmp = [IO.Path]::Combine($p.Home, 'temp'); [void][IO.Directory]::CreateDirectory($ttmp)
        $al = @('--storage', "type=file,path=$($p.Sess)", '--reconnect-timeout', '2m', '-l', '10', '-t', '2', 'dl', '--continue', '--group', '--skip-same',
                '--template', '{{ filenamify .FileName }}', '-d', $tmp)
        foreach ($u in $urls) { $al += '-u'; $al += $u }
        $psi = New-Object Diagnostics.ProcessStartInfo; $psi.FileName = $p.Tdl; $psi.Arguments = (($al | ForEach-Object { TgQuote $_ }) -join ' ')
        $psi.WorkingDirectory = $p.Home; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
        foreach ($ev in 'USERPROFILE', 'HOME', 'APPDATA', 'LOCALAPPDATA') { $psi.EnvironmentVariables[$ev] = $p.Home }      # o tdl guarda log/extensões na "pasta do usuário": fica tudo em Cache\Telegram\tdl
        foreach ($ev in 'TEMP', 'TMP') { $psi.EnvironmentVariables[$ev] = $ttmp }
        $pr = [Diagnostics.Process]::Start($psi)
        try { $pr.StandardInput.Close() } catch { $Error.Clear() }
    } catch {
        LogEx 'ERRO' "Não foi possível iniciar o download de '$($g.Name)': $($_.Exception.Message)" $_
        [void][Windows.Forms.MessageBox]::Show("Não foi possível iniciar o download de '$($g.Name)'.`n$($_.Exception.Message)", 'Baixar jogo', 'OK', 'Warning'); return
    }
    $run.UP = @{ Proc = $pr; Tmp = $tmp; Urls = @($urls); Out = (New-Object Text.StringBuilder); Poll = (Get-Date); Since = (Get-Date); Wait = 0
                 Rd = @(@{ R = $pr.StandardOutput; Buf = (New-Object char[] 8192); T = $null; Eof = $false }, @{ R = $pr.StandardError; Buf = (New-Object char[] 8192); T = $null; Eof = $false }) }
    $script:Ext[$id] = @{ Phase = 'run'; P = 0.0; T = 0.0; Since = (Get-Date); End = $null; Idx = -1 }
    $script:Runs += $run; RunStatus
    if ($runTm) { $runTm.Start() }; if ($extTm) { $extTm.Start() }
    $grid.Invalidate()
    Log 'INFO' "Baixando '$($g.Name)' pelo Telegram ($($urls.Count) link(s): $($urls -join ' '))"
}
# Lê a saída do tdl sem travar a janela (leituras assíncronas conferidas a cada tique do timer)
function TgPump($dl) {
    foreach ($r in $dl.Rd) {
        if ($r.Eof) { continue }
        for ($k = 0; $k -lt 64; $k++) {
            if ($null -eq $r.T) { try { $r.T = $r.R.ReadAsync($r.Buf, 0, $r.Buf.Length) } catch { $Error.Clear(); $r.Eof = $true; break } }
            if (-not $r.T.IsCompleted) { break }
            $n = 0; try { $n = [int]$r.T.Result } catch { $Error.Clear(); $n = 0 }
            $r.T = $null
            if ($n -le 0) { $r.Eof = $true; break }
            [void]$dl.Out.Append($r.Buf, 0, $n)
        }
    }
    if ($dl.Out.Length -gt 262144) { $keep = $dl.Out.ToString($dl.Out.Length - 65536, 65536); [void]$dl.Out.Clear(); [void]$dl.Out.Append($keep) }
}
function TgClean($t) { ("$t" -replace '\x1b\[[0-9;?]*[ -/]*[@-~]', '') }
# Progresso total: a barra geral do tdl ([#####.....], a mais longa da tela) diz quanto do total já veio
function TgFrac($dl) {
    $len = [Math]::Min($dl.Out.Length, 16000); if ($len -le 0) { return -1.0 }
    $t = TgClean ($dl.Out.ToString($dl.Out.Length - $len, $len))
    $ms = [regex]::Matches($t, '\[([#.]{20,})\]'); if (-not $ms.Count) { return -1.0 }
    $bar = $ms[$ms.Count - 1].Groups[1].Value
    ($bar.Length - $bar.Replace('#', '').Length) / [double]$bar.Length
}
function TgIsAuthErr($t) { "$t" -match '(?i)not authorized|AUTH_KEY_UNREGISTERED|AUTH_KEY_INVALID|AUTH_KEY_DUPLICATED|SESSION_REVOKED|SESSION_EXPIRED|USER_DEACTIVATED' }
function TgSaveLog($dl, $code) {
    try { WriteText ([IO.Path]::Combine($LogDir, 'telegram_ultimo.log')) ("Saída do tdl (código $code)`r`n" + (TgClean $dl.Out.ToString())) } catch { $Error.Clear() }
}
function TgTick($run) {
    $dl = $run.UP; $id = "$($run.Id)"; $e = $script:Ext[$id]
    TgPump $dl
    if (((Get-Date) - $dl.Poll).TotalMilliseconds -ge 700) {
        $dl.Poll = Get-Date
        $f = TgFrac $dl
        if ($f -ge 0 -and $e) { $e.T = [Math]::Min(0.985, [Math]::Max([double]$e.T, $f)) }
    }
    if (-not $dl.Proc.HasExited) { return }
    $eof = $true; foreach ($r in $dl.Rd) { if (-not $r.Eof) { $eof = $false } }
    if (-not $eof) { $dl.Wait++; if ($dl.Wait -lt 20) { return } }      # terminou: espera a saída acabar de chegar (no máximo ~10 s)
    $code = $dl.Proc.ExitCode; try { $dl.Proc.Dispose() } catch { $Error.Clear() }
    $txt = TgClean $dl.Out.ToString(); TgSaveLog $dl $code
    $files = @(); $partial = $false
    try { foreach ($f0 in [IO.Directory]::GetFiles($dl.Tmp)) { if ($f0 -like '*.tmp') { $partial = $true } else { $files += $f0 } } } catch { $Error.Clear() }
    $itemErr = ($txt -cmatch 'failed!' -or $txt -cmatch '-> .* error: ')      # o tdl só avisa na tela quando UM arquivo falha (e termina com código 0)
    if ($code -eq 0 -and $files.Count -and -not $partial -and -not $itemErr) { TgFinish $run $files; return }
    Log 'AVISO' "tdl terminou com código $code ao baixar '$($run.Name)' ($($files.Count) arquivo(s) prontos; saída em Logs\telegram_ultimo.log)"
    if (TgIsAuthErr $txt) {
        try { [IO.File]::Delete((TgPaths).Sess) } catch { $Error.Clear() }
        Log 'AVISO' 'A conta do Telegram foi desconectada: sessão apagada, pedindo para conectar de novo'
        TgFail $run '' $false
        [void][Windows.Forms.MessageBox]::Show("Sua conta do Telegram foi desconectada do launcher.`nConecte de novo para continuar o download.", 'Baixar jogo', 'OK', 'Information')
        if (TgConnect) { TgStart $run.Game $dl.Urls }
        return
    }
    $err = ''; $m = [regex]::Match($txt, '(?m)Error:\s*(.+)$'); if ($m.Success) { $err = $m.Groups[1].Value.Trim() }
    if ($err.Length -gt 220) { $err = $err.Substring(0, 220) + '...' }
    $why = if ($txt -match '(?i)FLOOD_WAIT|FLOOD_PREMIUM') { 'O Telegram limitou os downloads desta conta por alguns minutos. Tente de novo mais tarde.' }
           elseif ($txt -match '(?i)CHANNEL_PRIVATE|CHANNEL_INVALID|USERNAME_NOT_OCCUPIED|USERNAME_INVALID|MSG_ID_INVALID|message not found|invalid message link') { "A mensagem do Telegram não foi encontrada (o link do jogo pode estar errado ou a postagem foi apagada).`n$err" }
           elseif ($itemErr -and $code -eq 0) { 'Um ou mais arquivos não terminaram de baixar. Tente de novo: o que já veio fica guardado.' }
           elseif ($code -eq 0 -and -not $files.Count) { 'A mensagem do Telegram não tem nenhum arquivo para baixar. Confira o link do jogo.' }
           elseif ($txt -match '(?i)dial tcp|i/o timeout|connection refused|no such host|network is unreachable|context deadline exceeded|reconnect') { 'Não foi possível conectar ao Telegram. Confira sua internet e tente de novo.' }
           elseif ($err) { "O download falhou: $err" } else { "O download falhou (código $code)." }
    TgFail $run $why $true
}
function TgFail($run, $why, [bool]$show) {
    $id = "$($run.Id)"; $dl = $run.UP
    if ($dl -and $dl.Proc) { try { if (-not $dl.Proc.HasExited) { $dl.Proc.Kill(); [void]$dl.Proc.WaitForExit(3000) } } catch { $Error.Clear() } }
    if ($dl -and $dl.Tmp) { try { foreach ($tf in [IO.Directory]::GetFiles($dl.Tmp, '*.tmp')) { try { [IO.File]::Delete($tf) } catch { $Error.Clear() } } } catch { $Error.Clear() } }
    if ($why) { Log 'ERRO' "Download de '$($run.Name)' falhou: $why" }
    $script:Ext[$id] = @{ Phase = 'fail'; P = 0.0; T = 0.0; Since = (Get-Date); End = (Get-Date); Idx = -1 }
    RunRemove $run; if ($extTm) { $extTm.Start() }; $grid.Invalidate()
    if ($show) { [void][Windows.Forms.MessageBox]::Show("Não foi possível baixar '$($run.Name)'.`n$why`n`nO que já foi baixado fica guardado: tente de novo pelo Baixar Jogo.", 'Baixar jogo', 'OK', 'Warning') }
}
function TgCancel($id) {
    $run = RunFind "$id"; if (-not $run -or $run.Stage -ne 'dl') { return }
    Log 'INFO' "Download de '$($run.Name)' cancelado pela pessoa"
    TgFail $run '' $false
}
function TgFinish($run, $files) {
    $id = "$($run.Id)"; $dl = $run.UP; $jd = [IO.Path]::Combine($Root, 'Jogos'); $mv = 0
    try {
        foreach ($f0 in $files) {
            $dst = [IO.Path]::Combine($jd, [IO.Path]::GetFileName($f0))
            if ([IO.File]::Exists($dst)) { [IO.File]::Delete($dst) }      # versão antiga do mesmo arquivo: a nova substitui
            [IO.File]::Move($f0, $dst); $mv++
        }
    } catch { TgFail $run "Os arquivos foram baixados, mas não puderam ser movidos para a pasta Jogos: $($_.Exception.Message)" $true; return }
    if (-not [CaFs]::DeleteTree($dl.Tmp)) { Log 'AVISO' "Pasta temporária do download não pôde ser apagada: $([CaFs]::LastError)" }
    $script:Drive = @{}; $script:PathSeen = @{}; [void](CheckGame $run.Game); InstSave
    $st = $script:InstState[$id]
    Log 'INFO' "Download de '$($run.Name)' concluído: $mv arquivo(s) em Jogos\ em $([int](((Get-Date) - $dl.Since).TotalSeconds)) s (estado: $st)"
    $script:Ext[$id] = @{ Phase = 'done'; P = 1.0; T = 1.0; Since = (Get-Date); End = (Get-Date); Idx = -1 }
    $run.Stage = ''; $run.UP = $null; RunRemove $run
    if ($extTm) { $extTm.Start() }
    Populate; ShowGame (Sel)
    if ($st -ne 'ok' -and $st -ne 'archived') {
        $gf = GameFolder $run.Game; $nm = $(if ($gf) { $gf.Name } else { "$($run.Name)" })
        Log 'AVISO' "Download de '$($run.Name)': os arquivos baixados não correspondem ao jogo (esperado '$nm.rar' ou '$nm.part1.rar' em Jogos\)"
        [void][Windows.Forms.MessageBox]::Show("O download de '$($run.Name)' terminou e os arquivos estão na pasta Jogos, mas o launcher não reconheceu o jogo.`nO arquivo precisa se chamar '$nm.rar' (ou '$nm.part1.rar', '$nm.part2.rar'...).", 'Baixar jogo', 'OK', 'Warning')
    }
}

# ---- Login do Telegram: lido da pasta tdata do Telegram portátil (o mesmo formato que o tdl importa com "tdl login -T desktop") ----
#  Só a conta que está aberta no Telegram portátil. Senha de bloqueio local (se a pessoa usa) é pedida na janela de conectar.
#  Gera o sessao.json no formato de armazenamento "file" do tdl. A chave da conta nunca vai para o log.
function TgSub([byte[]]$b, [int]$o, [int]$n) { $r = New-Object byte[] $n; [Array]::Copy($b, $o, $r, 0, $n); , $r }
function TgBE32([byte[]]$b, [int]$o) { [long]$b[$o] * 16777216 + [long]$b[$o + 1] * 65536 + [long]$b[$o + 2] * 256 + [long]$b[$o + 3] }
function TgCat { $ms = New-Object IO.MemoryStream; foreach ($a in $args) { $ms.Write([byte[]]$a, 0, $a.Length) }; , $ms.ToArray() }
function TgSha1([byte[]]$b) { $h = [Security.Cryptography.SHA1]::Create(); try { $r = $h.ComputeHash($b) } finally { $h.Dispose() }; , $r }
function TgReadAll($fp) {
    $fs = New-Object IO.FileStream $fp, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]'ReadWrite, Delete')
    try { $b = New-Object byte[] $fs.Length; $o = 0; while ($o -lt $b.Length) { $n = $fs.Read($b, $o, $b.Length - $o); if ($n -le 0) { break }; $o += $n } } finally { $fs.Dispose() }
    , $b
}
function TgReadTd($base) {      # arquivo do Telegram: 'TDF$' + versão + dados + MD5; tenta os nomes <base>s, <base>0 e <base>1
    foreach ($suf in 's', '0', '1') {
        $fp = $base + $suf; if (-not [IO.File]::Exists($fp)) { continue }
        $b = TgReadAll $fp
        if ($b.Length -lt 24 -or $b[0] -ne 84 -or $b[1] -ne 68 -or $b[2] -ne 70 -or $b[3] -ne 36) { continue }
        $data = TgSub $b 8 ($b.Length - 24); $ver = TgSub $b 4 4
        $md = [Security.Cryptography.MD5]::Create()
        try { $chk = $md.ComputeHash((TgCat $data ([BitConverter]::GetBytes([int]$data.Length)) $ver ([byte[]](84, 68, 70, 36)))) } finally { $md.Dispose() }
        $ok = $true; for ($i = 0; $i -lt 16; $i++) { if ($chk[$i] -ne $b[$b.Length - 16 + $i]) { $ok = $false; break } }
        if ($ok) { return , $data }
    }
    $null
}
function TgArr([byte[]]$d, [int]$o) {
    $n = TgBE32 $d $o
    if ($n -eq 4294967295) { return @{ B = (New-Object byte[] 0); N = $o + 4 } }
    if ($o + 4 + $n -gt $d.Length) { throw 'arquivo do Telegram incompleto' }
    @{ B = (TgSub $d ($o + 4) ([int]$n)); N = $o + 4 + [int]$n }
}
function TgIgeDec([byte[]]$key, [byte[]]$iv, [byte[]]$src) {
    $aes = New-Object Security.Cryptography.RijndaelManaged
    $aes.BlockSize = 128; $aes.KeySize = 256; $aes.Mode = [Security.Cryptography.CipherMode]::ECB; $aes.Padding = [Security.Cryptography.PaddingMode]::None; $aes.Key = $key
    $dec = $aes.CreateDecryptor()
    $out = New-Object byte[] $src.Length; $x = New-Object byte[] 16; $y = New-Object byte[] 16
    $c = TgSub $iv 0 16; $m = TgSub $iv 16 16
    try {
        for ($o = 0; $o -lt $src.Length; $o += 16) {
            for ($i = 0; $i -lt 16; $i++) { $x[$i] = $src[$o + $i] -bxor $m[$i] }
            [void]$dec.TransformBlock($x, 0, 16, $y, 0)
            for ($i = 0; $i -lt 16; $i++) { $out[$o + $i] = $y[$i] -bxor $c[$i] }
            $c = TgSub $src $o 16; $m = TgSub $out $o 16
        }
    } finally { $dec.Dispose(); $aes.Clear() }
    , $out
}
function TgDecLocal([byte[]]$enc, [byte[]]$lk) {      # $null = chave errada (senha de bloqueio errada)
    if ($enc.Length -lt 32 -or ($enc.Length % 16) -ne 0) { throw 'dados do Telegram em formato inesperado' }
    $mk = TgSub $enc 0 16; $x = 8
    $a = TgSha1 (TgCat $mk (TgSub $lk $x 32))
    $b = TgSha1 (TgCat (TgSub $lk (32 + $x) 16) $mk (TgSub $lk (48 + $x) 16))
    $c = TgSha1 (TgCat (TgSub $lk (64 + $x) 32) $mk)
    $d = TgSha1 (TgCat $mk (TgSub $lk (96 + $x) 32))
    $key = TgCat (TgSub $a 0 8) (TgSub $b 8 12) (TgSub $c 4 12)
    $iv = TgCat (TgSub $a 8 12) (TgSub $b 0 8) (TgSub $c 16 4) (TgSub $d 0 8)
    $dec = TgIgeDec $key $iv (TgSub $enc 16 ($enc.Length - 16))
    $h = TgSha1 $dec; for ($i = 0; $i -lt 16; $i++) { if ($h[$i] -ne $mk[$i]) { return $null } }
    , $dec
}
function TgPbkdf2([byte[]]$pw, [byte[]]$salt, [int]$it) {      # PBKDF2-HMAC-SHA512, 256 bytes
    try {
        $kd = [Security.Cryptography.Rfc2898DeriveBytes]::new($pw, $salt, $it, [Security.Cryptography.HashAlgorithmName]::SHA512)
        try { $r = $kd.GetBytes(256) } finally { $kd.Dispose() }
        return , $r
    } catch { $Error.Clear() }
    $hm = New-Object Security.Cryptography.HMACSHA512 (, $pw); $out = New-Object byte[] 256
    try {
        for ($blk = 1; $blk -le 4; $blk++) {
            $u = $hm.ComputeHash((TgCat $salt ([byte[]](0, 0, 0, $blk)))); $t = [byte[]]$u.Clone()
            for ($j = 2; $j -le $it; $j++) { $u = $hm.ComputeHash($u); for ($i = 0; $i -lt 64; $i++) { $t[$i] = $t[$i] -bxor $u[$i] } }
            [Array]::Copy($t, 0, $out, ($blk - 1) * 64, 64)
        }
    } finally { $hm.Dispose() }
    , $out
}
function TgFileKey($s) {      # nome do arquivo de dados da conta: MD5 com os dois "meio-bytes" trocados, 16 primeiros caracteres
    $md = [Security.Cryptography.MD5]::Create(); try { $h = $md.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) } finally { $md.Dispose() }
    $sb = New-Object Text.StringBuilder
    foreach ($v in $h) { [void]$sb.Append((((([int]$v -shl 4) -band 0xF0) -bor ([int]$v -shr 4))).ToString('X2')) }
    $sb.ToString().Substring(0, 16)
}
function TgImport($pass) {
    $res = @{ Ok = $false; NeedPass = $false; Msg = '' }
    $notYet = 'Ainda não encontrei uma conta conectada no Telegram. Entre na sua conta na janela do Telegram e clique de novo em "Já entrei".'
    try {
        $p = TgPaths; $td = [IO.Path]::Combine([IO.Path]::GetDirectoryName($p.TgExe), 'tdata')
        if (-not [IO.Directory]::Exists($td)) { $res.Msg = $notYet; return $res }
        $kd = TgReadTd ([IO.Path]::Combine($td, 'key_data')); if ($null -eq $kd) { $res.Msg = $notYet; return $res }
        $a1 = TgArr $kd 0; $a2 = TgArr $kd $a1.N; $a3 = TgArr $kd $a2.N
        $salt = [byte[]]$a1.B; if ($salt.Length -ne 32) { throw 'formato do Telegram não reconhecido' }
        $pc = [Text.Encoding]::UTF8.GetBytes("$pass"); $it = 1; if ($pc.Length) { $it = 100000 }
        $sh = [Security.Cryptography.SHA512]::Create(); try { $hp = $sh.ComputeHash((TgCat $salt $pc $salt)) } finally { $sh.Dispose() }
        $inner = TgDecLocal $a2.B (TgPbkdf2 $hp $salt $it)
        if ($null -eq $inner) {
            $res.NeedPass = $true
            $res.Msg = $(if ($pc.Length) { 'Senha de bloqueio incorreta. Tente de novo.' } else { 'Seu Telegram tem uma senha de bloqueio. Digite-a abaixo e clique em "Já entrei".' })
            return $res
        }
        if ([BitConverter]::ToInt32($inner, 0) -lt 256) { throw 'chave local do Telegram inválida' }
        $lk = TgSub $inner 4 256
        $info = TgDecLocal $a3.B $lk; if ($null -eq $info) { throw 'não foi possível ler a lista de contas' }
        if ((TgBE32 $info 4) -lt 1) { $res.Msg = $notYet; return $res }
        $idx = TgBE32 $info 8
        $md = TgReadTd ([IO.Path]::Combine($td, (TgFileKey $(if ($idx -eq 0) { 'data' } else { "data#$($idx + 1)" })))); if ($null -eq $md) { $res.Msg = $notYet; return $res }
        $dec = TgDecLocal (TgArr $md 0).B $lk; if ($null -eq $dec) { throw 'não foi possível ler os dados da conta' }
        $o = 4
        if ((TgBE32 $dec $o) -ne 75) { $res.Msg = $notYet; return $res }      # 0x4b = dados de autorização
        $o += 8; $lu = TgBE32 $dec $o; $ld = TgBE32 $dec ($o + 4); $o += 8
        if ($lu -eq 4294967295 -and $ld -eq 4294967295) { $o += 8; $mdc = TgBE32 $dec $o; $o += 4 } else { $mdc = $ld }
        $nk = TgBE32 $dec $o; $o += 4; $key = $null
        for ($i = 0; $i -lt $nk; $i++) { if ((TgBE32 $dec $o) -eq $mdc) { $key = TgSub $dec ($o + 4) 256 }; $o += 260 }
        if ($null -eq $key) { $res.Msg = $notYet; return $res }
        $kid = TgSub (TgSha1 $key) 12 8
        $ips = @{ 1 = '149.154.175.53'; 2 = '149.154.167.51'; 3 = '149.154.175.100'; 4 = '149.154.167.91'; 5 = '91.108.56.130' }
        $ip = $ips[[int]$mdc]; if (-not $ip) { $ip = '149.154.167.51' }
        $sess = '{"Version":1,"Data":{"DC":' + [int]$mdc + ',"Addr":"' + $ip + ':443","AuthKey":"' + [Convert]::ToBase64String($key) + '","AuthKeyID":"' + [Convert]::ToBase64String($kid) + '","Salt":0}}'
        $store = '{"default":{"app":"' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('desktop')) + '","session":"' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sess)) + '"}}'
        [void][IO.Directory]::CreateDirectory($p.Dir)
        [IO.File]::WriteAllText($p.Sess, $store, (New-Object Text.UTF8Encoding $false))      # sem BOM (o tdl lê JSON puro)
        Log 'INFO' "Telegram conectado: login importado do Telegram portátil (DC $mdc)"
        $res.Ok = $true
    } catch {
        LogEx 'ERRO' "Falha ao ler o login do Telegram portátil: $($_.Exception.Message)" $_
        $res.Msg = "Não foi possível ler o login do Telegram: $($_.Exception.Message)"
    }
    $res
}
# Janela "Conectar ao Telegram" (no tema do launcher). Devolve $true quando a conta ficou conectada.
function TgConnect {
    $p = TgPaths
    if (-not $p.TgExe -or -not [IO.File]::Exists($p.TgExe)) {
        Log 'AVISO' "Telegram portátil não encontrado ($($S.TelegramPath))"
        [void][Windows.Forms.MessageBox]::Show("O Telegram portátil não foi encontrado em:`n$($S.TelegramPath)", 'Conectar ao Telegram', 'OK', 'Warning'); return $false
    }
    $c = $script:Cfg
    $bg = $(if ($c) { $c.Bg } else { [Drawing.Color]::FromArgb(11, 11, 11) }); $fg = $(if ($c) { $c.Text } else { [Drawing.Color]::White })
    $ac = $(if ($c) { $c.Accent } else { [Drawing.Color]::FromArgb(30, 144, 255) }); $sub = [Drawing.Color]::FromArgb(154, 154, 154)
    $pnl = [Drawing.Color]::FromArgb([Math]::Min(255, $bg.R + 18), [Math]::Min(255, $bg.G + 18), [Math]::Min(255, $bg.B + 18))
    $f = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; ShowInTaskbar = $false; Text = 'Conectar ao Telegram'; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'
        MaximizeBox = $false; MinimizeBox = $false; BackColor = $bg; ForeColor = $fg; Font = (New-Object Drawing.Font('Segoe UI', 10)); ClientSize = (New-Object Drawing.Size(500, 300)) }
    $tl = Lbl 'Conecte sua conta do Telegram' 24 18 452 30; $tl.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $tl.ForeColor = $fg
    $tx = Lbl ("Os jogos são baixados do Telegram com a sua conta. Isso só é feito uma vez:`n`n" +
               "1.  Clique em ""Abrir Telegram"" e entre na sua conta (pelo QR code no celular ou pelo número de telefone).`n" +
               "2.  Volte aqui e clique em ""Já entrei"".") 24 56 452 118
    $tx.ForeColor = $sub
    $pl = Lbl 'Senha de bloqueio do Telegram:' 24 178 220 24; $pl.ForeColor = $fg; $pl.Visible = $false
    $pt = New-Object Windows.Forms.TextBox -Property @{ UseSystemPasswordChar = $true; BorderStyle = 'FixedSingle'; BackColor = $pnl; ForeColor = $fg; Visible = $false }; $pt.SetBounds(244, 176, 232, 26)
    $msg = Lbl '' 24 206 452 40; $msg.ForeColor = [Drawing.Color]::FromArgb(235, 170, 95)
    $mk = {
        param($text, $x, [bool]$main)
        $b = New-Object Windows.Forms.Button -Property @{ Text = $text; FlatStyle = 'Flat'; Cursor = [Windows.Forms.Cursors]::Hand; ForeColor = [Drawing.Color]::White }
        $b.FlatAppearance.BorderSize = $(if ($main) { 0 } else { 1 }); $b.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(70, 70, 70)
        $b.BackColor = $(if ($main) { $ac } else { $pnl }); $b.SetBounds($x, 252, 140, 32); $b
    }
    $bo = & $mk 'Abrir Telegram' 24 $true; $bj = & $mk 'Já entrei' 176 $false; $bc = & $mk 'Cancelar' 336 $false
    $bc.DialogResult = 'Cancel'; $f.CancelButton = $bc
    $f.Tag = @{ Pt = $pt; Pl = $pl; Msg = $msg; Exe = $p.TgExe }
    $bo.Add_Click({
        $tg = $this.FindForm().Tag
        try {
            $psi = New-Object Diagnostics.ProcessStartInfo $tg.Exe; $psi.UseShellExecute = $true; $psi.WorkingDirectory = [IO.Path]::GetDirectoryName($tg.Exe)
            [void][Diagnostics.Process]::Start($psi); Log 'INFO' 'Conectar ao Telegram: Telegram portátil aberto'
            $tg.Msg.ForeColor = [Drawing.Color]::FromArgb(154, 154, 154); $tg.Msg.Text = 'Depois de entrar na sua conta no Telegram, clique em "Já entrei".'
        } catch { LogEx 'ERRO' "Não foi possível abrir o Telegram portátil: $($_.Exception.Message)" $_; $tg.Msg.Text = "Não foi possível abrir o Telegram: $($_.Exception.Message)" }
    })
    $bj.Add_Click({
        $fm = $this.FindForm(); $tg = $fm.Tag
        $fm.Cursor = [Windows.Forms.Cursors]::WaitCursor; $tg.Msg.ForeColor = [Drawing.Color]::FromArgb(154, 154, 154); $tg.Msg.Text = 'Conferindo...'; $fm.Refresh()
        $r = TgImport $tg.Pt.Text
        $fm.Cursor = [Windows.Forms.Cursors]::Default
        if ($r.Ok) { $fm.DialogResult = 'OK'; $fm.Close(); return }
        $tg.Msg.ForeColor = [Drawing.Color]::FromArgb(235, 170, 95); $tg.Msg.Text = $r.Msg
        if ($r.NeedPass) { $tg.Pl.Visible = $true; $tg.Pt.Visible = $true; $tg.Pt.SelectAll(); [void]$tg.Pt.Focus() }
    })
    $f.Controls.AddRange(@($tl, $tx, $pl, $pt, $msg, $bo, $bj, $bc))
    $f.Add_Shown({ try { [Dwm]::Dark($this.Handle, ((ColLum $this.BackColor) -lt 128), [int]($this.BackColor.R + 256 * $this.BackColor.G + 65536 * $this.BackColor.B), [int]($this.ForeColor.R + 256 * $this.ForeColor.G + 65536 * $this.ForeColor.B)) } catch { $Error.Clear() } })
    $ok = ($f.ShowDialog($form) -eq 'OK'); $f.Dispose()
    if (-not $ok) { Log 'INFO' 'Conectar ao Telegram: cancelado' }
    $ok
}

# ---- Extras do jogo (itens a mais no menu do botão direito) ----
#  Campo Extras do catálogo: texto com uma linha por item, no formato  Nome|Caminho|Argumentos|ExtrairEm|Depois
#  (o '|' não existe em caminhos do Windows). Caminho = arquivo (.exe, .pdf, imagem...), pasta, https:// ou protocolo.
#  Se o Caminho for um .rar: extrai (sem NUNCA apagar o .rar) em ExtrairEm (vazio = pasta do jogo), por cima dos arquivos
#  existentes, e depois abre: '' = o jogo, '-' = nada, outro texto = esse arquivo/pasta/site.
#  {JogoDir} = pasta do jogo (1º nível de Jogos\ ou a pasta do executável), além de {JogosDir}, {LauncherDir} e {TarginoRetroStationDir}.
function ExtrasParse($xeTxt) {
    $xeOut = @()
    foreach ($xeLine in ("$xeTxt" -split "`r?`n")) {
        if (-not $xeLine.Trim()) { continue }
        $xeP = $xeLine.Split('|'); while ($xeP.Count -lt 5) { $xeP += '' }
        $xeE = @{ Name = $xeP[0].Trim(); Path = $xeP[1].Trim(); Args = $xeP[2].Trim(); Dest = $xeP[3].Trim(); After = $xeP[4].Trim() }
        if ($xeE.Name -and $xeE.Path) { $xeOut += $xeE }
    }
    $xeOut      # sem vírgula: @(ExtrasParse ...) sempre devolve a lista certa (0, 1 ou vários)
}
function ExtrasJoin($xeList) {
    $xeL = foreach ($xeE in @($xeList)) {
        if (-not $xeE) { continue }
        (@('Name', 'Path', 'Args', 'Dest', 'After') | ForEach-Object { ("$($xeE[$_])" -replace '[\|\r\n]', ' ').Trim() }) -join '|'
    }
    (@($xeL) -join "`r`n")
}
function XeDirOfExe($xeExe) {   # pasta do jogo a partir do caminho completo do executável
    if (-not $xeExe) { return '' }
    $xeSub = JogosSub $xeExe; if ($xeSub) { return $xeSub }
    try { "$([IO.Path]::GetDirectoryName($xeExe))" } catch { $Error.Clear(); '' }
}
function XeGameDir($gm) { XeDirOfExe (ExePath $gm) }
function XeExpand($gm, $xeTxt) {   # troca {JogoDir} pela pasta do jogo (o resto é resolvido por Full/Expand)
    $xeTxt = "$xeTxt"; if ($xeTxt -notmatch '(?i)\{JogoDir\}') { return $xeTxt }
    $xeGd = XeGameDir $gm
    [regex]::Replace($xeTxt, '\{JogoDir\}', $xeGd.Replace('$', '$$'), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
function XeIsRar($gm, $xePath) { $xeT = TargetInfo (XeExpand $gm $xePath); [bool]($xeT -and $xeT.Kind -eq 'Local' -and "$($xeT.Raw)".EndsWith('.rar', 'OrdinalIgnoreCase')) }
function XeOpen($gm, $xePath, $xeArgs, $xeWhat) {   # abre arquivo/pasta/site pelas mesmas regras do campo Link (OpenTarget)
    $xeP = XeExpand $gm $xePath; $xeT = TargetInfo $xeP; if (-not $xeT) { return $false }
    if ($xeT.Kind -ne 'Local') { return (OpenTarget $xeP $xeWhat) }
    $xeTxt = '"' + $xeP.Trim('"') + '"'; $xeA = XeExpand $gm $xeArgs; if ($xeA) { $xeTxt += " $xeA" }
    OpenTarget $xeTxt $xeWhat
}
function XeIsProg($gm, $xe) {   # extra que é programa (.exe, .bat, .cmd, .com, .ps1): acompanhado como o Jogar
    $xeT = TargetInfo (XeExpand $gm $xe.Path)
    [bool]($xeT -and $xeT.Kind -eq 'Local' -and $xeT.Target -and ([IO.Path]::GetExtension("$($xeT.Target)") -in '.exe', '.bat', '.cmd', '.com', '.ps1'))
}
function XeKey($xe) { "$($xe.Name)|$($xe.Path)|$($xe.Args)" }   # identifica o extra (a lista é relida do catálogo a cada menu)
function ExtraRun($gm, $xe) {
    if (-not $gm -or -not $xe) { return }
    $xeWhat = "extra '$($xe.Name)' de '$($gm.Name)'"
    if (XeIsRar $gm $xe.Path) { ExtraUnrar $gm $xe; return }
    # Extra que é programa (.exe, .bat, .cmd, .com, .ps1): funciona como o Jogar (v2.40.0): capa pulsando, "Iniciando..."/"Em execução",
    #  duplo clique/"Fechar jogo" encerra. Pasta, site, documento etc. só abrem, como antes. Com o jogo já aberto, o extra abre sem
    #  trocar o acompanhamento (ex.: ferramenta de configuração junto com o jogo).
    $xeProg = XeIsProg $gm $xe
    $xeId = "$($gm.Id)"
    # v2.41.0: com algo do jogo aberto, o extra que está rodando vira "Fechar jogo" e os outros programas ficam indisponíveis
    $xePl = $script:Play[$xeId]
    if ($xeProg -and $xePl) {
        if ($xePl.Extra -and (XeKey $xePl.Extra) -eq (XeKey $xe)) { PlayStop $gm }
        else { Log 'INFO' "Extra '$($xe.Name)' de '$($gm.Name)' ignorado: o jogo já está aberto" }
        return
    }
    if ($xeProg -and -not $script:Play.ContainsKey($xeId) -and $script:Del.ContainsKey($xeId)) { [void][Windows.Forms.MessageBox]::Show("'$($gm.Name)' está sendo apagado do disco.", "$($xe.Name)"); return }
    if ($xeProg) { UnblockGame $gm }      # v2.47.0: mesmo desbloqueio do Jogar antes de abrir o programa
    $xeOk = XeOpen $gm $xe.Path $xe.Args $xeWhat
    $xePr = $script:OpenProc; $script:OpenProc = $null
    if ($xeOk -and $xeProg -and -not $script:Play.ContainsKey($xeId)) {
        Log 'INFO' ("Extra '$($xe.Name)' de '$($gm.Name)' iniciado" + $(if ($xePr) { " (processo $($xePr.Id))" }) + '; acompanhado como o Jogar')
        try { PlayBegin $gm $xePr; if ($script:Play[$xeId]) { $script:Play[$xeId].Extra = $xe } } catch { LogEx 'AVISO' "Não foi possível acompanhar o extra '$($xe.Name)' de '$($gm.Name)': $($_.Exception.Message)" $_; if ($xePr) { $xePr.Dispose() } }
    } elseif ($xePr) { try { $xePr.Dispose() } catch { $Error.Clear() } }
}
function ExtraUnrar($gm, $xe) {
    $xeId = "$($gm.Id)"; $xeTitle = "$($xe.Name)"
    if (RunFind $xeId) { [void][Windows.Forms.MessageBox]::Show("Já há uma extração de '$($gm.Name)' em andamento. Aguarde terminar.", $xeTitle); return }
    if ($script:Del.ContainsKey($xeId)) { [void][Windows.Forms.MessageBox]::Show("'$($gm.Name)' está sendo apagado do disco.", $xeTitle); return }
    $script:Drive = @{}; $script:PathSeen = @{}; if (CheckGame $gm) { InstSave; Populate }
    $xeSt = $script:InstState[$xeId]
    if ($xeSt -eq 'offline') { [void][Windows.Forms.MessageBox]::Show("A unidade do jogo não está conectada.", $xeTitle); return }
    if ($xeSt -eq 'archived' -and -not $xe.Dest) { [void][Windows.Forms.MessageBox]::Show("'$($gm.Name)' ainda está compactado.`nUse Jogar primeiro para extrair o jogo e depois '$xeTitle'.", $xeTitle); return }
    $xeExe = UnrarExe
    if (-not [IO.File]::Exists($xeExe)) { [void][Windows.Forms.MessageBox]::Show("UnRAR.exe não foi encontrado em: $(Short $xeExe)`nAjuste o caminho no modo desenvolvedor (aba Compactados).", $xeTitle, 'OK', 'Warning'); return }
    $xeArc = Full (XeExpand $gm $xe.Path)
    if (-not $xeArc -or -not [IO.File]::Exists($xeArc)) { Log 'AVISO' "Extra '$xeTitle' de '$($gm.Name)': arquivo não encontrado: $(Short $xeArc)"; [void][Windows.Forms.MessageBox]::Show("Arquivo não encontrado:`n$xeArc", $xeTitle, 'OK', 'Warning'); return }
    $xeVol = ArcVolumes $xeArc
    if ($xeVol.Missing) { [void][Windows.Forms.MessageBox]::Show('Faltam partes do arquivo compactado (a sequência de partes está incompleta).', $xeTitle, 'OK', 'Warning'); return }
    $xeDest = if ($xe.Dest) { Full (XeExpand $gm $xe.Dest) } else { XeGameDir $gm }
    if (-not $xeDest) { [void][Windows.Forms.MessageBox]::Show($(if ($xe.Dest) { "'Extrair em' precisa ser uma pasta dentro da pasta do launcher:`n$($xe.Dest)" } else { 'Não foi possível descobrir a pasta onde extrair.' }), $xeTitle, 'OK', 'Warning'); return }
    $up = @{ Arc = $xeArc; Dest = $xeDest; Proc = $null; Extra = $xe; Label = $xeTitle }
    $run = @{ Id = $xeId; Name = "$($gm.Name)"; Game = $gm; Stage = 'extra'; UP = $up }
    try {
        [void][IO.Directory]::CreateDirectory($xeDest)
        $up.Proc = ProcRedirect $xeExe "x -y -o+ $(PassArg) -idq -- `"$xeArc`" `"$($xeDest.TrimEnd('\', '/') + '\')`""
    } catch { LogEx 'ERRO' "Extra '$xeTitle' de '$($gm.Name)': não foi possível iniciar o UnRAR: $($_.Exception.Message)" $_; [void][Windows.Forms.MessageBox]::Show("Não foi possível iniciar a extração:`n$($_.Exception.Message)", $xeTitle, 'OK', 'Warning'); return }
    Log 'INFO' "Extra '$xeTitle' de '$($gm.Name)': extraindo $(Short $xeArc) em $(Short $xeDest) (o .rar será mantido)"
    $script:Ext[$xeId] = @{ Phase = 'run'; P = 0.0; T = -1.0; Since = (Get-Date); End = $null; Idx = -1 }
    $script:Runs += $run; RunStatus
    if ($runTm) { $runTm.Start() }; if ($extTm) { $extTm.Start() }
}
function ExtraFail($run, $why) {
    $up = $run.UP
    Log 'ERRO' "Extra '$($up.Label)' de '$($run.Name)' falhou: $why"
    if ($up -and $up.Proc) { try { if (-not $up.Proc.Proc.HasExited) { $up.Proc.Proc.Kill() } } catch { $Error.Clear() } }
    $script:Ext["$($run.Id)"] = @{ Phase = 'fail'; P = 0.0; T = 0.0; Since = (Get-Date); End = (Get-Date); Idx = -1 }
    RunRemove $run; if ($extTm) { $extTm.Start() }
    [void][Windows.Forms.MessageBox]::Show("Não foi possível extrair '$($up.Label)'.`n$why`n`nO arquivo .rar não foi apagado. Detalhes em TarginoRetroStation\Logs\launcher.log", $up.Label, 'OK', 'Warning')
}
function ExtraTick($run) {   # nunca apaga o .rar
    $up = $run.UP
    if (-not (ProcDone $up.Proc)) { return }
    $code = $up.Proc.Proc.ExitCode; $txt = ("$($up.Proc.Err.Result) $($up.Proc.Out.Result)").Trim(); $up.Proc.Proc.Dispose()
    if ($code -gt 1) {
        if ($txt.Length -gt 300) { $txt = $txt.Substring(0, 300) }
        ExtraFail $run $(if ($code -eq 11) { 'Senha incorreta ou ausente. Defina a senha no modo desenvolvedor (aba Compactados).' } else { "O UnRAR terminou com erro (código $code). $txt" }); return
    }
    if ($code -eq 1) { Log 'AVISO' "UnRAR terminou com aviso (código 1) no extra '$($up.Label)' de '$($run.Name)'" }
    try { UnblockTree $up.Dest $run.Name } catch { LogEx 'AVISO' "Desbloqueio após o extra '$($up.Label)' falhou: $($_.Exception.Message)" $_ }
    Log 'INFO' "Extra '$($up.Label)' de '$($run.Name)' extraído em $(Short $up.Dest) (o .rar foi mantido)"
    $script:Ext["$($run.Id)"] = @{ Phase = 'done'; P = 1.0; T = 1.0; Since = (Get-Date); End = (Get-Date); Idx = -1 }
    $run.Stage = ''; RunRemove $run
    $script:Drive = @{}; $script:PathSeen = @{}; if (CheckGame $run.Game) { InstSave; Populate }
    $xeAfter = "$($up.Extra.After)".Trim()
    if (-not $xeAfter) { Launch $run.Game }
    elseif ($xeAfter -ne '-') { [void](XeOpen $run.Game $xeAfter '' "depois do extra '$($up.Label)' de '$($run.Name)'") }
}

# ---- Estado da biblioteca ----
$script:View = @(); $script:SelIds = New-Object 'System.Collections.Generic.HashSet[string]'; $script:FavSet = New-Object 'System.Collections.Generic.HashSet[string]'
$script:Cur = $null; $script:CurIdx = -1; $script:Anchor = -1; $script:Hover = -1
$script:Cfg = $null; $script:Gx = $null; $script:Met = $null; $script:Filter = 'all'; $script:FilCounts = @{}; $script:CfgWarned = @{}
$script:CoverFail = New-Object 'System.Collections.Generic.HashSet[string]'
$script:CoverWarned = New-Object 'System.Collections.Generic.HashSet[string]'      # avisos de capa: um por arquivo por sessão
$script:CoverGen = 0
$script:Ix = $null; $script:ViewIds = $null
$script:Perf = @{ Paint = (New-Object 'System.Collections.Generic.Queue[double]'); Filtro = (New-Object 'System.Collections.Generic.Queue[double]'); ReadyMs = 0 }
$AllKeys = @('all', 'recent', 'fav', 'inst', 'notinst')

# ---- Leitura segura das configurações de aparência: valor inválido nunca quebra, usa o padrão e avisa uma vez no log ----
function CfgWarn($key) { if (-not $script:CfgWarned[$key]) { $script:CfgWarned[$key] = $true; Log 'AVISO' "Valor inválido em '$key' no layout (usando o padrão)" } }
function CfgNum($key, $min, $max, $def) {
    $v = 0
    if (-not [int]::TryParse("$($S[$key])", [ref]$v)) { CfgWarn $key; return $def }
    [Math]::Min($max, [Math]::Max($min, $v))
}
function CfgChoice($key, $allowed, $def) { $t = "$($S[$key])"; if ($allowed -contains $t) { $t } else { CfgWarn $key; $def } }
function CfgCol($key, $def) {
    $t = "$($S[$key])".Trim()
    if ($t -match '^#?[0-9A-Fa-f]{6}$') { if ($t[0] -ne '#') { $t = "#$t" }; return [Drawing.ColorTranslator]::FromHtml($t) }
    CfgWarn $key; [Drawing.ColorTranslator]::FromHtml($def)
}
function CfgColOpt($key, $fallback) {   # cor opcional: vazio = usa $fallback
    $t = "$($S[$key])".Trim(); if (-not $t) { return $fallback }
    if ($t -match '^#?[0-9A-Fa-f]{6}$') { if ($t[0] -ne '#') { $t = "#$t" }; return [Drawing.ColorTranslator]::FromHtml($t) }
    CfgWarn $key; $fallback
}
function LoadCfg {
    $c = @{}
    $c.Sizes = @((CfgNum 'CoverS1' 48 512 128), (CfgNum 'CoverS2' 48 512 180), (CfgNum 'CoverS3' 48 512 256))
    $c.GapH = CfgNum 'GapH' 0 200 20; $c.GapV = CfgNum 'GapV' 0 200 14; $c.PadX = CfgNum 'PadX' 0 200 24; $c.PadY = CfgNum 'PadY' 0 200 20
    $c.Center = [bool]$S.GridCenter
    $c.Fit = CfgChoice 'CoverFit' @('Preencher', 'Ajustar', 'Esticar') 'Preencher'
    $c.NameLines = CfgNum 'NameLines' 0 3 2; $c.NameSize = CfgNum 'NameSize' 7 24 9; $c.NameGap = CfgNum 'NameGap' 0 40 6
    $c.NotInst = CfgChoice 'NotInstalled' @('Preto e branco', 'Escurecida', 'Os dois', 'Nada') 'Preto e branco'
    $c.Dim = CfgNum 'DimNotInst' 0 100 60; $c.DimInst = CfgNum 'DimInstalled' 0 100 0; $c.SelBright = [bool]$S.SelBright
    $c.SelW = CfgNum 'SelWidth' 0 12 3; $c.SelGap = CfgNum 'SelGap' 0 16 3
    $c.SelStyle = CfgChoice 'SelStyle' @('Sólida', 'Tracejada') 'Sólida'
    $c.SelColor = CfgCol 'SelColor' '#1E90FF'; $c.Accent = CfgCol 'Accent' '#1E90FF'
    $c.Delete = CfgCol 'DeleteColor' '#E5484D'
    $c.Bg = CfgCol 'BgColor' '#0B0B0B'; $c.Side = CfgCol 'SideColor' '#141414'; $c.Text = CfgCol 'TextColor' '#FFFFFF'; $c.Sub = CfgCol 'SubColor' '#9A9A9A'
    $c.DetailW = CfgNum 'DetailWidth' 260 800 400; $c.DescFont = "$($S.DescFont)".Trim(); if (-not $c.DescFont -or $c.DescFont -eq 'Segoe UI') { $c.DescFont = "$($S.FontFamily)".Trim() }; $c.TextContrast = CfgNum 'TextContrast' 0 12 6; $c.TextRender = CfgChoice 'TextRender' @('ClearType', 'Suavizado (cinza)', 'Suavizado (grade)', 'Padrão do sistema', 'Sem suavização') 'ClearType'
    $c.DescSize = CfgNum 'DescSize' 8 24 10; $c.DescTitle = CfgNum 'DescTitleSize' 12 48 18; $c.DescSubT = CfgNum 'DescSubSize' 10 32 13; $c.DescLink = CfgCol 'DescLinkColor' '#4DA3FF'
    $c.DetailPad = CfgNum 'DetailPad' 0 60 15; $c.DetailBg = CfgColOpt 'DetailBg' $c.Bg
    $c.TitleFont = "$($S.TitleFont)".Trim(); $c.TitleSize = CfgNum 'TitleSize' 12 60 18; $c.TitleStyle = CfgChoice 'TitleStyle' @('Normal', 'Negrito', 'Itálico', 'Negrito + itálico') 'Normal'
    $c.TitleCol = CfgColOpt 'TitleColor' $c.Text; $c.TitleLines = CfgNum 'TitleLines' 1 4 2; $c.TitleAlign = CfgChoice 'TitleAlign' @('Esquerda', 'Centro', 'Direita') 'Esquerda'
    $c.StatusSize = CfgNum 'StatusSize' 8 20 9; $c.StatusCol = CfgColOpt 'StatusColor' ([Drawing.Color]::FromArgb(224, 123, 123)); $c.StatusStyle = CfgChoice 'StatusStyle' @('Normal', 'Negrito', 'Itálico', 'Negrito + itálico') 'Normal'
    $c.StatusAlign = CfgChoice 'StatusAlign' @('Esquerda', 'Centro', 'Direita') 'Centro'; $c.StatusGapTop = CfgNum 'StatusGapTop' 0 60 6; $c.StatusGapBottom = CfgNum 'StatusGapBottom' 0 60 10; $c.VersionSize = CfgNum 'VersionSize' 8 20 9; $c.VersionCol = CfgColOpt 'VersionColor' $c.Accent
    $c.DescCol = CfgColOpt 'DescColor' $c.Text; $c.DescTitleCol = CfgColOpt 'DescTitleColor' $c.Accent; $c.DescAlign = CfgChoice 'DescAlign' @('Esquerda', 'Centro', 'Direita') 'Esquerda'
    $c.RecentDays = CfgNum 'RecentDays' 1 3650 30; $c.SideCount = [bool]$S.ShowSideCount
    # jogo em execução (v2.37.0)
    $c.PlayPulse = CfgNum 'PlayPulse' 0 100 70; $c.PlayBorder = CfgColOpt 'PlayBorderColor' $c.Accent
    $c.PlayDot = CfgColOpt 'PlayDotColor' $c.Accent; $c.PlayDotSize = CfgNum 'PlayDotSize' 4 20 9
    $c.PlayTxt = CfgColOpt 'PlayTextColor' $c.Accent; $c.PlaySize = CfgNum 'PlayTextSize' 0 24 0
    $c.PlayBold = [bool]$S.PlayBold; $c.PlayItalic = [bool]$S.PlayItalic; $c.PlayCheck = CfgNum 'PlayCheckSec' 1 30 3
    # topo (v2.50.0)
    $c.HdrOn = [bool]$S.HeaderShow; $c.HdrText = "$($S.HeaderText)"; $c.HdrFont = "$($S.HeaderFont)".Trim(); $c.HdrSize = CfgNum 'HeaderSize' 10 72 22
    $c.HdrStyle = CfgChoice 'HeaderStyle' @('Normal', 'Negrito', 'Itálico', 'Negrito + itálico') 'Negrito'; $c.HdrCaps = [bool]$S.HeaderCaps; $c.HdrSpace = CfgNum 'HeaderSpacing' 0 30 1
    $c.HdrCol = CfgCol 'HeaderColor' '#3BA4FF'; $c.HdrFill = CfgChoice 'HeaderFill' @('Degradê suave', 'Cor sólida') 'Degradê suave'
    $c.HdrGlow = CfgNum 'HeaderGlow' 0 100 35; $c.HdrGlowSize = CfgNum 'HeaderGlowSize' 1 30 10; $c.HdrGlowCol = CfgColOpt 'HeaderGlowColor' $c.HdrCol
    $c.HdrPadT = CfgNum 'HeaderPadTop' 0 60 10; $c.HdrPadB = CfgNum 'HeaderPadBottom' 0 60 0
    $tpAreas = @('Área dos jogos', 'Janela inteira'); $tpAligns = @('Centro', 'Esquerda', 'Direita')
    $c.HdrArea = CfgChoice 'HeaderArea' $tpAreas 'Área dos jogos'; $c.HdrAlign = CfgChoice 'HeaderAlign' $tpAligns 'Centro'; $c.HdrOffX = CfgNum 'HeaderOffsetX' -3000 3000 0
    $c.TopJoin = [bool]$S.TopJoin
    $c.SearchArea = CfgChoice 'SearchArea' $tpAreas 'Área dos jogos'; $c.SearchAlign = CfgChoice 'SearchAlign' $tpAligns 'Centro'; $c.SearchOffX = CfgNum 'SearchOffsetX' -3000 3000 0
    $c.FilterArea = CfgChoice 'FilterArea' $tpAreas 'Área dos jogos'; $c.FilterAlign = CfgChoice 'FilterAlign' $tpAligns 'Centro'; $c.FilterOffX = CfgNum 'FilterOffsetX' -3000 3000 0
    $c.HdrLine = [bool]$S.HeaderLine; $c.HdrLineCol = CfgColOpt 'HeaderLineColor' $c.HdrCol; $c.HdrLineW = CfgNum 'HeaderLineWidth' 10 100 50
    $script:Cfg = $c
}
# Pincéis, canetas e fontes reutilizados em todo desenho (recriados só quando o layout muda)
function RebuildGfx {
    if ($script:Gx) { foreach ($k in @($script:Gx.Keys)) { try { $script:Gx[$k].Dispose() } catch { $Error.Clear() } } }
    $c = $script:Cfg; $gx = @{}
    $gx.Text = New-Object Drawing.SolidBrush ($c.Text); $gx.Sub = New-Object Drawing.SolidBrush ($c.Sub); $gx.Acc = New-Object Drawing.SolidBrush ($c.Accent)
    $gx.Dim = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int](255 * $c.Dim / 100), 0, 0, 0))
    $gx.DimI = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int](255 * $c.DimInst / 100), 0, 0, 0))
    $gx.Dim2 = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(140, 0, 0, 0)); $gx.PhOn = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(120, $c.Accent.R, $c.Accent.G, $c.Accent.B))
    $gx.Ph = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(40, 40, 40)); $gx.PhText = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(110, 255, 255, 255))
    $pen = New-Object Drawing.Pen ($c.SelColor), ([single][Math]::Max(1, $c.SelW))
    if ($c.SelStyle -eq 'Tracejada') { $pen.DashStyle = [Drawing.Drawing2D.DashStyle]::Dash }
    $gx.Sel = $pen; $gx.Hover = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(110, 255, 255, 255)), ([single]1)
    $gx.NameFont = UiFont $c.NameSize
    $gx.PlayFont = UiFont $(if ($c.PlaySize -gt 0) { $c.PlaySize } else { $c.NameSize }) ([int]$c.PlayBold + 2 * [int]$c.PlayItalic)   # "Em execução" (v2.37.0)
    $gx.InitFont = UiFont 40 1
    $f1 = New-Object Drawing.StringFormat; $f1.Alignment = 'Center'; $f1.LineAlignment = 'Near'; $f1.Trimming = 'EllipsisCharacter'; $f1.FormatFlags = [Drawing.StringFormatFlags]::LineLimit; $gx.Fmt = $f1
    $f2 = New-Object Drawing.StringFormat; $f2.Alignment = 'Center'; $f2.LineAlignment = 'Center'; $gx.FmtC = $f2
    $f3 = New-Object Drawing.StringFormat; $f3.Alignment = 'Near'; $f3.LineAlignment = 'Center'; $f3.Trimming = 'EllipsisCharacter'; $f3.FormatFlags = [Drawing.StringFormatFlags]::NoWrap; $gx.FmtL = $f3
    $f4 = New-Object Drawing.StringFormat; $f4.Alignment = 'Far'; $f4.LineAlignment = 'Center'; $gx.FmtR = $f4
    $cmx = New-Object Drawing.Imaging.ColorMatrix
    $cmx.Matrix00 = 0.3;  $cmx.Matrix01 = 0.3;  $cmx.Matrix02 = 0.3
    $cmx.Matrix10 = 0.59; $cmx.Matrix11 = 0.59; $cmx.Matrix12 = 0.59
    $cmx.Matrix20 = 0.11; $cmx.Matrix21 = 0.11; $cmx.Matrix22 = 0.11
    $ia = New-Object Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($cmx); $gx.Gray = $ia
    $script:Gx = $gx
}
function SetStyles($ctrl) {   # painel desenhado por nós: sem flicker, recebe foco e teclado
    $mi = [Windows.Forms.Control].GetMethod('SetStyle', [Reflection.BindingFlags]'Instance,NonPublic')
    foreach ($st in 'UserPaint', 'AllPaintingInWmPaint', 'OptimizedDoubleBuffer', 'ResizeRedraw', 'Selectable') { [void]$mi.Invoke($ctrl, @([Windows.Forms.ControlStyles]$st, $true)) }
}

# ---- Capas: carregadas sob demanda (só as da tela e de uma pequena margem), em segundo plano, com cache LRU limitado ----
#  Chave = geração|tamanho|ajuste|arquivo. Mudar o tamanho/ajuste muda a chave; CacheClear troca a geração, e resultados
#  que chegarem de uma geração antiga são descartados (Dispose) em vez de entrar no cache. Nunca altera o arquivo original.
function CacheClear {
    $script:CoverGen++
    $script:Lru.Clear(); $script:Loader.CancelAll(); $script:CoverFail.Clear()
    $script:PtView = $null; $script:Painter.Vis.Clear()
}
function CoverWarn($path, $why) { if ($script:CoverWarned.Add("$path")) { Log 'AVISO' "Capa não pôde ser carregada: $(Short $path) ($why)" } }
# Capa pronta para desenhar, ou $null (aí o pedido fica na fila e a capa aparece quando chegar). Usada só nos quadrados
#  desenhados em PowerShell (extração em andamento, jogo aberto); o resto da grade é desenhado pelo GridPainter.
function CoverGet($cp, $cover, $fit) {
    if (-not $cp) { return $null }
    $mediaStamp=''
    if ($cp.IndexOf('\Midia\',[StringComparison]::OrdinalIgnoreCase) -ge 0) { $mediaStamp=[IO.File]::GetLastWriteTimeUtc($cp).Ticks }
    $key = "$script:CoverGen|$cover|$fit|$cp|$mediaStamp"
    $bm = $script:Lru.Get($key); if ($bm) { return $bm }
    if (-not $script:CoverFail.Contains($key)) { [void]$script:Loader.Request($key, "$cp", [int]$cover, "$fit", $true) }
    $null
}
# Timer: recolhe as capas prontas (até ~12 ms por vez) e redesenha só o quadrado de cada uma
function CoverDrain {
    $fl = New-Object 'System.Collections.Generic.List[CoverLoader+Res]'
    $script:Painter.Gen = [int]$script:CoverGen
    foreach ($rc in $script:Painter.Drain([int]$vsb.Value, 12, $fl)) { $grid.Invalidate($rc) }
    # O carrossel usa posições diferentes da grade: redesenha após recolher as capas,
    # inclusive quando esta coleta esvazia a fila (último resultado recebido).
    if ($S.CinemaMode) { $grid.Invalidate() }
    foreach ($rs in $fl) { CoverWarn $rs.Path $(if ($rs.Missing) { 'arquivo não encontrado' } else { "$($rs.Error)" }) }
    if ($script:Loader.Pending -gt 0) { $loadTm.Start() }
}

# ---- Geometria da grade (funções puras: só números, sem controles) ----
# selExt = espaço reservado em volta da capa para a borda de seleção; assim ela nunca é cortada nem encosta no vizinho
function GridMetrics($width, $count, $cover, $gapH, $gapV, $padX, $padY, $selExt, $nameH, $nameGap, $center) {
    $tileW = $cover + 2 * $selExt
    $tileH = $cover + 2 * $selExt; if ($nameH -gt 0) { $tileH += $nameGap + $nameH }
    $cellW = $tileW + $gapH; $cellH = $tileH + $gapV
    $cols = [Math]::Max(1, [int][Math]::Floor((($width - 2 * $padX) + $gapH) / $cellW))
    $contentW = $cols * $cellW - $gapH
    $offX = $padX; if ($center) { $offX = [Math]::Max($padX, [int][Math]::Floor(($width - $contentW) / 2)) }
    $rows = 0; if ($count -gt 0) { $rows = [int][Math]::Ceiling($count / $cols) }
    $totalH = 0; if ($rows) { $totalH = 2 * $padY + $rows * $cellH - $gapV }
    @{ Cols = $cols; Rows = $rows; CellW = $cellW; CellH = $cellH; TileW = $tileW; TileH = $tileH; OffX = $offX; PadY = $padY; TotalH = $totalH; SelExt = $selExt; Cover = $cover; NameH = $nameH; NameGap = $nameGap }
}
function TileXY($met, $i) { @(($met.OffX + ($i % $met.Cols) * $met.CellW), ($met.PadY + [int][Math]::Floor($i / $met.Cols) * $met.CellH)) }
# Qual jogo está sob o ponto (x, y)? Coordenadas do conteúdo (já somada a rolagem). -1 = nenhum (fundo, espaço entre itens)
function GridHit($met, $x, $y, $count) {
    $px = $x - $met.OffX; $py = $y - $met.PadY
    if ($px -lt 0 -or $py -lt 0) { return -1 }
    $col = [int][Math]::Floor($px / $met.CellW); $rw = [int][Math]::Floor($py / $met.CellH)
    if ($col -ge $met.Cols) { return -1 }
    if (($px - $col * $met.CellW) -ge $met.TileW -or ($py - $rw * $met.CellH) -ge $met.TileH) { return -1 }
    $idx = $rw * $met.Cols + $col
    if ($idx -ge $count) { return -1 }
    $idx
}

# ---- Helpers de interface ----
function Mk($type, $props, $parent) {
    $c = New-Object $type
    if ($c -is [Windows.Forms.Label]) { $c.AutoSize = $false }
    foreach ($k in $props.Keys) { $c.$k = $props[$k] }
    $parent.Controls.Add($c); $c
}
function Lbl($text, $x, $y, $w, $h) { $l = New-Object Windows.Forms.Label; $l.AutoSize = $false; $l.SetBounds($x, $y, $w, $h); $l.Text = $text; $l }
# ---- Janelas redimensionáveis (v2.33.0): o modo dev usa janelas que podem ser aumentadas/maximizadas; o tamanho fica em Dados\janelas.json (v2.52.0) ----
function WinSizable($f, $key, $minW, $minH) {
    $f.FormBorderStyle = 'Sizable'; $f.MaximizeBox = $true; $f.MinimizeBox = $false; $f.SizeGripStyle = 'Show'
    $f.MinimumSize = New-Object Drawing.Size([int]$minW, [int]$minH)
    $f.Name = "$key"
    $f.Add_Load({ param($snd, $ev) WinRestore $snd })
    $f.Add_FormClosing({ param($snd, $ev) WinRemember $snd })
}
function WinRestore($f) {
    try {
        $v = "$($DevWin[$f.Name])"; if (-not $v) { return }
        $p = $v -split ','; if ($p.Count -lt 2) { return }
        $wa = [Windows.Forms.Screen]::FromControl($f).WorkingArea
        $w = [Math]::Max($f.MinimumSize.Width, [Math]::Min([int]$p[0], $wa.Width))
        $h = [Math]::Max($f.MinimumSize.Height, [Math]::Min([int]$p[1], $wa.Height))
        $f.Size = New-Object Drawing.Size($w, $h)
        $ow = $f.Owner; if (-not $ow -and $form -and $form.Visible) { $ow = $form }
        $c = if ($ow -and $ow.Visible -and $ow.WindowState -ne 'Minimized') { $ow.Bounds } else { $wa }
        $x = $c.X + [int](($c.Width - $w) / 2); $y = $c.Y + [int](($c.Height - $h) / 2)
        $x = [Math]::Max($wa.X, [Math]::Min($x, $wa.Right - $w)); $y = [Math]::Max($wa.Y, [Math]::Min($y, $wa.Bottom - $h))
        $f.StartPosition = 'Manual'; $f.Location = New-Object Drawing.Point($x, $y)
        if ($p.Count -ge 3 -and $p[2] -eq '1') { $f.WindowState = 'Maximized' }
    } catch { $Error.Clear() }
}
function WinRemember($f) {
    try {
        $b = if ($f.WindowState -eq 'Normal') { $f.Size } else { $f.RestoreBounds.Size }
        $DevWin[$f.Name] = "$($b.Width),$($b.Height),$(if ($f.WindowState -eq 'Maximized') { 1 } else { 0 })"
        SaveWin
    } catch { $Error.Clear() }
}
function TxtW($text, $font) { [Windows.Forms.TextRenderer]::MeasureText("$text", $font).Width }

# ---- Janela principal ----
#  [barra do topo: busca, menu de filtros, + Adicionar / Personalizar no modo dev]
#  [grade de capas desenhada por nós + rolagem]  [painel de detalhes à direita]
# ---- Visual escuro próprio: barra de rolagem, menus, barra de título, rótulos e descrição (C#) ----
$UiSrc = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

// Rótulo que desenha o texto por GDI+ com a mesma suavização/contraste da grade (o Label padrão segue só a configuração do Windows).
public class ClearLabel : Label
{
    public TextRenderingHint Hint = TextRenderingHint.ClearTypeGridFit;
    public int Contrast = 6;
    public StringAlignment HAlign = StringAlignment.Near;
    public ClearLabel()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        using (SolidBrush bk = new SolidBrush(BackColor)) g.FillRectangle(bk, ClientRectangle);
        if (string.IsNullOrEmpty(Text)) return;
        g.TextRenderingHint = Hint;
        try { g.TextContrast = Math.Max(0, Math.Min(12, Contrast)); } catch (Exception) { }
        using (StringFormat sf = new StringFormat(StringFormat.GenericTypographic))
        using (SolidBrush tb = new SolidBrush(ForeColor))
        {
            sf.Trimming = StringTrimming.EllipsisCharacter; sf.Alignment = HAlign;
            sf.FormatFlags |= StringFormatFlags.LineLimit;
            g.DrawString(Text, Font, tb, new RectangleF(0, 0, ClientSize.Width, ClientSize.Height), sf);
        }
    }
}

// Barra de rolagem fina e escura (substitui a VScrollBar branca do Windows). Mesma API usada pelo launcher.
public class DarkScroll : Control
{
    private int mn = 0, mx = 100, lc = 10, sc = 20, val = 0;
    private bool hot = false, drag = false;
    private int dragOff = 0;
    public Color TrackColor = Color.FromArgb(11, 11, 11);
    public Color ThumbColor = Color.FromArgb(60, 60, 60);
    public Color ThumbHotColor = Color.FromArgb(110, 110, 110);
    public event EventHandler ValueChanged;

    public DarkScroll()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.Selectable, false);
        TabStop = false;
        Width = 12;
    }
    public int Minimum { get { return mn; } set { mn = value; Clamp(); Invalidate(); } }
    public int Maximum { get { return mx; } set { mx = value; Clamp(); Invalidate(); } }
    public int LargeChange { get { return lc; } set { lc = Math.Max(1, value); Clamp(); Invalidate(); } }
    public int SmallChange { get { return sc; } set { sc = Math.Max(1, value); } }
    private int MaxValue { get { return Math.Max(mn, mx - lc + 1); } }
    public int Value
    {
        get { return val; }
        set
        {
            int v = Math.Max(mn, Math.Min(MaxValue, value));
            if (v == val) return;
            val = v; Invalidate(); Update();      // a barra se redesenha já (antes esperava a grade terminar de desenhar)
            if (ValueChanged != null) ValueChanged(this, EventArgs.Empty);
        }
    }
    private void Clamp()
    {
        int v = Math.Max(mn, Math.Min(MaxValue, val));
        if (v != val) { val = v; if (ValueChanged != null) ValueChanged(this, EventArgs.Empty); }
    }
    private bool Active { get { return Enabled && (mx - mn) >= lc && MaxValue > mn; } }
    private Rectangle ThumbRect()
    {
        int h = ClientSize.Height; int range = Math.Max(1, mx - mn + 1);
        int len = (int)Math.Max(28, (long)h * lc / range); if (len > h) len = h;
        int span = Math.Max(1, MaxValue - mn);
        int top = (int)((long)(h - len) * (val - mn) / span);
        return new Rectangle(2, top, Math.Max(2, ClientSize.Width - 4), len);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        using (SolidBrush bk = new SolidBrush(TrackColor)) g.FillRectangle(bk, ClientRectangle);
        if (!Active) return;
        Rectangle r = ThumbRect();
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (GraphicsPath p = Round(r, Math.Min(r.Width, 8)))
        using (SolidBrush tb = new SolidBrush(hot || drag ? ThumbHotColor : ThumbColor)) g.FillPath(tb, p);
    }
    private static GraphicsPath Round(Rectangle r, int d)
    {
        GraphicsPath p = new GraphicsPath();
        if (d < 2) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure(); return p;
    }
    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (!Active || e.Button != MouseButtons.Left) return;
        Rectangle r = ThumbRect();
        if (r.Contains(e.Location)) { drag = true; dragOff = e.Y - r.Top; Capture = true; Invalidate(); }
        else Value = val + (e.Y < r.Top ? -lc : lc);
    }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!Active) return;
        if (drag)
        {
            Rectangle r = ThumbRect(); int free = Math.Max(1, ClientSize.Height - r.Height);
            int top = Math.Max(0, Math.Min(free, e.Y - dragOff));
            Value = mn + (int)((long)top * Math.Max(1, MaxValue - mn) / free);
        }
        else { bool h = ThumbRect().Contains(e.Location); if (h != hot) { hot = h; Invalidate(); } }
    }
    protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); if (drag) { drag = false; Capture = false; Invalidate(); } }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (hot) { hot = false; Invalidate(); } }
    protected override void OnMouseWheel(MouseEventArgs e) { base.OnMouseWheel(e); if (Active) Value = val - Math.Sign(e.Delta) * sc * 3; }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
}

// Menus escuros e achatados (sem a margem de ícones nem o azul do Windows). O item sob o mouse recebe a cor oposta à do menu.
public class DarkMenuRenderer : ToolStripProfessionalRenderer
{
    public Color Bg = Color.FromArgb(20, 20, 20), Border = Color.FromArgb(60, 60, 60), Text = Color.White;
    public Color HoverBg = Color.FromArgb(230, 230, 230), HoverFg = Color.FromArgb(16, 16, 16), Accent = Color.DodgerBlue;
    public Color DangerFg = Color.FromArgb(229, 72, 77);      // item com Tag = "danger" (ex.: Deletar jogo)
    public DarkMenuRenderer() : base() { RoundedEdges = false; }
    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        using (SolidBrush b = new SolidBrush(Bg)) e.Graphics.FillRectangle(b, e.AffectedBounds);
    }
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        using (Pen p = new Pen(Border)) e.Graphics.DrawRectangle(p, 0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
    }
    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) { }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        ToolStripItem it = e.Item; Rectangle r = new Rectangle(2, 1, it.Width - 4, it.Height - 2);
        if (it.Selected && it.Enabled) { using (SolidBrush b = new SolidBrush(HoverBg)) e.Graphics.FillRectangle(b, r); }
        ToolStripMenuItem mi = it as ToolStripMenuItem;
        if (mi != null && mi.Checked) { using (SolidBrush a = new SolidBrush(Accent)) e.Graphics.FillRectangle(a, 2, 4, 3, Math.Max(2, it.Height - 8)); }
    }
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        ToolStripMenuItem mi = e.Item as ToolStripMenuItem;
        Color c = Text;
        if (!e.Item.Enabled) c = Color.FromArgb(110, 110, 110);
        else if (e.Item.Selected) c = HoverFg;
        else if (mi != null && mi.Checked) c = Accent;
        if (e.Item.Enabled && (e.Item.Tag as string) == "danger") c = DangerFg;
        e.TextColor = c;
        base.OnRenderItemText(e);
    }
    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e) { }
    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        int y = e.Item.Height / 2;
        using (Pen p = new Pen(Border)) e.Graphics.DrawLine(p, 8, y, e.Item.Width - 8, y);
    }
}

// Barra de título escura (Windows 10 1809+ e Windows 11). Em versões sem suporte, simplesmente não faz nada.
public static class Dwm
{
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public static void Dark(IntPtr h, bool on, int caption, int text)
    {
        try
        {
            int v = on ? 1 : 0;
            if (DwmSetWindowAttribute(h, 20, ref v, 4) != 0) DwmSetWindowAttribute(h, 19, ref v, 4);
            if (caption >= 0) { DwmSetWindowAttribute(h, 35, ref caption, 4); DwmSetWindowAttribute(h, 34, ref caption, 4); }
            if (text >= 0) DwmSetWindowAttribute(h, 36, ref text, 4);
            SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, 0x37);      // força o Windows a redesenhar o quadro com a nova cor
        }
        catch (Exception) { }
    }
}

// Fontes da pasta fonts: ficam disponíveis só para este programa (FR_PRIVATE), nada é instalado no Windows e somem ao fechar.
public static class Fnt
{
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] private static extern int AddFontResourceEx(string file, uint flags, IntPtr res);
    public static int Add(string path)
    {
        try { return AddFontResourceEx(path, 0x10, IntPtr.Zero); }
        catch (Exception) { return 0; }
    }
}

// Descrição (RichTextBox): congela o desenho enquanto o texto é montado (sem tremer) e esconde o cursor de texto (v2.34.2).
public static class Rtb
{
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] private static extern bool HideCaret(IntPtr h);
    public static void Redraw(Control c, bool on)
    {
        try { if (c != null && c.IsHandleCreated) SendMessage(c.Handle, 0x000B, (IntPtr)(on ? 1 : 0), IntPtr.Zero); }
        catch (Exception) { }
    }
    public static void NoCaret(Control c)
    {
        try { if (c != null && c.IsHandleCreated) HideCaret(c.Handle); }
        catch (Exception) { }
    }
}

// Caixa da descrição: o cursor do mouse é decidido só aqui (mão sobre link, seta no resto). O RichTextBox padrão
// troca o cursor sozinho a cada movimento (I/seta) e brigava com a mão, fazendo o cursor piscar (v2.35.2).
public class DescBox : RichTextBox
{
    private bool overLink;
    public bool OverLink
    {
        get { return overLink; }
        set { if (overLink == value) return; overLink = value; System.Windows.Forms.Cursor.Current = value ? Cursors.Hand : Cursors.Default; }
    }
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x0020 && ((int)(long)m.LParam & 0xFFFF) == 1)   // WM_SETCURSOR na área do texto (HTCLIENT)
        {
            System.Windows.Forms.Cursor.Current = overLink ? Cursors.Hand : Cursors.Default;
            m.Result = (IntPtr)1;
            return;
        }
        base.WndProc(ref m);
    }
}
'@

# ---- Núcleo da biblioteca grande (C#): carregador de capas em segundo plano, cache LRU, índice de busca, desenho da grade ----
$CoreSrc = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

// Cache de capas por ordem de uso (LRU) com limite em bytes. Só é usado pela thread da interface.
// Ao passar do limite, descarta (Dispose) as capas usadas há mais tempo, mas nunca abaixo de "keep" itens
// (as que estão na tela agora), para não ficar descartando e recarregando a mesma capa.
public sealed class CoverLru
{
    private sealed class Entry { public string Key; public IDisposable Obj; public long Bytes; }
    private readonly Dictionary<string, LinkedListNode<Entry>> map = new Dictionary<string, LinkedListNode<Entry>>(StringComparer.Ordinal);
    private readonly LinkedList<Entry> order = new LinkedList<Entry>();
    public long Budget = 96L * 1024 * 1024;
    public long Bytes;
    public long Evicted;
    public long Hits;
    public long Misses;
    public int Count { get { return map.Count; } }
    public object Get(string key)
    {
        LinkedListNode<Entry> nd;
        if (!map.TryGetValue(key, out nd)) { Misses++; return null; }
        Hits++;
        if (nd != order.First) { order.Remove(nd); order.AddFirst(nd); }
        return nd.Value.Obj;
    }
    public bool Contains(string key) { return map.ContainsKey(key); }
    public void Put(string key, IDisposable obj, long bytes, int keep)
    {
        LinkedListNode<Entry> old;
        if (map.TryGetValue(key, out old))
        {
            order.Remove(old); map.Remove(key); Bytes -= old.Value.Bytes;
            if (!object.ReferenceEquals(old.Value.Obj, obj)) old.Value.Obj.Dispose();
        }
        Entry e = new Entry(); e.Key = key; e.Obj = obj; e.Bytes = bytes;
        map[key] = order.AddFirst(e); Bytes += bytes;
        Trim(keep);
    }
    public void Trim(int keep)
    {
        while (Bytes > Budget && map.Count > Math.Max(0, keep) && order.Last != null)
        {
            LinkedListNode<Entry> last = order.Last; order.RemoveLast(); map.Remove(last.Value.Key); Bytes -= last.Value.Bytes; Evicted++;
            try { last.Value.Obj.Dispose(); } catch (Exception) { }
        }
    }
    public void Clear()
    {
        foreach (Entry e in order) { try { e.Obj.Dispose(); } catch (Exception) { } }
        order.Clear(); map.Clear(); Bytes = 0;
    }
}

// Carregador de capas em segundo plano. A interface pede (Request), as threads decodificam e reduzem a imagem,
// e a interface recolhe os resultados (Take) num timer. Pedidos repetidos são ignorados; pedidos que saíram da
// tela são retirados da fila (Retain); "urgente" (na tela) passa à frente dos de antecipação.
public sealed class CoverLoader : IDisposable
{
    public sealed class Req { public string Key; public string Path; public int Size; public string Fit; }
    public sealed class Res { public string Key; public string Path; public object Bmp; public bool Missing; public string Error; }
    public delegate object DecodeFn(string path, int size, string fit);

    private readonly object lk = new object();
    private readonly LinkedList<Req> hi = new LinkedList<Req>();
    private readonly LinkedList<Req> lo = new LinkedList<Req>();
    private readonly Dictionary<string, LinkedListNode<Req>> queued = new Dictionary<string, LinkedListNode<Req>>(StringComparer.Ordinal);
    private readonly HashSet<string> loading = new HashSet<string>(StringComparer.Ordinal);
    private readonly Queue<Res> done = new Queue<Res>();
    private readonly HashSet<string> doneKeys = new HashSet<string>(StringComparer.Ordinal);      // prontas, ainda não recolhidas
    private readonly List<Thread> threads = new List<Thread>();
    private volatile bool stop;
    public DecodeFn Decode;
    public long Loaded, Failed, Dropped, Requested;
    // Miniaturas em disco: a capa já reduzida (tamanho/ajuste da grade) fica numa pasta; nas aberturas seguintes lê-se o arquivo pequeno
    // em vez de ler e reduzir o original (~1 MB). ThumbDir vazio = desligado. O nome do arquivo vem do NOME da capa (não do caminho
    // completo), então a pasta do launcher pode ser copiada/renomeada sem perder nada.
    public delegate object ThumbLoadFn(string thumbPath, int size);
    public delegate void ThumbSaveFn(object bmp, string thumbPath);
    public ThumbLoadFn ThumbLoad;
    public ThumbSaveFn ThumbSave;
    public string ThumbDir = "";
    public long ThumbHits, ThumbMiss, ThumbSaved, ThumbSaveErr, ThumbLoadErr, DecodeN, DecodeMs, DecodeMaxMs, ThumbMs, ThumbMaxMs;
    public static long SrcPix;
    private readonly object statLk = new object();
    public int Threads { get { return threads.Count; } }

    public CoverLoader(int count)
    {
        Decode = DecodeGdi; ThumbLoad = LoadThumbGdi; ThumbSave = SaveThumbGdi;
        count = Math.Max(1, Math.Min(8, count));
        for (int i = 0; i < count; i++)
        {
            Thread t = new Thread(Run); t.IsBackground = true; t.Priority = ThreadPriority.BelowNormal; t.Name = "CA-capas-" + i;
            threads.Add(t); t.Start();
        }
    }
    public bool Request(string key, string path, int size, string fit, bool urgent)
    {
        lock (lk)
        {
            if (stop || loading.Contains(key) || doneKeys.Contains(key)) return false;      // já decodificando ou já pronta: não refaz
            LinkedListNode<Req> nd;
            if (queued.TryGetValue(key, out nd))
            {
                if (urgent && nd.List == lo) { lo.Remove(nd); hi.AddLast(nd); }
                return false;
            }
            Req r = new Req(); r.Key = key; r.Path = path; r.Size = size; r.Fit = fit;
            queued[key] = urgent ? hi.AddLast(r) : lo.AddLast(r);
            Requested++;
            Monitor.Pulse(lk);
            return true;
        }
    }
    // Mantém na fila só o que ainda interessa (na tela ou na margem). Devolve quantos pedidos foram retirados.
    public int Retain(HashSet<string> wanted)
    {
        int n = 0;
        lock (lk)
        {
            n += Prune(hi, wanted); n += Prune(lo, wanted);
            Dropped += n;
        }
        return n;
    }
    private int Prune(LinkedList<Req> list, HashSet<string> wanted)
    {
        int n = 0; LinkedListNode<Req> nd = list.First;
        while (nd != null)
        {
            LinkedListNode<Req> nx = nd.Next;
            if (!wanted.Contains(nd.Value.Key)) { list.Remove(nd); queued.Remove(nd.Value.Key); n++; }
            nd = nx;
        }
        return n;
    }
    public void CancelAll()
    {
        lock (lk)
        {
            Dropped += hi.Count + lo.Count;
            hi.Clear(); lo.Clear(); queued.Clear();
        }
    }
    public Res Take() { lock (lk) { if (done.Count == 0) return null; Res t = done.Dequeue(); doneKeys.Remove(t.Key); return t; } }
    public int Queued { get { lock (lk) { return hi.Count + lo.Count; } } }
    public int Pending { get { lock (lk) { return hi.Count + lo.Count + loading.Count + done.Count; } } }

    private void Run()
    {
        while (true)
        {
            Req r;
            lock (lk)
            {
                while (!stop && hi.Count == 0 && lo.Count == 0) Monitor.Wait(lk);
                if (stop) return;
                LinkedList<Req> src = hi.Count > 0 ? hi : lo;
                r = src.First.Value; src.RemoveFirst(); queued.Remove(r.Key); loading.Add(r.Key);
            }
            Res res = new Res(); res.Key = r.Key; res.Path = r.Path;
            try
            {
                if (!File.Exists(r.Path)) res.Missing = true;
                else res.Bmp = DecodeCached(r.Path, r.Size, r.Fit);
            }
            catch (Exception ex) { res.Error = ex.Message; res.Bmp = null; }
            lock (lk)
            {
                loading.Remove(r.Key);
                if (stop) { IDisposable d = res.Bmp as IDisposable; if (d != null) d.Dispose(); return; }
                done.Enqueue(res); doneKeys.Add(res.Key);
                if (res.Bmp != null) Loaded++; else Failed++;
            }
        }
    }
    public static string ThumbName(string fileName, int size, string fit, long len)
    {
        string k = (fileName ?? "").ToLowerInvariant() + "|" + size.ToString(CultureInfo.InvariantCulture) + "|" + (fit ?? "") + "|" + len.ToString(CultureInfo.InvariantCulture);
        ulong h = 14695981039346656037UL;
        for (int i = 0; i < k.Length; i++) { h ^= (ulong)k[i]; h *= 1099511628211UL; }
        return h.ToString("x16", CultureInfo.InvariantCulture) + ".png";
    }
    private static bool SameTime(DateTime a, DateTime b) { return Math.Abs((a - b).TotalSeconds) <= 2.5; }      // tolerância: FAT/exFAT arredondam a data
    private object DecodeCached(string path, int size, string fit)
    {
        long t0 = System.Diagnostics.Stopwatch.GetTimestamp();
        string dir = ThumbDir; string tp = null; DateTime srcTime = DateTime.MinValue; object bmp = null; bool hit = false;
        if (!string.IsNullOrEmpty(dir))
        {
            try
            {
                FileInfo fi = new FileInfo(path); srcTime = fi.LastWriteTimeUtc;
                tp = Path.Combine(dir, ThumbName(fi.Name, size, fit, fi.Length));
                FileInfo ti = new FileInfo(tp);
                if (ti.Exists && SameTime(ti.LastWriteTimeUtc, srcTime))
                {
                    try { bmp = ThumbLoad(tp, size); } catch (Exception) { bmp = null; }
                    if (bmp != null) hit = true; else Interlocked.Increment(ref ThumbLoadErr);
                }
            }
            catch (Exception) { tp = null; bmp = null; }
        }
        if (bmp == null)
        {
            bmp = Decode(path, size, fit);
            if (bmp != null && tp != null)
            {
                try { Directory.CreateDirectory(dir); ThumbSave(bmp, tp); Interlocked.Increment(ref ThumbSaved); }
                catch (Exception) { Interlocked.Increment(ref ThumbSaveErr); }
                try { if (File.Exists(tp)) File.SetLastWriteTimeUtc(tp, srcTime); } catch (Exception) { }
            }
        }
        long ms = (System.Diagnostics.Stopwatch.GetTimestamp() - t0) * 1000L / System.Diagnostics.Stopwatch.Frequency;
        lock (statLk)
        {
            DecodeN++;
            if (hit) { ThumbHits++; ThumbMs += ms; if (ms > ThumbMaxMs) ThumbMaxMs = ms; }
            else { ThumbMiss++; DecodeMs += ms; if (ms > DecodeMaxMs) DecodeMaxMs = ms; }
        }
        return bmp;
    }
    // Lê a miniatura (PNG já no tamanho final) para um Bitmap próprio. null se o arquivo estiver estranho (então usa o original).
    public static object LoadThumbGdi(string thumbPath, int size)
    {
        using (FileStream fs = new FileStream(thumbPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 65536))
        using (Image im = Image.FromStream(fs, false, false))
        {
            if (im.Width != size || im.Height != size) return null;
            Bitmap b = new Bitmap(size, size, PixelFormat.Format32bppPArgb);
            try
            {
                using (Graphics g = Graphics.FromImage(b))
                {
                    g.CompositingMode = CompositingMode.SourceCopy; g.InterpolationMode = InterpolationMode.NearestNeighbor; g.PixelOffsetMode = PixelOffsetMode.Half;
                    g.DrawImage(im, new Rectangle(0, 0, size, size), 0, 0, size, size, GraphicsUnit.Pixel);
                }
                return b;
            }
            catch { b.Dispose(); throw; }
        }
    }
    // Grava a miniatura (PNG) por arquivo temporário + troca, para nunca deixar um arquivo pela metade.
    public static void SaveThumbGdi(object bmp, string thumbPath)
    {
        Bitmap b = bmp as Bitmap; if (b == null) return;
        string tmp = thumbPath + "." + Thread.CurrentThread.ManagedThreadId.ToString(CultureInfo.InvariantCulture) + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(thumbPath));
            b.Save(tmp, ImageFormat.Png);
            if (File.Exists(thumbPath)) File.Delete(thumbPath);
            File.Move(tmp, thumbPath);
        }
        catch { try { if (File.Exists(tmp)) File.Delete(tmp); } catch (Exception) { } throw; }
    }
    // Decodifica e reduz para um quadrado size x size (mesmas regras de antes: Preencher, Ajustar, Esticar).
    public static object DecodeGdi(string path, int size, string fit)
    {
        using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 65536))
        using (Image src = Image.FromStream(fs, false, false))
        {
            Interlocked.Add(ref SrcPix, (long)src.Width * src.Height);
            Bitmap bmp = new Bitmap(size, size, PixelFormat.Format32bppPArgb);
            try
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.FromArgb(40, 40, 40));
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    float w = src.Width, h = src.Height;
                    if (fit == "Preencher")
                    {
                        float sd = Math.Min(w, h);
                        g.DrawImage(src, new RectangleF(0, 0, size, size), new RectangleF((w - sd) / 2f, (h - sd) / 2f, sd, sd), GraphicsUnit.Pixel);
                    }
                    else if (fit == "Ajustar")
                    {
                        float k = Math.Min(size / w, size / h); float dw = w * k, dh = h * k;
                        g.DrawImage(src, new RectangleF((size - dw) / 2f, (size - dh) / 2f, dw, dh), new RectangleF(0, 0, w, h), GraphicsUnit.Pixel);
                    }
                    else g.DrawImage(src, new RectangleF(0, 0, size, size), new RectangleF(0, 0, w, h), GraphicsUnit.Pixel);
                }
                return bmp;
            }
            catch { bmp.Dispose(); throw; }
        }
    }
    public void Dispose()
    {
        lock (lk)
        {
            stop = true; Monitor.PulseAll(lk);
            hi.Clear(); lo.Clear(); queued.Clear();
            while (done.Count > 0) { IDisposable d = done.Dequeue().Bmp as IDisposable; if (d != null) d.Dispose(); }
            doneKeys.Clear();
        }
    }
}

// Índice do catálogo para filtrar/buscar rápido. Montado só quando o catálogo muda; a busca não relê nenhum JSON.
public static class ViewIx
{
    // v2.52.0: assinatura da descrição (FNV-1a 64 bits), para perceber quando ela muda. Ignora \r e espaços nas pontas.
    // Devolve os índices cujo DescSig gravado é diferente do atual; newSigs recebe as assinaturas atuais de todos.
    public static int[] DescDiff(string[] descs, string[] oldSigs, out string[] newSigs)
    {
        int n = descs.Length; newSigs = new string[n]; List<int> chg = new List<int>();
        for (int i = 0; i < n; i++)
        {
            string s = (descs[i] ?? "").Replace("\r", "").Trim();
            ulong h = 14695981039346656037UL;
            for (int j = 0; j < s.Length; j++) { h ^= s[j]; h *= 1099511628211UL; }
            newSigs[i] = h.ToString("x16");
            if (!string.Equals(oldSigs[i], newSigs[i], StringComparison.Ordinal)) chg.Add(i);
        }
        return chg.ToArray();
    }
    // Ordem alfabética (mesma regra do Sort-Object: cultura atual, sem diferenciar maiúsculas)
    public static int[] SortOrder(string[] names)
    {
        int n = names.Length; int[] p = new int[n]; string[] k = new string[n];
        for (int i = 0; i < n; i++) { p[i] = i; k[i] = names[i] ?? ""; }
        Array.Sort(k, p, StringComparer.CurrentCultureIgnoreCase);
        return p;
    }
    public static object[] Reorder(object[] a, int[] p) { object[] r = new object[p.Length]; for (int i = 0; i < p.Length; i++) r[i] = a[p[i]]; return r; }
    public static string[] ReorderS(string[] a, int[] p) { string[] r = new string[p.Length]; for (int i = 0; i < p.Length; i++) r[i] = a[p[i]]; return r; }
    // "yyyy-MM-dd" -> ticks; -1 sem data ou data inválida
    public static long[] ParseDates(string[] s)
    {
        long[] r = new long[s.Length]; DateTime d;
        for (int i = 0; i < s.Length; i++)
            r[i] = (s[i] != null && DateTime.TryParseExact(s[i], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out d)) ? d.Ticks : -1;
        return r;
    }
    // key: 0 todos, 1 recentes, 2 favoritos, 3 instalados, 4 não instalados.
    // counts (5 posições) recebe as contagens de cada visão, que não dependem da busca.
    public static object[] Filter(object[] games, string[] ids, string[] names, long[] added, HashSet<string> fav, IDictionary inst,
                                  int key, string term, long cutoff, int[] counts, out string[] viewIds)
    {
        for (int i = 0; i < 5 && i < counts.Length; i++) counts[i] = 0;
        List<int> hit = new List<int>(games.Length);
        bool search = !string.IsNullOrEmpty(term);
        for (int i = 0; i < games.Length; i++)
        {
            string id = ids[i] ?? "";
            bool isFav = fav != null && fav.Contains(id);
            object iv = inst != null ? inst[id] : null;
            bool isIn = iv is bool ? (bool)iv : false;
            bool isRec = added[i] >= 0 && added[i] >= cutoff;
            counts[0]++; if (isFav) counts[2]++; if (isIn) counts[3]++; else counts[4]++; if (isRec) counts[1]++;
            if (search && (names[i] ?? "").IndexOf(term, StringComparison.OrdinalIgnoreCase) < 0) continue;
            bool ok = key == 2 ? isFav : key == 3 ? isIn : key == 4 ? !isIn : key == 1 ? isRec : true;
            if (ok) hit.Add(i);
        }
        if (key == 1)
        {
            // mais recentes primeiro; empate mantém a ordem alfabética (ordenação estável)
            int[] arr = hit.ToArray(); long[] ks = new long[arr.Length];
            for (int j = 0; j < arr.Length; j++) ks[j] = added[arr[j]];
            int[] pos = new int[arr.Length]; for (int j = 0; j < pos.Length; j++) pos[j] = j;
            Array.Sort(pos, delegate (int a, int b) { int c = ks[b].CompareTo(ks[a]); return c != 0 ? c : a.CompareTo(b); });
            List<int> h2 = new List<int>(arr.Length); for (int j = 0; j < pos.Length; j++) h2.Add(arr[pos[j]]);
            hit = h2;
        }
        object[] view = new object[hit.Count]; viewIds = new string[hit.Count];
        for (int j = 0; j < hit.Count; j++) { view[j] = games[hit[j]]; viewIds[j] = ids[hit[j]] ?? ""; }
        return view;
    }
    // Mantém só a seleção que continua na lista e acha a posição do jogo atual (-1 se saiu)
    public static HashSet<string> Keep(string[] viewIds, HashSet<string> sel, string curId, out int curIdx)
    {
        HashSet<string> keep = new HashSet<string>(StringComparer.Ordinal); curIdx = -1;
        bool any = sel != null && sel.Count > 0;
        for (int i = 0; i < viewIds.Length; i++)
        {
            if (any && sel.Contains(viewIds[i])) keep.Add(viewIds[i]);
            if (curIdx < 0 && curId != null && viewIds[i] == curId) curIdx = i;
        }
        return keep;
    }
}

// Desenho da grade de capas (v2.28.0). Faz em código compilado o que antes era um laço em PowerShell por capa a cada
// pintura (a rolagem redesenha a tela inteira dezenas de vezes por segundo). Mesmo resultado visual do PaintTile.
// Jogos com extração em andamento ou com o sinal de "extraído/falhou" (ExtIds) NÃO são desenhados aqui: o índice
// volta para o PowerShell, que desenha esses poucos com a animação de sempre.
public sealed class GridPainter
{
    // aparência (vem do RebuildGfx/Relayout)
    public Color Bg;
    public Brush Text, Sub, Dim, DimI, Ph, PhText;
    public Pen Sel, Hover;
    public Font NameFont, InitFont;
    public StringFormat Fmt, FmtC;
    public ImageAttributes Gray;
    public bool GrayNotInst, DimNotInst, SelBright;
    public int DimInstPct, SelW, SelGap, Contrast;
    public TextRenderingHint Hint = TextRenderingHint.ClearTypeGridFit;
    public string EmptyText = "";
    // geometria (GridMetrics)
    public int Cols = 1, Rows, CellW = 1, CellH = 1, TileW, OffX, PadY, SelExt, Cover = 1, NameH, NameGap, PrefetchRows = 2;
    public string Fit = "Preencher";
    public int Gen;
    // lista atual. Names/Paths: null = ainda não preenchido pelo PowerShell (NeedFill); Paths "" = jogo sem capa
    public string[] Ids = new string[0], Names = new string[0], Paths = new string[0];
    public int Count { get { return Ids.Length; } }
    // estado (referências lidas a cada pintura)
    public IDictionary Inst, InstState;
    public HashSet<string> SelIds, FavSet, ExtIds, Fail;
    public int HoverIdx = -1;
    public CoverLru Lru;
    public CoverLoader Loader;
    // resultado da última pintura completa
    public Dictionary<string, Rectangle> Vis = new Dictionary<string, Rectangle>(StringComparer.Ordinal);
    public int Keep;
    public bool NoRetain;      // tela de carregamento: não tirar da fila o que não está na tela
    public bool Wait;

    public void SetView(string[] ids)
    {
        int n = ids == null ? 0 : ids.Length;
        Ids = new string[n]; Names = new string[n]; Paths = new string[n];
        for (int i = 0; i < n; i++) Ids[i] = ids[i] ?? "";
        Vis.Clear();
    }
    public void ResetPaths() { for (int i = 0; i < Paths.Length; i++) { Paths[i] = null; Names[i] = null; } Vis.Clear(); }

    private void RowRange(int vOff, int viewH, out int r0, out int r1)
    {
        r0 = Math.Max(0, (int)Math.Floor((double)(vOff - PadY) / CellH));
        r1 = Math.Min(Rows - 1, (int)Math.Floor((double)(vOff + viewH - PadY) / CellH));
    }
    // Índices (tela + margem de antecipação) cujo nome/caminho da capa o PowerShell ainda precisa preencher
    public int[] NeedFill(int vOff, int viewH)
    {
        List<int> r = new List<int>(); int n = Count; if (n == 0 || Cols < 1) return r.ToArray();
        int r0, r1; RowRange(vOff, viewH, out r0, out r1);
        int p0 = Math.Max(0, r0 - PrefetchRows), p1 = Math.Min(Rows - 1, r1 + PrefetchRows);
        int a = p0 * Cols, b = Math.Min(n - 1, (p1 + 1) * Cols - 1);
        for (int i = a; i <= b; i++) if (Names[i] == null || Paths[i] == null) r.Add(i);
        return r.ToArray();
    }
    public int CountReady(string[] keys)
    {
        int n = 0;
        foreach (string k in keys) if ((Lru != null && Lru.Contains(k)) || (Fail != null && Fail.Contains(k))) n++;
        return n;
    }
    public string Key(string path) { return Gen.ToString(CultureInfo.InvariantCulture) + "|" + Cover.ToString(CultureInfo.InvariantCulture) + "|" + Fit + "|" + path; }
    private static bool IsTrue(IDictionary d, string id) { if (d == null) return false; object v = d[id]; return v is bool && (bool)v; }

    // Desenha a área pedida. Devolve os índices que o PowerShell deve desenhar (extração/sinal).
    public int[] Paint(Graphics g, int vOff, int viewW, int viewH)
    {
        List<int> special = new List<int>();
        Wait = false;
        g.Clear(Bg);
        g.TextRenderingHint = Hint; g.TextContrast = Contrast;
        int n = Count;
        if (n == 0)
        {
            if (NameFont != null) g.DrawString(EmptyText ?? "", NameFont, Sub, new RectangleF(0, 40, viewW, 40), FmtC);
            return special.ToArray();
        }
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        int r0, r1; RowRange(vOff, viewH, out r0, out r1);
        RectangleF clip = g.ClipBounds;
        bool full = clip.Width >= viewW && clip.Height >= viewH;
        bool anyExt = ExtIds != null && ExtIds.Count > 0;
        // Versões prontas (v2.39.1): capa sem cor e/ou escurecida é montada UMA vez e guardada no cache (VariantOf);
        // antes o filtro de cor (ColorMatrix) e o véu escuro eram refeitos pixel a pixel em toda pintura (rolagem pesada).
        string niTag = ((!GrayNotInst || Gray == null) ? "" : "g") + ((DimNotInst && Dim is SolidBrush) ? ((SolidBrush)Dim).Color.ToArgb().ToString(CultureInfo.InvariantCulture) : "");
        string inTag = (DimInstPct > 0 && DimI is SolidBrush) ? ((SolidBrush)DimI).Color.ToArgb().ToString(CultureInfo.InvariantCulture) : "";
        for (int r = r0; r <= r1; r++)
        {
            for (int col = 0; col < Cols; col++)
            {
                int i = r * Cols + col; if (i >= n) break;
                int x = OffX + col * CellW, y = PadY + r * CellH - vOff;
                if (!clip.IntersectsWith(new RectangleF(x, y, CellW, CellH))) continue;
                string id = Ids[i];
                if (anyExt && ExtIds.Contains(id)) { special.Add(i); continue; }
                int cx = x + SelExt, cy = y + SelExt;
                bool inst = IsTrue(Inst, id);
                Rectangle rect = new Rectangle(cx, cy, Cover, Cover);
                // --- capa ---
                Image bmp = null; string path = Paths[i]; string key = null;
                bool sel = SelIds != null && SelIds.Contains(id);
                bool bright = SelBright && sel;
                bool dimDone = false;
                if (!string.IsNullOrEmpty(path) && Lru != null)
                {
                    key = Key(path);
                    bmp = Lru.Get(key) as Image;
                    if (bmp == null && (Fail == null || !Fail.Contains(key)) && Loader != null) { Loader.Request(key, path, Cover, Fit, true); Wait = true; }
                }
                else if (path == null) Wait = true;      // ainda sem caminho: a próxima pintura pede
                if (bmp != null)
                {
                    bool wGray = !inst && GrayNotInst && Gray != null;
                    Brush wDim = bright ? null : (!inst ? (DimNotInst ? Dim : null) : (DimInstPct > 0 ? DimI : null));
                    if (wGray || wDim != null)
                    {
                        Image vb = null;
                        try { vb = VariantOf(key, bmp, wGray, wDim, (inst ? "I" + inTag : "N" + niTag) + (wDim == null ? "b" : "")); } catch (Exception) { vb = null; }
                        if (vb != null) { g.DrawImage(vb, rect); dimDone = wDim != null; }
                        else if (wGray) g.DrawImage(bmp, rect, 0, 0, bmp.Width, bmp.Height, GraphicsUnit.Pixel, Gray);
                        else g.DrawImage(bmp, rect);
                    }
                    else g.DrawImage(bmp, rect);
                }
                else
                {
                    g.FillRectangle(Ph, rect);
                    string nm = (Names[i] ?? "").Trim();
                    if (nm.Length > 0 && InitFont != null) g.DrawString(nm.Substring(0, 1).ToUpper(), InitFont, PhText, new RectangleF(cx, cy, Cover, Cover), FmtC);
                }
                if (!dimDone)
                {
                    if (!inst && DimNotInst) { if (!bright) g.FillRectangle(Dim, rect); }
                    else if (inst && DimInstPct > 0 && !bright) g.FillRectangle(DimI, rect);
                }
                if (InstState != null && (InstState[id] as string) == "offline")
                    g.FillEllipse(Sub, (float)(cx + Cover - 14), (float)(cy + 4), 10f, 10f);
                // --- borda de seleção / mouse em cima ---
                if (sel)
                {
                    if (SelW > 0)
                    {
                        float ext = SelGap + SelW / 2.0f;
                        g.DrawRectangle(Sel, cx - ext, cy - ext, Cover + 2 * ext, Cover + 2 * ext);
                    }
                }
                else if (i == HoverIdx)
                {
                    float ext = Math.Max(1, SelGap) + 0.5f;
                    g.DrawRectangle(Hover, cx - ext, cy - ext, Cover + 2 * ext, Cover + 2 * ext);
                }
                // --- nome embaixo ---
                if (NameH > 0 && NameFont != null)
                {
                    string txt = ((FavSet != null && FavSet.Contains(id)) ? "★ " : "") + (Names[i] ?? "");
                    RectangleF tr = new RectangleF(x, cy + Cover + SelExt + NameGap, TileW, NameH);
                    g.DrawString(txt, NameFont, inst ? Text : Sub, tr, Fmt);
                }
            }
        }
        if (full) Plan(r0, r1);
        return special.ToArray();
    }

    // Capa já sem cor e/ou escurecida, montada uma vez e guardada no mesmo cache das capas (chave "V|tag|chave da capa").
    // A tag muda junto com as opções (preto e branco, % de escurecimento), então mudar a opção gera versões novas.
    private Image VariantOf(string key, Image src, bool gray, Brush over, string tag)
    {
        if (key == null || Lru == null) return null;
        string vk = "V|" + tag + "|" + key;
        Image v = Lru.Get(vk) as Image; if (v != null) return v;
        int w = src.Width, h = src.Height;
        Bitmap b = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        using (Graphics vg = Graphics.FromImage(b))
        {
            vg.InterpolationMode = InterpolationMode.NearestNeighbor; vg.PixelOffsetMode = PixelOffsetMode.Half;
            if (gray && Gray != null) vg.DrawImage(src, new Rectangle(0, 0, w, h), 0, 0, w, h, GraphicsUnit.Pixel, Gray);
            else vg.DrawImage(src, new Rectangle(0, 0, w, h));
            if (over != null) vg.FillRectangle(over, 0, 0, w, h);
        }
        Lru.Put(vk, b, (long)w * h * 4, Keep);      // pode tirar do cache a capa original (já usada aqui); ela é recarregada se precisar
        return b;
    }

    // Depois de uma pintura completa: guarda onde está cada capa visível, pede a margem e tira da fila o que saiu da tela
    public void Plan(int r0, int r1)
    {
        if (Loader == null || Lru == null) return;
        int n = Count;
        int p0 = Math.Max(0, r0 - PrefetchRows), p1 = Math.Min(Rows - 1, r1 + PrefetchRows);
        HashSet<string> want = new HashSet<string>(StringComparer.Ordinal); Dictionary<string, Rectangle> vis = new Dictionary<string, Rectangle>(StringComparer.Ordinal); int kp = 0;
        for (int rr = p0; rr <= p1; rr++)
        {
            for (int cc = 0; cc < Cols; cc++)
            {
                int ii = rr * Cols + cc; if (ii >= n) break;
                string cp = Paths[ii]; if (string.IsNullOrEmpty(cp)) continue;
                string key = Key(cp); want.Add(key); kp++;
                if (rr >= r0 && rr <= r1)
                {
                    Rectangle rc = new Rectangle(OffX + cc * CellW, PadY + rr * CellH, CellW, CellH);
                    Rectangle prev;
                    if (vis.TryGetValue(key, out prev)) rc = Rectangle.Union(prev, rc);      // capa repetida em dois jogos
                    vis[key] = rc;
                }
                else if (!Lru.Contains(key) && (Fail == null || !Fail.Contains(key)))
                    Loader.Request(key, cp, Cover, Fit, false);
            }
        }
        if (!NoRetain) Loader.Retain(want);
        Vis = vis; Keep = kp;
    }

    // Recolhe as capas prontas (até "ms" milissegundos). Devolve os retângulos (na tela) a redesenhar;
    // as falhas vão para "fails" (o PowerShell registra o aviso uma vez por arquivo).
    public Rectangle[] Drain(int vOff, int ms, List<CoverLoader.Res> fails)
    {
        List<Rectangle> inv = new List<Rectangle>();
        if (Loader == null || Lru == null) return inv.ToArray();
        string pre = Gen.ToString(CultureInfo.InvariantCulture) + "|";
        System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < ms)
        {
            CoverLoader.Res rs = Loader.Take(); if (rs == null) break;
            if (rs.Bmp != null)
            {
                Image im = rs.Bmp as Image;
                if (im != null && rs.Key != null && rs.Key.StartsWith(pre, StringComparison.Ordinal))
                {
                    Lru.Put(rs.Key, im, (long)im.Width * im.Height * 4, Keep);
                    Rectangle rc;
                    if (Vis.TryGetValue(rs.Key, out rc)) inv.Add(new Rectangle(rc.X, rc.Y - vOff, rc.Width, rc.Height));
                }
                else { IDisposable d = rs.Bmp as IDisposable; if (d != null) d.Dispose(); }      // pedido de antes de uma limpeza
            }
            else
            {
                if (Fail != null && rs.Key != null) Fail.Add(rs.Key);
                if (fails != null) fails.Add(rs);
            }
        }
        return inv.ToArray();
    }
}

// Números do processo para o diagnóstico (memória e objetos gráficos do Windows)
public static class Perf
{
    [DllImport("user32.dll")] private static extern int GetGuiResources(IntPtr proc, int flags);
    public static int Gdi() { try { return GetGuiResources(System.Diagnostics.Process.GetCurrentProcess().Handle, 0); } catch (Exception) { return -1; } }
    public static int User() { try { return GetGuiResources(System.Diagnostics.Process.GetCurrentProcess().Handle, 1); } catch (Exception) { return -1; } }
}
'@
# Barra de tarefas: ícone grande da janela, AppUserModelID e "Relaunch" (como o Windows reabre o launcher fixado na barra)
$TaskSrc = @'
using System; using System.Runtime.InteropServices;
public static class ArqTask {
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore { int GetCount(out uint c); int GetAt(uint i, out PKey k); int GetValue(ref PKey k, out PVar v); int SetValue(ref PKey k, ref PVar v); int Commit(); }
    [StructLayout(LayoutKind.Sequential, Pack = 4)] struct PKey { public Guid fmtid; public uint pid; }
    [StructLayout(LayoutKind.Explicit, Size = 24)] struct PVar { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }
    [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, out IPropertyStore ps);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    // Só o ícone GRANDE (ICON_BIG = 1): é o que a barra de tarefas e o Alt+Tab usam. O pequeno (ICON_SMALL) não é enviado,
    // porque é ele que aparece no canto superior esquerdo da janela; com ShowIcon = false a barra de título fica sem ícone.
    public static void SetBigIcon(IntPtr hwnd, IntPtr big) { SendMessage(hwnd, 0x80, new IntPtr(1), big); }
    public static void AppId(string id) { SetCurrentProcessExplicitAppUserModelID(id); }
    static void Put(IPropertyStore ps, uint pid, string text) {
        PKey k = new PKey(); k.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); k.pid = pid;
        PVar v = new PVar(); v.vt = 31; v.p = Marshal.StringToCoTaskMemUni(text);
        ps.SetValue(ref k, ref v);
    }
    public static void Window(IntPtr hwnd, string id, string cmd, string name, string icon) {
        Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"); IPropertyStore ps;
        if (SHGetPropertyStoreForWindow(hwnd, ref iid, out ps) != 0 || ps == null) return;
        // o ID por ÚLTIMO: o Windows lê os "Relaunch" quando o ID muda
        try { Put(ps, 2, cmd); Put(ps, 4, name); Put(ps, 3, icon); Put(ps, 5, id); ps.Commit(); } finally { Marshal.ReleaseComObject(ps); }
    }
}
'@
# ---- Componentes em C#: compilados UMA vez para TarginoRetroStation\Cache\Compilado\Nucleo_<hash>.dll ----
#  Nas aberturas seguintes a DLL é só carregada (sem compilar). O <hash> vem do código-fonte: nova versão do launcher = compila de novo
#  e apaga a DLL antiga. A compilação usa uma pasta temporária DENTRO de TarginoRetroStation\Cache (nada vai para a pasta Temp do Windows, no C:).
#  A DLL é lida para a memória (o arquivo não fica preso e não depende da marca "baixado da internet").
#  Sem esses componentes o launcher não abre: o erro exato vai para o log e aparece numa mensagem.
# Dica dentro da caixa de busca ("Pesquisar jogos..."), some ao digitar (v2.50.0)
$HdrSrc = @'
using System;
using System.Runtime.InteropServices;
public static class CaCue
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessageW(IntPtr h, int msg, IntPtr w, string l);
    public static void Set(IntPtr h, string text) { SendMessageW(h, 0x1501, new IntPtr(1), text ?? ""); }      // EM_SETCUEBANNER (mostra também com foco)
}
'@
$musicSourcePath=Join-Path $Arq 'TarginoMusic.cs'
$musicSource=if([IO.File]::Exists($musicSourcePath)){[IO.File]::ReadAllText($musicSourcePath,[Text.Encoding]::UTF8)}else{''}
$CsSrcs = [string[]]@($UiSrc, $CoreSrc, $script:GpSrc, $script:UbSrc, $TaskSrc, $HdrSrc, $musicSource)
function CoreLoad {
    $cdir = [IO.Path]::Combine((ArqDir 'Cache'), 'Compilado'); [void][IO.Directory]::CreateDirectory($cdir)
    $dll = [IO.Path]::Combine($cdir, 'Nucleo_' + (Hash (($CsSrcs -join "`n") + "|$([Environment]::Version)")).Substring(0, 16) + '.dll')
    if ([IO.File]::Exists($dll)) {
        try { [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll)); return 'carregados do cache' }
        catch { LogEx 'AVISO' "DLL dos componentes não pôde ser carregada; compilando de novo: $($_.Exception.Message)" $_; try { [IO.File]::Delete($dll) } catch { $Error.Clear() } }
    }
    $ctmp = [IO.Path]::Combine((ArqDir 'Cache'), 'Temp'); [void][IO.Directory]::CreateDirectory($ctmp)
    $oldTmp = $env:TMP; $oldTemp = $env:TEMP; $env:TMP = $ctmp; $env:TEMP = $ctmp      # o compilador do .NET também usa a pasta temporária
    try {
        $prov = New-Object Microsoft.CSharp.CSharpCodeProvider
        $par = New-Object System.CodeDom.Compiler.CompilerParameters
        $par.ReferencedAssemblies.AddRange([string[]]@('System.dll', 'System.Core.dll', 'System.Drawing.dll', 'System.Windows.Forms.dll'))
        $par.GenerateInMemory = $false; $par.OutputAssembly = $dll; $par.CompilerOptions = '/optimize+'
        $par.TempFiles = New-Object System.CodeDom.Compiler.TempFileCollection($ctmp, $false)
        $cres = $prov.CompileAssemblyFromSource($par, $CsSrcs)
        $cerr = @($cres.Errors | Where-Object { -not $_.IsWarning })
        if ($cerr.Count) {
            try { if ([IO.File]::Exists($dll)) { [IO.File]::Delete($dll) } } catch { $Error.Clear() }
            throw ('os componentes em C# não compilaram: ' + ((@($cerr | Select-Object -First 3) | ForEach-Object { "$($_.ErrorText) (linha $($_.Line))" }) -join ' | '))
        }
        $prov.Dispose()
    } finally {
        $env:TMP = $oldTmp; $env:TEMP = $oldTemp
        try { [IO.Directory]::Delete($ctmp, $true) } catch { $Error.Clear() }
    }
    foreach ($od in [IO.Directory]::GetFiles($cdir, 'Nucleo_*.dll')) { if ($od -ine $dll) { try { [IO.File]::Delete($od) } catch { $Error.Clear() } } }
    [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
    'compilados'
}
$swc = [Diagnostics.Stopwatch]::StartNew()
$coreHow = CoreLoad
$script:CompileMs = $swc.ElapsedMilliseconds
# v2.47.0: desbloqueia os arquivos do próprio launcher (marca de "baixado da internet"): o .exe e os .bat/.cmd da raiz, os .ps1 de
#  TarginoRetroStation\ e tudo em TarginoRetroStation\Ferramentas\ (UnRAR, instaladores das dependências...). Assim o Windows reclama no máximo na
#  1ª abertura (a do .exe, que acontece antes de qualquer código nosso rodar) e nunca mais. Jogos\ fica de fora (é desbloqueado ao jogar).
#  Arquivo já desbloqueado é só pulado; falha nunca impede o launcher de abrir.
function UnblockSelf {
    $usSw = [Diagnostics.Stopwatch]::StartNew(); $usClear = 0; $usBad = 0; $usLast = ''
    $usTop = @()
    foreach ($usPat in '*.exe', '*.bat', '*.cmd') { $usTop += @([IO.Directory]::GetFiles($Root, $usPat)) }
    $usTop += @([IO.Directory]::GetFiles($Arq, '*.ps1'))
    foreach ($usF in $usTop) {
        try { if (Get-Item -LiteralPath $usF -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) { Unblock-File -LiteralPath $usF -ErrorAction Stop; $usClear++ } }
        catch { $usBad++; $usLast = "$usF ($($_.Exception.Message))" }
    }
    $Error.Clear()
    $usTools = ArqDir 'Ferramentas'
    if ([IO.Directory]::Exists($usTools)) {
        try {
            [CaUnblock]::Run($usTools, [string[]]@('.exe', '.bat', '.cmd', '.ps1'))
            $usClear += [CaUnblock]::Cleared; $usBad += [CaUnblock]::Failed; if ([CaUnblock]::LastError) { $usLast = [CaUnblock]::LastError }
        } catch { $usBad++; $usLast = $_.Exception.Message; $Error.Clear() }
    }
    if ($usClear) { Log 'INFO' "Desbloqueio do launcher: $usClear arquivo(s) liberado(s) em $($usSw.ElapsedMilliseconds) ms" }
    if ($usBad) { Log 'AVISO' "Desbloqueio do launcher: $usBad falha(s); última: $usLast" }
}
try { UnblockSelf } catch { LogEx 'AVISO' "Desbloqueio do launcher falhou: $($_.Exception.Message)" $_ }
$script:Lru = New-Object CoverLru; $script:Loader = New-Object CoverLoader -ArgumentList ([int](CfgNum 'CoverThreads' 1 4 2))
if ([bool]$S.ThumbCache) { $script:Loader.ThumbDir = [IO.Path]::Combine((ArqDir 'Cache'), 'Miniaturas') }      # sempre dentro da pasta do launcher
$script:Painter = New-Object GridPainter; $script:Painter.Lru = $script:Lru; $script:Painter.Loader = $script:Loader; $script:Painter.Fail = $script:CoverFail
$script:PtGx = $null; $script:PtMet = $null; $script:PtCfg = $null; $script:PtView = $null; $script:PtImgGen = -1
Log 'INFO' "Componentes em C# $coreHow em $script:CompileMs ms"

$bg = [Drawing.Color]::FromArgb(11, 11, 11); $dk = [Drawing.Color]::FromArgb(28, 28, 28)
# Ícone próprio na barra de tarefas: TarginoRetroStation\Launcher.ico (ou o ícone embutido no executável do launcher).
# O AppUserModelID separa este programa do PowerShell na barra; os valores "Relaunch" dizem ao Windows como REABRIR o launcher quando a
# pessoa fixa a janela na barra de tarefas: pelo executável do launcher (sem ele não há o que fixar, então nada é definido).
$IcoFile = [IO.Path]::Combine($Arq, 'Launcher.ico'); $script:LauncherExe = LauncherExe
# ID por pasta (hash do caminho): cada cópia do launcher (H:, G:, outra pasta) tem o seu botão e o seu atalho fixado.
$md5 = [Security.Cryptography.MD5]::Create()
try { $script:TaskId = 'TarginoRetroStation.Launcher.' + (-join ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') })) } finally { $md5.Dispose() }
$form = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = 'Launcher'; Size = '1280,760'; StartPosition = 'CenterScreen'; BackColor = $bg; ForeColor = 'White'; KeyPreview = $true; Font = (New-Object Drawing.Font('Segoe UI', 9)) }
# ShowIcon fica desligado: nada de ícone na barra de título. A barra de tarefas recebe:
#  (1) o ícone GRANDE da janela (WM_SETICON ICON_BIG, sem o pequeno, que é o do canto superior esquerdo);
#  (2) AppUserModelID + "Relaunch": ao fixar na barra, o Windows guarda o EXECUTÁVEL do launcher (mesmo renomeado) e o ícone dele.
if ($script:LauncherExe -or [IO.File]::Exists($IcoFile)) {
    $script:TaskIcon = $null
    try {
        # .ico primeiro (tem vários tamanhos: pega o certo para a escala da tela); sem ele, o ícone embutido no .exe
        if ([IO.File]::Exists($IcoFile)) { $script:TaskIcon = New-Object Drawing.Icon($IcoFile, [Windows.Forms.SystemInformation]::IconSize) }
        else { $script:TaskIcon = [Drawing.Icon]::ExtractAssociatedIcon($script:LauncherExe) }
    } catch { $Error.Clear() }
    $form.Add_HandleCreated({
        try {
            if ($script:TaskIcon) { [ArqTask]::SetBigIcon($form.Handle, $script:TaskIcon.Handle) }
            if ($script:HydraNavigationEnabled) {
                $powershellPath=Join-Path $PSHOME 'powershell.exe'
                $rc="`"$powershellPath`" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:SelfPath`""
                $ri="$IcoFile,0"
            } else {
                $rc = "`"$($script:LauncherExe)`""; $ri = "$($script:LauncherExe),0"
            }
            [ArqTask]::Window($form.Handle, $script:TaskId, $rc, 'TarginoRetroStation', $ri)
            [ArqTask]::AppId($script:TaskId)   # o do processo (outras janelas do launcher) só DEPOIS da janela principal estar pronta
            Log 'INFO' "Barra de tarefas: ID $($script:TaskId), reabrir por $rc (ícone: $ri)"
        } catch { LogEx 'AVISO' "Barra de tarefas: não foi possível definir o ícone/comando de reabrir ($($_.Exception.Message))" $_ }
    })
}
$mainP = New-Object Windows.Forms.Panel -Property @{ Dock = 'Fill'; BackColor = $bg }
$libP  = New-Object Windows.Forms.Panel -Property @{ Dock = 'Fill'; BackColor = $bg }
$grid  = New-Object Windows.Forms.Panel -Property @{ Dock = 'Fill'; BackColor = $bg; TabStop = $true }
$vsb = New-Object DarkScroll -Property @{ Dock = 'Right'; Width = 12; Minimum = 0; Maximum = 100; LargeChange = 10; SmallChange = 20 }
SetStyles $grid
$libP.Controls.Add($grid); $libP.Controls.Add($vsb)
$right = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock = 'Right'; Width = 400; BackColor = $bg; FlowDirection = 'TopDown'; WrapContents = $false; Padding = '15,15,5,5' }
$bot = New-Object Windows.Forms.Panel -Property @{ Dock = 'Bottom'; Height = 32 }
$top = New-Object Windows.Forms.Panel -Property @{ Dock = 'Top'; Height = 44 }      # v2.51.0: posição de cada item escolhida na aba Topo (TopCenter)
$mainP.Controls.AddRange(@($libP, $right, $bot, $top))
$hdr = New-Object Windows.Forms.Panel -Property @{ Dock = 'Top'; Height = 48; BackColor = $bg }      # nome do launcher com brilho (v2.50.0)
$hdMi = [Windows.Forms.Control].GetMethod('SetStyle', [Reflection.BindingFlags]'Instance,NonPublic')      # sem flicker (e sem roubar o foco da grade)
foreach ($hdSt in 'UserPaint', 'AllPaintingInWmPaint', 'OptimizedDoubleBuffer', 'ResizeRedraw') { [void]$hdMi.Invoke($hdr, @([Windows.Forms.ControlStyles]$hdSt, $true)) }
$mainP.Controls.Add($hdr)      # adicionado por último = fica acima da barra de busca
$form.Controls.Add($mainP)
# Camada visual opcional: a pessoa escolhe as imagens no painel Personalizar.
$script:BackgroundPic = New-Object Windows.Forms.PictureBox -Property @{ Dock = 'Fill'; Height = 280; SizeMode = 'Zoom'; BackColor = $bg; TabStop = $false }
$script:AvatarPic = New-Object Windows.Forms.PictureBox -Property @{ Size = '84,84'; SizeMode = 'Zoom'; BackColor = [Drawing.Color]::Transparent; TabStop = $false; Left = 14; Top = 14 }
$mainP.Controls.Add($script:BackgroundPic)
$script:BackgroundPic.Controls.Add($script:AvatarPic)
$script:AvatarPic.BringToFront()
function ApplyBranding {
    try {
        if ($script:BackgroundPic) {
            $oldImage = $script:BackgroundPic.Image; $script:BackgroundPic.Image = $null
            if ($oldImage) { $oldImage.Dispose() }
            $bp = "$($S.BackgroundImage)".Trim()
            if ($bp -and [IO.File]::Exists($bp)) {
                $sourceImage = [Drawing.Image]::FromFile($bp)
                try { $script:BackgroundPic.Image = New-Object Drawing.Bitmap($sourceImage) } finally { $sourceImage.Dispose() }
            }
            $script:BackgroundPic.Visible = [bool]($script:BackgroundPic.Image -or "$($S.AvatarImage)".Trim())
        }
        if ($script:AvatarPic) {
            $oldImage = $script:AvatarPic.Image; $script:AvatarPic.Image = $null
            if ($oldImage) { $oldImage.Dispose() }
            $ap = "$($S.AvatarImage)".Trim()
            if ($ap -and [IO.File]::Exists($ap)) {
                $sourceImage = [Drawing.Image]::FromFile($ap)
                try { $script:AvatarPic.Image = New-Object Drawing.Bitmap($sourceImage) } finally { $sourceImage.Dispose() }
            }
            $script:AvatarPic.Visible = [bool]$script:AvatarPic.Image
        }
    } catch { LogEx 'AVISO' 'Personalização visual: imagem inválida ou inacessível' $_ }
}
ApplyBranding
$script:HeroTitle = New-Object Windows.Forms.Label -Property @{ AutoSize = $false; Height = 60; Dock = 'Bottom'; ForeColor = [Drawing.Color]::White; BackColor = [Drawing.Color]::FromArgb(18,18,24); Font = (New-Object Drawing.Font('Segoe UI',20,[Drawing.FontStyle]::Bold)); TextAlign = 'MiddleCenter'; Text = 'Targino RetroStation' }
$script:BackgroundPic.Controls.Add($script:HeroTitle)
$script:CinemaActions = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock='Bottom'; Height=46; FlowDirection='LeftToRight'; WrapContents=$false; BackColor=[Drawing.Color]::FromArgb(12,16,24); Padding='16,4,0,0' }
$script:CinemaPlay = New-Object Windows.Forms.Button -Property @{ Text='▶  Jogar'; Width=130; Height=34; FlatStyle='Flat'; BackColor=[Drawing.Color]::FromArgb(0,116,190); ForeColor=[Drawing.Color]::White; TabStop=$false }
$script:CinemaDetails = New-Object Windows.Forms.Button -Property @{ Text='Detalhes (D)'; Width=130; Height=34; FlatStyle='Flat'; BackColor=[Drawing.Color]::FromArgb(24,30,40); ForeColor=[Drawing.Color]::White; TabStop=$false }
$script:CinemaActions.Controls.AddRange(@($script:CinemaPlay,$script:CinemaDetails))
$script:BackgroundPic.Controls.Add($script:CinemaActions)
$script:CinemaPlay.Add_Click({ $gm=Sel; if ($gm) { Launch $gm } })
$script:CinemaDetails.Add_Click({ ShowCinemaDetails })
$form.Add_KeyDown({ param($sender,$eventArgs)
    if ($S.CinemaMode -and $grid.Focused -and $eventArgs.KeyCode -eq 'D' -and -not $eventArgs.Control -and -not $eventArgs.Alt) {
        $eventArgs.SuppressKeyPress=$true; $eventArgs.Handled=$true; ShowCinemaDetails
    }
})
function ShowCinemaDetails {
    $gm=Sel; if (-not $gm) { return }
    if($gm.HydraKind -ne 'system' -and (Get-Command ShowHydraDetails -ErrorAction SilentlyContinue)){ShowHydraDetails $gm;return}
    $dlg=New-Object Windows.Forms.Form -Property @{ Text="Detalhes — $($gm.Name)"; StartPosition='CenterParent'; Size='760,700'; MinimumSize='520,420'; BackColor=[Drawing.Color]::FromArgb(12,16,24); ForeColor=[Drawing.Color]::White; ShowIcon=$false; KeyPreview=$true }
    $footer=New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock='Bottom'; Height=50; Padding='10,8,0,0' }
    $play=New-Object Windows.Forms.Button -Property @{ Text='Jogar'; Width=120; Height=32; DialogResult='OK' }
    $close=New-Object Windows.Forms.Button -Property @{ Text='Fechar'; Width=120; Height=32; DialogResult='Cancel' }
    $footer.Controls.AddRange(@($play,$close)); $dlg.CancelButton=$close
    $dlg.AcceptButton=$play
    $result='Cancel'; $oldDock=$right.Dock; $oldScroll=$right.AutoScroll
    try {
        $right.Parent=$dlg; $right.Dock='Fill'; $right.AutoScroll=$true; $right.Visible=$true
        $dlg.Controls.Add($footer); $right.BringToFront()
        ShowGame $gm
        $result=$dlg.ShowDialog($form)
    } finally {
        $right.Visible=$false; $right.Parent=$mainP; $right.Dock=$oldDock; $right.AutoScroll=$oldScroll
        $script:BackgroundPic.Parent.Controls.SetChildIndex($script:BackgroundPic,0)
        $dlg.Dispose(); [void]$grid.Focus()
    }
    if ($result -eq 'OK') { Launch $gm }
}
$script:BackgroundPic.Add_Resize({
    $im = $script:BackgroundPic.Image
    if ($im -and $S.CinemaMode) {
        $script:BackgroundPic.Invalidate()
    }
})
$script:BackgroundPic.Add_Paint({ param($sender,$e)
    if ($S.CinemaMode) { DrawCinemaScene $e.Graphics $sender; return }
    $im = $sender.Image
    if (-not $im -or -not $S.CinemaMode -or $sender.Width -le 0 -or $sender.Height -le 0) { return }
    $scale = [Math]::Max($sender.Width/[double]$im.Width,$sender.Height/[double]$im.Height)
    $w = [single]($im.Width*$scale); $h = [single]($im.Height*$scale)
    $rect = New-Object Drawing.RectangleF(([single](($sender.Width-$w)/2)),([single](($sender.Height-$h)/2)),$w,$h)
    $e.Graphics.DrawImage($im,$rect)
})
function SearchKeyboardMove([int]$direction) {
    $win=$script:SearchWindow; if (-not $win -or $win.IsDisposed) { return }
    $state=$win.Tag; $index=[int]$state.Index
    if ($direction -band 1) { $index-- } elseif ($direction -band 2) { $index++ }
    elseif ($direction -band 4) { $index-=10 } elseif ($direction -band 8) { $index+=10 }
    $state.Index=[Math]::Max(0,[Math]::Min($state.Keys.Count-1,$index))
    [void]$state.Keys[$state.Index].Focus()
}
function ShowSearchDialog {
    $fm.Close(); $cm.Close(); $addm.Close()
    $win=New-Object Windows.Forms.Form -Property @{ Text='Buscar jogos'; StartPosition='CenterParent'; ClientSize='670,370'; FormBorderStyle='FixedDialog'; MaximizeBox=$false; MinimizeBox=$false; ShowIcon=$false; KeyPreview=$true; BackColor=[Drawing.Color]::FromArgb(15,20,30); ForeColor=[Drawing.Color]::White }
    $inputBox=New-Object Windows.Forms.TextBox -Property @{ Left=18; Top=18; Width=634; Text=$q.Text }
    $help=New-Object Windows.Forms.Label -Property @{ Left=18; Top=50; Width=634; Height=36; Text='Direcional: escolher tecla   •   A: pressionar   •   Start: buscar   •   B: cancelar. Também aceita teclado.' }
    $win.Controls.AddRange(@($inputBox,$help))
    $keys=New-Object System.Collections.ArrayList
    $values=@('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z','0','1','2','3','4','5','6','7','8','9','Espaço','⌫','Limpar','Buscar','Fechar')
    for($index=0;$index -lt $values.Count;$index++) {
        $button=New-Object Windows.Forms.Button -Property @{ Text=$values[$index]; Left=(18+($index%10)*64); Top=(92+[int][Math]::Floor($index/10)*48); Width=58; Height=40; FlatStyle='Flat'; BackColor=[Drawing.Color]::FromArgb(29,40,56); ForeColor=[Drawing.Color]::White; Tag=$values[$index] }
        $button.Add_PreviewKeyDown({param($sender,$eventArgs) if($eventArgs.KeyCode -in 'Left','Right','Up','Down'){$eventArgs.IsInputKey=$true}})
        $button.Add_Click({param($sender,$eventArgs)
            $dlg=$sender.FindForm();$box=$dlg.Tag.Input
            switch($sender.Tag) {
                'Espaço' { $box.AppendText(' ') }
                '⌫' { if($box.TextLength -gt 0){$box.Text=$box.Text.Substring(0,$box.TextLength-1)} }
                'Limpar' { $box.Clear() }
                'Buscar' { $dlg.DialogResult='OK' }
                'Fechar' { $dlg.DialogResult='Cancel' }
                default { $box.AppendText([string]$sender.Tag) }
            }
        })
        $button.Add_GotFocus({param($sender,$eventArgs) $dlg=$sender.FindForm();if($dlg.Tag){$dlg.Tag.Index=$dlg.Tag.Keys.IndexOf($sender)}})
        [void]$keys.Add($button);$win.Controls.Add($button)
    }
    $win.Tag=@{Input=$inputBox;Keys=$keys;Index=0}
    $win.Add_KeyDown({param($sender,$eventArgs)
        if($eventArgs.KeyCode -eq 'Escape'){$sender.DialogResult='Cancel';$eventArgs.SuppressKeyPress=$true}
        elseif($eventArgs.KeyCode -eq 'Return'){$sender.DialogResult='OK';$eventArgs.SuppressKeyPress=$true}
        elseif($sender.ActiveControl -is [Windows.Forms.Button]) {
            $dir=switch($eventArgs.KeyCode){'Left'{1};'Right'{2};'Up'{4};'Down'{8};default{0}}
            if($dir){SearchKeyboardMove $dir;$eventArgs.SuppressKeyPress=$true}
        }
    })
    $win.Add_KeyPress({param($sender,$eventArgs)
        if($sender.ActiveControl -is [Windows.Forms.Button] -and [char]::IsLetterOrDigit($eventArgs.KeyChar)) {$sender.Tag.Input.AppendText([string]$eventArgs.KeyChar);$eventArgs.Handled=$true}
    })
    $win.Add_Shown({param($sender,$eventArgs) [void]$sender.Tag.Keys[0].Focus()})
    $script:SearchWindow=$win
    try { if($win.ShowDialog($form) -eq 'OK') { $q.Text=$inputBox.Text; Populate } }
    finally { $script:SearchWindow=$null; $win.Dispose(); [void]$grid.Focus() }
}
function DrawCinemaScene($gr,$control) {
    $im = $script:BackgroundPic.Image
    $origin = $mainP.PointToClient($control.PointToScreen([Drawing.Point]::Empty))
    $w = [Math]::Max(1,$mainP.ClientSize.Width); $h = [Math]::Max(1,$mainP.ClientSize.Height)
    $cached = $script:CinemaScene
    if (-not $cached -or $cached.Width -ne $w -or $cached.Height -ne $h -or -not [object]::ReferenceEquals($script:CinemaSceneSource,$im)) {
        if ($cached) { $cached.Dispose() }
        $script:CinemaScene = New-Object Drawing.Bitmap($w,$h,([Drawing.Imaging.PixelFormat]::Format32bppPArgb))
        $bgGraphics = [Drawing.Graphics]::FromImage($script:CinemaScene)
        try {
            $bgGraphics.Clear([Drawing.Color]::FromArgb(9,12,19))
            if ($im) {
                $scale = [Math]::Max($w/[double]$im.Width,$h/[double]$im.Height)
                $iw = [single]($im.Width*$scale); $ih = [single]($im.Height*$scale)
                $dest = New-Object Drawing.RectangleF(([single](($w-$iw)/2)),([single](($h-$ih)/2)),$iw,$ih)
                $bgGraphics.DrawImage($im,$dest)
            }
            $area = New-Object Drawing.Rectangle(0,0,$w,$h)
            $shade = New-Object Drawing.Drawing2D.LinearGradientBrush($area,([Drawing.Color]::FromArgb(95,4,8,16)),([Drawing.Color]::FromArgb(242,4,8,16)),([single]90))
            try { $bgGraphics.FillRectangle($shade,$area) } finally { $shade.Dispose() }
        } finally { $bgGraphics.Dispose() }
        $script:CinemaSceneSource = $im
    }
    # Copia apenas o trecho visível. Fundo e degradê são calculados uma vez por tamanho/imagem.
    $region = New-Object Drawing.Rectangle($origin.X,$origin.Y,$control.ClientSize.Width,$control.ClientSize.Height)
    $gr.DrawImage($script:CinemaScene,0,0,$region,[Drawing.GraphicsUnit]::Pixel)
}
$script:HeroTitle.Add_Paint({ param($sender,$e)
    if ($S.CinemaMode) {
        DrawCinemaScene $e.Graphics $sender
        [Windows.Forms.TextRenderer]::DrawText($e.Graphics,$sender.Text,$sender.Font,$sender.ClientRectangle,$sender.ForeColor,([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,EndEllipsis,SingleLine,NoPrefix'))
    }
})
$mainP.Add_Resize({ if ($S.CinemaMode) { $mainP.Invalidate($true) } })

$q = Mk Windows.Forms.TextBox @{ Width = 280; BackColor = $dk; ForeColor = 'White'; BorderStyle = 'FixedSingle'; Margin = '0,0,14,0' } $top
$btnFil = Mk Windows.Forms.Button @{ Text = 'Biblioteca  ▾'; Width = 170; Height = 24; FlatStyle = 'Flat'; ForeColor = 'White'; BackColor = $dk; TextAlign = 'MiddleCenter'; Padding = '0,0,0,0'; Margin = '0,0,14,0'; TabStop = $false } $top
$btnAdd = Mk Windows.Forms.Button @{ Text = '+ Adicionar  ▾'; Width = 120; Height = 24; FlatStyle = 'Flat'; ForeColor = 'White'; BackColor = $dk; Visible = $false; Margin = '10,0,0,0' } $top
$btnDev = Mk Windows.Forms.Button @{ Text = 'Personalizar'; Width = 100; Height = 24; FlatStyle = 'Flat'; ForeColor = 'White'; BackColor = $dk; Visible = $false; Margin = '8,0,0,0' } $top
# ---- Posição dos itens do topo (v2.51.0, aba Topo do modo dev) ----
#  Cada item (nome, busca, filtros) tem: área de referência (área dos jogos = sem o painel de detalhes, ou janela inteira),
#  alinhamento (esquerda / centro / direita) e um deslocamento em px (negativo = para a esquerda). Com "busca e filtros juntos",
#  os dois andam como um bloco só, pelas opções da busca. Recalculado ao redimensionar a janela ou o painel de detalhes.
function TopArea($area) {      # @(x inicial, largura) da área escolhida
    $tw = $top.ClientSize.Width
    if ("$area" -eq 'Janela inteira' -or $libP.Width -le 0 -or $libP.Width -ge $tw) { return @(0, $tw) }
    @(0, $libP.Width)
}
function TopPlaceX($w, $area, $align, $off, $limit) {      # x do item, sem sair da janela
    $ar = TopArea $area
    $x = switch ("$align") { 'Esquerda' { $ar[0] + 14 } 'Direita' { $ar[0] + $ar[1] - $w - 14 } default { $ar[0] + [Math]::Round(($ar[1] - $w) / 2.0) } }
    $x += [int]$off
    [int][Math]::Max(0, [Math]::Min($x, $limit - $w))
}
function TopCenter {
    if (-not $top.IsHandleCreated -or -not $top.Visible) { return }
    $c = $script:Cfg; if (-not $c) { return }
    $tw = $top.ClientSize.Width; $gap = 14; $y = 9
    $qOn = [bool]$q.Visible; $fOn = [bool]$btnFil.Visible
    $script:TopLineCx = $null
    if ($c.TopJoin -or -not ($qOn -and $fOn)) {      # bloco único (ou só um dos dois visível): segue as opções da busca (ou dos filtros, se a busca estiver escondida)
        $bw = $(if ($qOn) { $q.Width } else { 0 }) + $(if ($qOn -and $fOn) { $gap } else { 0 }) + $(if ($fOn) { $btnFil.Width } else { 0 })
        if ($qOn) { $bx = TopPlaceX $bw $c.SearchArea $c.SearchAlign $c.SearchOffX $tw } else { $bx = TopPlaceX $bw $c.FilterArea $c.FilterAlign $c.FilterOffX $tw }
        if ($qOn) { $q.Location = New-Object Drawing.Point($bx, $y) }
        if ($fOn) { $btnFil.Location = New-Object Drawing.Point(($bx + $(if ($qOn) { $q.Width + $gap } else { 0 })), $y) }
        if ($bw -gt 0) { $script:TopLineCx = $bx + $bw / 2.0 }
    } else {
        $qx = TopPlaceX $q.Width $c.SearchArea $c.SearchAlign $c.SearchOffX $tw; $q.Location = New-Object Drawing.Point($qx, $y)
        $fx = TopPlaceX $btnFil.Width $c.FilterArea $c.FilterAlign $c.FilterOffX $tw; $btnFil.Location = New-Object Drawing.Point($fx, $y)
        $script:TopLineCx = $qx + $q.Width / 2.0      # a linha acompanha a busca
    }
    # botões do modo dev: no canto direito
    $dx = $tw - 14
    foreach ($db in $btnDev, $btnAdd) { if ($db.Visible) { $dx -= $db.Width; $db.Location = New-Object Drawing.Point($dx, $y); $dx -= 8 } }
    $top.Invalidate()
}
$top.Add_Resize({ TopCenter; $top.Invalidate() })
# ---- Topo (v2.50.0): nome do launcher centralizado, com brilho (neon) discreto, e linha decorativa sob a busca ----
#  O texto vira um contorno (GraphicsPath); o brilho são várias passadas desse contorno com canetas largas e quase transparentes
#  (das mais largas e fracas para as mais finas), e por cima o texto preenchido (degradê suave ou cor sólida). Tudo ajustável na aba Topo.
$script:HdrFontObj = $null
function HdrFont {
    $c = $script:Cfg; $fn = $c.HdrFont; if (-not $fn) { $fn = "$($S.FontFamily)" }
    $st = switch ($c.HdrStyle) { 'Negrito' { 1 } 'Itálico' { 2 } 'Negrito + itálico' { 3 } default { 0 } }
    try { FontMake $fn $c.HdrSize $st $true }
    catch { LogEx 'AVISO' "Não foi possível criar a fonte do topo: $($_.Exception.Message)" $_; New-Object Drawing.Font('Segoe UI', [single]$c.HdrSize, [Drawing.FontStyle]::Bold) }
}
function HdrPath($gr) {      # contorno do texto na origem (0,0); $null se não houver texto
    $c = $script:Cfg; $fo = $script:HdrFontObj; $tx = "$($c.HdrText)".Trim(); if ($c.HdrCaps) { $tx = $tx.ToUpper() }
    if (-not $tx -or -not $fo) { return $null }
    $em = [single]($fo.SizeInPoints * $gr.DpiY / 72.0); $fam = $fo.FontFamily; $fst = [int]$fo.Style
    $sf = New-Object Drawing.StringFormat ([Drawing.StringFormat]::GenericTypographic); $sf.FormatFlags = $sf.FormatFlags -bor [Drawing.StringFormatFlags]::MeasureTrailingSpaces
    $gp = New-Object Drawing.Drawing2D.GraphicsPath
    try {
        if ($c.HdrSpace -le 0) { $gp.AddString($tx, $fam, $fst, $em, (New-Object Drawing.PointF 0, 0), $sf) }
        else {      # espaço extra entre as letras: uma letra de cada vez
            $x = [single]0
            foreach ($ch in $tx.ToCharArray()) {
                $cs = [string]$ch; $gp.AddString($cs, $fam, $fst, $em, (New-Object Drawing.PointF $x, 0), $sf)
                $x += [single]$gr.MeasureString($cs, $fo, (New-Object Drawing.PointF 0, 0), $sf).Width + [single]$c.HdrSpace
            }
        }
    } finally { $sf.Dispose() }
    $gp
}
function HdrApply {      # chamado pelo ApplyLayout: fonte, altura do topo, dica da busca
    $c = $script:Cfg; if (-not $c) { return }
    if ($script:HdrFontObj) { try { $script:HdrFontObj.Dispose() } catch { $Error.Clear() } }
    $script:HdrFontObj = HdrFont
    $hdr.BackColor = $c.Bg
    $hh = 0
    if ($c.HdrOn -and "$($c.HdrText)".Trim()) {
        $gr = $hdr.CreateGraphics()
        try { $gp = HdrPath $gr; if ($gp) { try { $hh = [int][Math]::Ceiling($gp.GetBounds().Height) } finally { $gp.Dispose() } } } finally { $gr.Dispose() }
        if ($hh -gt 0) { $hh += $c.HdrPadT + $c.HdrPadB + 2 * [int][Math]::Ceiling($c.HdrGlowSize * 0.8) }      # o brilho cabe inteiro (sem corte reto)
    }
    $hdr.Visible = ($hh -gt 0); if ($hh -gt 0 -and $hdr.Height -ne $hh) { $hdr.Height = $hh }
    $hdr.Invalidate(); $top.Invalidate()
    try { if ($q.IsHandleCreated) { [CaCue]::Set($q.Handle, "$($S.SearchHint)") } } catch { $Error.Clear() }
}
$hdr.Add_Paint({ param($snd, $pe)
    if ($S.CinemaMode) {
        DrawCinemaScene $pe.Graphics $snd
        $titleFont = New-Object Drawing.Font('Segoe UI',20,[Drawing.FontStyle]::Bold)
        try {
            $rect = New-Object Drawing.Rectangle(104,0,([Math]::Max(1,$snd.Width-110)),$snd.Height)
            [Windows.Forms.TextRenderer]::DrawText($pe.Graphics,'Targino RetroStation',$titleFont,$rect,[Drawing.Color]::White,([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,NoPrefix'))
            if ($script:JoyStatusText) {
                $statusRect=New-Object Drawing.Rectangle(104,68,([Math]::Max(1,$snd.Width-120)),20)
                [Windows.Forms.TextRenderer]::DrawText($pe.Graphics,$script:JoyStatusText,$snd.Font,$statusRect,[Drawing.Color]::LightSkyBlue,([Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis,SingleLine,NoPrefix'))
            }
        } finally { $titleFont.Dispose() }
        return
    }
    $c = $script:Cfg; if (-not $c) { return }
    $gr = $pe.Graphics; $gr.Clear($c.Bg)
    $gp = $null; $res = New-Object System.Collections.ArrayList
    try {
        $gr.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias; $gr.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $gp = HdrPath $gr; if (-not $gp) { return }
        $b = $gp.GetBounds()
        $gs = [single]$c.HdrGlowSize; $avail = $hdr.ClientSize.Height - $c.HdrPadT - $c.HdrPadB
        $nx = TopPlaceX ([int][Math]::Ceiling($b.Width)) $c.HdrArea $c.HdrAlign $c.HdrOffX $hdr.ClientSize.Width      # posição escolhida na aba Topo (v2.51.0)
        $dx = [single]($nx - $b.X)
        $dy = [single]([Math]::Round($c.HdrPadT + ($avail - $b.Height) / 2.0) - $b.Y)
        $mx = New-Object Drawing.Drawing2D.Matrix; [void]$res.Add($mx); $mx.Translate($dx, $dy); $gp.Transform($mx)
        if ($c.HdrGlow -gt 0) {      # brilho: das passadas largas e fracas para as finas e um pouco mais fortes
            $gc = $c.HdrGlowCol; $n = [int][Math]::Min(14, [Math]::Max(3, $gs)); $base = 70.0 * $c.HdrGlow / 100.0
            for ($i = $n; $i -ge 1; $i--) {
                $k = ($n - $i + 1) / [double]$n; $al = [int][Math]::Max(1, [Math]::Min(255, $base * $k * $k))
                $pw = New-Object Drawing.Pen ([Drawing.Color]::FromArgb($al, $gc.R, $gc.G, $gc.B)), ([single](2.0 * $gs * $i / $n)); [void]$res.Add($pw)
                $pw.LineJoin = [Drawing.Drawing2D.LineJoin]::Round; $gr.DrawPath($pw, $gp)
            }
        }
        $tb = $gp.GetBounds(); $hc = $c.HdrCol
        if ($c.HdrFill -eq 'Degradê suave' -and $tb.Height -gt 1) {
            $top1 = MixCol $hc ([Drawing.Color]::White) 0.45
            $fb = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.RectangleF $tb.X, ($tb.Y - 1), $tb.Width, ($tb.Height + 2))), $top1, $hc, ([single]90)
        } else { $fb = New-Object Drawing.SolidBrush ($hc) }
        [void]$res.Add($fb); $gr.FillPath($fb, $gp)
    } catch { $Error.Clear() }
    finally { if ($gp) { $gp.Dispose() }; foreach ($o in $res) { try { $o.Dispose() } catch { $Error.Clear() } } }
})
$hdr.Add_Resize({ $hdr.Invalidate() })
$libP.Add_Resize({ $hdr.Invalidate(); TopCenter })      # painel de detalhes mudou de largura / foi mostrado ou escondido
# Linha decorativa sob a busca: some nas pontas (transparente -> cor -> transparente), centralizada
$top.Add_Paint({ param($snd, $pe)
    if ($S.CinemaMode) { DrawCinemaScene $pe.Graphics $snd }
    $c = $script:Cfg; if (-not $c -or -not $c.HdrLine) { return }
    $w = [int]((TopArea $c.SearchArea)[1] * $c.HdrLineW / 100.0); if ($w -lt 20) { return }
    $lcx = $script:TopLineCx; if ($null -eq $lcx) { $lcx = $top.ClientSize.Width / 2.0 }
    $x0 = [int]($lcx - $w / 2.0); $y = $top.ClientSize.Height - 2; $lc = $c.HdrLineCol
    $rc = New-Object Drawing.Rectangle $x0, $y, $w, 1
    $lb = New-Object Drawing.Drawing2D.LinearGradientBrush $rc, ([Drawing.Color]::FromArgb(0, $lc.R, $lc.G, $lc.B)), ([Drawing.Color]::FromArgb(0, $lc.R, $lc.G, $lc.B)), ([single]0)
    try {
        $bl = New-Object Drawing.Drawing2D.ColorBlend 3
        $bl.Colors = [Drawing.Color[]]@(([Drawing.Color]::FromArgb(0, $lc.R, $lc.G, $lc.B)), ([Drawing.Color]::FromArgb(150, $lc.R, $lc.G, $lc.B)), ([Drawing.Color]::FromArgb(0, $lc.R, $lc.G, $lc.B)))
        $bl.Positions = [single[]]@(0, 0.5, 1); $lb.InterpolationColors = $bl
        $pe.Graphics.FillRectangle($lb, $rc)
    } finally { $lb.Dispose() }
})
$q.Add_HandleCreated({ try { [CaCue]::Set($q.Handle, "$($S.SearchHint)") } catch { $Error.Clear() } })
$top.Add_VisibleChanged({ TopCenter })
$fm = New-Object Windows.Forms.ContextMenuStrip -Property @{ ShowImageMargin = $false; ShowCheckMargin = $false }
$script:MenuRend = New-Object DarkMenuRenderer; $fm.Renderer = $script:MenuRend
$addm = New-Object Windows.Forms.ContextMenuStrip -Property @{ ShowImageMargin = $false; ShowCheckMargin = $false }   # menu do botão '+ Adicionar' (modo dev)
$addm.Renderer = $script:MenuRend
$zlab = Mk Windows.Forms.Label @{ Text = "$($S.T_Zoom)"; Left = 10; Top = 8; Width = 105; Height = 20 } $bot
$zm = Mk Windows.Forms.TrackBar @{ Left = 115; Top = 2; Width = 110; TickStyle = 'BottomRight' } $bot
$zm.Minimum = 1; $zm.Maximum = 3
$form.MinimumSize = New-Object Drawing.Size(820, 540)
$windowModule=Join-Path $Arq 'TarginoWindow.ps1'
if([IO.File]::Exists($windowModule)){. $windowModule}
$zm.Value = [Math]::Min(3, [Math]::Max(1, [int]$S.Zoom))      # zoom ao abrir = o do layout.json (v2.52.0: a escolha da pessoa vale só na sessão)

# Painel de detalhes (não há mais botão Jogar: duplo clique na capa ou botão direito > Jogar)
#  Rótulos com ClearType próprio (ClearLabel, igual à grade). $lst = aviso de unidade desconectada / jogo compactado.
$lt   = Mk ClearLabel @{ Width = 370; Height = 70; Font = (New-Object Drawing.Font('Segoe UI', 18)); Margin = '0,0,0,8' } $right
$row  = Mk Windows.Forms.FlowLayoutPanel @{ Width = 375; Height = 46; FlowDirection = 'LeftToRight'; WrapContents = $false; BackColor = $bg; Margin = '0,0,0,6' } $right
$btnFav = Mk Windows.Forms.Button @{ Text = '☆ Favoritar'; Width = 120; Height = 36; FlatStyle = 'Flat'; ForeColor = 'White'; BackColor = $dk; Margin = '3,0,8,0' } $row
foreach ($b in $btnFav, $btnAdd, $btnDev, $btnFil) { $b.FlatAppearance.BorderSize = 0 }
$lst  = Mk ClearLabel @{ Width = 370; Height = 22; ForeColor = [Drawing.Color]::FromArgb(230, 120, 90); Visible = $false; Margin = '0,0,0,4' } $right
$lver = Mk ClearLabel @{ Width = 370; Height = 22; Margin = '0,0,0,4' } $right
$ld   = Mk DescBox @{ Width = 365; Height = 130; Margin = '0,0,0,8'; ReadOnly = $true; BorderStyle = 'None'; ScrollBars = 'Vertical'; DetectUrls = $false; TabStop = $false; BackColor = $bg; ForeColor = 'White'; Cursor = 'Default' } $right
$pic  = Mk Windows.Forms.PictureBox @{ Width = 365; Height = 260; SizeMode = 'Zoom' } $right

# ---- Descrição formatada ----
#  Marcação simples (maiúsculas/minúsculas tanto faz):  [b]negrito[/b]  [i]itálico[/i]  [u]sublinhado[/u]
#  [cor=#FF8800]texto[/cor]  [tam=14]tamanho em pt (8 a 40)[/tam]  [titulo]título[/titulo]  [sub]subtítulo[/sub]
#  [link=https://site]texto[/link]   (endereços http(s):// soltos no texto também viram link)
#  Tag desconhecida, valor inválido ou fechamento sem abertura aparecem como texto comum. Tag aberta e não fechada vale até o fim.
#  Linhas em branco separam parágrafos. Links só abrem URL/protocolo (nunca arquivo ou programa local).
function DescAdd($segs, $st, $text) {
    if (-not $text) { return }
    $lk = ''; if ($st.Link.Count) { $lk = $st.Link.Peek() }
    $parts = @($text)
    if (-not $lk) { $parts = [regex]::Split($text, '(https?://[^\s\[\]<>"'']+)') }
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $pt = $parts[$i]; if (-not $pt) { continue }
        $url = ''
        if (-not $lk -and ($i % 2) -eq 1) {
            $tail = ''; while ($pt.Length -gt 8 -and '.,;:!?)'.Contains($pt.Substring($pt.Length - 1))) { $tail = $pt.Substring($pt.Length - 1) + $tail; $pt = $pt.Substring(0, $pt.Length - 1) }
            $url = $pt
            [void]$segs.Add(@{ Text = $pt; B = ($st.B -gt 0); I = ($st.I -gt 0); U = ($st.U -gt 0); Title = ($st.T -gt 0); Sub = ($st.S -gt 0); Color = ''; Size = 0; Link = $url })
            if ($tail) { [void]$segs.Add(@{ Text = $tail; B = ($st.B -gt 0); I = ($st.I -gt 0); U = ($st.U -gt 0); Title = ($st.T -gt 0); Sub = ($st.S -gt 0); Color = ''; Size = 0; Link = '' }) }
            continue
        }
        $cor = ''; if ($st.Cor.Count) { $cor = $st.Cor.Peek() }
        $tam = 0; if ($st.Tam.Count) { $tam = $st.Tam.Peek() }
        [void]$segs.Add(@{ Text = $pt; B = ($st.B -gt 0); I = ($st.I -gt 0); U = ($st.U -gt 0); Title = ($st.T -gt 0); Sub = ($st.S -gt 0); Color = $cor; Size = $tam; Link = $lk })
    }
}
function DescParse($txt) {
    $txt = ("$txt" -replace "`r`n", "`n") -replace "`r", "`n"
    $segs = New-Object System.Collections.ArrayList
    $st = @{ B = 0; I = 0; U = 0; T = 0; S = 0; Cor = (New-Object 'System.Collections.Generic.Stack[string]'); Tam = (New-Object 'System.Collections.Generic.Stack[int]'); Link = (New-Object 'System.Collections.Generic.Stack[string]') }
    $rx = [regex]'(?i)\[(/?)(b|i|u|cor|tam|titulo|sub|link)(?:=([^\[\]]*))?\]'
    $pos = 0
    foreach ($m in $rx.Matches($txt)) {
        if ($m.Index -gt $pos) { DescAdd $segs $st $txt.Substring($pos, $m.Index - $pos) }
        $pos = $m.Index + $m.Length
        $close = ($m.Groups[1].Value -eq '/'); $tag = $m.Groups[2].Value.ToLowerInvariant(); $val = $m.Groups[3].Value.Trim(); $ok = $true
        if ($close) {
            switch ($tag) {
                'b' { if ($st.B -gt 0) { $st.B-- } else { $ok = $false } }
                'i' { if ($st.I -gt 0) { $st.I-- } else { $ok = $false } }
                'u' { if ($st.U -gt 0) { $st.U-- } else { $ok = $false } }
                'titulo' { if ($st.T -gt 0) { $st.T-- } else { $ok = $false } }
                'sub' { if ($st.S -gt 0) { $st.S-- } else { $ok = $false } }
                'cor' { if ($st.Cor.Count) { [void]$st.Cor.Pop() } else { $ok = $false } }
                'tam' { if ($st.Tam.Count) { [void]$st.Tam.Pop() } else { $ok = $false } }
                'link' { if ($st.Link.Count) { [void]$st.Link.Pop() } else { $ok = $false } }
            }
        } else {
            switch ($tag) {
                'b' { $st.B++ }
                'i' { $st.I++ }
                'u' { $st.U++ }
                'titulo' { $st.T++ }
                'sub' { $st.S++ }
                'cor' { if ($val -match '^#?[0-9a-fA-F]{6}$') { $st.Cor.Push($(if ($val[0] -eq '#') { $val } else { "#$val" })) } else { $ok = $false } }
                'tam' { $nv = 0; if ([int]::TryParse($val, [ref]$nv) -and $nv -ge 8 -and $nv -le 40) { $st.Tam.Push($nv) } else { $ok = $false } }
                'link' {   # URL/protocolo, ou (v2.42.0) caminho RELATIVO à pasta do launcher (documento/imagem/pasta; conferido no clique, DescOpenLocal)
                    $lkUrl = ($val -match '^(?i)(www\.|[a-z][a-z0-9+.\-]+:)' -and $val -notmatch '^[a-zA-Z]:[\\/]')
                    $lkRel = ($val -and $val -notmatch '^[a-zA-Z]:' -and $val -notmatch '^[\\/]' -and $val -notmatch '(?i)^[a-z][a-z0-9+.\-]+:')
                    if ($lkUrl -or $lkRel) { $st.Link.Push($val) } else { $ok = $false }
                }
            }
        }
        if (-not $ok) { DescAdd $segs $st $m.Value }
    }
    if ($pos -lt $txt.Length) { DescAdd $segs $st $txt.Substring($pos) }
    , $segs
}
# Escreve os trechos no RichTextBox (somente leitura) e guarda onde ficam os links em Tag.
function DescRender($rtb, $segs, $cf) {
    [Rtb]::Redraw($rtb, $false)   # nada é desenhado até o texto estar completo (v2.34.2)
    $rtb.Clear(); $links = New-Object System.Collections.ArrayList; $fonts = @{}
    try {
        foreach ($sg in $segs) {
            $tx = "$($sg.Text)"; if (-not $tx) { continue }
            $p0 = $rtb.TextLength; $rtb.AppendText($tx)
            $sz = [single]$cf.Size; $fs = [Drawing.FontStyle]::Regular; $col = $cf.Color
            if ($sg.Title) { $sz = [single]$cf.TitleSize; $fs = [Drawing.FontStyle]::Bold; $col = $cf.Accent }
            elseif ($sg.Sub) { $sz = [single]$cf.SubSize; $fs = [Drawing.FontStyle]::Bold }
            elseif ($sg.Size -gt 0) { $sz = [single]$sg.Size }
            if ($sg.B) { $fs = $fs -bor [Drawing.FontStyle]::Bold }
            if ($sg.I) { $fs = $fs -bor [Drawing.FontStyle]::Italic }
            if ($sg.U) { $fs = $fs -bor [Drawing.FontStyle]::Underline }
            if ($sg.Color) { try { $col = [Drawing.ColorTranslator]::FromHtml($sg.Color) } catch { $Error.RemoveAt(0) } }
            if ($sg.Link) { $col = $cf.LinkColor }   # v2.32.1: link só colorido, sem sublinhado
            $fk = "$sz|$([int]$fs)"
            if (-not $fonts.ContainsKey($fk)) { $fonts[$fk] = FontMake $cf.Family $sz ([int]$fs) $true }
            $rtb.Select($p0, $tx.Length); $rtb.SelectionFont = $fonts[$fk]; $rtb.SelectionColor = $col
            if ($sg.Link) { [void]$links.Add(@{ S = $p0; E = ($p0 + $tx.Length); U = "$($sg.Link)" }) }
        }
        $al = switch ("$($cf.Align)") { 'Centro' { [Windows.Forms.HorizontalAlignment]::Center } 'Direita' { [Windows.Forms.HorizontalAlignment]::Right } default { [Windows.Forms.HorizontalAlignment]::Left } }
        $rtb.SelectAll(); $rtb.SelectionAlignment = $al
        $rtb.Select(0, 0); $rtb.ScrollToCaret()
    } finally {
        foreach ($fo in $fonts.Values) { $fo.Dispose() }
        [Rtb]::Redraw($rtb, $true); [Rtb]::NoCaret($rtb)
        $rtb.Invalidate()
    }
    $rtb.Tag = @{ Links = $links }
}
function DescCfg {
    $c = $script:Cfg; if (-not $c) { LoadCfg; $c = $script:Cfg }
    @{ Family = $c.DescFont; Size = $c.DescSize; TitleSize = $c.DescTitle; SubSize = $c.DescSubT; Color = $c.DescCol; Accent = $c.DescTitleCol; LinkColor = $c.DescLink; Align = $c.DescAlign }
}
function DescLinkAt($rtb, $pt) {
    $lk = $rtb.Tag; if (-not $lk -or -not $lk.Links -or -not $lk.Links.Count) { return $null }
    $i = $rtb.GetCharIndexFromPosition($pt)
    foreach ($ln in $lk.Links) {
        if ($i -lt $ln.S -or $i -ge $ln.E) { continue }
        $cp = $rtb.GetPositionFromCharIndex($i); $np = $rtb.GetPositionFromCharIndex($i + 1)
        if ($pt.Y -lt $cp.Y - 4 -or $pt.Y -gt $cp.Y + 2 * $rtb.Font.Height) { return $null }
        $xEnd = $cp.X + $rtb.Font.Height; if ($np.Y -eq $cp.Y -and $np.X -gt $cp.X) { $xEnd = $np.X }
        if ($pt.X -lt $cp.X - 2 -or $pt.X -gt $xEnd + 2) { return $null }
        return $ln
    }
    $null
}
# Arquivo local na descrição (v2.42.0): só DOCUMENTOS/IMAGENS (lista abaixo) ou pasta, e só DENTRO da pasta do launcher; abre com o
#  programa padrão do Windows. Programas e scripts (.exe, .bat, .ps1, .lnk...) continuam bloqueados: a descrição vai nas atualizações.
#  Caminho relativo à pasta do launcher; {JogoDir} = pasta do jogo selecionado.
$DescDocExts = '.pdf', '.txt', '.md', '.rtf', '.doc', '.docx', '.odt', '.xls', '.xlsx', '.csv', '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.mp4', '.mkv', '.webm', '.mp3'
function DescOpenLocal($url) {
    $gm = Sel; $txt = "$url".Trim().Trim('"')
    if ($gm) { $txt = XeExpand $gm $txt }
    $p = Full $txt
    $rootF = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $p -or -not $p.StartsWith($rootF, 'OrdinalIgnoreCase')) { Log 'AVISO' "Link da descrição ignorado (arquivo fora da pasta do launcher): $url"; return }
    if ([IO.Directory]::Exists($p)) { Log 'INFO' "Abrindo pasta (link da descrição): $(Short $p)"; [void](ShellOpen $p '' ''); return }
    if (-not [IO.File]::Exists($p)) { Log 'AVISO' "Link da descrição: arquivo não encontrado: $(Short $p)"; [void][Windows.Forms.MessageBox]::Show("Não foi encontrado:`n$p", 'Link'); return }
    if ($DescDocExts -notcontains [IO.Path]::GetExtension($p).ToLowerInvariant()) { Log 'AVISO' "Link da descrição ignorado (tipo de arquivo não permitido): $(Short $p)"; return }
    Log 'INFO' "Abrindo arquivo (link da descrição): $(Short $p)"
    try { [void](ShellOpen $p '' ([IO.Path]::GetDirectoryName($p))) } catch { LogEx 'ERRO' "Falha ao abrir '$(Short $p)': $($_.Exception.Message)" $_; [void][Windows.Forms.MessageBox]::Show("Não foi possível abrir:`n$p`n`n$($_.Exception.Message)", 'Link') }
}
function DescOpenLink($url) {
    $ti = TargetInfo $url
    if (-not $ti) { return }
    if ($ti.Kind -eq 'Local') { DescOpenLocal $url; return }
    if ($ti.Kind -eq 'Protocolo') {
        if ([Windows.Forms.MessageBox]::Show("Abrir este link no aplicativo associado?`n`n$($ti.Target)", 'Abrir link', 'YesNo') -ne 'Yes') { return }
    }
    [void](OpenTarget $url 'link da descrição' $false)
}
function DescAttach($rtb) {   # cursor de mão + clique abre o link (seguro)
    # sem cursor de texto piscando (barra branca) ao passar o mouse/clicar na descrição (v2.34.2)
    $rtb.Add_GotFocus({ param($snd, $ev) [Rtb]::NoCaret($snd) })
    $rtb.Add_MouseDown({ param($snd, $ev) [Rtb]::NoCaret($snd) })
    $rtb.Add_SelectionChanged({ param($snd, $ev) [Rtb]::NoCaret($snd) })
    # só o cursor de mão (sem dica com o endereço); ele só muda quando entra/sai de um link (DescBox, v2.35.2)
    $rtb.Add_MouseMove({ param($snd, $me) $snd.OverLink = [bool](DescLinkAt $snd $me.Location) })
    $rtb.Add_MouseLeave({ param($snd, $ev) $snd.OverLink = $false })
    $rtb.Add_MouseUp({ param($snd, $me)
        if ($me.Button -ne 'Left' -or $snd.SelectionLength -gt 0) { return }
        $ln = DescLinkAt $snd $me.Location; if ($ln) { DescOpenLink $ln.U }
    })
}
$script:DescLast = ''
DescAttach $ld
# Foco ao passar o mouse (para a roda rolar sem clicar) SÓ com o launcher como janela ativa (v2.37.4): sem isso, passar o mouse
#  pelo launcher roubava a frente de qualquer janela aberta por ele (ex.: o aviso de segurança do Windows ao abrir um jogo).
function FormActive { [Windows.Forms.Form]::ActiveForm -eq $form }
$ld.Add_MouseEnter({ if ((FormActive) -and ($grid.Focused -or $form.ActiveControl -eq $grid)) { [void]$ld.Focus() } })
$ld.Add_MouseLeave({ if ((FormActive) -and $ld.Focused) { [void]$grid.Focus() } })
function DescShow($gm) {
    $dt = "$($gm.Desc)".Trim()
    $ld.Visible = [bool]($S.ShowDesc -and $dt)
    if (-not $ld.Visible) { $ld.Clear(); $ld.Tag = $null; $script:DescLast = ''; $script:DescContentH = 0; return }
    $sg = "$($gm.Id)|$dt|$script:DescCfgSig"
    if ($script:DescLast -eq $sg) { return }
    $script:DescLast = $sg
    try { DescRender $ld (DescParse $dt) (DescCfg) } catch { LogEx 'AVISO' "Descrição de '$($gm.Name)' não pôde ser exibida: $($_.Exception.Message)" $_; $ld.Clear(); $ld.Text = $dt }
}
$script:DescCfgSig = ''
# Painel da direita: acompanha a largura/altura da janela (nada de coordenadas fixas)
function RightLayout {
    if (-not $right.Visible -or $script:InRL) { return }
    $script:InRL = $true
    try {
        $w = $right.ClientSize.Width - $right.Padding.Horizontal; if ($w -lt 150) { $w = 150 }
        foreach ($ct in $lt, $row, $lst, $lver, $ld, $pic) { if ($ct.Width -ne $w) { $ct.Width = $w } }
        $used = 0
        foreach ($ct in $lt, $row, $lst, $lver) { if ($ct.Visible) { $used += $ct.Height + $ct.Margin.Vertical } }
        $avail = $right.ClientSize.Height - $right.Padding.Vertical - $used
        # altura natural da captura (proporção real da imagem); sem imagem carregada, 16:9
        $nat = 0
        if ($pic.Visible) {
            if ($pic.Image -and $pic.Image.Width -gt 0) { $nat = [int][Math]::Round($w * $pic.Image.Height / [double]$pic.Image.Width) } else { $nat = [int][Math]::Round($w * 9.0 / 16.0) }
            if ($nat -lt 1) { $nat = 1 }
        }
        $pv = 0; if ($pic.Visible) { $pv = $pic.Margin.Vertical }
        if ($ld.Visible) {
            # a descrição tem a altura do próprio texto (a captura fica colada embaixo dela); só rola se faltar espaço
            $mv = $ld.Margin.Vertical
            $minPic = 0; if ($pic.Visible) { $minPic = [Math]::Min($nat, 120) }
            $maxD = [Math]::Max(40, $avail - $mv - $pv - $minPic)
            $want = [Math]::Max(24, $script:DescContentH + 4)
            $descH = [int][Math]::Min($want, $maxD)
            if ($ld.Height -ne $descH) { $ld.Height = $descH }
            if ($pic.Visible) { $room = $avail - $descH - $mv - $pv; $pic.Height = [int][Math]::Max(0, [Math]::Min($nat, $room)) }
        } elseif ($pic.Visible) { $pic.Height = [int][Math]::Max(0, [Math]::Min($nat, $avail - $pv)) }
    } finally { $script:InRL = $false }
}
$script:InRL = $false; $script:DescContentH = 0; $script:DescBusy = $false
$ld.Add_ContentsResized({ param($snd, $ev)
    $hh = [int]$ev.NewRectangle.Height
    if ($hh -ne $script:DescContentH) { $script:DescContentH = $hh; if (-not $script:DescBusy) { RightLayout } }   # durante a troca de jogo só anota a altura (v2.34.1)
})
$right.Add_Resize({ RightLayout })

function Sel { if ($script:Cur -and $script:CurIdx -ge 0) { $script:Cur } }
function ShowGame($g) {
    # No carrossel, o painel de detalhes só é montado quando sua janela é aberta.
    # Evita ler/decodificar a captura e formatar a descrição a cada seta pressionada.
    if ($S.CinemaMode -and $right.Parent -eq $mainP) { return }
    if (-not $g) {
        $lt.Text = ''; $lver.Text = ''; $ld.Clear(); $ld.Visible = $false; $script:DescLast = ''; $script:DescContentH = 0; $pic.Visible = $false; $lst.Visible = $false; $row.Visible = $false
        if ($pic.Image) { $pic.Image.Dispose(); $pic.Image = $null }
        return
    }
    # v2.34.1: o painel fica "congelado" enquanto a descrição é montada e a captura é trocada; senão cada trecho da
    # descrição fazia o painel empurrar a captura um pouco para baixo e redesenhar, deixando faixas da imagem pelo caminho.
    $script:DescBusy = $true; $right.SuspendLayout()
    try {
    $inst = [bool]$script:Inst["$($g.Id)"]
    $lt.Text = $g.Name
    $btnFav.Text = if ($U.Fav -contains $g.Id) { "★ $($S.T_Faved)" } else { "☆ $($S.T_Fav)" }
    $btnFav.Visible = [bool]$S.ShowFav
    $offl = ($script:InstState["$($g.Id)"] -eq 'offline')
    $arch = ($script:InstState["$($g.Id)"] -eq 'archived')
    $lst.Text = if ($offl) { "$($S.T_Offline) ($(DriveOf (ExePath $g)))" } elseif ($arch) { "$($S.T_Archived)" } else { '' }
    $lst.ForeColor = $script:Cfg.StatusCol      # v2.54.0: cor do aviso definida no modo dev (StatusColor)
    $lst.Visible = ($offl -or $arch)   # jogo ausente não tem aviso: a capa em P&B/escura já indica
    $row.Visible = [bool]$S.ShowFav
    $lver.Text = if ($g.Version) { "$($S.T_Version)  $($g.Version)" } else { '' }
    DescShow $g
    if ($pic.Image) { $pic.Image.Dispose(); $pic.Image = $null }
    $p = ShotPath $g
    if ($p -and [IO.File]::Exists($p)) { try { $pic.Image = [Drawing.Image]::FromStream((New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($p)))) } catch { LogEx 'AVISO' "Captura de tela não pôde ser carregada: $(Short $p) ($($_.Exception.Message))" $_ } }
    $pic.Visible = [bool]($S.ShowShot -and $pic.Image)
    } finally {
        $script:DescBusy = $false
        try { RightLayout } catch { LogEx 'AVISO' "Painel de detalhes: $($_.Exception.Message)" $_ }
        $right.ResumeLayout($true)      # um único posicionamento, já com a altura final da descrição
        $right.Invalidate($true); $right.Update()
    }
}

# ---- Visões (menu de filtros ao lado da busca) ----
function FilterText($key) {
    switch ($key) { 'all' { "$($S.T_All)" } 'recent' { "$($S.T_Recent)" } 'fav' { "$($S.T_Favs)" } 'inst' { "$($S.T_Inst)" } 'notinst' { "$($S.T_NotInst)" } default { "$key" } }
}
function FilterKeys {   # opções visíveis no menu, na ordem escolhida no modo dev
    $ks = @(("$($S.SideItems)" -split '[,; ]+') | Where-Object { $AllKeys -contains $_ } | Select-Object -Unique)
    if (-not $ks) { $ks = @('all') }
    $ks
}
# Menu suspenso de filtros, ao lado da busca. É montado a cada abertura,
# com a opção atual marcada e a quantidade de jogos ao lado (quando ligado no modo dev).
function FilterMenuShow {
    foreach ($old in @($fm.Items)) { $old.Dispose() }; $fm.Items.Clear()
    if ($script:HydraNavigationEnabled) { HydraAddSystemMenu }
    foreach ($k in @(FilterKeys)) {
        $txt = FilterText $k
        if ($script:Cfg -and $script:Cfg.SideCount) { $txt = "$txt  ($($script:FilCounts[$k]))" }
        $mi = $fm.Items.Add("$txt", $null, { param($snd, $ev) SetFilter "$($snd.Tag)" })
        $mi.Tag = $k; $mi.Checked = ($k -eq $script:Filter)
        $mi.Padding = New-Object Windows.Forms.Padding (12, 3, 14, 3)
    }
    if($S.CinemaMode -or $script:BigPictureEnabled -or -not $btnFil.Visible){
        $fm.Show($grid,(New-Object Drawing.Point(16,([Math]::Max(0,$grid.Height-50)))),[Windows.Forms.ToolStripDropDownDirection]::AboveRight)
    }else{$fm.Show($btnFil, 0, $btnFil.Height)}
}
function FilterLabel {
    $btnFil.Text = "$(FilterText $script:Filter)  ▾"
    if ($script:HydraNavigationEnabled) {
        $btnFil.Text = $(if($script:HydraHome){'Sistemas  ▾'}else{$script:HydraSystemLookup[$script:HydraSystem].Name+' · '+(FilterText $script:Filter)+'  ▾'})
    }
    $btnFil.Visible = [bool]$S.ShowFilter; FilBtnFit; TopCenter
}
# Botão de filtros: só o texto (sem caixa de fundo nem contorno); ao passar o mouse o texto fica na cor de destaque.
# A largura acompanha o texto, para a barra do topo ficar bem centralizada.
function FilBtnFit {
    $fbW = [Windows.Forms.TextRenderer]::MeasureText("$($btnFil.Text)", $btnFil.Font).Width + 12
    if ($btnFil.Width -ne $fbW) { $btnFil.Width = $fbW }
}
$btnFil.Add_MouseEnter({ if ($script:Cfg) { $btnFil.ForeColor = $script:Cfg.Accent } })
$btnFil.Add_MouseLeave({ if ($script:Cfg) { $btnFil.ForeColor = $script:Cfg.Text } })
function EnsureFilter {
    if (-not $S.ShowFilter) { $script:Filter = 'all'; return }
    $ks = @(FilterKeys); if ($ks -notcontains $script:Filter) { $script:Filter = $ks[0] }
}
function InitFilter {   # visão inicial: o último filtro usado pela pessoa (Dados\ultimo_filtro.txt); sem ele ou inválido = 1ª opção do menu
    $key = FilLoad
    if (@(FilterKeys) -notcontains $key) { $key = @(FilterKeys)[0] }
    $script:Filter = $key; EnsureFilter
}
function SetFilter($key) {   # guarda como último filtro usado (abre nele da próxima vez)
    if ($key -eq $script:Filter) { return }
    $script:Filter = $key; FilSave $key
    $script:SelIds.Clear(); $script:Cur = $null; $script:CurIdx = -1; $script:Anchor = -1
    $vsb.Value = 0
    Populate
}

# ---- Fontes: pasta fonts + peso e contraste do texto ----
#  Coloque arquivos .ttf/.otf na pasta "fonts" ao lado do launcher e escolha a família no painel dev (aba Fontes e texto).
#  As fontes valem só para este programa (nada é instalado no Windows). Famílias que não existirem caem em Segoe UI.
$FontsDir = ArqDir 'Fonts'
$script:Pfc = $null; $script:FontFiles = @{}; $script:FontFam = @{}; $script:SysFam = @{}; $script:FontWarned = @{}
function FontsScan {
    if (-not [IO.Directory]::Exists($FontsDir)) { return }
    $added = 0
    foreach ($fp in [IO.Directory]::EnumerateFiles($FontsDir)) {
        if ([IO.Path]::GetExtension($fp).ToLower() -notin '.ttf', '.otf') { continue }
        $key = $fp.ToLower(); if ($script:FontFiles.ContainsKey($key)) { continue }
        $script:FontFiles[$key] = 1
        try {
            if (-not $script:Pfc) { $script:Pfc = New-Object Drawing.Text.PrivateFontCollection }
            $script:Pfc.AddFontFile($fp); [void][Fnt]::Add($fp); $added++
        } catch { LogEx 'AVISO' "Fonte ignorada ($([IO.Path]::GetFileName($fp))): $($_.Exception.Message)" $_ }
    }
    if ($added -and $script:Pfc) {
        foreach ($ff in $script:Pfc.Families) { $script:FontFam[$ff.Name.ToLower()] = $ff }
        Log 'INFO' "Fontes da pasta fonts: $added arquivo(s) novo(s); famílias: $((@($script:FontFam.Values | ForEach-Object { $_.Name } | Sort-Object) -join ', '))"
    }
}
# Família por nome: primeiro as da pasta fonts, depois as instaladas no Windows. $null se não existir.
function FontFamObj($name) {
    $nm = "$name".Trim(); if (-not $nm) { return $null }
    $lk = $nm.ToLower()
    if ($script:FontFam.ContainsKey($lk)) { return $script:FontFam[$lk] }
    if (-not $script:SysFam.ContainsKey($lk)) {
        $fo = $null
        try { $fo = New-Object Drawing.FontFamily($nm) } catch { $Error.Clear() }
        $script:SysFam[$lk] = $fo
    }
    $script:SysFam[$lk]
}
# Decide família e estilo (lógica pura, sem GDI+; $has é um bloco que diz se uma família existe).
#  Peso: Normal; Médio = variante Semibold/Medium da própria família, se existir (senão fica Normal); Negrito.
function FontPick($fname, $style, $weight, $weighted, $has) {
    $fn = "$fname".Trim(); if (-not $fn) { $fn = 'Segoe UI' }
    $st = [int]$style; $bold = 1
    if ($weighted -and ($st -band $bold) -eq 0) {
        if ($weight -eq 'Médio') { foreach ($sfx in ' Semibold', ' SemiBold', ' Medium', ' DemiBold') { if (& $has ($fn + $sfx)) { $fn = $fn + $sfx; break } } }
        elseif ($weight -eq 'Negrito') { $st = ($st -bor $bold) }
    }
    if (-not (& $has $fn)) { $fn = 'Segoe UI' }
    @{ Name = $fn; Style = $st }
}
function TextHint($mode) {
    switch ("$mode") {
        'ClearType'         { [Drawing.Text.TextRenderingHint]::ClearTypeGridFit; break }
        'Padrão do sistema' { [Drawing.Text.TextRenderingHint]::SystemDefault; break }
        'Suavizado (cinza)' { [Drawing.Text.TextRenderingHint]::AntiAlias; break }
        'Suavizado (grade)' { [Drawing.Text.TextRenderingHint]::AntiAliasGridFit; break }
        'Sem suavização'    { [Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit; break }
        default             { [Drawing.Text.TextRenderingHint]::ClearTypeGridFit }
    }
}
function FontMake($fname, $size, $style, $weighted) {
    $w = CfgChoice 'TextWeight' @('Normal', 'Médio', 'Negrito') 'Médio'
    $want = "$fname".Trim()
    if ($want -and $want -ne 'Segoe UI' -and -not (FontFamObj $want) -and -not $script:FontWarned[$want.ToLower()]) {
        $script:FontWarned[$want.ToLower()] = 1; Log 'AVISO' "Fonte '$want' não encontrada (pasta fonts ou Windows); usando Segoe UI."
    }
    $pk = FontPick $fname $style $w $weighted { param($nm) [bool](FontFamObj $nm) }
    $ff = FontFamObj $pk.Name; if (-not $ff) { $ff = [Drawing.FontFamily]::GenericSansSerif }
    # estilo pedido; se a família não tiver (ex.: só Negrito), tenta sem negrito/itálico (mantendo sublinhado) e por fim o normal
    foreach ($cand in @($pk.Style, ($pk.Style -band 12), 0, 1, 2)) {
        if ($ff.IsStyleAvailable([Drawing.FontStyle]($cand -band 3))) { return (New-Object Drawing.Font($ff, [single]$size, ([Drawing.FontStyle]$cand), [Drawing.GraphicsUnit]::Point)) }
    }
    New-Object Drawing.Font($ff, [single]$size)
}
# Fonte só do título do jogo (painel da direita): família, tamanho e estilo próprios; vazio = a mesma da interface
function MakeTitleFont {
    $c = $script:Cfg; $fn = $c.TitleFont; if (-not $fn) { $fn = "$($S.FontFamily)" }
    $st = switch ($c.TitleStyle) { 'Negrito' { 1 } 'Itálico' { 2 } 'Negrito + itálico' { 3 } default { 0 } }
    try { FontMake $fn $c.TitleSize $st $true }
    catch { LogEx 'AVISO' "Não foi possível criar a fonte do título: $($_.Exception.Message)" $_; New-Object Drawing.Font('Segoe UI', [single]$c.TitleSize) }
}
# Fonte da interface (família escolhida no dev, com o peso configurado)
function UiFont($size, $style = 0) {
    try { FontMake "$($S.FontFamily)" $size $style $true }
    catch { LogEx 'AVISO' "Não foi possível criar a fonte da interface: $($_.Exception.Message)" $_; New-Object Drawing.Font('Segoe UI', [single]$size, ([Drawing.FontStyle]($style -band 3))) }
}

# ---- Tema dos controles próprios (rolagem, menus, botões, barra de título) ----
function MixCol($ca, $cb, $kk) {
    [Drawing.Color]::FromArgb([int]($ca.R + ($cb.R - $ca.R) * $kk), [int]($ca.G + ($cb.G - $ca.G) * $kk), [int]($ca.B + ($cb.B - $ca.B) * $kk))
}
function ColLum($cl) { 0.299 * $cl.R + 0.587 * $cl.G + 0.114 * $cl.B }
function ThemeTitle {
    if (-not $script:Cfg -or -not $form.IsHandleCreated) { return }
    try {
        $bgc = $script:Cfg.Bg; $tc = $script:Cfg.Text
        [Dwm]::Dark($form.Handle, ((ColLum $bgc) -lt 128), [int]($bgc.R + 256 * $bgc.G + 65536 * $bgc.B), [int]($tc.R + 256 * $tc.G + 65536 * $tc.B))
    } catch { $Error.Clear() }
}
function ThemeApply {
    $c = $script:Cfg; if (-not $c) { return }
    $white = [Drawing.Color]::White; $dark = ((ColLum $c.Side) -lt 128)
    $mr = $script:MenuRend
    $mr.DangerFg = $c.Delete
    $mr.Bg = $c.Side; $mr.Text = $c.Text; $mr.Accent = $c.Accent; $mr.Border = (MixCol $c.Side $white 0.2)
    # item sob o mouse: cor oposta à do menu (menu escuro => destaque claro com letra escura, e vice-versa)
    if ($dark) { $mr.HoverBg = [Drawing.Color]::FromArgb(232, 232, 232); $mr.HoverFg = [Drawing.Color]::FromArgb(16, 16, 16) }
    else { $mr.HoverBg = [Drawing.Color]::FromArgb(30, 30, 30); $mr.HoverFg = [Drawing.Color]::FromArgb(245, 245, 245) }
    $vsb.TrackColor = $c.Bg; $vsb.ThumbColor = (MixCol $c.Bg $white 0.22); $vsb.ThumbHotColor = (MixCol $c.Bg $white 0.4); $vsb.Invalidate()
    $btnFil.FlatAppearance.BorderSize = 0; $btnFil.FlatAppearance.MouseOverBackColor = $c.Bg; $btnFil.FlatAppearance.MouseDownBackColor = $c.Bg   # filtros: só o texto, sem caixa
    foreach ($bt1 in $btnFav, $btnAdd, $btnDev) {
        $bt1.FlatAppearance.BorderSize = 0
        $bt1.FlatAppearance.MouseOverBackColor = (MixCol $c.Side $white 0.12); $bt1.FlatAppearance.MouseDownBackColor = (MixCol $c.Side $white 0.22)
    }
    $fm.Font = UiFont 9; $cm.Font = UiFont 9; $addm.Font = UiFont 9
    ThemeTitle
}
# ---- Layout / aparência ----
function ApplyWindowMode($target) {
    if ($S.Fullscreen) {
        $screenBounds=[Windows.Forms.Screen]::FromControl($target).Bounds
        if ($target.FormBorderStyle -ne 'None') {
            $script:WindowedBounds=$(if ($target.WindowState -eq 'Normal') {$target.Bounds} else {$target.RestoreBounds})
            $target.WindowState='Normal'; $target.FormBorderStyle='None'
        }
        $target.WindowState='Normal'; $target.Bounds=$screenBounds
    } else {
        if ($target.FormBorderStyle -eq 'None') {
            $target.WindowState='Normal'; $target.FormBorderStyle='Sizable'
            if ($script:WindowedBounds -and $script:WindowedBounds.Width -gt 0) { $target.Bounds=$script:WindowedBounds }
        }
        $target.WindowState=$(if ($S.Maximized) {'Maximized'} else {'Normal'})
    }
}
$form.Add_KeyDown({param($sender,$eventArgs)
    if ($eventArgs.KeyCode -eq 'F11' -and -not $eventArgs.Control -and -not $eventArgs.Alt) {
        $eventArgs.SuppressKeyPress=$true; $eventArgs.Handled=$true
        $S.Fullscreen=-not $S.Fullscreen; ApplyWindowMode $form
        if(Get-Command TarginoWindowSave -ErrorAction SilentlyContinue){TarginoWindowSave $form}
    }
})
function ApplyLayout {
    if(Get-Command TarginoEnforceIdentity -ErrorAction SilentlyContinue){TarginoEnforceIdentity}
    ApplyBranding
    FontsScan; LoadCfg; RebuildGfx; $c = $script:Cfg
    $form.Font = UiFont 9; $lt.Font = (MakeTitleFont)
    $form.BackColor = $c.Bg; $form.ForeColor = $c.Text; $mainP.BackColor = $c.Bg; $libP.BackColor = $c.Bg; $grid.BackColor = $c.Bg
    $right.BackColor = $c.DetailBg; $top.BackColor = $c.Bg; $row.BackColor = $c.DetailBg; $bot.BackColor = $c.Bg
    $form.Text = "$($S.Title)" + $(if ($script:Dev) { '  [DEV]' })
    ApplyWindowMode $form
    $q.Visible = [bool]$S.ShowSearch; $q.BackColor = $c.Side; $q.ForeColor = $c.Text
    $btnFil.BackColor = $c.Bg; $btnFil.ForeColor = $c.Text; $btnFil.FlatAppearance.MouseOverBackColor = $c.Bg; $btnFil.FlatAppearance.MouseDownBackColor = $c.Bg; $btnFil.FlatAppearance.BorderColor = $c.Bg; $fm.BackColor = $c.Side; $fm.ForeColor = $c.Text; $addm.BackColor = $c.Side; $addm.ForeColor = $c.Text
    $btnAdd.Visible = [bool]$script:Dev; $btnDev.Visible = [bool]$script:Dev
    $top.Visible = [bool]($S.ShowSearch -or $S.ShowFilter -or $script:Dev)
    $bot.Visible = [bool]$S.ShowZoom; $right.Visible = [bool]$S.ShowPanel
    foreach ($cl in $lt, $lst, $lver) { $cl.Hint = (TextHint $c.TextRender); $cl.Contrast = [int]$c.TextContrast; $cl.Invalidate() }
    $lt.Visible = [bool]$S.ShowTitle; $lt.ForeColor = $c.TitleCol
    $lt.Height = [Math]::Max(24, $lt.Font.Height * $c.TitleLines + 6)
    $lst.Font = UiFont $c.StatusSize $(switch ($c.StatusStyle) { 'Negrito' { 1 } 'Itálico' { 2 } 'Negrito + itálico' { 3 } default { 0 } }); $lst.Height = $lst.Font.Height + 6
    $lst.HAlign = [Drawing.StringAlignment]$(switch ($c.StatusAlign) { 'Centro' { 'Center' } 'Direita' { 'Far' } default { 'Near' } }); $lst.Margin = New-Object Windows.Forms.Padding(0, $c.StatusGapTop, 0, $c.StatusGapBottom); $lst.ForeColor = $c.StatusCol
    $lver.Font = UiFont $c.VersionSize; $lver.Height = $lver.Font.Height + 6
    $lt.HAlign = [Drawing.StringAlignment]$(switch ($c.TitleAlign) { 'Centro' { 'Center' } 'Direita' { 'Far' } default { 'Near' } })
    $right.Padding = New-Object Windows.Forms.Padding($c.DetailPad, $c.DetailPad, 5, 5)
    $btnFav.BackColor = $c.Side; $btnAdd.BackColor = $c.Side; $btnDev.BackColor = $c.Side
    FilBtnFit; TopCenter; HdrApply
    $lver.Visible = [bool]$S.ShowVersion; $lver.ForeColor = $c.VersionCol; $ld.BackColor = $c.DetailBg; $ld.ForeColor = $c.DescCol; $right.Width = $c.DetailW; $script:DescCfgSig = "$($c.DescFont)|$($c.DescSize)|$($c.DescTitle)|$($c.DescSubT)|$($c.DescLink.Name)|$($c.Text.Name)|$($c.Accent.Name)|$($S.FontFamily)|$($S.TextWeight)|$($c.DescCol.Name)|$($c.DescTitleCol.Name)|$($c.DescAlign)"; $script:DescLast = ''
    $zlab.Text = "$($S.T_Zoom)"
    $script:Lru.Budget = [long](CfgNum 'CoverCacheMB' 16 2048 96) * 1MB; $script:Lru.Trim([int]$script:Painter.Keep)
    EnsureFilter; FilterLabel; ThemeApply; CacheClear; Relayout
    RightLayout
    ShowGame (Sel)
    ApplyCinema
}
function ApplyCinema {
    if ($S.CinemaMode) {
        $right.Visible = $false; $vsb.Visible = $false; $bot.Visible = $false
        $libP.Dock = 'Bottom'; $libP.Height = $(if($script:HydraNavigationEnabled){354}else{330})
        $script:BackgroundPic.Dock = 'Fill'
        $script:BackgroundPic.Parent.Controls.SetChildIndex($script:BackgroundPic, 0)
        $script:BackgroundPic.Visible = $true
        $script:HeroTitle.Visible = $false
        $script:CinemaActions.Visible = $false
        $hdr.Visible = $true; $hdr.Height = 92
        $hdr.Controls.Add($script:AvatarPic); $script:AvatarPic.SetBounds(20,12,68,68)
        $script:AvatarPic.BringToFront()
    } else {
        $libP.Dock = 'Fill'; $vsb.Visible = $true
        $script:BackgroundPic.Dock = 'Top'; $script:BackgroundPic.Height = 280
        $script:HeroTitle.Visible = $false
        $script:CinemaActions.Visible = $false
        $script:BackgroundPic.Controls.Add($script:AvatarPic); $script:AvatarPic.SetBounds(14,14,84,84)
    }
    if(Get-Command BigPictureLayout -ErrorAction SilentlyContinue){BigPictureLayout}
    Relayout
}
function PaintCinema($gr) {
    if($script:BigPictureEnabled){PaintBigPicture $gr;return}
    DrawCinemaScene $gr $grid
    $script:CinemaHits = @()
    $n = $script:View.Count
    if (-not $script:Cfg) { return }
    if (-not $n) {
        if ($script:HydraNavigationEnabled) {
            $emptyFont=New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Regular)
            try {
                $message="Biblioteca vazia`nUse o menu Sistemas para escolher a pasta de ROMs.`nNa primeira execucao, prepare os cores no Hydra original."
                [Windows.Forms.TextRenderer]::DrawText($gr,$message,$emptyFont,(New-Object Drawing.Rectangle(30,35,($grid.Width-60),220)),[Drawing.Color]::Silver,([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,WordBreak,NoPrefix'))
            } finally {$emptyFont.Dispose()}
        }
        return
    }
    $selectedIndex = [Math]::Max(0,$script:CurIdx)
    if ($null -eq $script:CinemaPosition) { $script:CinemaPosition = [double]$selectedIndex }
    $center = [double]$script:CinemaPosition
    $cardScale=if($script:BigPictureEnabled){[Math]::Min(1.6,[Math]::Max(1,($grid.Height-112)/260.0))}else{1.0}
    $step = [int](168*$cardScale); $mid = [int]($grid.ClientSize.Width / 2)
    $reach = [int][Math]::Ceiling($grid.ClientSize.Width / $step / 2) + 1
    $font = New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
    $brush = New-Object Drawing.SolidBrush([Drawing.Color]::White)
    $pen = New-Object Drawing.Pen($script:Cfg.Accent,4)
    $fmt = New-Object Drawing.StringFormat
    $fmt.Alignment = 'Center'; $fmt.Trimming = 'EllipsisCharacter'
    try {
        for ($i=[int][Math]::Max(0,[Math]::Floor($center)-$reach); $i -le [Math]::Min($n-1,[Math]::Ceiling($center)+$reach); $i++) {
            $selected = $i -eq $selectedIndex
            $focus = [Math]::Max(0,1-[Math]::Abs($i-$center))
            $size = [int]((140+24*$focus)*$cardScale); $height = [int]((198+32*$focus)*$cardScale); $y = [int](36-32*$focus)
            $x = $mid + ($i-$center)*$step - [int]($size/2)
            $rect = New-Object Drawing.Rectangle($x,$y,$size,$height)
            $gm = $script:View[$i]
            # Um único tamanho de cache evita outra decodificação ao mudar o destaque.
            $fit=if($gm.HydraArt -or $gm.HydraKind -eq 'system'){'Ajustar'}else{$script:Cfg.Fit}
            $bmp = CoverGet (CoverPath $gm) $(if($script:BigPictureEnabled){280}else{176}) $fit
            $installed = ($gm.HydraKind -eq 'system' -or [bool]$script:Inst["$($gm.Id)"])
            $gray = -not $installed -and $script:Cfg.NotInst -in 'Preto e branco','Os dois'
            $dim = -not $installed -and $script:Cfg.NotInst -in 'Escurecida','Os dois'
            if ($bmp) {
                # Recorte central para formato vertical sem esticar a imagem.
                $sourceW = [single]($bmp.Height*$size/[double]$height)
                $sourceX = [single](($bmp.Width-$sourceW)/2)
                if ($gray) {
                    $gr.DrawImage($bmp,$rect,$sourceX,([single]0),$sourceW,([single]$bmp.Height),[Drawing.GraphicsUnit]::Pixel,$script:Gx.Gray)
                } else {
                    $gr.DrawImage($bmp,$rect,$sourceX,([single]0),$sourceW,([single]$bmp.Height),[Drawing.GraphicsUnit]::Pixel)
                }
                # Mantém o estado dos não instalados mesmo quando selecionados.
                if ($dim) { $gr.FillRectangle($script:Gx.Dim,$rect) }
                elseif ($installed -and $script:Cfg.DimInst -gt 0 -and -not ($selected -and $script:Cfg.SelBright)) { $gr.FillRectangle($script:Gx.DimI,$rect) }
            }
            else { $gr.FillRectangle($script:Gx.Ph,$rect) }
            if ($selected) {
                for ($glow=12; $glow -ge 4; $glow-=4) {
                    $glowPen = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(32,$script:Cfg.Accent)),([single]$glow))
                    try { $gr.DrawRectangle($glowPen,$rect) } finally { $glowPen.Dispose() }
                }
                $gr.DrawRectangle($pen,$rect)
            }
            $badgeParts = @()
            if ($gm.HydraKind -eq 'system') { $badgeParts += $gm.Version }
            if ($U.Fav -contains $gm.Id) { $badgeParts += '★ Favorito' }
            if ($badgeParts.Count) {
                $badgeRect = New-Object Drawing.Rectangle($x,($y+$height-24),$size,24)
                $badgeBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(215,8,16,25))
                try { $gr.FillRectangle($badgeBrush,$badgeRect) } finally { $badgeBrush.Dispose() }
                [Windows.Forms.TextRenderer]::DrawText($gr,($badgeParts -join ' · '),$font,$badgeRect,[Drawing.Color]::White,([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,EndEllipsis,SingleLine,NoPrefix'))
            }
            $textRect = New-Object Drawing.RectangleF($x,($y+$height+8),$size,42)
            $gr.DrawString("$($gm.Name)",$font,$brush,$textRect,$fmt)
            $script:CinemaHits += @{ Index=$i; Rect=$rect }
        }
        $script:CinemaFooterHits = @()
        $labels = @('Jogar [A/Enter]','Detalhes [X/D]','Filtros [Y/F]','Ações [Select]','Buscar [Select+Y]')
        if ($script:HydraNavigationEnabled) {
            if ($script:HydraHome) { $labels[0]='Abrir [A/Enter]' }
            $labels += 'Sistemas [B/Esc]'
        }
        $footW = [Math]::Min(1000,$grid.Width-30); $itemW=[int]($footW/$labels.Count)
        $startX=[int](($grid.Width-$footW)/2)
        for ($fi=0; $fi -lt $labels.Count; $fi++) {
            $fr=New-Object Drawing.Rectangle(($startX+$fi*$itemW),($grid.Height-32),$itemW,30)
            [Windows.Forms.TextRenderer]::DrawText($gr,$labels[$fi],$font,$fr,[Drawing.Color]::White,([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix'))
            $script:CinemaFooterHits += @{ Rect=$fr; Action=$fi }
        }
        if ($script:HydraArtStatus) {
            $statusRect=New-Object Drawing.Rectangle(16,($grid.Height-58),($grid.Width-32),20)
            [Windows.Forms.TextRenderer]::DrawText($gr,$script:HydraArtStatus,$font,$statusRect,[Drawing.Color]::Silver,([Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,SingleLine,NoPrefix'))
        }
        $gr.DrawString('‹',$font,$brush,(New-Object Drawing.RectangleF(4,100,24,40)),$fmt)
        $gr.DrawString('›',$font,$brush,(New-Object Drawing.RectangleF(($grid.Width-28),100,24,40)),$fmt)
    } finally { $font.Dispose(); $brush.Dispose(); $pen.Dispose(); $fmt.Dispose() }
}
# Índice do catálogo (ordena por nome e guarda nome/id/data em listas): só quando o catálogo muda, nunca na rolagem
# Últimas atualizações (v2.52.0): o filtro "recent" mostra os jogos adicionados E os atualizados nos últimos RecentDays dias.
#  "Atualizado" = a descrição mudou. O catálogo guarda a assinatura da descrição (DescSig); se ela não bater mais, o jogo
#  ganha Updated = hoje. 1ª vez (sem DescSig) só registra, sem marcar. Como tudo fica no catalogo.json, a data viaja no
#  UpdateWinPort: quem recebe a atualização vê a mesma data do desenvolvedor (as assinaturas já chegam batendo).
#  Data usada no filtro = a mais nova entre Added e Updated.
function CatIndex {
    $cnt0 = @($script:Games).Count
    $nms = New-Object string[] $cnt0; $gids = New-Object string[] $cnt0; $ads = New-Object string[] $cnt0
    $dss = New-Object string[] $cnt0; $sgs = New-Object string[] $cnt0
    $arr = [object[]]@($script:Games)
    for ($k1 = 0; $k1 -lt $cnt0; $k1++) {
        $gm = $arr[$k1]; $nms[$k1] = "$($gm.Name)"; $gids[$k1] = "$($gm.Id)"; $dss[$k1] = "$($gm.Desc)"; $sgs[$k1] = "$($gm.DescSig)"
        $ad = "$($gm.Added)"; $up = "$($gm.Updated)"; if ($up -gt $ad) { $ad = $up }; $ads[$k1] = $ad
    }
    $nsg = $null; $chg = [ViewIx]::DescDiff($dss, $sgs, [ref]$nsg)
    if ($chg.Count -and -not $script:CatBroken) {
        $today = Get-Date -Format 'yyyy-MM-dd'; $upd = New-Object Collections.Generic.List[string]
        foreach ($k2 in $chg) {
            $gm = $arr[$k2]
            if ($sgs[$k2]) { $gm | Add-Member NoteProperty Updated $today -Force; $ads[$k2] = $today; $upd.Add("$($gm.Name)") }
            $gm | Add-Member NoteProperty DescSig $nsg[$k2] -Force
        }
        $muSt = $false; if ($script:MassUndo) { try { $muSt = ((New-Object IO.FileInfo $Db).LastWriteTimeUtc.Ticks -eq $script:MassUndoStamp) } catch { $Error.Clear() } }
        Save
        if ($muSt) { try { $script:MassUndoStamp = (New-Object IO.FileInfo $Db).LastWriteTimeUtc.Ticks } catch { $Error.Clear() } }      # esta gravação faz parte da própria edição em massa: o "Desfazer" não deve avisar de alteração posterior
        if ($upd.Count) { Log 'INFO' ("Descrição alterada em $($upd.Count) jogo(s), marcado(s) como atualizado(s): " + (($upd | Select-Object -First 10) -join '; ') + $(if ($upd.Count -gt 10) { '; ...' } else { '' })) }
        else { Log 'INFO' "Assinatura da descrição registrada em $($chg.Count) jogo(s) (sem marcar como atualizado)" }
    }
    $ord = [ViewIx]::SortOrder($nms)
    $script:Games = [ViewIx]::Reorder($arr, $ord)
    $script:Ix = @{ Games = $script:Games; Ids = [ViewIx]::ReorderS($gids, $ord); Names = [ViewIx]::ReorderS($nms, $ord); Added = [ViewIx]::ParseDates([ViewIx]::ReorderS($ads, $ord)) }
}
function CatRefresh {   # catálogo mudou: ordena/indexa, confere as pastas de imagens e o estado de instalação dos jogos novos/editados
    $sw = [Diagnostics.Stopwatch]::StartNew()
    CatIndex
    if (-not $script:Ready) { InstLoadCache; ImgLoadDisk }
    [void](ImgEnsureAll $false)
    [void](InstCheckStale)
    $script:CoverFail.Clear()      # o cache de capas fica: as chaves mudam sozinhas se o arquivo da capa mudar
    if (-not $script:Ready) {
        $cn = InstCounts
        Log 'INFO' "Catálogo: $($script:Games.Count) jogo(s), $($cn[0]) não instalado(s) pelo último estado conhecido (carregado em $($sw.ElapsedMilliseconds) ms)"
    }
}
function Relayout {   # recalcula a geometria da grade (janela redimensionada, zoom, layout, lista nova)
    $c = $script:Cfg; if (-not $c -or -not $script:Gx) { return }
    $z = [Math]::Min(3, [Math]::Max(1, [int]$zm.Value)); $cover = $c.Sizes[$z - 1]
    $script:Gx.InitFont.Dispose(); $script:Gx.InitFont = UiFont ([Math]::Max(10, $cover / 3.0)) 1
    $nameH = 0; if ($c.NameLines -gt 0) { $nameH = $script:Gx.NameFont.Height * $c.NameLines + 2 }
    $selExt = 0; if ($c.SelW -gt 0) { $selExt = $c.SelW + $c.SelGap }
    $script:Met = GridMetrics $grid.ClientSize.Width $script:View.Count $cover $c.GapH $c.GapV $c.PadX $c.PadY $selExt $nameH $c.NameGap $c.Center
    UpdateScroll
    $grid.Invalidate()
}
function UpdateScroll {
    $met = $script:Met; if (-not $met) { return }
    $viewH = [Math]::Max(1, $grid.ClientSize.Height); $total = $met.TotalH
    try {
        $vsb.Minimum = 0; $vsb.Maximum = [Math]::Max($total, $viewH); $vsb.LargeChange = $viewH; $vsb.SmallChange = [Math]::Max(1, [int]($met.CellH / 3))
        $maxV = [Math]::Max(0, $total - $viewH)
        if ($vsb.Value -gt $maxV) { $vsb.Value = $maxV }
        $vsb.Enabled = ($total -gt $viewH)
    } catch { LogEx 'AVISO' "Falha ao ajustar a rolagem: $($_.Exception.Message)" $_ }
}
function Populate {
    if (-not $script:Cfg) { LoadCfg }
    $prevId = $null; if ($script:Cur) { $prevId = "$($script:Cur.Id)" }
    $fs = New-Object 'System.Collections.Generic.HashSet[string]'; foreach ($fid in $U.Fav) { [void]$fs.Add("$fid") }; $script:FavSet = $fs
    $cutoff = (Get-Date).Date.AddDays(-$script:Cfg.RecentDays)
    $swf = [Diagnostics.Stopwatch]::StartNew()
    if (-not $script:Ix -or -not [object]::ReferenceEquals($script:Ix.Games, $script:Games)) { CatIndex }      # catálogo trocado sem CatRefresh: refaz o índice
    $cn = New-Object int[] 5; $vids = $null; $kix = [Array]::IndexOf(@('all', 'recent', 'fav', 'inst', 'notinst'), "$script:Filter"); if ($kix -lt 0) { $kix = 0 }
    $sourceIx=if($script:HydraNavigationEnabled){HydraScopedIndex}else{$script:Ix}
    $script:View = [ViewIx]::Filter($sourceIx.Games, $sourceIx.Ids, $sourceIx.Names, $sourceIx.Added, $fs, $script:Inst, $kix, "$($q.Text)", $cutoff.Ticks, $cn, [ref]$vids)
    if ($script:HydraNavigationEnabled -and $script:HydraHome) {
        $script:View=[object[]]@($script:HydraSystemCards | Where-Object {-not $q.Text -or $_.Name.IndexOf($q.Text,[StringComparison]::OrdinalIgnoreCase) -ge 0})
        $vids=[string[]]@($script:View | ForEach-Object {$_.Id})
    }
    $script:FilCounts = @{ all = $cn[0]; recent = $cn[1]; fav = $cn[2]; inst = $cn[3]; notinst = $cn[4] }
    # mantém a seleção só dos jogos que continuam na lista
    $ci = -1; $script:SelIds = [ViewIx]::Keep($vids, $script:SelIds, $prevId, [ref]$ci); $script:ViewIds = $vids
    $script:CurIdx = $ci; $script:Cur = $(if ($ci -ge 0) { $script:View[$ci] } else { $null })
    if ($S.CinemaMode) {
        $script:CinemaPosition = [double][Math]::Max(0,$ci)
        if ($script:HeroTitle) { $script:HeroTitle.Text = $(if ($script:Cur) { "$($script:Cur.Name)" } else { "$($S.T_Empty)" }) }
    }
    PerfAdd 'Filtro' $swf.Elapsed.TotalMilliseconds
    FilterLabel
    Relayout
    if ($script:CurIdx -ge 0) { EnsureVisible $script:CurIdx }
    ShowGame (Sel)
}

# ---- Seleção e navegação ----
function SelectIdx($i, $mode) {
    $n = $script:View.Count; if ($i -lt 0 -or $i -ge $n) { return }
    $g = $script:View[$i]; $id = "$($g.Id)"
    if (-not $script:Dev) { $mode = 'single' }      # seleção múltipla (Ctrl/Shift) só no modo desenvolvedor
    if ($mode -eq 'toggle') {
        if ($script:SelIds.Contains($id)) { [void]$script:SelIds.Remove($id) } else { [void]$script:SelIds.Add($id) }
        $script:Anchor = $i
    } elseif ($mode -eq 'range') {
        $a = $script:Anchor; if ($a -lt 0) { $a = $i }
        $script:SelIds.Clear()
        for ($j = [Math]::Min($a, $i); $j -le [Math]::Max($a, $i); $j++) { [void]$script:SelIds.Add("$($script:View[$j].Id)") }
    } else {
        $script:SelIds.Clear(); [void]$script:SelIds.Add($id); $script:Anchor = $i
    }
    $script:Cur = $g; $script:CurIdx = $i
    if($script:BigPictureEnabled){$grid.Invalidate()}
    if ($S.CinemaMode -and -not $S.CinemaAnimate) { $script:CinemaPosition = [double]$i }
    if ($script:HeroTitle) { $script:HeroTitle.Text = "$($g.Name)" }
    ShowGame $g; $grid.Invalidate()
}
function EnsureVisible($i) {
    if ($S.CinemaMode) { $grid.Invalidate(); return }
    $met = $script:Met; if (-not $met -or $i -lt 0) { return }
    $xy = TileXY $met $i; $v = [int]$vsb.Value; $h = $grid.ClientSize.Height; $nv = $v
    if ($xy[1] - $met.PadY -lt $v) { $nv = $xy[1] - $met.PadY } elseif ($xy[1] + $met.TileH + $met.PadY -gt $v + $h) { $nv = $xy[1] + $met.TileH + $met.PadY - $h }
    $nv = [Math]::Max(0, [Math]::Min($nv, [Math]::Max(0, $met.TotalH - $h)))
    if ($nv -ne $v) { $vsb.Value = $nv }
}
function HitAt($x, $y) {
    if ($S.CinemaMode) {
        foreach ($item in $script:CinemaHits) { if ($item.Rect.Contains([int]$x,[int]$y)) { return $item.Index } }
        return -1
    }
    if (-not $script:Met) { return -1 }
    GridHit $script:Met $x ($y + [int]$vsb.Value) $script:View.Count
}

# ---- Desenho da grade de capas: o laço por capa roda no GridPainter (C#); o PowerShell só preenche nome/caminho da capa de
#  jogos que entram na tela pela primeira vez e desenha os que estão extraindo ou abertos (animação, PaintTile).
function PaintGrid($gr) {
    if ($S.CinemaMode) { PaintCinema $gr; return }
    $c = $script:Cfg; $gx = $script:Gx; $met = $script:Met
    if ($c -and $gx -and $met) { PaintGridFast $gr $c $gx $met $script:Painter }
}
# Um quadrado da grade (capa, véus, sinais, borda e nome). x/y = canto da célula já na tela.
function PaintTile($gr, $c, $gx, $met, $i, $x, $y, $gray, $dim) {
    $g = $script:View[$i]; $id = "$($g.Id)"; $cover = $met.Cover
    $cx = $x + $met.SelExt; $cy = $y + $met.SelExt
    $ex = $script:Ext[$id]; $prog = [bool]($ex -and ($ex.Phase -eq 'list' -or $ex.Phase -eq 'run'))      # extraindo: capa volta a ser escura e vai ganhando cor
    $inst = ([bool]$script:Inst[$id] -and -not $prog)
    $rect = New-Object Drawing.Rectangle $cx, $cy, $cover, $cover
    # --- capa ---
    $bmp = CoverGet (CoverPath $g) $cover $c.Fit
    if ($bmp) {
        if (-not $inst -and ($gray -or $prog)) { $gr.DrawImage($bmp, $rect, 0, 0, $bmp.Width, $bmp.Height, [Drawing.GraphicsUnit]::Pixel, $gx.Gray) }
        else { $gr.DrawImage($bmp, $rect) }
    } else {
        $gr.FillRectangle($gx.Ph, $rect)
        $ini = "$($g.Name)".Trim(); if ($ini.Length) { $gr.DrawString($ini.Substring(0, 1).ToUpper(), $gx.InitFont, $gx.PhText, (New-Object Drawing.RectangleF $cx, $cy, $cover, $cover), $gx.FmtC) }
    }
    $bright = ($c.SelBright -and $script:SelIds.Contains($id))      # capa selecionada: sem escurecimento (só a extração em andamento mantém o seu)
    if (-not $inst -and $dim) { if ($prog -or -not $bright) { $gr.FillRectangle($gx.Dim, $rect) } }
    elseif ($prog) { $gr.FillRectangle($gx.Dim2, $rect) }
    elseif ($inst -and $c.DimInst -gt 0 -and -not $bright) { $gr.FillRectangle($gx.DimI, $rect) }
    if ($prog) { PaintProgress $gr $gx $ex $rect $bmp; if ($met.NameH -le 0) { PaintBandLabel $gr $c $gx $rect (ExtLabel $id) } }
    elseif ($ex) { PaintExtMark $gr $c $ex $rect }
    $pl = $null; if (-not $prog) { $pl = $script:Play[$id]; if ($pl) { PaintPlaying $gr $c $gx $pl $rect $met } }   # jogo aberto (v2.36.0)
    if ($script:InstState[$id] -eq 'offline') {      # unidade desconectada: bolinha discreta no canto (o resto fica como no último estado conhecido)
        $gr.FillEllipse($gx.Sub, [single]($cx + $cover - 14), [single]($cy + 4), [single]10, [single]10)
    }
    # --- borda de seleção (a capa continua visível; nada é pintado por cima dela) ---
    if ($script:SelIds.Contains($id)) {
        if ($c.SelW -gt 0) {
            $ext = $c.SelGap + $c.SelW / 2.0
            $gr.DrawRectangle($gx.Sel, [single]($cx - $ext), [single]($cy - $ext), [single]($cover + 2 * $ext), [single]($cover + 2 * $ext))
        }
    } elseif ($i -eq $script:Hover) {
        $ext = [Math]::Max(1, $c.SelGap) + 0.5
        $gr.DrawRectangle($gx.Hover, [single]($cx - $ext), [single]($cy - $ext), [single]($cover + 2 * $ext), [single]($cover + 2 * $ext))
    }
    # --- nome embaixo ---
    if ($met.NameH -gt 0) {
        $txt = "$(if ($script:FavSet.Contains($id)) { '★ ' })$($g.Name)"
        $tr = New-Object Drawing.RectangleF ([single]$x), ([single]($cy + $cover + $met.SelExt + $met.NameGap)), ([single]$met.TileW), ([single]$met.NameH)
        if ($prog) { PaintPlayLabel $gr $c $gx $null $tr $false (ExtLabel $id) }      # extraindo: bolinha + "Extraindo seu jogo" no lugar do nome (v2.48.0)
        elseif ($pl) { PaintPlayLabel $gr $c $gx $pl $tr $false }      # jogo aberto: bolinha + "Em execução" no lugar do nome (v2.37.0)
        else {
            $brush = $gx.Text; if (-not $inst) { $brush = $gx.Sub }
            $gr.DrawString($txt, $gx.NameFont, $brush, $tr, $gx.Fmt)
        }
    }
}
# Passa aparência/geometria para o GridPainter só quando mudam (mesmos objetos = nada a fazer)
function PtSync($pt, $c, $gx, $met) {
    if ([object]::ReferenceEquals($script:PtGx, $gx) -and [object]::ReferenceEquals($script:PtMet, $met) -and [object]::ReferenceEquals($script:PtCfg, $c)) { return }
    $pt.Bg = $c.Bg; $pt.Text = $gx.Text; $pt.Sub = $gx.Sub; $pt.Dim = $gx.Dim; $pt.DimI = $gx.DimI; $pt.Ph = $gx.Ph; $pt.PhText = $gx.PhText
    $pt.Sel = $gx.Sel; $pt.Hover = $gx.Hover; $pt.NameFont = $gx.NameFont; $pt.InitFont = $gx.InitFont; $pt.Fmt = $gx.Fmt; $pt.FmtC = $gx.FmtC; $pt.Gray = $gx.Gray
    $pt.GrayNotInst = [bool]($c.NotInst -eq 'Preto e branco' -or $c.NotInst -eq 'Os dois')
    $pt.DimNotInst = [bool](($c.NotInst -eq 'Escurecida' -or $c.NotInst -eq 'Os dois') -and $c.Dim -gt 0)
    $pt.SelBright = [bool]$c.SelBright; $pt.DimInstPct = [int]$c.DimInst; $pt.SelW = [int]$c.SelW; $pt.SelGap = [int]$c.SelGap
    $pt.Contrast = [int]$c.TextContrast; $pt.Hint = (TextHint $c.TextRender); $pt.Fit = "$($c.Fit)"
    $pt.Cols = [int]$met.Cols; $pt.Rows = [int]$met.Rows; $pt.CellW = [int]$met.CellW; $pt.CellH = [int]$met.CellH; $pt.TileW = [int]$met.TileW
    $pt.OffX = [int]$met.OffX; $pt.PadY = [int]$met.PadY; $pt.SelExt = [int]$met.SelExt; $pt.Cover = [int]$met.Cover; $pt.NameH = [int]$met.NameH; $pt.NameGap = [int]$met.NameGap
    $pt.PrefetchRows = CfgNum 'CoverPrefetchRows' 0 10 2
    $script:PtGx = $gx; $script:PtMet = $met; $script:PtCfg = $c
}
function PaintGridFast($gr, $c, $gx, $met, $pt) {
    PtSync $pt $c $gx $met
    if (-not [object]::ReferenceEquals($script:PtView, $script:View)) { $pt.SetView([string[]]$script:ViewIds); $script:PtView = $script:View; $script:PtImgGen = $script:ImgGen }
    elseif ($script:PtImgGen -ne $script:ImgGen) { $pt.ResetPaths(); $script:PtImgGen = $script:ImgGen }      # pasta/índice de imagens mudou
    $vOff = [int]$vsb.Value; $viewH = $grid.ClientSize.Height
    $pt.Gen = [int]$script:CoverGen
    if ($script:Loader.Pending -gt 0) {      # recolhe as capas prontas aqui também: arrastando a barra, o timer quase não tem vez
        $fl = New-Object 'System.Collections.Generic.List[CoverLoader+Res]'
        [void]$pt.Drain($vOff, 4, $fl)
        foreach ($rs in $fl) { CoverWarn $rs.Path $(if ($rs.Missing) { 'arquivo não encontrado' } else { "$($rs.Error)" }) }
    }
    $need = $pt.NeedFill($vOff, $viewH)      # só jogos que entram na tela (ou na margem) pela primeira vez
    if ($need.Length) { $vw = $script:View; foreach ($ni in $need) { $gm = $vw[$ni]; $pt.Names[$ni] = "$($gm.Name)"; $pt.Paths[$ni] = "$(CoverPath $gm)" } }
    $pt.Gen = [int]$script:CoverGen; $pt.HoverIdx = [int]$script:Hover; $pt.EmptyText = "$($S.T_Empty)"
    $pt.Inst = $script:Inst; $pt.InstState = $script:InstState; $pt.SelIds = $script:SelIds; $pt.FavSet = $script:FavSet
    $pt.ExtIds = $null
    if ($script:Ext.Count -or $script:Play.Count) {      # extraindo/sinal de concluído/jogo aberto: desenhados em PowerShell
        $es = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($ek in $script:Ext.Keys) { [void]$es.Add("$ek") }; foreach ($ek in $script:Play.Keys) { [void]$es.Add("$ek") }
        $pt.ExtIds = $es
    }
    $spec = $pt.Paint($gr, $vOff, $grid.ClientSize.Width, $viewH)
    if ($spec.Length) {      # extraindo / sinal de concluído: desenhados aqui, com a animação de sempre
        $gray = [bool]$pt.GrayNotInst; $dim = [bool]$pt.DimNotInst
        foreach ($si in $spec) {
            $x = $met.OffX + ($si % $met.Cols) * $met.CellW; $y = $met.PadY + [int][Math]::Floor($si / $met.Cols) * $met.CellH - $vOff
            PaintTile $gr $c $gx $met $si $x $y $gray $dim
        }
    }
    if ($pt.Wait -or $script:Loader.Pending -gt 0) { $loadTm.Start() }
}
# ---- Cadastro de jogos (só no modo desenvolvedor) ----
function RemoveGame($g) {
    if (-not $g -or [Windows.Forms.MessageBox]::Show("Remover '$($g.Name)' da lista?", 'Confirmar', 'YesNo') -ne 'Yes') { return }
    [void](Backup $Db 'antes-remover')
    $script:Games = @($script:Games | Where-Object { $_ -ne $g }); Save; Log 'INFO' "Jogo removido do catálogo: '$($g.Name)' ($($g.Id))"
    CatRefresh; Populate
}
# Prévia ao vivo (editor de jogo): janela ao lado do editor que se atualiza enquanto se digita (v2.33.0)
function DescPreviewLive($owner, $st) {
    if ($st.Pf -and -not $st.Pf.IsDisposed) { $st.Pf.Activate(); return }
    $pvBg = $script:Cfg.DetailBg; if (-not $pvBg) { $pvBg = $script:Cfg.Bg }
    $pf = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = $(if ($st.Title) { "$($st.Title) (ao vivo)" } else { 'Prévia da descrição (ao vivo)' }); Size = '480,620'; StartPosition = 'Manual'; BackColor = $pvBg; ShowInTaskbar = $false }
    WinSizable $pf 'PreviaDescricao' 280 220
    try { $pf.ClientSize = New-Object Drawing.Size(([int]$script:Cfg.DetailW + 24), 600) } catch { $Error.Clear() }   # mesma largura do painel de detalhes = mesmas quebras de linha
    $pr = New-Object DescBox -Property @{ Dock = 'Fill'; ReadOnly = $true; BorderStyle = 'None'; ScrollBars = 'Vertical'; DetectUrls = $false; BackColor = $pvBg; ForeColor = $script:Cfg.Text }
    $pn = New-Object Windows.Forms.Panel -Property @{ Dock = 'Fill'; Padding = (New-Object Windows.Forms.Padding(12)); BackColor = $pvBg }
    $pn.Controls.Add($pr); $pf.Controls.Add($pn); DescAttach $pr
    $pf.Tag = @{ Rtb = $pr; Owner = $owner }
    $pf.Add_Load({ param($snd, $ev)   # depois do WinRestore: encosta à direita do editor (ou à esquerda, se não couber)
        try {
            $ow = $snd.Tag.Owner; $wa = [Windows.Forms.Screen]::FromControl($ow).WorkingArea
            $x = $ow.Right + 4; if ($x + $snd.Width -gt $wa.Right) { $x = $ow.Left - $snd.Width - 4 }
            $x = [Math]::Max($wa.X, [Math]::Min($x, $wa.Right - $snd.Width)); $y = [Math]::Max($wa.Y, [Math]::Min($ow.Top, $wa.Bottom - $snd.Height))
            if ($snd.WindowState -eq 'Normal') { $snd.Location = New-Object Drawing.Point($x, $y) }
        } catch { $Error.Clear() }
    })
    $st.Pf = $pf
    DescPreviewRender $st
    $pf.Show($owner)
}
function DescPreviewRender($st) {
    $pf = $st.Pf; if (-not $pf -or $pf.IsDisposed) { return }
    $pr = $pf.Tag.Rtb
    try {
        $txt = $st.Src.Text
        if ($st.Row) {   # editar em massa: aplica o modo escolhido na descrição do 1º jogo selecionado
            $txt = "$($st.Game.Desc)"
            if ($st.Row.Cb.Checked) { $txt = MassValue $txt "$($st.Row.Cmb.SelectedItem)" $st.Row.A.Text $st.Row.B.Text }
        }
        $pr.SuspendLayout(); DescRender $pr (DescParse $txt) (DescCfg); $pr.ResumeLayout()
    } catch { LogEx 'AVISO' "Prévia da descrição falhou: $($_.Exception.Message)" $_ }
}
# ---- Janela de um extra (usada no editor de jogo) ----
function XeRel($xeFull, $xeExeText) {   # caminho escolhido no seletor: dentro da pasta do jogo vira {JogoDir}\..., senão relativo ao launcher
    $xeGd = XeDirOfExe (Full $xeExeText); $xeSep = [string][IO.Path]::DirectorySeparatorChar
    if ($xeGd -and $xeFull -ieq $xeGd) { return '{JogoDir}' }
    if ($xeGd -and $xeFull.StartsWith($xeGd + $xeSep, 'OrdinalIgnoreCase')) { return '{JogoDir}' + $xeFull.Substring($xeGd.Length) }
    Short $xeFull
}
function XeStartDir($xeCur, $xeExeText) {   # pasta inicial dos seletores: a do caminho atual, senão a do jogo, senão Jogos\
    $xeTry = @()
    if ("$xeCur".Trim()) { $xeF = Full ("$xeCur" -replace '(?i)\{JogoDir\}', (XeDirOfExe (Full $xeExeText)).Replace('$', '$$')); if ($xeF) { $xeTry += $xeF; try { $xeTry += [IO.Path]::GetDirectoryName($xeF) } catch { $Error.Clear() } } }
    $xeTry += (XeDirOfExe (Full $xeExeText)); $xeTry += [IO.Path]::Combine($Root, 'Jogos'); $xeTry += $Root
    foreach ($xeD in $xeTry) { if ($xeD -and [IO.Directory]::Exists($xeD)) { return $xeD } }
    $Root
}
function XeSetPicked($xeTb, $xePicked, $xeExeText) {   # só aceita o que está dentro da pasta do launcher
    if (-not (InRoot $xePicked)) { [void][Windows.Forms.MessageBox]::Show("Escolha algo de dentro da pasta do launcher:`n$Root", 'Fora da pasta do launcher'); return }
    $xeTb.Text = XeRel $xePicked $xeExeText
}
function XePickFile($xeTb, $xeExeText, $xeFilter) {
    $xeDlg = New-Object Windows.Forms.OpenFileDialog -Property @{ Filter = $xeFilter; InitialDirectory = (XeStartDir $xeTb.Text $xeExeText) }
    if ($xeDlg.ShowDialog() -eq 'OK') { XeSetPicked $xeTb $xeDlg.FileName $xeExeText }
    $xeDlg.Dispose()
}
function XePickDir($xeTb, $xeExeText) {
    $xeDlg = New-Object Windows.Forms.FolderBrowserDialog -Property @{ SelectedPath = (XeStartDir $xeTb.Text $xeExeText); ShowNewFolderButton = $true }
    if ($xeDlg.ShowDialog() -eq 'OK') { XeSetPicked $xeTb $xeDlg.SelectedPath $xeExeText }
    $xeDlg.Dispose()
}
function ExtraDialog($xeIn, $xeExeText) {
    $xe = @{ Name = ''; Path = ''; Args = ''; Dest = ''; After = '' }; if ($xeIn) { foreach ($xeK in @($xeIn.Keys)) { $xe[$xeK] = "$($xeIn[$xeK])" } }
    $xd = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = 'Extra do jogo'; StartPosition = 'CenterParent' }
    WinSizable $xd 'ExtraJogo' 620 420; $xd.ClientSize = New-Object Drawing.Size(600, 392)
    $xeAll = 'Todos|*.*|Programas|*.exe;*.bat;*.cmd;*.ps1;*.lnk|Documentos|*.pdf;*.txt;*.htm;*.html;*.doc;*.docx|Imagens|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp|Arquivo RAR|*.rar'
    $xd.Controls.Add((Lbl 'Nome no menu' 10 18 135 20))
    $xeName = New-Object Windows.Forms.TextBox -Property @{ Left = 150; Top = 15; Width = 438; Text = $xe.Name; Anchor = 'Top, Left, Right' }
    $xd.Controls.Add((Lbl 'Abrir' 10 50 135 20))
    $xePath = New-Object Windows.Forms.TextBox -Property @{ Left = 150; Top = 47; Width = 300; Text = $xe.Path; Anchor = 'Top, Left, Right' }
    $xeBf = New-Object Windows.Forms.Button -Property @{ Text = 'Arquivo...'; Left = 455; Top = 46; Width = 70; Anchor = 'Top, Right'; Tag = @($xePath, $xeAll) }
    $xeBd = New-Object Windows.Forms.Button -Property @{ Text = 'Pasta...'; Left = 528; Top = 46; Width = 60; Anchor = 'Top, Right'; Tag = $xePath }
    $xd.Controls.Add((Lbl 'Argumentos' 10 82 135 20))
    $xeArgs = New-Object Windows.Forms.TextBox -Property @{ Left = 150; Top = 79; Width = 438; Text = $xe.Args; Anchor = 'Top, Left, Right' }
    $xeH = Lbl 'Se for um arquivo .rar (extrai e NÃO apaga o .rar):' 10 120 560 20; $xeH.Font = New-Object Drawing.Font($xeH.Font, [Drawing.FontStyle]::Bold)
    $xd.Controls.Add((Lbl 'Extrair em' 10 150 135 20))
    $xeDest = New-Object Windows.Forms.TextBox -Property @{ Left = 150; Top = 147; Width = 360; Text = $xe.Dest; Anchor = 'Top, Left, Right' }
    $xeBdd = New-Object Windows.Forms.Button -Property @{ Text = 'Pasta...'; Left = 518; Top = 146; Width = 70; Anchor = 'Top, Right'; Tag = $xeDest }
    $xeHd = Lbl 'Vazio = pasta do jogo. Arquivos com o mesmo nome são substituídos.' 150 172 440 18; $xeHd.ForeColor = 'Gray'
    $xd.Controls.Add((Lbl 'Depois de extrair' 10 200 135 20))
    $xeCmb = New-Object Windows.Forms.ComboBox -Property @{ DropDownStyle = 'DropDownList'; Left = 150; Top = 197; Width = 150 }
    [void]$xeCmb.Items.AddRange([object[]]@('Abrir o jogo', 'Não abrir nada', 'Abrir outro:'))
    $xeAft = New-Object Windows.Forms.TextBox -Property @{ Left = 305; Top = 197; Width = 218; Anchor = 'Top, Left, Right' }
    $xeBa = New-Object Windows.Forms.Button -Property @{ Text = '...'; Left = 528; Top = 196; Width = 60; Anchor = 'Top, Right'; Tag = @($xeAft, $xeAll) }
    if (-not $xe.After) { $xeCmb.SelectedIndex = 0 } elseif ($xe.After -eq '-') { $xeCmb.SelectedIndex = 1 } else { $xeCmb.SelectedIndex = 2; $xeAft.Text = $xe.After }
    $xeCmb.Tag = @($xeAft, $xeBa)
    $xeCmb.Add_SelectedIndexChanged({ param($snd, $ev) $xeOn = ($snd.SelectedIndex -eq 2); $snd.Tag[0].Enabled = $xeOn; $snd.Tag[1].Enabled = $xeOn })
    $xeAft.Enabled = ($xeCmb.SelectedIndex -eq 2); $xeBa.Enabled = $xeAft.Enabled
    $xeHint = Lbl ('Abrir: programa (.exe), PDF, imagem, qualquer arquivo, pasta ou site (https://). Para .rar em várias partes, escolha a primeira (.part1.rar). ' +
                   'Caminhos sem raiz são relativos à pasta do launcher; {JogoDir} = pasta do jogo (o seletor já usa isso quando o arquivo está dentro dela). ' +
                   'Também aceita {JogosDir}, {LauncherDir} e {TarginoRetroStationDir}. Nada pode ficar fora da pasta do launcher. Argumentos: só para programas.') 10 235 578 100
    $xeHint.ForeColor = 'Gray'; $xeHint.Anchor = 'Top, Bottom, Left, Right'; $xeH.Anchor = 'Top, Left, Right'; $xeHd.Anchor = 'Top, Left, Right'
    $xeOk = New-Object Windows.Forms.Button -Property @{ Text = 'Salvar'; Left = 412; Top = 352; Width = 85; Height = 28; DialogResult = 'OK'; Anchor = 'Bottom, Right' }
    $xeCa = New-Object Windows.Forms.Button -Property @{ Text = 'Cancelar'; Left = 503; Top = 352; Width = 85; Height = 28; DialogResult = 'Cancel'; Anchor = 'Bottom, Right' }
    $xd.Tag = $xeExeText
    foreach ($xeB in $xeBf, $xeBa) { $xeB.Add_Click({ param($snd, $ev) XePickFile $snd.Tag[0] $snd.FindForm().Tag $snd.Tag[1] }) }
    foreach ($xeB in $xeBd, $xeBdd) { $xeB.Add_Click({ param($snd, $ev) XePickDir $snd.Tag $snd.FindForm().Tag }) }
    $xd.Controls.AddRange(@($xeName, $xePath, $xeBf, $xeBd, $xeArgs, $xeH, $xeDest, $xeBdd, $xeHd, $xeCmb, $xeAft, $xeBa, $xeHint, $xeOk, $xeCa))
    $xd.AcceptButton = $xeOk; $xd.CancelButton = $xeCa
    $xeRes = $null
    while ($xd.ShowDialog() -eq 'OK') {
        $xeN = ($xeName.Text -replace '[\|\r\n]', ' ').Trim(); $xeP = ($xePath.Text -replace '[\|\r\n]', ' ').Trim()
        if (-not $xeN -or -not $xeP) { [void][Windows.Forms.MessageBox]::Show('Preencha o nome e o que abrir.', 'Extra do jogo'); continue }
        if ($xeCmb.SelectedIndex -eq 2 -and -not $xeAft.Text.Trim()) { [void][Windows.Forms.MessageBox]::Show('Informe o que abrir depois de extrair (ou escolha outra opção).', 'Extra do jogo'); continue }
        $xeAf = switch ($xeCmb.SelectedIndex) { 1 { '-' } 2 { ($xeAft.Text -replace '[\|\r\n]', ' ').Trim() } default { '' } }
        $xeRes = @{ Name = $xeN; Path = $xeP; Args = ($xeArgs.Text -replace '[\|\r\n]', ' ').Trim(); Dest = ($xeDest.Text -replace '[\|\r\n]', ' ').Trim(); After = $xeAf }
        break
    }
    $xd.Dispose(); $xeRes
}
function XeItemSet($xeIt, $xe) {
    $xeIt.Text = "$($xe.Name)"; $xeIt.Tag = $xe
    $xeDesc = "$($xe.Path)"; if ($xeDesc.EndsWith('.rar', 'OrdinalIgnoreCase')) { $xeDesc = "extrair $xeDesc" }
    while ($xeIt.SubItems.Count -lt 2) { [void]$xeIt.SubItems.Add('') }
    $xeIt.SubItems[1].Text = $xeDesc
}
function XeListBox($xeForm, $xeY, $xeTxt, $xeExeTb) {   # lista de extras + botões, dentro do editor de jogo; devolve a ListView
    $xeForm.Controls.Add((Lbl 'Extras (menu do botão direito)' 10 ($xeY + 3) 130 36))
    $xeLv = New-Object Windows.Forms.ListView -Property @{ View = 'Details'; FullRowSelect = $true; HideSelection = $false; MultiSelect = $false; HeaderStyle = 'Nonclickable' }
    $xeLv.SetBounds(145, $xeY, 335, 124)
    [void]$xeLv.Columns.Add('Nome', 120); [void]$xeLv.Columns.Add('Abre', 205)
    foreach ($xe in (ExtrasParse $xeTxt)) { $xeIt = New-Object Windows.Forms.ListViewItem; XeItemSet $xeIt $xe; [void]$xeLv.Items.Add($xeIt) }
    $xeLv.Tag = $xeExeTb
    $xeForm.Controls.Add($xeLv)
    $xeBtns = @(
        @('Novo', { param($snd, $ev) $xeV = $snd.Tag; $xeR = ExtraDialog $null $xeV.Tag.Text; if ($xeR) { $xeIt = New-Object Windows.Forms.ListViewItem; XeItemSet $xeIt $xeR; [void]$xeV.Items.Add($xeIt); $xeIt.Selected = $true } }),
        @('Editar', { param($snd, $ev) XeEditSel $snd.Tag }),
        @('Tirar', { param($snd, $ev) $xeV = $snd.Tag; if ($xeV.SelectedItems.Count) { $xeV.Items.Remove($xeV.SelectedItems[0]) } }),
        @('Subir', { param($snd, $ev) XeMove $snd.Tag -1 }),
        @('Descer', { param($snd, $ev) XeMove $snd.Tag 1 })
    )
    $xeK = 0
    foreach ($xeB in $xeBtns) {
        $xeBt = New-Object Windows.Forms.Button -Property @{ Text = $xeB[0]; Tag = $xeLv }; $xeBt.SetBounds(485, ($xeY + 25 * $xeK), 60, 23)
        $xeBt.Add_Click($xeB[1]); $xeForm.Controls.Add($xeBt); $xeK++
    }
    $xeLv.Add_DoubleClick({ param($snd, $ev) XeEditSel $snd })
    $xeLv
}
function XeEditSel($xeV) {
    if (-not $xeV.SelectedItems.Count) { return }
    $xeIt = $xeV.SelectedItems[0]; $xeR = ExtraDialog $xeIt.Tag $xeV.Tag.Text
    if ($xeR) { XeItemSet $xeIt $xeR }
}
function XeMove($xeV, $xeDir) {
    if (-not $xeV.SelectedItems.Count) { return }
    $xeIt = $xeV.SelectedItems[0]; $xeI = $xeIt.Index; $xeJ = $xeI + $xeDir
    if ($xeJ -lt 0 -or $xeJ -ge $xeV.Items.Count) { return }
    $xeV.Items.RemoveAt($xeI); $xeV.Items.Insert($xeJ, $xeIt); $xeIt.Selected = $true; $xeIt.EnsureVisible()
}
# Referência da marcação da descrição (editor de jogo e editar em massa)
$script:DescFmtRef = @'
[b]texto[/b]                     negrito
[i]texto[/i]                     itálico
[u]texto[/u]                     sublinhado
[cor=#FF8800]texto[/cor]         cor do texto (#RRGGBB)
[tam=14]texto[/tam]              tamanho da letra (8 a 40)
[titulo]texto[/titulo]           título grande
[sub]texto[/sub]                 subtítulo
[link=https://site]texto[/link]  link clicável (site ou tg://...)
[link=Jogos\X\manual.pdf]texto[/link]  abre documento/imagem/pasta
                                 de dentro do launcher ({JogoDir} = pasta do jogo)

Enter = novo parágrafo. Endereços https:// soltos já viram link.
Dá para combinar: [b][cor=#FF8800]texto[/cor][/b]
'@
function Edit($g) {
    $new = -not $g
    if ($new) { $g = [pscustomobject]@{ Id = ''; Name = ''; Exe = ''; Args = ''; Cover = ''; Shot = ''; Version = ''; Link = ''; Desc = ''; ImgName = ''; Archive = ''; Added = (Get-Date -Format 'yyyy-MM-dd') } }
    # Janela redimensionável (v2.33.0): campos em cima esticam com a largura; a descrição ocupa todo o espaço livre,
    # com a referência de formatação ao lado (divisória ajustável); extras e botões ficam embaixo.
    $f = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = $(if ($new) { 'Novo jogo' } else { "Jogo - $($g.Name)" }); StartPosition = 'CenterParent' }
    WinSizable $f 'EditorJogo' 680 600
    $f.ClientSize = New-Object Drawing.Size(940, 780)
    $W = $f.ClientSize.Width
    $fields = @(@('Name','Nome',''), @('Exe','Executável','exe'), @('Archive','Arquivo compactado','rar'), @('Args','Argumentos',''), @('PlayName','Nome da ação Jogar',''), @('Cover','Capa','img'), @('Shot','Captura de tela','img'), @('ImgName','Nome da imagem',''), @('Version','Versão',''), @('Link','Link (site ou local)',''))
    $lw = TxtW 'Extras (menu do botão direito)' $f.Font
    foreach ($fd in $fields) { $lw = [Math]::Max($lw, (TxtW $fd[1] $f.Font)) }
    $lw = [Math]::Min(260, $lw + 10); $x0 = 12 + $lw + 6
    $pTop = New-Object Windows.Forms.Panel -Property @{ Dock = 'Top'; Width = $W }
    $tb = @{}; $y = 12
    foreach ($fd in $fields) {
        $hasB = ($fd[2] -in 'exe', 'img', 'rar')
        $pTop.Controls.Add((Lbl $fd[1] 12 ($y + 3) $lw 20))
        $t = New-Object Windows.Forms.TextBox -Property @{ Left = $x0; Top = $y; Width = ($W - $x0 - 12 - $(if ($hasB) { 52 } else { 0 })); Text = "$($g.($fd[0]))"; Anchor = 'Top, Left, Right' }
        $pTop.Controls.Add($t); $tb[$fd[0]] = $t
        if ($hasB) {
            $b = New-Object Windows.Forms.Button -Property @{ Text = '...'; Left = ($W - 12 - 46); Top = ($y - 1); Width = 46; Anchor = 'Top, Right'; Tag = @($t, $fd[2], $tb['Name']) }
            $b.Add_Click({
                $t, $kind, $nm = $this.Tag
                $d = New-Object Windows.Forms.OpenFileDialog
                $d.InitialDirectory = if ($kind -eq 'exe' -and [IO.Directory]::Exists("$Root\Jogos")) { "$Root\Jogos" } else { $Root }
                $d.Filter = if ($kind -eq 'exe') { 'Executável|*.exe|Todos|*.*' } elseif ($kind -eq 'rar') { 'Arquivo RAR|*.rar|Todos|*.*' } else { 'Imagens|*.jpg;*.jpeg;*.png;*.bmp|Todos|*.*' }
                if ($d.ShowDialog() -eq 'OK') {
                    if (-not (InRoot $d.FileName)) { [void][Windows.Forms.MessageBox]::Show("Escolha um arquivo de dentro da pasta do launcher:`n$Root", 'Fora da pasta do launcher'); $d.Dispose(); return }
                    $t.Text = Short $d.FileName
                    if ($kind -eq 'exe' -and -not $nm.Text) { $nm.Text = NameFromFolder (Split-Path (Split-Path $d.FileName) -Leaf) }
                }
            })
            $pTop.Controls.Add($b)
        }
        $y += 30
    }
    $pTop.Height = $y + 2
    # Descrição (esquerda, cresce com a janela) + referência de formatação (direita)
    $split = New-Object Windows.Forms.SplitContainer -Property @{ Dock = 'Fill'; Orientation = 'Vertical'; SplitterWidth = 6 }
    $split.Panel1.Padding = New-Object Windows.Forms.Padding(12, 2, 3, 4); $split.Panel2.Padding = New-Object Windows.Forms.Padding(3, 2, 12, 4)
    $td = New-Object Windows.Forms.TextBox -Property @{ Dock = 'Fill'; Multiline = $true; AcceptsReturn = $true; ScrollBars = 'Vertical'; WordWrap = $true; Text = "$($g.Desc)" }
    $td.Font = New-Object Drawing.Font('Consolas', 10)
    $ldh = New-Object Windows.Forms.Label -Property @{ Dock = 'Top'; Height = 20; Text = 'Descrição  (Enter = novo parágrafo; o botão "Prévia ao vivo" mostra como fica)' }
    $split.Panel1.Controls.Add($td); $split.Panel1.Controls.Add($ldh); $tb['Desc'] = $td
    $refTxt = $script:DescFmtRef + @'

---- Dicas dos campos ----
Caminhos são sempre relativos à pasta do launcher (ex: Jogos\MeuJogo\jogo.exe) e não podem apontar para fora dela; aceita {LauncherDir}, {JogosDir} e {TarginoRetroStationDir}.

Nome da ação Jogar: texto do "Jogar" no menu do botão direito só deste jogo (ex: Jogar (Vulkan)). Vazio = o texto geral de Renomear textos.

Nome da imagem: só se o arquivo de capa/captura da pasta automática tiver nome diferente do jogo.

Link: https://site, tg://resolve?domain=canal ou programa local com argumentos (ex: Telegram\Telegram.exe -- tg://resolve?domain=canal).

Arquivo compactado: opcional; sem ele o launcher procura NomeDaPasta.rar ao lado da pasta do jogo e extrai sozinho ao jogar.

Várias partes (.part1.rar, .part2.rar...): basta a primeira; ao terminar a extração com sucesso, todas as partes são apagadas.
'@
    $rb = New-Object Windows.Forms.TextBox -Property @{ Dock = 'Fill'; Multiline = $true; ReadOnly = $true; ScrollBars = 'Vertical'; WordWrap = $true; BackColor = [Drawing.Color]::White; Font = (New-Object Drawing.Font('Consolas', 9)); Text = ($refTxt -replace "`r?`n", "`r`n") }
    $lrh = New-Object Windows.Forms.Label -Property @{ Dock = 'Top'; Height = 20; Text = 'Formatação (selecione e copie com Ctrl+C)' }
    $split.Panel2.Controls.Add($rb); $split.Panel2.Controls.Add($lrh)
    # Extras (menu do botão direito)
    $pEx = New-Object Windows.Forms.Panel -Property @{ Dock = 'Bottom'; Width = $W; Height = 142 }
    $xeLv = XeListBox $pEx 8 "$($g.Extras)" $tb['Exe']
    foreach ($xc in @($pEx.Controls)) {
        if ($xc -is [Windows.Forms.ListView]) { $xc.SetBounds($x0, 8, ($W - $x0 - 12 - 72), 126); $xc.Anchor = 'Top, Left, Right' }
        elseif ($xc -is [Windows.Forms.Button]) { $xc.Left = $W - 12 - 66; $xc.Width = 66; $xc.Anchor = 'Top, Right' }
        elseif ($xc -is [Windows.Forms.Label]) { $xc.Left = 12; $xc.Width = $lw }
    }
    $xeLv.Add_Resize({ param($snd, $ev) try { $snd.Columns[1].Width = [Math]::Max(120, $snd.ClientSize.Width - $snd.Columns[0].Width - 4) } catch { $Error.Clear() } })
    # Botões
    $pBt = New-Object Windows.Forms.Panel -Property @{ Dock = 'Bottom'; Width = $W; Height = 46 }
    $ok = New-Object Windows.Forms.Button -Property @{ Text = 'Salvar'; Left = ($W - 12 - 186); Top = 9; Width = 90; Height = 28; DialogResult = 'OK'; Anchor = 'Top, Right' }
    $ca = New-Object Windows.Forms.Button -Property @{ Text = 'Cancelar'; Left = ($W - 12 - 90); Top = 9; Width = 90; Height = 28; DialogResult = 'Cancel'; Anchor = 'Top, Right' }
    $pvSt = @{ Pf = $null; Src = $td; Tm = (New-Object Windows.Forms.Timer -Property @{ Interval = 350 }) }
    $pv = New-Object Windows.Forms.Button -Property @{ Text = 'Prévia ao vivo'; Left = 12; Top = 9; Width = 140; Height = 28; Anchor = 'Top, Left'; Tag = $pvSt }
    $pv.Add_Click({ param($snd, $ev) DescPreviewLive $snd.FindForm() $snd.Tag })
    $pvSt.Tm.Tag = $pvSt
    $pvSt.Tm.Add_Tick({ param($snd, $ev) $snd.Stop(); DescPreviewRender $snd.Tag })
    $td.Tag = $pvSt
    $td.Add_TextChanged({ param($snd, $ev) $st = $snd.Tag; if ($st.Pf -and -not $st.Pf.IsDisposed) { $st.Tm.Stop(); $st.Tm.Start() } })
    $pBt.Controls.AddRange(@($pv, $ok, $ca))
    # ordem de encaixe: o último adicionado encaixa primeiro (Top/Bottom), o Fill fica com o resto
    $f.Controls.Add($split); $f.Controls.Add($pEx); $f.Controls.Add($pBt); $f.Controls.Add($pTop)
    $f.Tag = @{ Sp = $split; Nm = $tb['Name'] }
    $f.Add_Load({ param($snd, $ev)
        $sp = $snd.Tag.Sp
        try {
            $dv = 0; [void][int]::TryParse("$($DevWin['EditorJogoDiv'])", [ref]$dv)
            if ($dv -lt 220 -or $dv -gt $sp.Width - 160) { $dv = [int]($sp.Width * 0.62) }
            $sp.SplitterDistance = $dv
            $sp.Panel1MinSize = 220; $sp.Panel2MinSize = 160
        } catch { $Error.Clear() }
        $snd.ActiveControl = $snd.Tag.Nm
    })
    $f.Add_FormClosing({ param($snd, $ev) try { $sp = $snd.Tag.Sp; if ($sp.Width -gt 0) { $DevWin['EditorJogoDiv'] = "$($sp.SplitterDistance)"; SaveWin } } catch { $Error.Clear() } })
    # sem AcceptButton/CancelButton: Enter faz parágrafo na descrição e Esc não fecha; só Salvar/Cancelar (ou o X) fecham
    $res = $f.ShowDialog()
    $pvSt.Tm.Stop(); $pvSt.Tm.Dispose()
    if ($pvSt.Pf -and -not $pvSt.Pf.IsDisposed) { $pvSt.Pf.Close(); $pvSt.Pf.Dispose() }
    if ($res -ne 'OK' -or -not $tb['Name'].Text.Trim()) { $f.Dispose(); return $false }
    foreach ($k in $tb.Keys) { $g | Add-Member NoteProperty $k $tb[$k].Text -Force }
    if (-not "$($g.PlayName)".Trim()) { $g.PSObject.Properties.Remove('PlayName') } else { $g.PlayName = "$($g.PlayName)".Trim() }   # vazio = texto geral (T_CtxPlay)
    $xeTxt = ExtrasJoin @(foreach ($xeIt in $xeLv.Items) { $xeIt.Tag })
    if ($xeTxt -or $g.PSObject.Properties['Extras']) { $g | Add-Member NoteProperty Extras $xeTxt -Force }
    if ($new) { $g | Add-Member NoteProperty Id (NewId $g.Name) -Force; $script:Games += $g }
    Save; $true
}
# ---- Adicionar jogos em massa (pasta Jogos) ----
#  Cada pasta de 1º nível de Jogos\ que tenha .exe e ainda não esteja no catálogo vira um jogo, com os mesmos campos do
#  cadastro manual (+ Adicionar): Nome = nome da pasta (sem os trechos de NameStrip), Executável = caminho relativo,
#  o resto vazio, Added = hoje. Pasta "já no catálogo" = algum jogo tem o executável (do catálogo) dentro dela; isso inclui jogos compactados ainda não extraídos. Nada é gravado sem a janela de
#  conferência; backup do catálogo antes.
#  Executável: só UM, o primeiro encontrado (ordem alfabética). Primeiro na própria pasta do jogo; se não houver,
#  procura nas subpastas, nível por nível (todas as subpastas de 1º nível, depois as de 2º...), sem seguir atalhos/junções.
function NameFromFolder($nfDir) {   # nome do jogo a partir do nome da pasta, tirando os trechos de NameStrip (painel dev, aba Geral)
    $nfN = "$nfDir"
    foreach ($nfT in ("$($S.NameStrip)" -split ';')) {
        $nfT = $nfT.Trim(); if ($nfT) { $nfN = [regex]::Replace($nfN, [regex]::Escape($nfT), '', [Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    }
    $nfN = ($nfN -replace '\s{2,}', ' ').Trim().TrimEnd(' ', '-', '_').Trim()
    if (-not $nfN) { $nfN = "$nfDir".Trim() }      # nunca deixa o nome vazio
    $nfN
}
function JaSorted($jaArr) { $jaL = [string[]]$jaArr; [Array]::Sort($jaL, [StringComparer]::OrdinalIgnoreCase); , $jaL }
function JaFirstExe($jaDir) {   # primeiro .exe da pasta do jogo; se não houver, das subpastas, nível por nível ('' = nenhum)
    $jaLevel = @($jaDir)
    while ($jaLevel.Count -gt 0) {
        $jaNext = New-Object System.Collections.ArrayList
        foreach ($jaP in $jaLevel) {
            try {
                foreach ($jaF in (JaSorted ([IO.Directory]::GetFiles($jaP, '*.exe')))) { if ($jaF.EndsWith('.exe', 'OrdinalIgnoreCase')) { return $jaF } }
                foreach ($jaS in (JaSorted ([IO.Directory]::GetDirectories($jaP)))) { if (([int][IO.File]::GetAttributes($jaS) -band 1024) -eq 0) { [void]$jaNext.Add($jaS) } }
            } catch { LogEx 'AVISO' "Adicionar em massa: não foi possível ler '$(Short $jaP)' ($($_.Exception.Message))" $_ }
        }
        $jaLevel = @($jaNext.ToArray())
    }
    ''
}
function JaScan {   # só lê o disco; não altera nada
    $jaJd = [IO.Path]::Combine($Root, 'Jogos')
    $jaUsed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($jaG in $script:Games) {
        $jaSub = JogosSub (ExePath $jaG); if ($jaSub) { [void]$jaUsed.Add($jaSub) }
    }
    $jaRows = New-Object System.Collections.ArrayList; $jaIn = 0; $jaNo = 0
    foreach ($jaD in (JaSorted ([IO.Directory]::GetDirectories($jaJd)))) {
        $jaName = [IO.Path]::GetFileName($jaD)
        if ($jaName.StartsWith('.') -or $jaName.EndsWith('.anterior', 'OrdinalIgnoreCase')) { continue }   # temporária da extração / pasta incompleta guardada
        if ($jaUsed.Contains($jaD)) { $jaIn++; continue }
        $jaExe = JaFirstExe $jaD
        if (-not $jaExe) { $jaNo++; continue }
        [void]$jaRows.Add([pscustomobject]@{ Name = (NameFromFolder $jaName); Dir = $jaD; Exe = $jaExe })
    }
    [pscustomobject]@{ Rows = @($jaRows.ToArray()); InCat = $jaIn; NoExe = $jaNo }
}
function JaCountText($jaLv) { "Adicionar ($($jaLv.CheckedItems.Count))" }
function BulkAdd {
    if ($script:CatBroken) { [void][Windows.Forms.MessageBox]::Show('O catálogo não pôde ser lido ao abrir o launcher; nada será gravado até o problema ser resolvido.', 'Adicionar em massa', 'OK', 'Warning'); return }
    $jaJd = [IO.Path]::Combine($Root, 'Jogos')
    if (-not [IO.Directory]::Exists($jaJd)) { [void][IO.Directory]::CreateDirectory($jaJd); [void][Windows.Forms.MessageBox]::Show("Pasta 'Jogos' criada. Coloque os jogos nela (uma pasta por jogo) e tente de novo.", 'Adicionar em massa'); return }
    $jaSw = [Diagnostics.Stopwatch]::StartNew()
    try { [Windows.Forms.Cursor]::Current = [Windows.Forms.Cursors]::WaitCursor; $jaScan = JaScan }
    catch { LogEx 'ERRO' "Adicionar em massa: falha ao ler a pasta Jogos: $($_.Exception.Message)" $_; [void][Windows.Forms.MessageBox]::Show("Não foi possível ler a pasta Jogos:`n$($_.Exception.Message)", 'Adicionar em massa'); return }
    finally { [Windows.Forms.Cursor]::Current = [Windows.Forms.Cursors]::Default }
    Log 'INFO' "Adicionar em massa: $($jaScan.Rows.Count) pasta(s) nova(s) com .exe, $($jaScan.InCat) já no catálogo, $($jaScan.NoExe) sem .exe ($($jaSw.ElapsedMilliseconds) ms)"
    $jaInfo = "Já no catálogo: $($jaScan.InCat) pasta(s).  Sem .exe (ex.: só .rar): $($jaScan.NoExe) pasta(s)."
    if ($jaScan.Rows.Count -eq 0) { [void][Windows.Forms.MessageBox]::Show("Nenhum jogo novo com .exe em Jogos\.`n`n$jaInfo", 'Adicionar em massa'); return }

    $jaF = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = 'Adicionar jogos em massa'; Size = '820,560'; StartPosition = 'CenterParent'; MinimizeBox = $false; MinimumSize = '600,360' }
    $jaTop = Lbl ("$($jaScan.Rows.Count) jogo(s) novo(s) em Jogos\. O nome é o nome da pasta (sem os trechos da aba Geral do painel dev). Desmarque o que não quiser adicionar.`n$jaInfo") 10 10 780 36
    $jaTop.Anchor = 'Top, Left, Right'
    $jaLv = New-Object Windows.Forms.ListView -Property @{ View = 'Details'; CheckBoxes = $true; FullRowSelect = $true; HideSelection = $false; MultiSelect = $false; Anchor = 'Top, Bottom, Left, Right' }
    $jaLv.SetBounds(10, 50, 785, 410)
    [void]$jaLv.Columns.Add('Nome', 320); [void]$jaLv.Columns.Add('Executável', 440)
    foreach ($jaR in $jaScan.Rows) {
        $jaIt = New-Object Windows.Forms.ListViewItem("$($jaR.Name)")
        [void]$jaIt.SubItems.Add((Short $jaR.Exe))
        $jaIt.Checked = $true; $jaIt.Tag = $jaR; [void]$jaLv.Items.Add($jaIt)
    }
    $jaOk  = New-Object Windows.Forms.Button -Property @{ Text = (JaCountText $jaLv); DialogResult = 'OK'; Anchor = 'Bottom, Right' }
    $jaCa  = New-Object Windows.Forms.Button -Property @{ Text = 'Cancelar'; DialogResult = 'Cancel'; Anchor = 'Bottom, Right' }
    $jaAll = New-Object Windows.Forms.Button -Property @{ Text = 'Marcar todos'; Anchor = 'Bottom, Left'; Tag = @($jaLv, $true) }
    $jaNone = New-Object Windows.Forms.Button -Property @{ Text = 'Desmarcar todos'; Anchor = 'Bottom, Left'; Tag = @($jaLv, $false) }
    $jaExe = New-Object Windows.Forms.Button -Property @{ Text = 'Trocar executável...'; Anchor = 'Bottom, Left'; Tag = $jaLv }
    $jaAll.SetBounds(10, 472, 110, 30); $jaNone.SetBounds(126, 472, 120, 30); $jaExe.SetBounds(252, 472, 150, 30)
    $jaOk.SetBounds(585, 472, 110, 30); $jaCa.SetBounds(701, 472, 94, 30)
    $jaLv.Tag = $jaOk
    $jaLv.Add_ItemChecked({ param($snd, $ev) $snd.Tag.Text = JaCountText $snd; $snd.Tag.Enabled = ($snd.CheckedItems.Count -gt 0) })
    foreach ($jaB in $jaAll, $jaNone) { $jaB.Add_Click({ param($snd, $ev) $jaV = $snd.Tag[0]; $jaV.BeginUpdate(); foreach ($jaI in $jaV.Items) { $jaI.Checked = [bool]$snd.Tag[1] }; $jaV.EndUpdate() }) }
    $jaExe.Add_Click({
        param($snd, $ev)
        $jaV = $snd.Tag
        if ($jaV.SelectedItems.Count -lt 1) { [void][Windows.Forms.MessageBox]::Show('Clique primeiro no jogo da lista.', 'Trocar executável'); return }
        $jaI = $jaV.SelectedItems[0]; $jaR = $jaI.Tag
        $jaD = New-Object Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = $jaR.Dir; Filter = 'Executável|*.exe'; Title = "Executável de '$($jaR.Name)'" }
        if ($jaD.ShowDialog() -eq 'OK') {
            if ((JogosSub $jaD.FileName) -ine $jaR.Dir) { [void][Windows.Forms.MessageBox]::Show("Escolha um .exe de dentro da pasta:`n$(Short $jaR.Dir)", 'Trocar executável'); return }
            $jaR.Exe = $jaD.FileName; $jaI.SubItems[1].Text = Short $jaD.FileName; $jaI.Checked = $true
        }
        $jaD.Dispose()
    })
    $jaF.Controls.AddRange(@($jaTop, $jaLv, $jaAll, $jaNone, $jaExe, $jaOk, $jaCa))
    $jaF.CancelButton = $jaCa
    $jaRes = $jaF.ShowDialog($form)
    $jaSel = @(foreach ($jaI in $jaLv.CheckedItems) { $jaI.Tag })
    $jaF.Dispose()
    if ($jaRes -ne 'OK' -or $jaSel.Count -eq 0) { return }

    [void](Backup $Db 'antes-adicionar-massa')
    $jaDay = Get-Date -Format 'yyyy-MM-dd'
    foreach ($jaR in $jaSel) {
        # mesmos campos e mesma ordem do cadastro manual (Edit)
        $script:Games += [pscustomobject]@{ Id = (NewId $jaR.Name); Name = $jaR.Name; Exe = (Short $jaR.Exe); Args = ''; Cover = ''; Shot = ''; Version = ''; Link = ''; Desc = ''; ImgName = ''; Archive = ''; Added = $jaDay }
    }
    Save
    Log 'INFO' "Adicionar em massa: $($jaSel.Count) jogo(s) adicionado(s): $((@($jaSel | ForEach-Object { $_.Name }) | Select-Object -First 30) -join '; ')$(if ($jaSel.Count -gt 30) { '; ...' })"
    CatRefresh; Populate
    [void][Windows.Forms.MessageBox]::Show("$($jaSel.Count) jogo(s) adicionado(s).", 'Adicionar em massa')
}

# ---- Atualização automática (UpdateWinPort) ----
#  Você mesmo cria o arquivo (.zip ou .rar) e sobe no endereço da aba Atualização (UpdUrl, ex.: GitHub). A cada abertura, com a
#  janelinha de carregamento: pede só o cabeçalho do arquivo (HEAD) e compara a ETag com a guardada em Dados\atualizacao.json
#  (sem ETag no servidor: data + tamanho). Igual, sem internet ou servidor fora = segue a abertura normal.
#  Diferente = baixa (com progresso), extrai tudo POR CIMA dos arquivos do launcher (sem perguntar, sem backup), apaga o download,
#  guarda a ETag e abre o launcher de novo para ele seguir normalmente.
#  Onde extrai: se o arquivo tem a pasta TarginoRetroStation\ dentro, ele é extraído na pasta do launcher (a de cima: TarginoRetroStation\, Jogos\,
#  o executável...); se não tem, é extraído DENTRO de TarginoRetroStation\ (ex.: Launcher.ps1, Dados\layout.json, Capas\...). Uma pasta
#  única envolvendo tudo é ignorada. Nunca são substituídos (são só da pessoa/deste PC): Dados\usuario.json (favoritos), Dados\ultimo_filtro.txt,
#  Dados\atualizacao.json (a ETag), Dados\cache_instalacao.json, Dados\cache_imagens.json (e os .bak deles),
#  componentes_instalados.txt, Logs\ e Cache\. Todo o resto (Launcher.ps1, layout.json, catalogo.json, janelas.json, capas...)
#  é substituído. Nada é gravado fora da pasta do launcher.
#  Arquivo em uso (o executável aberto, uma fonte carregada) é tirado do caminho para Cache\Substituidos (apagada na próxima abertura).
$UpdFile = [IO.Path]::Combine($DataDir, 'atualizacao.json')
$UpdSkip = 'TarginoRetroStation\Dados\usuario.json', 'TarginoRetroStation\Dados\usuario.json.bak', 'TarginoRetroStation\Dados\ultimo_filtro.txt', 'TarginoRetroStation\Dados\ultimo_filtro.txt.bak', 'TarginoRetroStation\Dados\atualizacao.json', 'TarginoRetroStation\Dados\atualizacao.json.bak',
    'TarginoRetroStation\Dados\cache_instalacao.json', 'TarginoRetroStation\Dados\cache_instalacao.json.bak', 'TarginoRetroStation\Dados\cache_imagens.json', 'TarginoRetroStation\Dados\cache_imagens.json.bak',
    'TarginoRetroStation\componentes_instalados.txt', 'TarginoRetroStation\Logs\', 'TarginoRetroStation\Cache\'
Add-Type -AssemblyName System.IO.Compression.FileSystem
function UpdTls {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 }
    catch { $Error.Clear() }
}
# Aceita só HTTPS e endereço com nome de servidor comum (sem usuário:senha, sem IP literal entre colchetes)
function UpdOkUrl($url) {
    $u2 = "$url".Trim(); if (-not $u2) { return $false }
    try { $ur = [uri]$u2 } catch { $Error.Clear(); return $false }
    ($ur.Scheme -eq 'https' -and $ur.Host -and -not $ur.UserInfo -and $ur.Host -notmatch '[\[\]]')
}
function UpdState { $o = ReadJson $UpdFile $false; "$($o.ETag)" }
function UpdSaveState($upEtag) { [void](WriteJson $UpdFile ([ordered]@{ ETag = "$upEtag"; Data = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }) 2) }
# Espera uma tarefa (rede) sem travar a janelinha; $onTick roda a cada volta (progresso). $false = passou do tempo.
function UpdWait($upTask, $upMs, $onTick) {
    $upSw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $upTask.IsCompleted) {
        if ($onTick) { & $onTick }
        [Windows.Forms.Application]::DoEvents()
        if ($upSw.ElapsedMilliseconds -gt $upMs) { return $false }
        Start-Sleep -Milliseconds 50
    }
    $true
}
# Cabeçalho do arquivo no servidor: @{ Id; Bytes } ou $null (sem internet, não encontrado, não respondeu)
function UpdHead($url) {
    UpdTls
    $uq = [Net.HttpWebRequest][Net.WebRequest]::Create($url)
    $uq.Method = 'HEAD'; $uq.UserAgent = "TarginoRetroStation/$AppVer"; $uq.AllowAutoRedirect = $true; $uq.Timeout = 15000
    $uq.CachePolicy = New-Object Net.Cache.RequestCachePolicy([Net.Cache.RequestCacheLevel]::NoCacheNoStore)
    $ut = $uq.GetResponseAsync()
    if (-not (UpdWait $ut 15000 $null)) { try { $uq.Abort() } catch { $Error.Clear() }; Log 'AVISO' 'Atualização: o servidor não respondeu em 15 s'; return $null }
    if ($ut.IsFaulted -or $ut.IsCanceled) {
        $why = 'sem resposta'; try { $why = $ut.Exception.GetBaseException().Message } catch { $Error.Clear() }
        Log 'INFO' "Atualização: não foi possível consultar o servidor ($why)"; return $null
    }
    $urs = $ut.Result
    try { $et = "$($urs.Headers['ETag'])".Trim(); $len = [long]$urs.ContentLength; $lm = "$($urs.Headers['Last-Modified'])".Trim() } finally { $urs.Close() }
    if (-not $et) { $et = "$lm|$len" }
    @{ Id = $et; Bytes = $len }
}
# Baixa o arquivo mostrando o andamento na janelinha. Erro = exceção.
function UpdDownload($url, $upDst, $upBytes) {
    UpdTls
    $wc = New-Object Net.WebClient; $wc.Headers.Add('User-Agent', "TarginoRetroStation/$AppVer")
    try {
        $tk = $wc.DownloadFileTaskAsync($url, $upDst)
        $upMb = [Math]::Max(0.1, $upBytes / 1MB)
        $ok = UpdWait $tk 1800000 {
            $upHave = 0; try { if ([IO.File]::Exists($upDst)) { $upHave = (New-Object IO.FileInfo $upDst).Length } } catch { $Error.Clear() }
            if ($upBytes -gt 0) { SplashSet ("Baixando atualização... {0:N0}% ({1:N1} de {2:N1} MB)" -f (100.0 * $upHave / $upBytes), ($upHave / 1MB), $upMb) (0.05 + 0.6 * [Math]::Min(1.0, $upHave / [double]$upBytes)) $false }
            else { SplashSet ("Baixando atualização... {0:N1} MB" -f ($upHave / 1MB)) 0.3 $false }
        }
        if (-not $ok) { $wc.CancelAsync(); throw 'o download passou de 30 minutos' }
        if ($tk.IsFaulted -or $tk.IsCanceled) { $why = 'falha de rede'; try { $why = $tk.Exception.GetBaseException().Message } catch { $Error.Clear() }; throw "o download falhou ($why)" }
    } finally { $wc.Dispose() }
    $got = (New-Object IO.FileInfo $upDst).Length
    if ($upBytes -gt 0 -and $got -ne $upBytes) { throw "o download chegou incompleto ($got de $upBytes bytes)" }
}
# Descompacta o arquivo baixado (.zip ou .rar, conferido pelo conteúdo, não pelo nome) numa pasta temporária
function UpdUnpack($upArc, $upOut) {
    $hdr = New-Object byte[] 4
    $fs = [IO.File]::OpenRead($upArc); try { [void]$fs.Read($hdr, 0, 4) } finally { $fs.Dispose() }
    [void][IO.Directory]::CreateDirectory($upOut)
    if ($hdr[0] -eq 0x50 -and $hdr[1] -eq 0x4B) { [IO.Compression.ZipFile]::ExtractToDirectory($upArc, $upOut); return }
    if ($hdr[0] -eq 0x52 -and $hdr[1] -eq 0x61 -and $hdr[2] -eq 0x72 -and $hdr[3] -eq 0x21) {      # "Rar!"
        $ux = UnrarExe; if (-not [IO.File]::Exists($ux)) { throw "o arquivo é .rar e o UnRAR.exe não foi encontrado em $(Short $ux)" }
        $pp = ProcRedirect $ux "x -y -o+ $(PassArg "$($S.UpdPass)") -idq -- `"$upArc`" `"$($upOut.TrimEnd('\') + '\')`""
        $upK = 0.0
        while (-not (ProcDone $pp)) { $upK += (1 - $upK) * 0.01; SplashSet 'Extraindo atualização...' (0.65 + 0.2 * $upK) $false $true; Start-Sleep -Milliseconds 100 }
        $code = $pp.Proc.ExitCode; $pp.Proc.Dispose()
        if ($code -gt 1) { throw $(if ($code -eq 11) { 'senha do .rar da atualização incorreta ou ausente (modo dev, aba Atualização)' } else { "o UnRAR terminou com erro (código $code)" }) }
        return
    }
    throw 'o arquivo baixado não é .zip nem .rar'
}
# Copia o que foi extraído por cima da pasta do launcher. Devolve @(arquivos substituídos, falhas).
function UpdReplace($upOut) {
    $src = $upOut
    # pasta única envolvendo uma cópia do launcher (ex.: "TarginoRetroStation\TarginoRetroStation\..."): entra nela
    $subs = @([IO.Directory]::GetDirectories($src))
    if (@([IO.Directory]::GetFiles($src)).Count -eq 0 -and $subs.Count -eq 1 -and [IO.Directory]::Exists([IO.Path]::Combine($subs[0], $ArqName))) { $src = $subs[0] }
    $intoRoot = [IO.Directory]::Exists([IO.Path]::Combine($src, $ArqName))
    $dstBase = $(if ($intoRoot) { $Root } else { $Arq })
    $files = @([IO.Directory]::GetFiles($src, '*', [IO.SearchOption]::AllDirectories))
    $aside = [IO.Path]::Combine((ArqDir 'Cache'), 'Substituidos')
    $nOk = 0; $nBad = 0; $k = 0
    foreach ($f in $files) {
        $k++
        SplashSet "Atualizando arquivos ($k de $($files.Count))..." (0.85 + 0.15 * $k / [Math]::Max(1, $files.Count)) $false $true
        $rel = $f.Substring($src.Length).TrimStart('\', '/')
        $dst = [IO.Path]::GetFullPath([IO.Path]::Combine($dstBase, $rel))
        $relRoot = $dst.Substring([Math]::Min($dst.Length, $Root.Length)).TrimStart('\', '/')
        if (-not (InRoot $dst)) { $nBad++; Log 'AVISO' "Atualização: arquivo fora da pasta do launcher recusado ($rel)"; continue }
        if (@($UpdSkip | Where-Object { $relRoot -ieq $_ -or ($_.EndsWith('\') -and $relRoot.StartsWith($_, 'OrdinalIgnoreCase')) }).Count) { continue }
        try {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
            if ([IO.File]::Exists($dst)) {
                try { [IO.File]::SetAttributes($dst, [IO.FileAttributes]::Normal); [IO.File]::Delete($dst) }
                catch {      # em uso (ex.: o executável aberto agora): tira do caminho (renomear funciona mesmo em uso) e põe o novo no lugar
                    $Error.Clear(); [void][IO.Directory]::CreateDirectory($aside)
                    [IO.File]::Move($dst, [IO.Path]::Combine($aside, [Guid]::NewGuid().ToString('N') + '_' + [IO.Path]::GetFileName($dst)))
                }
            }
            [IO.File]::Move($f, $dst); $nOk++
        } catch { $nBad++; LogEx 'AVISO' "Atualização: não foi possível substituir $relRoot ($($_.Exception.Message))" $_ }
    }
    Log 'INFO' "Atualização: extraída em $(if ($intoRoot) { 'pasta do launcher' } else { $ArqName + '\' }); $nOk arquivo(s) substituído(s)$(if ($nBad) { ", $nBad falha(s)" })"
    @($nOk, $nBad)
}
# Fluxo completo na abertura. $true = atualizou (reabrir o launcher).
function UpdRun {
    $url = "$($S.UpdUrl)".Trim(); if (-not $url) { return $false }
    if (-not (UpdOkUrl $url)) { Log 'AVISO' "Atualização: endereço recusado (só https): $url"; return $false }
    SplashSet 'Procurando atualização...' 0.02 $true $true
    $hd = UpdHead $url; if (-not $hd) { return $false }
    if ($hd.Id -ceq (UpdState)) { return $false }      # nada novo no servidor
    $tmp = [IO.Path]::Combine((ArqDir 'Cache'), 'Atualizacao'); $arc = [IO.Path]::Combine($tmp, 'UpdateWinPort.baixado'); $out = [IO.Path]::Combine($tmp, 'extraido')
    Log 'INFO' ("Atualização: arquivo novo no servidor ({0:N1} MB); baixando" -f ($hd.Bytes / 1MB))
    try {
        if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }
        [void][IO.Directory]::CreateDirectory($tmp)
        UpdDownload $url $arc $hd.Bytes
        SplashSet 'Extraindo atualização...' 0.65 $true $true
        UpdUnpack $arc $out
        $res = UpdReplace $out
        if ($res[1]) { throw "$($res[1]) arquivo(s) não puderam ser substituídos (detalhes no log)" }
        UpdSaveState $hd.Id
        return $true
    } catch {
        $why = "$($_.Exception.Message)"
        LogEx 'ERRO' "Atualização: não foi concluída ($why); será tentada de novo na próxima abertura" $_
        SplashSet "Não foi possível atualizar agora: $why" 1.0 $true $true; Start-Sleep -Milliseconds 2500
        return $false
    } finally { try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) } } catch { $Error.Clear() } }      # o download é sempre apagado
}
# Depois de atualizar: abre o launcher de novo (pelo executável) e fecha este, para ele seguir normalmente já atualizado
function UpdRestart {
    SplashSet 'Atualização concluída. Abrindo o launcher...' 1.0 $true $true
    $ex = LauncherExe
    if ($ex) {
        try { [void][Diagnostics.Process]::Start((New-Object Diagnostics.ProcessStartInfo -Property @{ FileName = $ex; WorkingDirectory = $Root; UseShellExecute = $true })) }
        catch { LogEx 'ERRO' "Atualização: não foi possível reabrir o launcher: $($_.Exception.Message)" $_; $ex = '' }
    }
    if (-not $ex) { SplashClose; [void][Windows.Forms.MessageBox]::Show('A atualização foi aplicada. Abra o launcher de novo.', 'Atualização') }
    Log 'INFO' 'Atualização: reabrindo o launcher'
    SplashClose; $form.Close()
}
# Restos de uma atualização anterior (arquivos que estavam em uso e foram tirados do caminho)
function UpdCleanup { $sd = [IO.Path]::Combine((ArqDir 'Cache'), 'Substituidos'); if ([IO.Directory]::Exists($sd)) { try { [IO.Directory]::Delete($sd, $true) } catch { $Error.Clear() } } }
# ---- Diagnóstico de desempenho (modo dev > Ações): números medidos agora, para comparar versões e tamanhos de catálogo ----
function PerfAdd($kind, $ms) { $qq = $script:Perf[$kind]; $qq.Enqueue([double]$ms); while ($qq.Count -gt 300) { [void]$qq.Dequeue() } }
function PerfStat($kind) {
    $arr = @($script:Perf[$kind].ToArray()); if (-not $arr.Count) { return 'sem medições ainda' }
    $srt = @($arr | Sort-Object); $avg = ($arr | Measure-Object -Average).Average
    $p95 = $srt[[Math]::Min($srt.Count - 1, [int][Math]::Floor($srt.Count * 0.95))]
    "{0} medições: média {1:N1} ms, 95% até {2:N1} ms, máximo {3:N1} ms" -f $arr.Count, $avg, $p95, $srt[-1]
}
function PerfReport {
    $pr = [Diagnostics.Process]::GetCurrentProcess(); $pr.Refresh()
    $mb = 1MB; $ln = @()
    $ln += "TarginoRetroStation v$AppVer  -  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $ln += "Jogos no catálogo: $(@($script:Games).Count)   |   na lista atual: $($script:View.Count)"
    if ($script:Met) { $ln += "Grade: $($script:Met.Cols) coluna(s), capa de $($script:Met.Cover) px, $($script:Met.Rows) linha(s)" }
    $tot = $script:Lru.Hits + $script:Lru.Misses; $hp = $(if ($tot) { 100.0 * $script:Lru.Hits / $tot } else { 0 })
    $ln += "Capas em memória: $($script:Lru.Count) ({0:N1} MB de {1:N0} MB)  |  aproveitamento do cache: {2:N0}%  |  descartadas por limite: $($script:Lru.Evicted)" -f ($script:Lru.Bytes / $mb), ($script:Lru.Budget / $mb), $hp
    $ldr = $script:Loader
    $ln += "Carregador: $($ldr.Threads) thread(s), na fila: $($ldr.Queued), carregadas: $($ldr.Loaded), com erro: $($ldr.Failed), retiradas da fila (saíram da tela): $($ldr.Dropped)"
    $ln += "Desenho da grade: $(PerfStat 'Paint')"
    $ln += "Filtro/busca: $(PerfStat 'Filtro')"
    $ln += "Abertura até a janela pronta: $($script:Perf.ReadyMs) ms  (componentes em C#: $script:CompileMs ms)"
    $ln += "Memória do processo: conjunto de trabalho {0:N0} MB, privada {1:N0} MB, gerenciada (.NET) {2:N0} MB" -f ($pr.WorkingSet64 / $mb), ($pr.PrivateMemorySize64 / $mb), ([GC]::GetTotalMemory($false) / $mb)
    $ln += "Objetos do Windows: GDI $([Perf]::Gdi()), USER $([Perf]::User())"
    $txt = $ln -join "`r`n"
    Log 'INFO' ("Diagnóstico de desempenho:`r`n" + $txt)
    $f = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = 'Diagnóstico de desempenho'; StartPosition = 'CenterParent' }
    WinSizable $f 'Diagnostico' 500 260; $f.ClientSize = New-Object Drawing.Size(805, 322)
    $tx = New-Object Windows.Forms.TextBox -Property @{ Left = 10; Top = 10; Width = 785; Height = 260; Multiline = $true; ReadOnly = $true; ScrollBars = 'Vertical'; BackColor = 'White'; Text = $txt; Anchor = 'Top, Bottom, Left, Right' }
    $tx.Font = New-Object Drawing.Font 'Consolas', 9; $tx.Select(0, 0)
    $bc = New-Object Windows.Forms.Button -Property @{ Text = 'Copiar'; Left = 595; Top = 282; Width = 95; Height = 28; Anchor = 'Bottom, Right' }
    $bc.Add_Click({ param($snd, $ev) [Windows.Forms.Clipboard]::SetText("$($snd.Tag)") }); $bc.Tag = $txt
    $bf = New-Object Windows.Forms.Button -Property @{ Text = 'Fechar'; Left = 700; Top = 282; Width = 95; Height = 28; DialogResult = 'Cancel'; Anchor = 'Bottom, Right' }
    $f.Controls.AddRange(@($tx, $bc, $bf)); $f.CancelButton = $bf
    [void]$f.ShowDialog(); $f.Dispose()
}
# ---- Edição em massa (modo desenvolvedor) ----
#  Altera o MESMO campo em vários jogos de uma vez. Só os campos marcados são tocados; os outros ficam
#  como estão em cada jogo. Nome e Executável ficam de fora (são individuais). Capa e Captura só podem ser
#  limpadas (as imagens vêm da pasta automática). Antes de gravar: backup do catálogo em TarginoRetroStation\Dados\Backups,
#  guardado para o "Desfazer edição em massa" (vale só nesta sessão do launcher).
$script:MassFields = @(
    @{ Key = 'Version'; Label = 'Versão'; Multi = $false; ClearOnly = $false }
    @{ Key = 'Link'; Label = 'Link'; Multi = $false; ClearOnly = $false }
    @{ Key = 'Args'; Label = 'Argumentos'; Multi = $false; ClearOnly = $false }
    @{ Key = 'Archive'; Label = 'Arq. compactado'; Multi = $false; ClearOnly = $false }
    @{ Key = 'ImgName'; Label = 'Nome da imagem'; Multi = $false; ClearOnly = $false }
    @{ Key = 'Cover'; Label = 'Capa (só limpar)'; Multi = $false; ClearOnly = $true }
    @{ Key = 'Shot'; Label = 'Captura (só limpar)'; Multi = $false; ClearOnly = $true }
    @{ Key = 'Desc'; Label = 'Descrição'; Multi = $true; ClearOnly = $false }
)
$script:MassModes = 'Substituir', 'Acrescentar no fim', 'Acrescentar no começo', 'Localizar e trocar', 'Limpar'
# Novo valor de um campo. 'Localizar e trocar' é literal (não é expressão) e ignora maiúsculas/minúsculas.
function MassValue($old, $mode, $a, $b) {
    $o = "$old"
    if ($mode -eq 'Substituir') { return "$a" }
    if ($mode -eq 'Acrescentar no fim') { return ($o + "$a") }
    if ($mode -eq 'Acrescentar no começo') { return ("$a" + $o) }
    if ($mode -eq 'Limpar') { return '' }
    if ($mode -eq 'Localizar e trocar') {
        if (-not "$a") { return $o }
        $sb = New-Object Text.StringBuilder; $k0 = 0
        while ($true) {
            $k = $o.IndexOf("$a", $k0, [StringComparison]::OrdinalIgnoreCase)
            if ($k -lt 0) { [void]$sb.Append($o.Substring($k0)); break }
            [void]$sb.Append($o.Substring($k0, $k - $k0)); [void]$sb.Append("$b"); $k0 = $k + "$a".Length
        }
        return $sb.ToString()
    }
    $o
}
# Lista o que mudaria, sem gravar nada: @{ Id; Name; Key; Label; Old; New }
function MassPlan($games, $sets) {
    $out = @()
    foreach ($gm in @($games)) {
        foreach ($st in @($sets)) {
            $was = "$($gm.($st.Key))"
            $now = MassValue $was $st.Mode $st.A $st.B
            if ($now -ne $was) { $out += @{ Id = "$($gm.Id)"; Name = "$($gm.Name)"; Key = $st.Key; Label = $st.Label; Old = $was; New = $now } }
        }
    }
    $out
}
function MassShow($txt) {
    $sh = "$txt" -replace '\s+', ' '
    if ($sh.Length -gt 60) { $sh = $sh.Substring(0, 57) + '...' }
    if ($sh) { "'$sh'" } else { '(vazio)' }
}
# Prévia: antes -> depois. Devolve $true se a pessoa confirmar.
function MassPreview($plan, $sets)
{
    $ids = @{}; foreach ($ch in @($plan)) { $ids["$($ch.Id)"] = 1 }
    $head = "$($ids.Count) jogo(s), $(@($plan).Count) alteração(ões)." + "`r`n" +
            'Campos: ' + ((@($sets) | ForEach-Object { "$($_.Label) ($($_.Mode))" }) -join ', ') + "`r`n`r`n"
    $lines = @(); $max = 60; $i = 0
    foreach ($ch in @($plan)) {
        if ($i -ge $max) { break }
        $lines += "$($ch.Name)  |  $($ch.Label): $(MassShow $ch.Old)  ->  $(MassShow $ch.New)"
        $i++
    }
    if (@($plan).Count -gt $max) { $lines += '', "... e mais $(@($plan).Count - $max) alteração(ões) (todas serão aplicadas)." }
    $f = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = 'Confirmar edição em massa'; StartPosition = 'CenterParent' }
    WinSizable $f 'ConfirmarMassa' 520 320; $f.ClientSize = New-Object Drawing.Size(745, 482)
    $tx = New-Object Windows.Forms.TextBox -Property @{ Left = 10; Top = 10; Width = 725; Height = 420; Multiline = $true; ReadOnly = $true; ScrollBars = 'Both'; WordWrap = $false; BackColor = 'White'; Anchor = 'Top, Bottom, Left, Right' }
    $tx.Font = New-Object Drawing.Font 'Consolas', 9
    $tx.Text = $head + ($lines -join "`r`n")
    $tx.Select(0, 0)
    $ok = New-Object Windows.Forms.Button -Property @{ Text = 'Aplicar'; Left = 545; Top = 442; Width = 90; Height = 28; DialogResult = 'OK'; Anchor = 'Bottom, Right' }
    $ca = New-Object Windows.Forms.Button -Property @{ Text = 'Cancelar'; Left = 645; Top = 442; Width = 90; Height = 28; DialogResult = 'Cancel'; Anchor = 'Bottom, Right' }
    $f.Controls.AddRange(@($tx, $ok, $ca))      # sem AcceptButton: Enter não aplica sem querer
    $r = $f.ShowDialog(); $f.Dispose()
    $r -eq 'OK'
}
# Grava: backup -> aplica -> salva. Devolve a quantidade de alterações.
function MassApply($games, $plan) {
    if (-not @($plan).Count) { return 0 }
    $bk = Backup $Db 'antes-massa'
    $byId = @{}; foreach ($gm in @($games)) { $byId["$($gm.Id)"] = $gm }
    $ids = @{}
    foreach ($ch in @($plan)) {
        $gm = $byId["$($ch.Id)"]
        if ($gm) { $gm | Add-Member NoteProperty $ch.Key $ch.New -Force; $ids["$($ch.Id)"] = 1 }
    }
    Save
    $keys = (@($plan | ForEach-Object { $_.Label } | Sort-Object -Unique) -join ', ')
    Log 'INFO' "Edição em massa: $($ids.Count) jogo(s), $(@($plan).Count) alteração(ões) nos campos: $keys"
    if ($bk) {
        $script:MassUndo = $bk
        $script:MassUndoInfo = "$($ids.Count) jogo(s), campos: $keys"
        $script:MassUndoStamp = $(try { (New-Object IO.FileInfo $Db).LastWriteTimeUtc.Ticks } catch { $Error.Clear(); 0 })
    }
    @($plan).Count
}
# Desfazer: volta o catálogo para o backup feito antes da última edição em massa desta sessão.
function MassUndoRun {
    $bk = "$script:MassUndo"
    if (-not $bk -or -not [IO.File]::Exists($bk)) {
        [void][Windows.Forms.MessageBox]::Show("Não há edição em massa para desfazer nesta sessão do launcher.`nAs cópias de segurança ficam em TarginoRetroStation\Dados\Backups.", 'Desfazer edição em massa'); return
    }
    $chg = $true
    try { $chg = ((New-Object IO.FileInfo $Db).LastWriteTimeUtc.Ticks -ne $script:MassUndoStamp) } catch { $Error.Clear() }
    $msg = "Desfazer a última edição em massa ($script:MassUndoInfo)?`n`nO catálogo volta para a cópia $(Split-Path $bk -Leaf)."
    $icon = 'Question'
    if ($chg) { $msg = "ATENÇÃO: o catálogo foi alterado depois dessa edição em massa.`nDesfazer também descarta essas alterações mais recentes.`n`n" + $msg; $icon = 'Warning' }
    if ([Windows.Forms.MessageBox]::Show($msg, 'Desfazer edição em massa', 'YesNo', $icon) -ne 'Yes') { return }
    $o = ReadJson $bk $false
    if ($null -eq $o) { [void][Windows.Forms.MessageBox]::Show('A cópia de segurança não pôde ser lida; nada foi alterado.', 'Desfazer edição em massa', 'OK', 'Warning'); return }
    [void](Backup $Db 'antes-desfazer')
    $script:Games = @($o | Where-Object { $_ })
    Save
    Log 'INFO' "Edição em massa desfeita a partir de $(Split-Path $bk -Leaf) ($($script:Games.Count) jogo(s))"
    $script:MassUndo = ''; $script:MassUndoInfo = ''
    CatRefresh; Populate; ShowGame (Sel)
    [void][Windows.Forms.MessageBox]::Show('Catálogo restaurado.', 'Desfazer edição em massa')
}
# Lê a janela, mostra a prévia e aplica. Devolve $true quando aplicou (aí a janela pode fechar).
function MassRun {
    $sets = @()
    foreach ($rw in @($script:MassRows)) {
        if (-not $rw.Cb.Checked) { continue }
        $sets += @{ Key = $rw.Key; Label = $rw.Label; Mode = "$($rw.Cmb.SelectedItem)"; A = $rw.A.Text; B = $rw.B.Text }
    }
    if (-not $sets.Count) { [void][Windows.Forms.MessageBox]::Show('Marque ao menos um campo para alterar.', 'Editar em massa'); return $false }
    $plan = MassPlan $script:MassGames $sets
    if (-not @($plan).Count) { [void][Windows.Forms.MessageBox]::Show('Nada a alterar: os jogos selecionados já estão com esses valores.', 'Editar em massa'); return $false }
    if (-not (MassPreview $plan $sets)) { return $false }
    $nch = MassApply $script:MassGames $plan
    CatRefresh; Populate; ShowGame (Sel)
    [void][Windows.Forms.MessageBox]::Show("$nch alteração(ões) aplicada(s).`nPara voltar atrás: 'Desfazer edição em massa' na aba Ações.", 'Editar em massa')
    $true
}
function MassLayout($pn) {   # estica as duas colunas de texto com a largura da janela
    $st = $pn.Tag; if (-not $st) { return }
    $half = [Math]::Max(140, [int](($pn.ClientSize.Width - $st.X - 18 - 6) / 2))
    foreach ($rw in $st.Rows) { $rw.A.Width = $half; $rw.B.Left = $st.X + $half + 6; $rw.B.Width = $half }
    $st.HA.Width = $half; $st.HB.Left = $st.X + $half + 6; $st.HB.Width = $half
    $st.Note.Width = [Math]::Max(200, $pn.ClientSize.Width - 24)
}
function MassDescMode($cmb) {   # modo da Descrição: liga/desliga as caixas e mostra "Trocar por" só em Localizar e trocar
    $st = $cmb.Tag; $md = "$($cmb.SelectedItem)"
    $st.A.Enabled = ($md -ne 'Limpar'); $st.B.Enabled = ($md -eq 'Localizar e trocar')
    $st.LA.Text = if ($md -eq 'Localizar e trocar') { 'Localizar (texto exato)' } elseif ($md -eq 'Limpar') { 'Texto (não usado: a descrição será apagada)' } else { 'Texto' }
    $sp = $st.Sp
    if ($md -eq 'Localizar e trocar') {
        if ($sp.Panel2Collapsed) { $sp.Panel2Collapsed = $false; try { $sp.SplitterDistance = [int]($sp.Height / 2) } catch { $Error.Clear() } }
    } else { $sp.Panel2Collapsed = $true }
}
function MassEdit($games) {
    $n = @($games).Count; if ($n -lt 1) { return }
    $f = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = "Editar em massa - $n jogo(s)"; StartPosition = 'CenterParent' }
    WinSizable $f 'EditarEmMassa' 760 600
    $f.ClientSize = New-Object Drawing.Size(1000, 800)
    $W = $f.ClientSize.Width
    # ---- campos de uma linha (em cima) ----
    $pn = New-Object Windows.Forms.Panel -Property @{ Dock = 'Top'; Width = $W }
    $lw = 60; foreach ($fd in $script:MassFields) { $lw = [Math]::Max($lw, (TxtW $fd.Label $f.Font)) }; $lw = [Math]::Min(220, $lw + 8)
    $xC = 30 + $lw + 4; $wC = 150; $xA = $xC + $wC + 6
    $pn.Controls.Add((Lbl 'Marque os campos que quer alterar. O que não estiver marcado continua como está em cada jogo.' 10 8 760 18))
    $hds = @()
    foreach ($hd in @(@('Campo', 30, $lw), @('Modo', $xC, $wC), @('Texto / localizar', $xA, 170), @('Trocar por', ($xA + 176), 170))) {
        $hl = Lbl $hd[0] $hd[1] 32 $hd[2] 18; $hl.ForeColor = 'Gray'; $pn.Controls.Add($hl); $hds += $hl
    }
    $rows = @(); $prow = @(); $y = 54; $dfd = $null
    foreach ($fd in $script:MassFields) {
        if ($fd.Multi) { $dfd = $fd; continue }   # a Descrição tem área própria embaixo
        $cb = New-Object Windows.Forms.CheckBox -Property @{ Left = 10; Top = ($y + 2); Width = 16; Height = 18 }
        $pn.Controls.Add($cb); $pn.Controls.Add((Lbl $fd.Label 30 ($y + 3) $lw 18))
        $cmb = New-Object Windows.Forms.ComboBox -Property @{ DropDownStyle = 'DropDownList'; Left = $xC; Top = $y; Width = $wC }
        [void]$cmb.Items.AddRange([object[]]@(if ($fd.ClearOnly) { 'Limpar' } else { $script:MassModes })); $cmb.SelectedIndex = 0
        $ta = New-Object Windows.Forms.TextBox -Property @{ Left = $xA; Top = $y; Width = 170 }
        $tb2 = New-Object Windows.Forms.TextBox -Property @{ Left = ($xA + 176); Top = $y; Width = 170 }
        $cmb.Tag = @($ta, $tb2)
        $cmb.Add_SelectedIndexChanged({ param($snd, $ev)
            $t1, $t2 = $snd.Tag; $md = "$($snd.SelectedItem)"
            $t1.Enabled = ($md -ne 'Limpar'); $t2.Enabled = ($md -eq 'Localizar e trocar')
        })
        $md0 = "$($cmb.SelectedItem)"; $ta.Enabled = ($md0 -ne 'Limpar'); $tb2.Enabled = ($md0 -eq 'Localizar e trocar')
        $pn.Controls.AddRange(@($cmb, $ta, $tb2))
        $rw = @{ Key = $fd.Key; Label = $fd.Label; Cb = $cb; Cmb = $cmb; A = $ta; B = $tb2 }
        $rows += $rw; $prow += $rw
        $y += 30
    }
    $nt = Lbl '"Localizar e trocar" procura o texto exato (ignora maiúsculas/minúsculas) em cada jogo. Antes de gravar você vê a prévia.' 10 ($y + 2) 760 18
    $nt.ForeColor = 'Gray'; $pn.Controls.Add($nt)
    $pn.Height = $y + 26
    $pn.Tag = @{ Rows = $prow; X = $xA; HA = $hds[2]; HB = $hds[3]; Note = $nt }
    $pn.Add_Resize({ param($snd, $ev) MassLayout $snd })
    # ---- Descrição: área grande (esquerda) + referência de formatação (direita) ----
    $split = New-Object Windows.Forms.SplitContainer -Property @{ Dock = 'Fill'; Orientation = 'Vertical'; SplitterWidth = 6 }
    $split.Panel1.Padding = New-Object Windows.Forms.Padding(10, 4, 3, 4); $split.Panel2.Padding = New-Object Windows.Forms.Padding(3, 4, 12, 4)
    $dHead = New-Object Windows.Forms.Panel -Property @{ Dock = 'Top'; Height = 32 }
    $dCb = New-Object Windows.Forms.CheckBox -Property @{ Left = 0; Top = 6; AutoSize = $true; Text = "$($dfd.Label)" }
    $dCb.Font = New-Object Drawing.Font($dCb.Font, [Drawing.FontStyle]::Bold)
    $dCmb = New-Object Windows.Forms.ComboBox -Property @{ DropDownStyle = 'DropDownList'; Left = 120; Top = 4; Width = 170 }
    [void]$dCmb.Items.AddRange([object[]]@($script:MassModes)); $dCmb.SelectedIndex = 0
    $dHead.Controls.AddRange(@($dCb, $dCmb))
    $sIn = New-Object Windows.Forms.SplitContainer -Property @{ Dock = 'Fill'; Orientation = 'Horizontal'; SplitterWidth = 6; Panel2Collapsed = $true }
    $dA = New-Object Windows.Forms.TextBox -Property @{ Dock = 'Fill'; Multiline = $true; AcceptsReturn = $true; ScrollBars = 'Vertical'; WordWrap = $true }
    $dB = New-Object Windows.Forms.TextBox -Property @{ Dock = 'Fill'; Multiline = $true; AcceptsReturn = $true; ScrollBars = 'Vertical'; WordWrap = $true }
    foreach ($t0 in @($dA, $dB)) { $t0.Font = New-Object Drawing.Font('Consolas', 10) }
    $dLA = New-Object Windows.Forms.Label -Property @{ Dock = 'Top'; Height = 18; Text = 'Texto' }
    $dLB = New-Object Windows.Forms.Label -Property @{ Dock = 'Top'; Height = 18; Text = 'Trocar por' }
    $sIn.Panel1.Controls.Add($dA); $sIn.Panel1.Controls.Add($dLA)
    $sIn.Panel2.Controls.Add($dB); $sIn.Panel2.Controls.Add($dLB)
    $split.Panel1.Controls.Add($sIn); $split.Panel1.Controls.Add($dHead)
    $rb = New-Object Windows.Forms.TextBox -Property @{ Dock = 'Fill'; Multiline = $true; ReadOnly = $true; ScrollBars = 'Vertical'; WordWrap = $true; BackColor = [Drawing.Color]::White; Font = (New-Object Drawing.Font('Consolas', 9)); Text = ($script:DescFmtRef -replace "`r?`n", "`r`n") }
    $lrh = New-Object Windows.Forms.Label -Property @{ Dock = 'Top'; Height = 20; Text = 'Formatação (selecione e copie com Ctrl+C)' }
    $split.Panel2.Controls.Add($rb); $split.Panel2.Controls.Add($lrh)
    $dCmb.Tag = @{ A = $dA; B = $dB; LA = $dLA; Sp = $sIn }
    $dCmb.Add_SelectedIndexChanged({ param($snd, $ev) MassDescMode $snd })
    $drw = @{ Key = $dfd.Key; Label = $dfd.Label; Cb = $dCb; Cmb = $dCmb; A = $dA; B = $dB }
    $rows += $drw
    $script:MassRows = $rows; $script:MassGames = @($games)
    # ---- prévia ao vivo: mostra como fica a descrição do 1º jogo selecionado ----
    $g1 = @($games)[0]
    $pvSt = @{ Pf = $null; Src = $dA; Row = $drw; Game = $g1; Title = "Prévia da descrição - $($g1.Name)"; Tm = (New-Object Windows.Forms.Timer -Property @{ Interval = 350 }) }
    $pvSt.Tm.Tag = $pvSt
    $pvSt.Tm.Add_Tick({ param($snd, $ev) $snd.Stop(); DescPreviewRender $snd.Tag })
    foreach ($c0 in @($dA, $dB)) { $c0.Tag = $pvSt; $c0.Add_TextChanged({ param($snd, $ev) $st = $snd.Tag; if ($st.Pf -and -not $st.Pf.IsDisposed) { $st.Tm.Stop(); $st.Tm.Start() } }) }
    $dCb.Tag = $pvSt; $dCb.Add_CheckedChanged({ param($snd, $ev) DescPreviewRender $snd.Tag })
    $dCmb.Add_SelectedIndexChanged({ param($snd, $ev) DescPreviewRender $snd.Tag.Pv })
    $dCmb.Tag.Pv = $pvSt
    MassDescMode $dCmb
    # ---- botões ----
    $pBt = New-Object Windows.Forms.Panel -Property @{ Dock = 'Bottom'; Height = 46; Width = $W }
    $pv = New-Object Windows.Forms.Button -Property @{ Text = 'Prévia ao vivo'; Left = 10; Top = 9; Width = 140; Height = 28; Anchor = 'Top, Left'; Tag = $pvSt }
    $pv.Add_Click({ param($snd, $ev) DescPreviewLive $snd.FindForm() $snd.Tag })
    $ap = New-Object Windows.Forms.Button -Property @{ Text = 'Ver prévia e aplicar'; Left = ($W - 12 - 262); Top = 9; Width = 160; Height = 28; Anchor = 'Top, Right' }
    $ap.Add_Click({ param($snd, $ev) if (MassRun) { $snd.FindForm().Close() } })
    $ca = New-Object Windows.Forms.Button -Property @{ Text = 'Cancelar'; Left = ($W - 12 - 92); Top = 9; Width = 92; Height = 28; Anchor = 'Top, Right' }
    $ca.Add_Click({ param($snd, $ev) $snd.FindForm().Close() })
    $pBt.Controls.AddRange(@($pv, $ap, $ca))
    # ordem de encaixe: o último adicionado encaixa primeiro
    $f.Controls.Add($split); $f.Controls.Add($pBt); $f.Controls.Add($pn)      # sem AcceptButton/CancelButton: Enter faz parágrafo na descrição
    $f.Tag = $split
    $f.Add_Load({ param($snd, $ev)
        $sp = $snd.Tag
        try {
            $dv = 0; [void][int]::TryParse("$($DevWin['EditarEmMassaDiv'])", [ref]$dv)
            if ($dv -lt 260 -or $dv -gt $sp.Width - 160) { $dv = [int]($sp.Width * 0.64) }
            $sp.SplitterDistance = $dv
            $sp.Panel1MinSize = 260; $sp.Panel2MinSize = 160
        } catch { $Error.Clear() }
    })
    $f.Add_FormClosing({ param($snd, $ev) try { $sp = $snd.Tag; if ($sp.Width -gt 0) { $DevWin['EditarEmMassaDiv'] = "$($sp.SplitterDistance)"; SaveWin } } catch { $Error.Clear() } })
    MassLayout $pn
    [void]$f.ShowDialog()
    $pvSt.Tm.Stop(); $pvSt.Tm.Dispose()
    if ($pvSt.Pf -and -not $pvSt.Pf.IsDisposed) { $pvSt.Pf.Close(); $pvSt.Pf.Dispose() }
    $script:MassRows = @(); $script:MassGames = @()
    $f.Dispose()
}
# Jogos marcados na grade, na ordem do catálogo
function SelGames { $out = @(); foreach ($gm in $script:Games) { if ($script:SelIds.Contains("$($gm.Id)")) { $out += $gm } }; $out }
function MassEditSel {
    if ($script:CatBroken) { [void][Windows.Forms.MessageBox]::Show('O catálogo não pôde ser lido ao abrir o launcher; nada será gravado até o problema ser resolvido.', 'Editar em massa', 'OK', 'Warning'); return }
    $gs = @(SelGames)
    if ($gs.Count -lt 1) { [void][Windows.Forms.MessageBox]::Show("Marque os jogos primeiro: Ctrl+clique, Shift+clique ou Ctrl+A na biblioteca.", 'Editar em massa'); return }
    MassEdit $gs
}
# ---- Modo desenvolvedor: senha + painel ----
function Ask($title, $msg) {
    $f = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = $title; Size = '360,170'; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; MaximizeBox = $false; MinimizeBox = $false }
    $f.Controls.Add((Lbl $msg 12 12 320 20))
    $t = New-Object Windows.Forms.TextBox; $t.SetBounds(12, 38, 320, 22); $t.UseSystemPasswordChar = $true; $f.Controls.Add($t)
    $ok = New-Object Windows.Forms.Button -Property @{ Text = 'OK'; DialogResult = 'OK' }; $ok.SetBounds(170, 80, 75, 26)
    $ca = New-Object Windows.Forms.Button -Property @{ Text = 'Cancelar'; DialogResult = 'Cancel' }; $ca.SetBounds(255, 80, 75, 26)
    $f.Controls.AddRange(@($ok, $ca)); $f.AcceptButton = $ok; $f.CancelButton = $ca
    if ($f.ShowDialog($form) -eq 'OK') { $t.Text } else { $null }
}
function SetPassword {
    $p = Ask 'Nova senha' 'Digite a nova senha:'
    if (-not $p) { return }
    $p2 = Ask 'Confirmar senha' 'Repita a senha:'
    if ($p -ceq $p2) { $S.PassHash = Hash $p; SaveSettings; [void][Windows.Forms.MessageBox]::Show('Senha definida.') }
    else { [void][Windows.Forms.MessageBox]::Show('As senhas não conferem.') }
}
function Unlock {
    if (-not $S.PassHash) { return $false }
    $p = Ask 'Modo desenvolvedor' 'Senha:'
    if ($null -eq $p) { return $false }
    if ((Hash $p) -ceq $S.PassHash) { return $true }
    [void][Windows.Forms.MessageBox]::Show('Senha incorreta.'); $false
}
function TextsPanel {
    $keys = @(@('T_Fav','Botão Favoritar'), @('T_Faved','Botão quando já é favorito'), @('T_Link','Link do jogo'), @('T_Version','Rótulo "Versão"'),
              @('T_Zoom','Rótulo da barra de tamanho'), @('T_All','Filtro: todos'), @('T_Favs','Filtro: favoritos'), @('T_Inst','Filtro: instalados'),
              @('T_NotInst','Filtro: não instalados'), @('T_CtxPlay','Menu: jogar'), @('T_CtxStop','Menu: fechar jogo aberto'), @('T_Starting','Capa: jogo abrindo'), @('T_Running','Capa: jogo em execução'), @('T_Extracting','Capa: jogo sendo extraído'), @('T_Downloading','Capa: jogo sendo baixado'), @('T_CtxCancelDl','Menu: cancelar download'), @('T_CtxFav','Menu: favoritar'), @('T_CtxUnfav','Menu: remover dos favoritos'), @('T_CtxDelete','Menu: deletar jogo'), @('T_Recent','Lista: últimas atualizações (adicionados e atualizados)'), @('T_Empty','Aviso de lista vazia'), @('T_Offline','Aviso de unidade desconectada'), @('T_Archived','Aviso de jogo compactado'))
    $f = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = 'Renomear textos'; StartPosition = 'CenterParent' }
    WinSizable $f 'RenomearTextos' 520 360; $f.ClientSize = New-Object Drawing.Size(640, 600)
    $pn = New-Object Windows.Forms.Panel -Property @{ Dock = 'Fill'; AutoScroll = $true }; $pn.Size = $f.ClientSize
    $lw = 120; foreach ($k in $keys) { $lw = [Math]::Max($lw, (TxtW $k[1] $f.Font) + 8) }; $lw = [Math]::Min(320, $lw); $x = 15 + $lw + 8
    $tx = @{}; $y = 15
    foreach ($k in $keys) {
        $pn.Controls.Add((Lbl $k[1] 15 ($y + 3) $lw 20))
        $t = New-Object Windows.Forms.TextBox; $t.SetBounds($x, $y, ($pn.Width - $x - 30), 22); $t.Anchor = 'Top, Left, Right'; $t.Text = "$($S[$k[0]])"; $pn.Controls.Add($t); $tx[$k[0]] = $t; $y += 32
    }
    $pBt = New-Object Windows.Forms.Panel -Property @{ Dock = 'Bottom'; Height = 46; Width = $f.ClientSize.Width }
    $ok = New-Object Windows.Forms.Button -Property @{ Text = 'Salvar'; DialogResult = 'OK'; Anchor = 'Top, Right' }; $ok.SetBounds(($pBt.Width - 12 - 176), 9, 84, 28)
    $ca = New-Object Windows.Forms.Button -Property @{ Text = 'Cancelar'; DialogResult = 'Cancel'; Anchor = 'Top, Right' }; $ca.SetBounds(($pBt.Width - 12 - 86), 9, 86, 28)
    $pBt.Controls.AddRange(@($ok, $ca)); $f.Controls.Add($pn); $f.Controls.Add($pBt); $f.AcceptButton = $ok; $f.CancelButton = $ca
    if ($f.ShowDialog($form) -eq 'OK') {
        foreach ($k in $tx.Keys) { if ($tx[$k].Text.Trim()) { $S[$k] = $tx[$k].Text } }
        SaveSettings; ApplyLayout; Populate
    }
}
# ---- Painel do modo desenvolvedor: abas geradas a partir de uma tabela (cada campo tem tipo, limites e padrão) ----
$script:DevSchema = @(
    @{ Tab = 'Geral'; Key = 'Title'; Type = 'text'; Label = 'Título da janela' }
    @{ Tab = 'Geral'; Key = 'Maximized'; Type = 'bool'; Label = 'Abrir maximizado' }
    @{ Tab = 'Geral'; Key = 'Fullscreen'; Type = 'bool'; Label = 'Tela cheia sem bordas (F11 alterna durante o uso)' }
    @{ Tab = 'Geral'; Key = 'ShowSearch'; Type = 'bool'; Label = 'Barra de busca' }
    @{ Tab = 'Geral'; Key = 'ShowZoom'; Type = 'bool'; Label = 'Barra Ampliar/Reduzir (vale só enquanto o launcher está aberto)' }
    @{ Tab = 'Geral'; Key = 'Zoom'; Type = 'int'; Min = 1; Max = 3; Label = 'Tamanho das capas ao abrir (1 a 3)' }
    @{ Tab = 'Geral'; Key = 'ShowPanel'; Type = 'bool'; Label = 'Painel de detalhes (direita)' }
    @{ Tab = 'Geral'; Key = 'ShowTitle'; Type = 'bool'; Label = '      Título do jogo' }
    @{ Tab = 'Geral'; Key = 'ShowFav'; Type = 'bool'; Label = '      Botão Favoritar (o item do botão direito aparece sempre)' }
    @{ Tab = 'Geral'; Key = 'ShowVersion'; Type = 'bool'; Label = '      Versão' }
    @{ Tab = 'Geral'; Key = 'ShowLink'; Type = 'bool'; Label = 'Opção "Baixar Jogo" no menu do botão direito (jogos com link)' }
    @{ Tab = 'Geral'; Key = 'ShowDesc'; Type = 'bool'; Label = '      Descrição' }
    @{ Tab = 'Geral'; Key = 'ShowShot'; Type = 'bool'; Label = '      Captura de tela' }
    @{ Tab = 'Geral'; Key = 'Accent'; Type = 'hex'; Label = 'Cor de destaque (#RRGGBB)' }
    @{ Tab = 'Geral'; Key = 'BgColor'; Type = 'hex'; Label = 'Cor de fundo (#RRGGBB)' }
    @{ Tab = 'Geral'; Key = 'SideColor'; Type = 'hex'; Label = 'Cor das caixas, botões e menus (#RRGGBB)' }
    @{ Tab = 'Geral'; Key = 'TextColor'; Type = 'hex'; Label = 'Cor dos textos (#RRGGBB)' }
    @{ Tab = 'Geral'; Key = 'SubColor'; Type = 'hex'; Label = 'Cor dos textos secundários (#RRGGBB)' }
    @{ Tab = 'Geral'; Key = 'BackgroundImage'; Type = 'text'; Label = 'Arte de fundo (caminho completo da imagem; vazio = sem imagem)' }
    @{ Tab = 'Geral'; Key = 'AvatarImage'; Type = 'text'; Label = 'Avatar (caminho completo da imagem; vazio = sem avatar)' }
    @{ Tab = 'Geral'; Key = 'CinemaMode'; Type = 'bool'; Label = 'Seleção horizontal de jogos (visual cinema)' }
    @{ Tab = 'Geral'; Key = 'CinemaAnimate'; Type = 'bool'; Label = 'Animar seleção das capas (desligado = resposta imediata)' }
    @{ Tab = 'Controle'; Key = 'JoystickEnabled'; Type = 'bool'; Label = 'Ativar controle USB/SNES na interface' }
    @{ Tab = 'Controle'; Key = 'JoyConfirm'; Type = 'int'; Min = 1; Max = 32; Label = 'Botão A: jogar / confirmar (número do botão)' }
    @{ Tab = 'Controle'; Key = 'JoyBack'; Type = 'int'; Min = 1; Max = 32; Label = 'Botão B: voltar / cancelar' }
    @{ Tab = 'Controle'; Key = 'JoyDetails'; Type = 'int'; Min = 1; Max = 32; Label = 'Botão X: detalhes' }
    @{ Tab = 'Controle'; Key = 'JoyFilters'; Type = 'int'; Min = 1; Max = 32; Label = 'Botão Y: filtros' }
    @{ Tab = 'Controle'; Key = 'JoyStart'; Type = 'int'; Min = 1; Max = 32; Label = 'Start: jogar / confirmar' }
    @{ Tab = 'Controle'; Key = 'JoyPageLeft'; Type = 'int'; Min = 1; Max = 32; Label = 'L1: saltar para trás na lista' }
    @{ Tab = 'Controle'; Key = 'JoyPageRight'; Type = 'int'; Min = 1; Max = 32; Label = 'R1: saltar para frente na lista' }
    @{ Tab = 'Controle'; Key = 'JoyPageSize'; Type = 'int'; Min = 1; Max = 50; Label = 'Quantidade de jogos por salto L1 / R1' }
    @{ Tab = 'Controle'; Key = 'JoyActions'; Type = 'int'; Min = 1; Max = 32; Label = 'Select: abrir menu de ações' }
    @{ Tab = 'Controle'; Key = 'JoySearchModifier'; Type = 'int'; Min = 1; Max = 32; Label = 'Buscar: segurar este botão + botão de Filtros (Y)' }
    @{ Tab = 'Geral'; Key = 'DeleteColor'; Type = 'hex'; Label = 'Cor da opção "Deletar jogo" no menu do botão direito (#RRGGBB)' }
    @{ Tab = 'Geral'; Key = 'H_Cadastro'; Type = 'header'; Label = 'Cadastro de jogos (nome tirado da pasta)' }
    @{ Tab = 'Geral'; Key = 'NameStrip'; Type = 'text'; Label = 'Tirar do nome da pasta (separe com ;)' }
    @{ Tab = 'Topo'; Key = 'H_TopPos'; Type = 'header'; Label = 'Posição (área: "Área dos jogos" não conta o painel de detalhes; deslocamento negativo = para a esquerda)' }
    @{ Tab = 'Topo'; Key = 'HeaderArea'; Type = 'combo'; Items = @('Área dos jogos', 'Janela inteira'); Label = 'Nome: área de referência' }
    @{ Tab = 'Topo'; Key = 'HeaderAlign'; Type = 'combo'; Items = @('Centro', 'Esquerda', 'Direita'); Label = 'Nome: alinhamento' }
    @{ Tab = 'Topo'; Key = 'HeaderOffsetX'; Type = 'int'; Min = -3000; Max = 3000; Label = 'Nome: deslocamento (px)' }
    @{ Tab = 'Topo'; Key = 'TopJoin'; Type = 'bool'; Label = 'Busca e filtros juntos, lado a lado (usam as opções da busca)' }
    @{ Tab = 'Topo'; Key = 'SearchArea'; Type = 'combo'; Items = @('Área dos jogos', 'Janela inteira'); Label = 'Busca: área de referência' }
    @{ Tab = 'Topo'; Key = 'SearchAlign'; Type = 'combo'; Items = @('Centro', 'Esquerda', 'Direita'); Label = 'Busca: alinhamento' }
    @{ Tab = 'Topo'; Key = 'SearchOffsetX'; Type = 'int'; Min = -3000; Max = 3000; Label = 'Busca: deslocamento (px)' }
    @{ Tab = 'Topo'; Key = 'FilterArea'; Type = 'combo'; Items = @('Área dos jogos', 'Janela inteira'); Label = 'Filtros: área de referência (separados)' }
    @{ Tab = 'Topo'; Key = 'FilterAlign'; Type = 'combo'; Items = @('Centro', 'Esquerda', 'Direita'); Label = 'Filtros: alinhamento (separados)' }
    @{ Tab = 'Topo'; Key = 'FilterOffsetX'; Type = 'int'; Min = -3000; Max = 3000; Label = 'Filtros: deslocamento (px, separados)' }
    @{ Tab = 'Topo'; Key = 'H_HdrNome'; Type = 'header'; Label = 'Nome no topo' }
    @{ Tab = 'Topo'; Key = 'HeaderShow'; Type = 'bool'; Label = 'Mostrar o nome no topo (centralizado)' }
    @{ Tab = 'Topo'; Key = 'HeaderText'; Type = 'text'; Label = 'Texto' }
    @{ Tab = 'Topo'; Key = 'HeaderFont'; Type = 'text'; Label = 'Fonte (vazio = a da interface; aceita as da pasta Fonts)' }
    @{ Tab = 'Topo'; Key = 'HeaderSize'; Type = 'int'; Min = 10; Max = 72; Label = 'Tamanho da fonte' }
    @{ Tab = 'Topo'; Key = 'HeaderStyle'; Type = 'combo'; Items = @('Normal', 'Negrito', 'Itálico', 'Negrito + itálico'); Label = 'Estilo' }
    @{ Tab = 'Topo'; Key = 'HeaderCaps'; Type = 'bool'; Label = 'Tudo em MAIÚSCULAS' }
    @{ Tab = 'Topo'; Key = 'HeaderSpacing'; Type = 'int'; Min = 0; Max = 30; Label = 'Espaço extra entre as letras (px)' }
    @{ Tab = 'Topo'; Key = 'HeaderColor'; Type = 'hex'; Label = 'Cor do texto (#RRGGBB)' }
    @{ Tab = 'Topo'; Key = 'HeaderFill'; Type = 'combo'; Items = @('Degradê suave', 'Cor sólida'); Label = 'Preenchimento (degradê = mais claro em cima)' }
    @{ Tab = 'Topo'; Key = 'H_HdrGlow'; Type = 'header'; Label = 'Brilho (neon)' }
    @{ Tab = 'Topo'; Key = 'HeaderGlow'; Type = 'int'; Min = 0; Max = 100; Label = 'Intensidade do brilho (0 = sem brilho)' }
    @{ Tab = 'Topo'; Key = 'HeaderGlowSize'; Type = 'int'; Min = 1; Max = 30; Label = 'Alcance do brilho (px)' }
    @{ Tab = 'Topo'; Key = 'HeaderGlowColor'; Type = 'hex'; Optional = $true; Label = 'Cor do brilho (vazio = a cor do texto)' }
    @{ Tab = 'Topo'; Key = 'H_HdrEsp'; Type = 'header'; Label = 'Espaço, linha e busca' }
    @{ Tab = 'Topo'; Key = 'HeaderPadTop'; Type = 'int'; Min = 0; Max = 60; Label = 'Espaço acima do nome (px)' }
    @{ Tab = 'Topo'; Key = 'HeaderPadBottom'; Type = 'int'; Min = 0; Max = 60; Label = 'Espaço entre o nome e a busca (px)' }
    @{ Tab = 'Topo'; Key = 'HeaderLine'; Type = 'bool'; Label = 'Linha decorativa embaixo da busca (some nas pontas)' }
    @{ Tab = 'Topo'; Key = 'HeaderLineColor'; Type = 'hex'; Optional = $true; Label = 'Cor da linha (vazio = a cor do texto)' }
    @{ Tab = 'Topo'; Key = 'HeaderLineWidth'; Type = 'int'; Min = 10; Max = 100; Label = 'Largura da linha (% da janela)' }
    @{ Tab = 'Topo'; Key = 'SearchHint'; Type = 'text'; Label = 'Dica dentro da caixa de busca (vazio = sem dica)' }
    @{ Tab = 'Biblioteca'; Key = 'CoverS1'; Type = 'int'; Min = 48; Max = 512; Label = 'Tamanho da capa, zoom 1 (px)' }
    @{ Tab = 'Biblioteca'; Key = 'CoverS2'; Type = 'int'; Min = 48; Max = 512; Label = 'Tamanho da capa, zoom 2 (px)' }
    @{ Tab = 'Biblioteca'; Key = 'CoverS3'; Type = 'int'; Min = 48; Max = 512; Label = 'Tamanho da capa, zoom 3 (px)' }
    @{ Tab = 'Biblioteca'; Key = 'CoverFit'; Type = 'combo'; Items = @('Preencher', 'Ajustar', 'Esticar'); Label = 'Encaixe da imagem (Preencher corta, Esticar deforma)' }
    @{ Tab = 'Biblioteca'; Key = 'GapH'; Type = 'int'; Min = 0; Max = 200; Label = 'Espaço horizontal entre capas (px)' }
    @{ Tab = 'Biblioteca'; Key = 'GapV'; Type = 'int'; Min = 0; Max = 200; Label = 'Espaço vertical entre capas (px)' }
    @{ Tab = 'Biblioteca'; Key = 'PadX'; Type = 'int'; Min = 0; Max = 200; Label = 'Margem lateral da biblioteca (px)' }
    @{ Tab = 'Biblioteca'; Key = 'PadY'; Type = 'int'; Min = 0; Max = 200; Label = 'Margem superior/inferior (px)' }
    @{ Tab = 'Biblioteca'; Key = 'GridCenter'; Type = 'bool'; Label = 'Centralizar a grade na janela' }
    @{ Tab = 'Biblioteca'; Key = 'NameLines'; Type = 'int'; Min = 0; Max = 3; Label = 'Linhas do nome sob a capa (0 = sem nome)' }
    @{ Tab = 'Biblioteca'; Key = 'NameSize'; Type = 'int'; Min = 7; Max = 24; Label = 'Tamanho da fonte do nome' }
    @{ Tab = 'Biblioteca'; Key = 'NameGap'; Type = 'int'; Min = 0; Max = 40; Label = 'Distância entre capa e nome (px)' }
    @{ Tab = 'Biblioteca'; Key = 'SelColor'; Type = 'hex'; Label = 'Cor da borda de seleção (#RRGGBB)' }
    @{ Tab = 'Biblioteca'; Key = 'SelWidth'; Type = 'int'; Min = 0; Max = 12; Label = 'Espessura da borda (0 = sem borda)' }
    @{ Tab = 'Biblioteca'; Key = 'SelGap'; Type = 'int'; Min = 0; Max = 16; Label = 'Distância entre a borda e a capa (px)' }
    @{ Tab = 'Biblioteca'; Key = 'SelStyle'; Type = 'combo'; Items = @('Sólida', 'Tracejada'); Label = 'Estilo da borda' }
    @{ Tab = 'Biblioteca'; Key = 'NotInstalled'; Type = 'combo'; Items = @('Preto e branco', 'Escurecida', 'Os dois', 'Nada'); Label = 'Jogo não instalado / indisponível' }
    @{ Tab = 'Compactados'; Key = 'UnrarPath'; Type = 'text'; Label = 'UnRAR.exe (relativo à pasta do launcher)' }
    @{ Tab = 'Compactados'; Key = 'TdlPath'; Type = 'text'; Label = 'tdl.exe para baixar do Telegram (relativo à pasta do launcher)' }
    @{ Tab = 'Compactados'; Key = 'TelegramPath'; Type = 'text'; Label = 'Telegram portátil, usado para conectar a conta (relativo à pasta do launcher)' }
    @{ Tab = 'Atualização'; Key = 'UpdUrl'; Type = 'text'; Label = 'Endereço do arquivo de atualização UpdateWinPort, .zip ou .rar (https://...; vazio = sem atualização automática)' }
    @{ Tab = 'Atualização'; Key = 'UpdPass'; Type = 'text'; Label = 'Senha do arquivo de atualização (só .rar; vazio = sem senha)' }
    @{ Tab = 'Compactados'; Key = 'ArchivePass'; Type = 'text'; Label = 'Senha dos arquivos .rar (vazio = sem senha)' }
    @{ Tab = 'Compactados'; Key = 'ArchiveDirs'; Type = 'text'; Label = 'Pastas extras com .rar (separe com ;)' }
    @{ Tab = 'Detalhes'; Key = 'H_Painel'; Type = 'header'; Label = 'Painel' }
    @{ Tab = 'Detalhes'; Key = 'DetailWidth'; Type = 'int'; Min = 260; Max = 800; Label = 'Largura do painel de detalhes (px)' }
    @{ Tab = 'Detalhes'; Key = 'DetailPad'; Type = 'int'; Min = 0; Max = 60; Label = 'Margem interna do painel (px)' }
    @{ Tab = 'Detalhes'; Key = 'DetailBg'; Type = 'hex'; Optional = $true; Label = 'Cor de fundo (vazio = a do fundo geral)' }
    @{ Tab = 'Detalhes'; Key = 'H_Titulo'; Type = 'header'; Label = 'Título do jogo' }
    @{ Tab = 'Detalhes'; Key = 'TitleFont'; Type = 'text'; Label = 'Fonte do título (vazio = a da interface)' }
    @{ Tab = 'Detalhes'; Key = 'TitleSize'; Type = 'int'; Min = 12; Max = 60; Label = 'Tamanho do título (pt)' }
    @{ Tab = 'Detalhes'; Key = 'TitleStyle'; Type = 'combo'; Items = @('Normal', 'Negrito', 'Itálico', 'Negrito + itálico'); Label = 'Estilo do título' }
    @{ Tab = 'Detalhes'; Key = 'TitleColor'; Type = 'hex'; Optional = $true; Label = 'Cor do título (vazio = cor do texto)' }
    @{ Tab = 'Detalhes'; Key = 'TitleLines'; Type = 'int'; Min = 1; Max = 4; Label = 'Linhas máximas do título' }
    @{ Tab = 'Detalhes'; Key = 'TitleAlign'; Type = 'combo'; Items = @('Esquerda', 'Centro', 'Direita'); Label = 'Alinhamento do título' }
    @{ Tab = 'Detalhes'; Key = 'H_Aviso'; Type = 'header'; Label = 'Avisos (unidade desconectada, compactado) e versão' }
    @{ Tab = 'Detalhes'; Key = 'StatusSize'; Type = 'int'; Min = 8; Max = 20; Label = 'Tamanho dos avisos (pt)' }
    @{ Tab = 'Detalhes'; Key = 'StatusColor'; Type = 'hex'; Optional = $true; Label = 'Cor dos avisos (vazio = vermelho suave)' }
    @{ Tab = 'Detalhes'; Key = 'StatusStyle'; Type = 'combo'; Items = @('Normal', 'Negrito', 'Itálico', 'Negrito + itálico'); Label = 'Estilo dos avisos' }
    @{ Tab = 'Detalhes'; Key = 'StatusAlign'; Type = 'combo'; Items = @('Esquerda', 'Centro', 'Direita'); Label = 'Alinhamento dos avisos' }
    @{ Tab = 'Detalhes'; Key = 'StatusGapTop'; Type = 'int'; Min = 0; Max = 60; Label = 'Espaço acima dos avisos (px)' }
    @{ Tab = 'Detalhes'; Key = 'StatusGapBottom'; Type = 'int'; Min = 0; Max = 60; Label = 'Espaço abaixo dos avisos (px)' }
    @{ Tab = 'Detalhes'; Key = 'VersionSize'; Type = 'int'; Min = 8; Max = 20; Label = 'Tamanho da versão (pt)' }
    @{ Tab = 'Detalhes'; Key = 'VersionColor'; Type = 'hex'; Optional = $true; Label = 'Cor da versão (vazio = cor de destaque)' }
    @{ Tab = 'Detalhes'; Key = 'H_Desc'; Type = 'header'; Label = 'Descrição' }
    @{ Tab = 'Detalhes'; Key = 'DescFont'; Type = 'text'; Label = 'Fonte só da descrição (vazio = a da interface)' }
    @{ Tab = 'Detalhes'; Key = 'DescSize'; Type = 'int'; Min = 8; Max = 24; Label = 'Tamanho do texto (pt)' }
    @{ Tab = 'Detalhes'; Key = 'DescColor'; Type = 'hex'; Optional = $true; Label = 'Cor do texto (vazio = cor do texto geral)' }
    @{ Tab = 'Detalhes'; Key = 'DescAlign'; Type = 'combo'; Items = @('Esquerda', 'Centro', 'Direita'); Label = 'Alinhamento do texto' }
    @{ Tab = 'Detalhes'; Key = 'DescTitleSize'; Type = 'int'; Min = 12; Max = 48; Label = 'Tamanho de [titulo] (pt)' }
    @{ Tab = 'Detalhes'; Key = 'DescTitleColor'; Type = 'hex'; Optional = $true; Label = 'Cor de [titulo] (vazio = cor de destaque)' }
    @{ Tab = 'Detalhes'; Key = 'DescSubSize'; Type = 'int'; Min = 10; Max = 32; Label = 'Tamanho de [sub] (pt)' }
    @{ Tab = 'Detalhes'; Key = 'DescLinkColor'; Type = 'hex'; Label = 'Cor dos links na descrição' }
    @{ Tab = 'Fontes e texto'; Key = 'FontFamily'; Type = 'combo'; Items = @('(padrão: Segoe UI)'); Label = 'Fonte da interface (arquivos .ttf/.otf da pasta fonts)' }
    @{ Tab = 'Fontes e texto'; Key = 'TextWeight'; Type = 'combo'; Items = @('Normal', 'Médio', 'Negrito'); Label = 'Peso do texto (Médio = meio termo; usa Semibold/Medium da fonte)' }
    @{ Tab = 'Fontes e texto'; Key = 'TextRender'; Type = 'combo'; Items = @('ClearType', 'Suavizado (cinza)', 'Suavizado (grade)', 'Padrão do sistema', 'Sem suavização'); Label = 'Suavização do texto na biblioteca (ClearType = padrão; Firmeza só age nos modos suavizados/ClearType)' }
    @{ Tab = 'Fontes e texto'; Key = 'TextContrast'; Type = 'int'; Min = 0; Max = 12; Label = 'Firmeza das letras na biblioteca (0 a 12; maior = mais firme)' }
    @{ Tab = 'Imagens'; Key = 'CoverDir'; Type = 'text'; Label = 'Pasta das capas (vazio = desligado)' }
    @{ Tab = 'Imagens'; Key = 'ShotDir'; Type = 'text'; Label = 'Pasta das capturas (vazio = desligado)' }
    @{ Tab = 'Imagens'; Key = 'CoverPattern'; Type = 'text'; Label = 'Nome da capa: {Nome} {Alt} {Id} separados por |' }
    @{ Tab = 'Imagens'; Key = 'ShotPattern'; Type = 'text'; Label = 'Nome da captura: {Nome} {Alt} {Id} separ. por |' }
    @{ Tab = 'Imagens'; Key = 'ImgExts'; Type = 'text'; Label = 'Extensões por prioridade (png,jpg,jpeg)' }
    @{ Tab = 'Imagens'; Key = 'ImgLoose'; Type = 'bool'; Label = 'Tolerante: ignora maiúsculas, acentos e símbolos no nome' }
    @{ Tab = 'Biblioteca'; Key = 'ThumbCache'; Type = 'bool'; Label = 'Guardar miniaturas das capas (abre bem mais rápido; vale ao reabrir)' }
    @{ Tab = 'Biblioteca'; Key = 'LoadScreen'; Type = 'bool'; Label = 'Tela "Carregando jogos" ao abrir (mostra o launcher com as capas prontas)' }
    @{ Tab = 'Biblioteca'; Key = 'CoverCacheMB'; Type = 'int'; Min = 16; Max = 2048; Label = 'Memória máxima para capas (MB)' }
    @{ Tab = 'Biblioteca'; Key = 'CoverPrefetchRows'; Type = 'int'; Min = 0; Max = 10; Label = 'Linhas carregadas antes de aparecer (acima e abaixo)' }
    @{ Tab = 'Biblioteca'; Key = 'CoverThreads'; Type = 'int'; Min = 1; Max = 4; Label = 'Threads para carregar capas (vale ao reabrir)' }
    @{ Tab = 'Biblioteca'; Key = 'InstRecheckSec'; Type = 'int'; Min = 0; Max = 3600; Label = 'Reverificar instalação ao voltar para a janela (segundos; 0 = só no F5)' }
    @{ Tab = 'Biblioteca'; Key = 'DimNotInst'; Type = 'int'; Min = 0; Max = 100; Label = 'Escurecimento dos não instalados (%)' }
    @{ Tab = 'Biblioteca'; Key = 'DimInstalled'; Type = 'int'; Min = 0; Max = 100; Label = 'Escurecimento dos instalados (%; 0 = nenhum)' }
    @{ Tab = 'Biblioteca'; Key = 'SelBright'; Type = 'bool'; Label = 'Capa selecionada sempre com brilho total (sem escurecer)' }
    @{ Tab = 'Biblioteca'; Key = 'SmoothScroll'; Type = 'bool'; Label = 'Rolagem suave (a roda do mouse desliza em vez de pular)' }
    @{ Tab = 'Biblioteca'; Key = 'H_Play'; Type = 'header'; Label = 'Jogo em execução' }
    @{ Tab = 'Biblioteca'; Key = 'PlayPulse'; Type = 'int'; Min = 0; Max = 100; Label = 'Intensidade do pulso da capa (0 = sem pulso)' }
    @{ Tab = 'Biblioteca'; Key = 'PlayBorderColor'; Type = 'hex'; Optional = $true; Label = 'Cor do pulso e da borda (vazio = cor de destaque)' }
    @{ Tab = 'Biblioteca'; Key = 'PlayDotColor'; Type = 'hex'; Optional = $true; Label = 'Cor da bolinha (vazio = cor de destaque)' }
    @{ Tab = 'Biblioteca'; Key = 'PlayDotSize'; Type = 'int'; Min = 4; Max = 20; Label = 'Tamanho da bolinha (px)' }
    @{ Tab = 'Biblioteca'; Key = 'PlayTextColor'; Type = 'hex'; Optional = $true; Label = 'Cor do texto "Em execução" (vazio = cor de destaque)' }
    @{ Tab = 'Biblioteca'; Key = 'PlayTextSize'; Type = 'int'; Min = 0; Max = 24; Label = 'Tamanho do texto (0 = o mesmo do nome do jogo)' }
    @{ Tab = 'Biblioteca'; Key = 'PlayBold'; Type = 'bool'; Label = 'Texto "Em execução" em negrito' }
    @{ Tab = 'Biblioteca'; Key = 'PlayItalic'; Type = 'bool'; Label = 'Texto "Em execução" em itálico' }
    @{ Tab = 'Biblioteca'; Key = 'PlayCheckSec'; Type = 'int'; Min = 1; Max = 30; Label = 'Verificar se o jogo continua aberto a cada (segundos)' }
    @{ Tab = 'Filtros'; Key = 'ShowFilter'; Type = 'bool'; Label = 'Mostrar o menu de filtros (ao lado da busca)' }
    @{ Tab = 'Filtros'; Key = 'ShowSideCount'; Type = 'bool'; Label = 'Mostrar a quantidade de jogos em cada opção' }
    @{ Tab = 'Filtros'; Key = 'RecentDays'; Type = 'int'; Min = 1; Max = 3650; Label = '"Últimas atualizações": adicionados ou com descrição alterada nos últimos N dias' }
    @{ Tab = 'Filtros'; Key = 'SideItems'; Type = 'sideitems'; Label = 'Opções do menu (marque para mostrar; use os botões para mudar a ordem)' }
)
function DevSwatch($tb) {   # pequena prévia da cor digitada
    $sw = $tb.Tag; $t = $tb.Text.Trim()
    if ($t -match '^#?[0-9A-Fa-f]{6}$') { if ($t[0] -ne '#') { $t = "#$t" }; $sw.BackColor = [Drawing.ColorTranslator]::FromHtml($t) } else { $sw.BackColor = [Drawing.Color]::Gray }
}
function DevFillSide($clb, $csv) {
    $vis = @(("$csv" -split '[,; ]+') | Where-Object { $AllKeys -contains $_ } | Select-Object -Unique)
    $order = New-Object System.Collections.ArrayList; $clb.Items.Clear()
    foreach ($k in $vis) { [void]$order.Add($k); [void]$clb.Items.Add((FilterText $k), $true) }
    foreach ($k in $AllKeys) { if ($vis -notcontains $k) { [void]$order.Add($k); [void]$clb.Items.Add((FilterText $k), $false) } }
    $clb.Tag = $order
}
function DevMoveSide($clb, $dir) {
    $i = $clb.SelectedIndex; $j = $i + $dir
    if ($i -lt 0 -or $j -lt 0 -or $j -ge $clb.Items.Count) { return }
    $ti = $clb.Items[$i]; $ci = $clb.GetItemChecked($i); $cj = $clb.GetItemChecked($j); $tj = $clb.Items[$j]
    $clb.Items[$i] = $tj; $clb.Items[$j] = $ti; $clb.SetItemChecked($i, $cj); $clb.SetItemChecked($j, $ci)
    $ord = $clb.Tag; $tmp = $ord[$i]; $ord[$i] = $ord[$j]; $ord[$j] = $tmp
    $clb.SelectedIndex = $j
}
function DevSetControls($ctl, $items, $src) {   # preenche os campos com os valores de $src (layout atual ou padrões)
    foreach ($d in $items) {
        $k = $d.Key; $ct = $ctl[$k]
        switch ($d.Type) {
            'text' { $ct.Text = "$($src[$k])" }
            'bool' { $ct.Checked = [bool]$src[$k] }
            'int' { $v = 0; if (-not [int]::TryParse("$($src[$k])", [ref]$v)) { $v = [int]$Defaults[$k] }; $ct.Value = [Math]::Min($d.Max, [Math]::Max($d.Min, $v)) }
            'hex' { $ct.Text = "$($src[$k])"; DevSwatch $ct }
            'combo' { $ix = $ct.Items.IndexOf("$($src[$k])"); if ($ix -lt 0) { $ix = 0 }; $ct.SelectedIndex = $ix }
            'sideitems' { DevFillSide $ct "$($src[$k])" }
        }
    }
}
function DevSave($dlg) {
    $st = $dlg.Tag; $ctl = $st.Ctl; $new = @{}
    foreach ($d in $script:DevSchema) {
        $k = $d.Key; $ct = $ctl[$k]
        switch ($d.Type) {
            'text' { $new[$k] = $ct.Text }
            'bool' { $new[$k] = [bool]$ct.Checked }
            'int' { $new[$k] = [int]$ct.Value }
            'hex' {
                $t = $ct.Text.Trim()
                if ($t -eq '' -and $d.Optional) { $new[$k] = ''; continue }
                if ($t -notmatch '^#?[0-9A-Fa-f]{6}$') {
                    [void][Windows.Forms.MessageBox]::Show("Cor inválida em: $($d.Label)`nUse o formato #RRGGBB (por exemplo #FF8800).", 'Cor inválida')
                    $st.Tc.SelectedTab = $ct.Parent; $ct.Focus() | Out-Null; return
                }
                if ($t[0] -ne '#') { $t = "#$t" }; $new[$k] = $t.ToUpper()
            }
            'combo' { $sv = "$($ct.SelectedItem)"; if ($sv.StartsWith('(')) { $sv = '' }; $new[$k] = $sv }
            'sideitems' {
                $vis = @(); for ($j = 0; $j -lt $ct.Items.Count; $j++) { if ($ct.GetItemChecked($j)) { $vis += $ct.Tag[$j] } }
                if (-not $vis) { $vis = @('all') }; $new[$k] = ($vis -join ',')
            }
        }
    }
    [void](Backup $SetFile 'antes-layout')
    foreach ($k in $new.Keys) { $S[$k] = $new[$k] }
    SaveSettings; Log 'INFO' 'Layout salvo pelo modo desenvolvedor'
    $zv = [Math]::Min(3, [Math]::Max(1, [int]$S.Zoom)); if ([int]$zm.Value -ne $zv) { $zm.Value = $zv }
    ApplyLayout; CatRefresh; Populate
}
function DevRestore($dlg, $all) {
    $st = $dlg.Tag
    $tab = $st.Tc.SelectedTab.Text
    $items = @($script:DevSchema | Where-Object { $all -or $_.Tab -eq $tab })
    if (-not $items) { return }
    $what = if ($all) { 'TODO o layout' } else { "a aba '$tab'" }
    if ([Windows.Forms.MessageBox]::Show("Restaurar $what para os valores de fábrica?`n(Os campos só são gravados quando você clicar em 'Salvar e aplicar'.)", 'Restaurar padrões', 'YesNo') -ne 'Yes') { return }
    DevSetControls $st.Ctl $items $Defaults
}
function DevPanel {
    if(-not $script:TarginoDeveloperAuthenticated){return}
    FontsScan
    foreach ($ds in $script:DevSchema) { if ($ds.Key -eq 'FontFamily') { $ds.Items = @('(padrão: Segoe UI)') + @($script:FontFam.Values | ForEach-Object { $_.Name } | Sort-Object -Unique) } }
    $f = New-Object Windows.Forms.Form -Property @{ ShowIcon = $false; Text = "Modo desenvolvedor - v$AppVer"; StartPosition = 'CenterParent' }
    WinSizable $f 'PainelDev' 760 520
    $f.ClientSize = New-Object Drawing.Size(900, 680)
    $tc = New-Object Windows.Forms.TabControl -Property @{ Dock = 'Fill' }
    $tabs = @{}; $ypos = @{}; $lws = @{}
    foreach ($tn in 'Geral', 'Topo', 'Biblioteca', 'Detalhes', 'Imagens', 'Fontes e texto', 'Compactados', 'Atualização', 'Filtros', 'Controle', 'Ações') {
        $tp = New-Object Windows.Forms.TabPage; $tp.Text = $tn; $tp.AutoScroll = $true; $tp.Tag = New-Object System.Collections.ArrayList
        [void]$tc.TabPages.Add($tp); $tabs[$tn] = $tp; $ypos[$tn] = 15; $lws[$tn] = 120
    }
    # largura da coluna de rótulos de cada aba = maior rótulo da aba (máx. 420 px; acima disso o rótulo quebra em 2 linhas)
    foreach ($d in $script:DevSchema) { if ($d.Type -notin 'bool', 'header') { $lws[$d.Tab] = [Math]::Max($lws[$d.Tab], (TxtW $d.Label $f.Font) + 8) } }
    foreach ($tn in @($lws.Keys)) { $lws[$tn] = [Math]::Min(420, $lws[$tn]) }
    $ctl = @{}
    foreach ($d in $script:DevSchema) {
        $tp = $tabs[$d.Tab]; $y = $ypos[$d.Tab]; $h = 28; $lw = $lws[$d.Tab]; $x = 15 + $lw + 10
        if ($d.Type -eq 'header') {
            $hl = New-Object Windows.Forms.Label -Property @{ AutoSize = $true; Left = 15; Top = ($y + 8); Text = $d.Label }
            $hl.Font = New-Object Drawing.Font($hl.Font, [Drawing.FontStyle]::Bold); $tp.Controls.Add($hl); $h = 36
        } elseif ($d.Type -eq 'bool') {
            $cb = New-Object Windows.Forms.CheckBox -Property @{ Left = 15; Top = $y; AutoSize = $true; Text = $d.Label }
            $tp.Controls.Add($cb); $ctl[$d.Key] = $cb; $h = 26
        } else {
            $lb = Lbl $d.Label 15 ($y + 3) $lw 20
            if ((TxtW $d.Label $f.Font) + 8 -gt $lw) { $lb.Height = 34; $h = 42 }
            $tp.Controls.Add($lb)
            if ($d.Type -eq 'text') {
                $tb = New-Object Windows.Forms.TextBox; $tb.SetBounds($x, $y, 330, 22); $tp.Controls.Add($tb); $ctl[$d.Key] = $tb; [void]$tp.Tag.Add($tb)
                if ($d.Key -in 'BackgroundImage','AvatarImage') {
                    $browse=New-Object Windows.Forms.Button -Property @{ Text='Procurar imagem…'; Left=$x; Top=($y+24); Width=145; Height=26; Tag=$tb }
                    $browse.Add_Click({ param($sender,$args)
                        $picker=New-Object Windows.Forms.OpenFileDialog -Property @{ Title='Escolher imagem'; Filter='Imagens|*.png;*.jpg;*.jpeg;*.bmp;*.gif|Todos os arquivos|*.*'; CheckFileExists=$true }
                        try { if ($picker.ShowDialog($sender.FindForm()) -eq 'OK') { $sender.Tag.Text=$picker.FileName } } finally { $picker.Dispose() }
                    })
                    $clear=New-Object Windows.Forms.Button -Property @{ Text='Remover'; Left=($x+153); Top=($y+24); Width=90; Height=26; Tag=$tb }
                    $clear.Add_Click({ param($sender,$args) $sender.Tag.Clear() })
                    $tp.Controls.AddRange(@($browse,$clear)); $h=58
                }
            } elseif ($d.Type -eq 'int') {
                $nu = New-Object Windows.Forms.NumericUpDown; $nu.Minimum = $d.Min; $nu.Maximum = $d.Max; $nu.SetBounds($x, $y, 80, 22); $tp.Controls.Add($nu); $ctl[$d.Key] = $nu
                $hl = New-Object Windows.Forms.Label -Property @{ AutoSize = $true; Left = ($x + 90); Top = ($y + 3); Text = "$($d.Min) a $($d.Max)"; ForeColor = 'Gray' }; $tp.Controls.Add($hl)
            } elseif ($d.Type -eq 'hex') {
                $tb = New-Object Windows.Forms.TextBox; $tb.SetBounds($x, $y, 100, 22); $tb.MaxLength = 7
                $sw = New-Object Windows.Forms.Panel -Property @{ Left = ($x + 110); Top = $y; Width = 40; Height = 22; BorderStyle = 'FixedSingle' }
                $tb.Tag = $sw; $tb.Add_TextChanged({ param($snd, $ev) DevSwatch $snd })
                $tp.Controls.Add($tb); $tp.Controls.Add($sw); $ctl[$d.Key] = $tb
            } elseif ($d.Type -eq 'combo') {
                $cw = 200; foreach ($it in @($d.Items)) { $cw = [Math]::Max($cw, (TxtW $it $f.Font) + 30) }
                $cmb = New-Object Windows.Forms.ComboBox -Property @{ DropDownStyle = 'DropDownList'; Left = $x; Top = $y; Width = [Math]::Min(400, $cw) }
                [void]$cmb.Items.AddRange([object[]]$d.Items); $tp.Controls.Add($cmb); $ctl[$d.Key] = $cmb
            } elseif ($d.Type -eq 'sideitems') {
                $clb = New-Object Windows.Forms.CheckedListBox -Property @{ Left = $x; Top = $y; Width = 260; Height = 130; CheckOnClick = $true }
                $up = New-Object Windows.Forms.Button -Property @{ Text = 'Subir'; Left = ($x + 270); Top = $y; Width = 80; Height = 26 }
                $dn = New-Object Windows.Forms.Button -Property @{ Text = 'Descer'; Left = ($x + 270); Top = ($y + 32); Width = 80; Height = 26 }
                $up.Tag = $clb; $dn.Tag = $clb
                $up.Add_Click({ param($snd, $ev) DevMoveSide $snd.Tag -1 }); $dn.Add_Click({ param($snd, $ev) DevMoveSide $snd.Tag 1 })
                $tp.Controls.AddRange(@($clb, $up, $dn)); $ctl[$d.Key] = $clb; $h = 140
            }
        }
        $ypos[$d.Tab] = $y + $h
    }
    # campos de texto esticam até a borda direita da aba
    foreach ($tp in $tabs.Values) {
        $tp.Add_Resize({ param($snd, $ev) foreach ($c in $snd.Tag) { $c.Width = [Math]::Max(200, $snd.ClientSize.Width - ($c.Left - $snd.AutoScrollPosition.X) - 20) } })
    }
    # aba Ações: cadastro e manutenção do catálogo
    $acts = @(
        @('+ Adicionar jogo',         { if (Edit $null) { CatRefresh; Populate } }),
        @('Adicionar jogos em massa...', { BulkAdd }),
        @('Reconstruir índice de imagens', { ImgRebuildReport }),
        @('Editar jogo selecionado',  { $g = Sel; if ($g -and (Edit $g)) { CatRefresh; Populate } }),
        @('Remover jogo selecionado', { RemoveGame (Sel) }),
        @('Editar em massa...',       { MassEditSel }),
        @('Desfazer edição em massa', { MassUndoRun }),
        @('Diagnóstico de desempenho', { PerfReport }),
        @('Renomear textos...',       { TextsPanel }),
        @('Trocar senha',             { SetPassword })
    )
    $aw = 260; foreach ($a in $acts) { $aw = [Math]::Max($aw, (TxtW $a[0] $f.Font) + 30) }
    $by = 15; $bx = 15; $half = [Math]::Ceiling($acts.Count / 2); $ai = 0
    foreach ($a in $acts) {   # duas colunas
        if ($ai -eq $half) { $by = 15; $bx = 15 + $aw + 15 }
        $b = New-Object Windows.Forms.Button -Property @{ Text = $a[0] }; $b.SetBounds($bx, $by, $aw, 32); $b.Add_Click($a[1]); $tabs['Ações'].Controls.Add($b); $by += 40; $ai++
    }
    $fl = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock = 'Bottom'; Height = 46; Padding = (New-Object Windows.Forms.Padding(8, 7, 8, 0)); WrapContents = $false }
    $btns = @(
        @('Salvar e aplicar',   { param($snd, $ev) DevSave $snd.FindForm() }),
        @('Restaurar esta aba', { param($snd, $ev) DevRestore $snd.FindForm() $false }),
        @('Restaurar tudo',     { param($snd, $ev) DevRestore $snd.FindForm() $true }),
        @('Sair do modo dev',   { param($snd, $ev) $script:Dev = $false; ApplyLayout; $snd.FindForm().Close() }),
        @('Fechar',             { param($snd, $ev) $snd.FindForm().Close() })
    )
    foreach ($bd in $btns) {
        $b = New-Object Windows.Forms.Button -Property @{ Text = $bd[0]; Height = 30; Width = [Math]::Max(130, (TxtW $bd[0] $f.Font) + 30); Margin = (New-Object Windows.Forms.Padding(4, 0, 6, 0)) }
        $b.Add_Click($bd[1]); $fl.Controls.Add($b)
    }
    $f.Controls.Add($tc); $f.Controls.Add($fl)
    $f.Tag = @{ Ctl = $ctl; Tc = $tc }
    DevSetControls $ctl $script:DevSchema $S
    $f.Add_Shown({ param($snd, $ev) foreach ($tp in $snd.Tag.Tc.TabPages) { foreach ($c in $tp.Tag) { $c.Width = [Math]::Max(200, $tp.ClientSize.Width - $c.Left - 20) } } })
    [void]$f.ShowDialog($form)
}

# ---- Eventos ----
# Menu do jogo: só abre sobre a capa/nome de um jogo e sempre age sobre o jogo clicado ($script:CtxGame).
# Regra de seleção: clicar com o direito num jogo já selecionado mantém a seleção; num jogo não selecionado,
# seleciona só ele antes de abrir o menu. Clique no fundo/espaço vazio não abre menu.
$script:CtxGame = $null
$cm = New-Object Windows.Forms.ContextMenuStrip -Property @{ ShowImageMargin = $false; ShowCheckMargin = $false }
$cm.Renderer = $script:MenuRend
# O menu é montado do zero a cada abertura, só com os itens que valem naquele momento.
function AddCtx($text, $action) { [void]$cm.Items.Add("$text", $null, $action) }
$cm.Add_Opening({
    param($snd, $e)
    $g = $script:CtxGame; if (-not $g) { $e.Cancel = $true; return }
    $ctxRun = RunFind "$($g.Id)"
    if ($ctxRun -and $ctxRun.Stage -ne 'dl') { $e.Cancel = $true; return }      # extraindo (v2.48.0): sem menu até terminar ou falhar
    foreach ($old in @($cm.Items)) { $old.Dispose() }; $cm.Items.Clear()
    if ($ctxRun) { AddCtx (PlayText 'T_CtxCancelDl' 'Cancelar download') { $g = $script:CtxGame; if ($g) { TgCancel "$($g.Id)" } }; return }      # baixando (v2.53.0): só "Cancelar download"
    # Jogo aberto (v2.41.0): a ação que está rodando (Jogar ou um extra-programa) vira "Fechar jogo"; as outras ações que abrem
    #  programa ficam cinza (uma de cada vez por jogo). Extras que são pasta/site/documento/.rar continuam disponíveis.
    $ctxPl = $script:Play["$($g.Id)"]; $ctxStop = PlayText 'T_CtxStop' 'Fechar jogo'
    if ($ctxPl -and -not $ctxPl.Extra) { AddCtx $ctxStop { $g = $script:CtxGame; if ($g) { PlayStop $g } } }   # jogo aberto pelo Jogar: encerra à força
    else {
        $jgMi = $cm.Items.Add($(if ("$($g.PlayName)".Trim()) { "$($g.PlayName)".Trim() } else { "$($S.T_CtxPlay)" }), $null, { $g = $script:CtxGame; if ($g) { Launch $g } })   # nome próprio do jogo (PlayName) ou o geral
        if ($ctxPl) { $jgMi.Enabled = $false }      # um extra está rodando
    }
    # Extras do jogo (campo Extras do editor): um item por extra, na ordem cadastrada, no MESMO bloco do Jogar (sem linha entre eles, v2.38.0)
    $xeList = @(ExtrasParse $g.Extras)
    if ($xeList.Count) {
        foreach ($xe in $xeList) {
            if ($ctxPl -and $ctxPl.Extra -and (XeKey $ctxPl.Extra) -eq (XeKey $xe)) { AddCtx $ctxStop { $g = $script:CtxGame; if ($g) { PlayStop $g } }; continue }   # este extra está rodando
            $xeMi = $cm.Items.Add("$($xe.Name)", $null, { param($snd, $ev) $g = $script:CtxGame; if ($g) { ExtraRun $g $snd.Tag } }); $xeMi.Tag = $xe
            if ($ctxPl -and (XeIsProg $g $xe)) { $xeMi.Enabled = $false }
        }
        [void]$cm.Items.Add('-')
    }
    # Favoritar/Remover dos favoritos: sempre no menu do botão direito (ShowFav controla só o botão do painel de detalhes)
    AddCtx $(if ($U.Fav -contains $g.Id) { $S.T_CtxUnfav } else { $S.T_CtxFav }) { $g = $script:CtxGame; if ($g) { ToggleFav $g; Populate; ShowGame (Sel) } }
    AddCtx 'Personalizar launcher...' {ShowTarginoPreferences}
    if ($S.ShowLink -and $g.Link) { AddCtx $S.T_Link { $g = $script:CtxGame; if ($g -and $g.Link) { GameLinkOpen $g } } }      # link do Telegram: baixa direto para Jogos (v2.53.0)
    if ($script:Dev) {
        [void]$cm.Items.Add('-')
        AddCtx 'Editar' { $g = $script:CtxGame; if ($g -and (Edit $g)) { CatRefresh; Populate } }
        if ($script:SelIds.Count -gt 1) { AddCtx "Editar em massa ($($script:SelIds.Count) jogos)..." { MassEditSel } }
        AddCtx 'Remover' { RemoveGame $script:CtxGame }
    }
    # "Deletar jogo": só aparece se o jogo está instalado (pasta existe, dentro de Jogos\) e não está sendo apagado; cor definida no modo dev (DeleteColor)
    $dlShow = $false
    try { $dlShow = (($script:InstState["$($g.Id)"] -eq 'ok') -and -not $script:Del.ContainsKey("$($g.Id)") -and [bool](DeleteFolderOf $g)) } catch { $Error.Clear() }
    if ($dlShow) {
        [void]$cm.Items.Add('-')
        $dlItem = $cm.Items.Add("$($S.T_CtxDelete)", $null, { $g = $script:CtxGame; if ($g) { DeleteGame $g } })
        $dlItem.Tag = 'danger'      # cor DeleteColor, aplicada pelo DarkMenuRenderer
    }
    foreach ($ci in $cm.Items) { if ($ci -is [Windows.Forms.ToolStripMenuItem]) { $ci.Padding = New-Object Windows.Forms.Padding (12, 3, 14, 3) } }
})
function ShowGameMenu($i, $pt) {
    if ($i -lt 0 -or $i -ge $script:View.Count) { return }
    $g = $script:View[$i]
    if (-not $script:SelIds.Contains("$($g.Id)")) { SelectIdx $i 'single' }
    if (RunFind "$($g.Id)") { return }      # extraindo (v2.48.0): o menu do botão direito não abre
    if (-not (FormActive)) { $form.Activate() }      # v2.52.0: com a janela inativa o Windows pode fechar o menu na hora em que ele abre
    $script:CtxGame = $g; $cm.Show($grid, $pt)
}
# v2.52.0: clique com o direito com um menu já aberto (o do jogo ou o de filtros). O menu aberto "engole" esse clique para se
#  fechar, e por isso era preciso clicar de novo. Agora, se ele fechou por um clique do botão direito em cima de um jogo,
#  o menu daquele jogo abre na mesma hora.
function CtxReopen($snd, $e) {
    if ($e.CloseReason -ne [Windows.Forms.ToolStripDropDownCloseReason]::AppClicked) { return }
    if (-not ([Windows.Forms.Control]::MouseButtons -band [Windows.Forms.MouseButtons]::Right)) { return }
    $pt = $grid.PointToClient([Windows.Forms.Cursor]::Position)
    if (-not $grid.ClientRectangle.Contains($pt)) { return }
    $i = HitAt $pt.X $pt.Y; if ($i -lt 0) { return }
    $script:CtxReopenAt = [Environment]::TickCount; $script:CtxPend = @{ I = $i; Pt = $pt }
    $ctxTm.Stop(); $ctxTm.Start()      # abre logo depois que o menu antigo terminar de fechar
}
$script:CtxReopenAt = 0; $script:CtxPend = $null
$ctxTm = New-Object Windows.Forms.Timer -Property @{ Interval = 10 }
$ctxTm.Add_Tick({ $ctxTm.Stop(); $cp = $script:CtxPend; $script:CtxPend = $null; if ($cp) { ShowGameMenu $cp.I $cp.Pt } })
$cm.Add_Closed({ param($snd, $e) CtxReopen $snd $e })
$fm.Add_Closed({ param($snd, $e) CtxReopen $snd $e })

# --- grade de capas ---
$grid.Add_Paint({ param($snd, $pe)
    $swp = [Diagnostics.Stopwatch]::StartNew()
    try { PaintGrid $pe.Graphics }
    catch { LogEx 'ERRO' "Falha ao desenhar a biblioteca: $($_.Exception.Message) (linha $($_.InvocationInfo.ScriptLineNumber))" $_ }
    PerfAdd 'Paint' $swp.Elapsed.TotalMilliseconds
})
$grid.Add_Resize({ Relayout })
$vsb.Add_ValueChanged({
    if (-not $script:ScrAnim) { $script:ScrTarget = -1 }      # mudança que não veio da animação (teclado, barra, nova lista): cancela a rolagem suave
    $grid.Invalidate(); $grid.Update()      # capas e barra andam juntas (desenho na hora, sem esperar a fila de mensagens)
})
# Rolagem suave (v2.39.0): cada giro da roda define um ALVO e a grade desliza até ele em ~0,2 s (aproxima uma fração do caminho
#  a cada quadro, pelo tempo real decorrido, então fica igual em PC rápido ou lento). Giros seguidos somam no alvo (roda rápida = vai mais longe).
#  Touchpad com rolagem fina (Delta menor que 120) anda proporcionalmente.
$script:ScrTarget = -1; $script:ScrAnim = $false; $script:ScrSw = New-Object Diagnostics.Stopwatch
$scrTm = New-Object Windows.Forms.Timer -Property @{ Interval = 10 }
$scrTm.Add_Tick({
    $met = $script:Met
    if (-not $met -or $script:ScrTarget -lt 0) { $scrTm.Stop(); $script:ScrTarget = -1; return }
    $maxV = [Math]::Max(0, $met.TotalH - $grid.ClientSize.Height)
    $t = [Math]::Max(0, [Math]::Min([int]$script:ScrTarget, $maxV)); $v = [int]$vsb.Value; $d = $t - $v
    $dt = [Math]::Max(5.0, [Math]::Min(50.0, $script:ScrSw.Elapsed.TotalMilliseconds)); $script:ScrSw.Restart()
    if ([Math]::Abs($d) -le 1) { $nv = $t; $script:ScrTarget = -1; $scrTm.Stop() }
    else {
        $k = 1.0 - [Math]::Pow(0.70, $dt / 16.7)      # ~30% do caminho restante a cada 16,7 ms (60 quadros/s)
        $st = [int][Math]::Round($d * $k); if ($st -eq 0) { $st = [Math]::Sign($d) }
        $nv = $v + $st
    }
    $script:ScrAnim = $true
    try { $vsb.Value = $nv } finally { $script:ScrAnim = $false }
})
$grid.Add_MouseEnter({ if ((FormActive) -and -not $q.Focused) { [void]$grid.Focus() } })   # só com o launcher ativo (v2.37.4)
$grid.Add_MouseWheel({ param($snd, $we)
    if ($S.CinemaMode) {
        if ($script:View.Count) { SelectIdx ([Math]::Max(0,[Math]::Min($script:View.Count-1,$script:CurIdx-[Math]::Sign($we.Delta)))) 'single' }
        return
    }
    $met = $script:Met; if (-not $met) { return }
    $step = [Math]::Max(24, [int]($met.CellH / 2)); $maxV = [Math]::Max(0, $met.TotalH - $grid.ClientSize.Height)
    if ($S.SmoothScroll -eq $false) {      # rolagem suave desligada no painel dev: pula direto, como antes da v2.39.0
        $script:ScrTarget = -1; $scrTm.Stop()
        $vsb.Value = [Math]::Max(0, [Math]::Min([int]$vsb.Value - [int][Math]::Round($we.Delta / 120.0 * $step), $maxV)); return
    }
    $base = $(if ($script:ScrTarget -ge 0) { [int]$script:ScrTarget } else { [int]$vsb.Value })      # giro durante a animação soma no alvo
    $nv = $base - [int][Math]::Round($we.Delta / 120.0 * $step)
    $script:ScrTarget = [Math]::Max(0, [Math]::Min($nv, $maxV))
    if (-not $scrTm.Enabled) { $script:ScrSw.Restart(); $scrTm.Start() }
})
$grid.Add_MouseDown({ param($snd, $me)
    [void]$grid.Focus()
    if ($me.Button -ne 'Left') { return }
    $i = HitAt $me.X $me.Y; if ($i -lt 0) { return }
    $mk = [Windows.Forms.Control]::ModifierKeys; $mode = 'single'
    if ($mk -band [Windows.Forms.Keys]::Control) { $mode = 'toggle' } elseif ($mk -band [Windows.Forms.Keys]::Shift) { $mode = 'range' }
    SelectIdx $i $mode
    if ($me.Clicks -ge 2 -and $mode -eq 'single') { $g = Sel; if ($g) { Launch $g } }      # duplo clique = jogar
})
$grid.Add_MouseUp({ param($snd, $me)
    if ($me.Button -ne 'Right') { return }
    if ($cm.Visible -and ([Environment]::TickCount - $script:CtxReopenAt) -lt 1500) { return }      # já reaberto por CtxReopen neste mesmo clique
    ShowGameMenu (HitAt $me.X $me.Y) $me.Location
})
$grid.Add_MouseMove({ param($snd, $me)
    $i = HitAt $me.X $me.Y
    if ($i -ne $script:Hover) { $script:Hover = $i; $grid.Cursor = $(if ($i -ge 0) { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Default }); $grid.Invalidate() }
})
$grid.Add_MouseLeave({ if ($script:Hover -ne -1) { $script:Hover = -1; $grid.Invalidate() } })
$grid.Add_MouseDown({ param($sender,$eventArgs)
    if (-not $S.CinemaMode -or $eventArgs.Button -ne 'Left') { return }
    foreach ($entry in $script:CinemaFooterHits) {
        if ($entry.Rect.Contains($eventArgs.Location)) {
            switch ($entry.Action) {
                0 { $gm=Sel; if ($gm) { Launch $gm } }
                1 { ShowCinemaDetails }
                2 { FilterMenuShow }
                3 { ShowGameMenu $script:CurIdx $eventArgs.Location }
                4 { ShowSearchDialog }
                5 { if($script:BigPictureEnabled -and $script:HydraHome){BigPictureFocusMenu}else{HydraShowSystems} }
            }
            return
        }
    }
    if ($script:BigPictureEnabled){return}
    if ($eventArgs.Y -ge 70 -and $eventArgs.Y -lt 180) {
        if ($eventArgs.X -lt 28) { SelectIdx ([Math]::Max(0,$script:CurIdx-1)) 'single' }
        elseif ($eventArgs.X -gt $grid.Width-28) { SelectIdx ([Math]::Min($script:View.Count-1,$script:CurIdx+1)) 'single' }
    }
})
$form.Add_KeyDown({ param($sender,$eventArgs)
    if ($S.CinemaMode -and $grid.Focused -and $eventArgs.KeyCode -eq 'F' -and -not $eventArgs.Control -and -not $eventArgs.Alt) {
        $eventArgs.SuppressKeyPress=$true; $eventArgs.Handled=$true; FilterMenuShow
    }
})
$grid.Add_PreviewKeyDown({ param($snd, $pk) if ($pk.KeyCode -in 'Left', 'Right', 'Up', 'Down', 'Home', 'End', 'PageUp', 'PageDown') { $pk.IsInputKey = $true } })
$grid.Add_KeyDown({ param($snd, $ke)
    if($ke.Handled){return}
    $n = $script:View.Count; $met = $script:Met; if (-not $n -or -not $met) { return }
    $i = $script:CurIdx; $t = $i
    if ($ke.KeyCode -eq 'Return') { $g = Sel; if ($g) { Launch $g }; $ke.Handled = $true; return }
    if ($ke.KeyCode -eq 'A' -and $ke.Control) {
        if ($script:Dev) { $script:SelIds.UnionWith([string[]]$script:ViewIds); $grid.Invalidate() }
        $ke.Handled = $true; return
    }
    $page = [Math]::Max(1, [int][Math]::Floor($grid.ClientSize.Height / $met.CellH)) * $met.Cols
    if ($i -lt 0) { $t = 0 }
    else {
        switch ($ke.KeyCode) {
            'Left' { $t = $i - 1 } 'Right' { $t = $i + 1 } 'Up' { $t = $i - $met.Cols } 'Down' { $t = $i + $met.Cols }
            'Home' { $t = 0 } 'End' { $t = $n - 1 } 'PageUp' { $t = $i - $page } 'PageDown' { $t = $i + $page }
            default { return }
        }
    }
    if (@('Left', 'Right', 'Up', 'Down', 'Home', 'End', 'PageUp', 'PageDown') -notcontains "$($ke.KeyCode)") { return }
    $t = [Math]::Max(0, [Math]::Min($n - 1, $t))
    $mode = 'single'; if ($ke.Shift) { $mode = 'range' }
    SelectIdx $t $mode; EnsureVisible $t; $ke.Handled = $true
})
# Teclado: Shift+F10 (ou a tecla Menu, se o teclado tiver) abre o menu do jogo em foco.
# Fica no formulário (KeyPreview) porque o F10 é uma tecla de sistema e pode não chegar à grade.
$form.Add_KeyDown({ param($snd, $ke)
    if ($script:HydraSystemCards -and $ke.KeyCode -eq 'Escape' -and $grid.Focused -and -not $script:HydraHome) {
        HydraShowSystems; $ke.Handled=$true; $ke.SuppressKeyPress=$true; return
    }
    if ($ke.KeyCode -eq 'F5') { if (InstCheckStale) { Populate }; InstStart; $ke.Handled = $true; return }
    if (-not $grid.Focused) { return }
    if ($ke.KeyCode -eq 'Apps') {
        $i = $script:CurIdx; $met = $script:Met
        if ($i -ge 0 -and $met) {
            $xy = TileXY $met $i
            ShowGameMenu $i (New-Object Drawing.Point(($xy[0] + [int]($met.TileW / 2)), ($xy[1] - [int]$vsb.Value + [int]($met.TileH / 2))))
            $ke.Handled = $true; $ke.SuppressKeyPress = $true
        }
    }
})

# --- menu de filtros (ao lado da busca) ---
$btnFil.Add_Click({ FilterMenuShow })

# --- painel de detalhes, topo, zoom ---
$btnFav.Add_Click({ $g = Sel; if ($g) { ToggleFav $g; Populate; ShowGame (Sel) } })
$btnAdd.Add_Click({
    foreach ($old in @($addm.Items)) { $old.Dispose() }; $addm.Items.Clear()
    [void]$addm.Items.Add('Adicionar um jogo...', $null, { if (Edit $null) { CatRefresh; Populate } })
    [void]$addm.Items.Add('Adicionar em massa (pasta Jogos)...', $null, { BulkAdd })
    $addm.Show($btnAdd, 0, $btnAdd.Height)
})
$btnDev.Add_Click({ DevPanel })
$searchTm = New-Object Windows.Forms.Timer -Property @{ Interval = 180 }      # espera o fim da digitação antes de filtrar
$searchTm.Add_Tick({ $searchTm.Stop(); Populate })
$q.Add_TextChanged({ $searchTm.Stop(); $searchTm.Start() })
$loadTm = New-Object Windows.Forms.Timer -Property @{ Interval = 20 }        # continua carregando capas visíveis sem travar a janela
$loadTm.Add_Tick({ $loadTm.Stop(); try { CoverDrain } catch { LogEx 'AVISO' "Falha ao receber capas: $($_.Exception.Message)" $_ } })
$tm = New-Object Windows.Forms.Timer -Property @{ Interval = 300 }
$tm.Add_Tick({ $tm.Stop(); CacheClear; Relayout })
$zm.Add_ValueChanged({ $tm.Stop(); $tm.Start() })
$playTm = New-Object Windows.Forms.Timer -Property @{ Interval = 3000 }     # acompanha os jogos abertos (v2.36.0; a cada PlayCheckSec s, padrão 3)
$playTm.Add_Tick({ try { PlayTick } catch { LogEx 'AVISO' "Falha ao acompanhar jogos abertos: $($_.Exception.Message)" $_ } })
$hydraReturnTm = New-Object Windows.Forms.Timer -Property @{ Interval = 500 }
$hydraReturnTm.Add_Tick({ HydraReturnTick })
$form.Add_FormClosed({ $hydraReturnTm.Stop(); $hydraReturnTm.Dispose() })
$hydraArtTm = New-Object Windows.Forms.Timer -Property @{ Interval = 1200 }
$hydraArtTm.Add_Tick({ if($script:HydraSystemCards){HydraArtworkTick} })
$hydraArtTm.Start()
$form.Add_FormClosed({ $hydraArtTm.Stop(); $hydraArtTm.Dispose() })
$playAnim = New-Object Windows.Forms.Timer -Property @{ Interval = 70 }     # animação da capa do jogo aberto
$playAnim.Add_Tick({ try { PlayAnim } catch { LogEx 'AVISO' "Falha na animação do jogo aberto: $($_.Exception.Message)" $_; $playAnim.Stop() } })
$runTm = New-Object Windows.Forms.Timer -Property @{ Interval = 500 }
$runTm.Add_Tick({ $runTm.Stop(); RunTick; if ($script:Runs.Count) { $runTm.Start() } })
$delTm = New-Object Windows.Forms.Timer -Property @{ Interval = 30 }
$delTm.Add_Tick({ try { DelTick } catch { LogEx 'ERRO' "Falha ao deletar jogo: $($_.Exception.Message)" $_; $delTm.Stop() } })
$extTm = New-Object Windows.Forms.Timer -Property @{ Interval = 70 }
$extTm.Add_Tick({ try { ExtAnim } catch { LogEx 'AVISO' "Falha na animação da extração: $($_.Exception.Message)" $_; $extTm.Stop() } })
$form.Add_FormClosing({ param($snd, $ce)     # sem mensagem
    foreach ($r2 in @($script:Runs | Where-Object { $_.Stage -eq 'unpack' -and $_.UP })) {      # extração em andamento: interrompe o UnRAR (a pasta temporária é refeita na próxima vez)
        try { if ($r2.UP.Proc -and -not $r2.UP.Proc.Proc.HasExited) { $r2.UP.Proc.Proc.Kill() } } catch { $Error.Clear() }
        Log 'AVISO' "Launcher fechado durante a extração de '$($r2.Name)': extração interrompida"
    }
    foreach ($r3 in @($script:Runs | Where-Object { $_.Stage -eq 'dl' -and $_.UP })) {      # download em andamento: interrompe o tdl (o que já terminou fica para a próxima vez)
        try { if (-not $r3.UP.Proc.HasExited) { $r3.UP.Proc.Kill() } } catch { $Error.Clear() }
        Log 'AVISO' "Launcher fechado durante o download de '$($r3.Name)': download interrompido"
    }
})
$instTm = New-Object Windows.Forms.Timer -Property @{ Interval = 25 }
$instTm.Add_Tick({
    $instTm.Stop()
    try {
        $fin = InstStep 15
        if ($fin) { if ($script:InstChanged) { $script:InstChanged = $false; Populate } }
        else { $instTm.Start() }
    } catch { LogEx 'ERRO' "Falha na verificação de instalação: $($_.Exception.Message)" $_; $script:InstRun = $false; $script:DirIdx = $null }
})
# voltar para a janela (depois de baixar/mover/conectar um HD): reverifica, no máximo a cada InstRecheckSec segundos
$form.Add_Activated({
    if (-not $script:Ready) { return }
    if (ImgEnsureAll $false) { CacheClear; $grid.Invalidate(); ShowGame (Sel) }     # pasta de imagens mudou (confere só a data da pasta)
    if ($script:InstRun) { return }
    $secs = CfgNum 'InstRecheckSec' 0 3600 60
    if ($secs -gt 0 -and ((Get-Date) - $script:InstLast).TotalSeconds -ge $secs) { InstStart }
})
# Personalizacao publica: Ctrl + Shift + F12. O modo dev exige Shift+F10 por 5 segundos.
$form.Add_HandleCreated({ ThemeTitle })
$form.Add_KeyDown({ if ($_.Control -and $_.Shift -and $_.KeyCode -eq 'F12') { $_.Handled=$true; $_.SuppressKeyPress=$true; ShowTarginoPreferences } })
# ---- Componentes que alguns jogos precisam (Visual C++, .NET Desktop Runtime, OpenAL, DirectX): instalados uma vez por computador ----
#  Na abertura, se TarginoRetroStation\componentes_instalados.txt não tem uma linha deste computador, os instaladores de
#  TarginoRetroStation\Ferramentas\Dependencias são rodados em silêncio, com o progresso na janelinha de carregamento (sem janela preta).
#  O Windows pede permissão de administrador UMA vez (todos os instaladores rodam num único processo auxiliar elevado e oculto).
#  O arquivo de checagem tem uma linha por computador (nome|data|resumo), porque o launcher é portátil: o mesmo HD/pasta usado em
#  outro PC instala de novo lá. Ele só é gravado quando o auxiliar chega ao fim; permissão recusada = tenta de novo na próxima abertura.
#  Sem a pasta Dependencias, nada acontece. Para reinstalar neste PC: apague a linha dele (ou o arquivo inteiro).
$DepsDir = [IO.Path]::Combine((ArqDir 'Ferramentas'), 'Dependencias')
$DepsFile = [IO.Path]::Combine($Arq, 'componentes_instalados.txt')
$DepsArgs2005 = '/q:a /c:"msiexec /i vcredist.msi /qn"'
$DepsList = @(      # nome mostrado | arquivo (relativo a Dependencias) | argumentos silenciosos | só em Windows 64 bits
    ,@('Visual C++ 2005 x86', 'vcredist2005_x86.exe', $DepsArgs2005, $false)
    ,@('Visual C++ 2005 x64', 'vcredist2005_x64.exe', $DepsArgs2005, $true)
    ,@('Visual C++ 2005 x86 (alt)', 'vcredist2005_altx86.exe', $DepsArgs2005, $false)
    ,@('Visual C++ 2005 x64 (alt)', 'vcredist2005_altx64.exe', $DepsArgs2005, $true)
    ,@('Visual C++ 2008 x86', 'vcredist2008_x86.exe', '/q', $false)
    ,@('Visual C++ 2008 x64', 'vcredist2008_x64.exe', '/q', $true)
    ,@('Visual C++ 2010 x86', 'vcredist2010_x86.exe', '/q /norestart', $false)
    ,@('Visual C++ 2010 x64', 'vcredist2010_x64.exe', '/q /norestart', $true)
    ,@('Visual C++ 2012 x86', 'vcredist2012_x86.exe', '/install /quiet /norestart', $false)
    ,@('Visual C++ 2012 x64', 'vcredist2012_x64.exe', '/install /quiet /norestart', $true)
    ,@('Visual C++ 2013 x86', 'vcredist2013_x86.exe', '/install /quiet /norestart', $false)
    ,@('Visual C++ 2013 x64', 'vcredist2013_x64.exe', '/install /quiet /norestart', $true)
    ,@('Visual C++ 2015-2022 x64', 'VC_redist2015-22x64.exe', '/install /quiet /norestart', $true)
    ,@('Visual C++ 2015-2022 x86', 'VC_redist2015-22x86.exe', '/install /quiet /norestart', $false)
    ,@('.NET Desktop Runtime 7', 'windowsdesktop-runtime-7.0.20-win-x64.exe', '/install /quiet /norestart', $true)
    ,@('.NET Desktop Runtime 10', 'windowsdesktop-runtime-10.0.11-win-x64.exe', '/install /quiet /norestart', $true)
    ,@('OpenAL', 'oalinst.exe', '/s', $false)
    ,@('DirectX', 'DirectX\DXSETUP.exe', '/silent', $false)
)
# Códigos de saída que contam como "instalado" (0 = ok, 3010/1641 = pede reiniciar, 1638/5100 = versão igual ou mais nova já instalada)
$DepsOkCodes = '0', '3010', '1641', '1638', '5100'
# Processo auxiliar (roda elevado e oculto): lê a lista, roda cada instalador sem janela e escreve o andamento num arquivo
$DepsHelper = @'
param([string]$Lista, [string]$Prog)
$ErrorActionPreference = 'Continue'
function Linha($t) { try { [IO.File]::AppendAllText($Prog, $t + "`r`n", (New-Object Text.UTF8Encoding $false)) } catch {} }
$itens = @([IO.File]::ReadAllLines($Lista, [Text.Encoding]::UTF8) | Where-Object { $_ })
$n = $itens.Count; $i = 0; $w64 = [Environment]::Is64BitOperatingSystem
foreach ($l in $itens) {
    $i++; $c = $l.Split("`t")
    Linha "I|$i|$n|$($c[0])"
    if ($c[3] -eq '1' -and -not $w64) { Linha "R|$i|pulado (Windows 32 bits)"; continue }
    if (-not [IO.File]::Exists($c[1])) { Linha "R|$i|ausente"; continue }
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo $c[1]
        $psi.Arguments = $c[2]; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = [IO.Path]::GetDirectoryName($c[1])
        $p = [Diagnostics.Process]::Start($psi); $p.WaitForExit(); Linha "R|$i|$($p.ExitCode)"; $p.Dispose()
    } catch { Linha "R|$i|erro: $($_.Exception.Message)" }
}
Linha 'PRONTO'
'@
function DepsNeeded {
    if (-not [IO.Directory]::Exists($DepsDir)) { return $false }
    if (-not [IO.File]::Exists($DepsFile)) { return $true }
    try { foreach ($dpL in [IO.File]::ReadAllLines($DepsFile)) { if ($dpL.StartsWith("$env:COMPUTERNAME|", 'OrdinalIgnoreCase')) { return $false } } }
    catch { LogEx 'AVISO' "Não foi possível ler $(Short $DepsFile): $($_.Exception.Message)" $_ }
    $true
}
function DepsReadProg($dpFile) {   # linhas do arquivo de andamento (o auxiliar pode estar escrevendo nele ao mesmo tempo)
    if (-not [IO.File]::Exists($dpFile)) { return @() }
    try {
        $dpFs = New-Object IO.FileStream($dpFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $dpRd = New-Object IO.StreamReader($dpFs, [Text.Encoding]::UTF8); @($dpRd.ReadToEnd() -split "`r?`n" | Where-Object { $_ }) } finally { $dpFs.Dispose() }
    } catch { $Error.Clear(); @() }
}
function DepsInstall {
    $dpSw = [Diagnostics.Stopwatch]::StartNew()
    $dpTmp = [IO.Path]::Combine((ArqDir 'Cache'), 'Componentes')
    $dpHelp = [IO.Path]::Combine($dpTmp, 'Instalar.ps1'); $dpList = [IO.Path]::Combine($dpTmp, 'lista.txt'); $dpProg = [IO.Path]::Combine($dpTmp, 'andamento.txt')
    $dpItems = @(foreach ($dpD in $DepsList) { "$($dpD[0])`t$([IO.Path]::Combine($DepsDir, $dpD[1]))`t$($dpD[2])`t$(if ($dpD[3]) { '1' } else { '0' })" })
    try {
        [void][IO.Directory]::CreateDirectory($dpTmp)
        if ([IO.File]::Exists($dpProg)) { [IO.File]::Delete($dpProg) }
        [IO.File]::WriteAllText($dpHelp, $DepsHelper, $Utf8Bom)
        [IO.File]::WriteAllLines($dpList, [string[]]$dpItems, $Utf8Bom)
    } catch { LogEx 'ERRO' "Componentes: não foi possível preparar a instalação: $($_.Exception.Message)" $_; return }
    Log 'INFO' "Componentes: instalando $($dpItems.Count) item(ns) neste computador ($env:COMPUTERNAME)"
    SplashSet 'Instalando componentes para os jogos (confirme a permissão do Windows)...' 0.0 $true $true
    $dpPsi = New-Object Diagnostics.ProcessStartInfo "$([Environment]::SystemDirectory)\WindowsPowerShell\v1.0\powershell.exe"
    $dpPsi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dpHelp`" -Lista `"$dpList`" -Prog `"$dpProg`""
    $dpPsi.UseShellExecute = $true; $dpPsi.Verb = 'runas'; $dpPsi.WindowStyle = 'Hidden'; $dpPsi.WorkingDirectory = $dpTmp
    $dpPr = $null
    try { $dpPr = [Diagnostics.Process]::Start($dpPsi) }
    catch {
        LogEx 'AVISO' "Componentes: instalação não iniciada (permissão recusada ou erro: $($_.Exception.Message)); será oferecida de novo na próxima abertura" $_
        SplashSet 'Instalação dos componentes cancelada; ela será oferecida de novo na próxima abertura.' 0.0 $true $true
        Start-Sleep -Milliseconds 1800
        try { [IO.Directory]::Delete($dpTmp, $true) } catch { $Error.Clear() }
        return
    }
    $dpTot = $dpItems.Count; $dpLast = ''
    while ($true) {
        $dpDone = $dpPr.HasExited
        $dpLines = DepsReadProg $dpProg
        $dpCur = @($dpLines | Where-Object { $_.StartsWith('I|') }) | Select-Object -Last 1
        if ($dpCur -and $dpCur -ne $dpLast) {
            $dpLast = $dpCur; $dpP = $dpCur.Split('|', 4)
            SplashSet "Instalando componentes ($($dpP[1]) de $dpTot): $($dpP[3])..." (([int]$dpP[1] - 1) / [double][Math]::Max(1, $dpTot)) $true $true
        } else { [Windows.Forms.Application]::DoEvents() }      # mantém a janelinha respondendo
        if ($dpDone) { break }
        Start-Sleep -Milliseconds 100
    }
    $dpPr.Dispose()
    # resultado de cada instalador vai para o log
    $dpLines = DepsReadProg $dpProg; $dpNames = @{}; $dpOk = 0; $dpBad = @(); $dpMiss = 0
    foreach ($dpL in $dpLines) {
        $dpP = $dpL.Split('|', 4)
        if ($dpP[0] -eq 'I') { $dpNames[$dpP[1]] = $dpP[3] }
        elseif ($dpP[0] -eq 'R') {
            $dpNm = $dpNames[$dpP[1]]; $dpRes = "$($dpP[2])"
            if ($DepsOkCodes -contains $dpRes) { $dpOk++; Log 'INFO' "Componentes: $dpNm instalado (código $dpRes)" }
            elseif ($dpRes -eq 'ausente' -or $dpRes.StartsWith('pulado')) { $dpMiss++; Log 'INFO' "Componentes: $dpNm $(if ($dpRes -eq 'ausente') { 'não está na pasta Dependencias (pulado)' } else { $dpRes })" }
            else { $dpBad += $dpNm; Log 'AVISO' "Componentes: $dpNm terminou com $(if ($dpRes -match '^-?\d+$') { "código $dpRes" } else { $dpRes })" }
        }
    }
    $dpEnd = ($dpLines -contains 'PRONTO')
    try { [IO.Directory]::Delete($dpTmp, $true) } catch { $Error.Clear() }
    if (-not $dpEnd) { Log 'AVISO' "Componentes: a instalação não chegou ao fim ($([int]$dpSw.Elapsed.TotalSeconds) s); será feita de novo na próxima abertura"; return }
    $dpSum = "$dpOk ok, $($dpBad.Count) com aviso, $dpMiss pulado(s)"
    try { [IO.File]::AppendAllText($DepsFile, "$env:COMPUTERNAME|$(Get-Date -Format 'yyyy-MM-dd HH:mm')|$dpSum`r`n", (New-Object Text.UTF8Encoding $false)) }
    catch { LogEx 'ERRO' "Componentes: não foi possível gravar $(Short $DepsFile): $($_.Exception.Message)" $_ }
    Log 'INFO' "Componentes: concluído em $([int]$dpSw.Elapsed.TotalSeconds) s ($dpSum)$(if ($dpBad.Count) { '; com aviso: ' + ($dpBad -join ', ') })"
    SplashSet 'Componentes instalados.' 1.0 $true $true
}
# ---- Tela de carregamento (v2.29.0): a janela principal fica invisível até as capas estarem prontas ----
function SplashOpen {
    try {
        $spBg = CfgCol 'BgColor' '#0B0B0B'; $spTx = CfgCol 'TextColor' '#FFFFFF'; $spSub = CfgCol 'SubColor' '#9A9A9A'; $spAcc = CfgCol 'Accent' '#1E90FF'; $spSide = CfgCol 'SideColor' '#141414'
        $spF = New-Object Windows.Forms.Form -Property @{ FormBorderStyle = 'None'; StartPosition = 'CenterScreen'; Size = '440,128'; BackColor = $spBg; ShowInTaskbar = $false; ShowIcon = $false; TopMost = $true; Text = "$($S.Title)" }
        $spT = New-Object Windows.Forms.Label -Property @{ Left = 24; Top = 20; Width = 392; Height = 30; ForeColor = $spTx; BackColor = $spBg; Text = "$($S.Title)"; Font = (New-Object Drawing.Font('Segoe UI', 14)) }
        $spL = New-Object Windows.Forms.Label -Property @{ Left = 24; Top = 56; Width = 392; Height = 20; ForeColor = $spSub; BackColor = $spBg; Text = 'Carregando jogos...'; Font = (New-Object Drawing.Font('Segoe UI', 9)) }
        $spTr = New-Object Windows.Forms.Panel -Property @{ Left = 24; Top = 88; Width = 392; Height = 6; BackColor = $spSide }
        $spFi = New-Object Windows.Forms.Panel -Property @{ Left = 0; Top = 0; Width = 0; Height = 6; BackColor = $spAcc }
        $spTr.Controls.Add($spFi); $spF.Controls.AddRange(@($spT, $spL, $spTr))
        $spF.Show(); $spF.Refresh()
        $script:Splash = @{ Form = $spF; L = $spL; Fill = $spFi; Track = $spTr; Sw = [Diagnostics.Stopwatch]::StartNew() }
    } catch { LogEx 'AVISO' "Tela de carregamento não abriu: $($_.Exception.Message)" $_; $script:Splash = $null }
}
function SplashSet($spText, $spFrac, $spForce, $spPump = $false) {      # atualiza no máximo a cada ~50 ms (o texto e a barra), mantendo a janelinha respondendo
    $sx = $script:Splash; if (-not $sx) { return }
    if (-not $spForce -and $sx.Sw.ElapsedMilliseconds -lt 150) { return }
    $sx.Sw.Restart()
    try {
        $sx.L.Text = "$spText"; $sx.Fill.Width = [int]($sx.Track.Width * [Math]::Max(0.0, [Math]::Min(1.0, [double]$spFrac)))
        $sx.Form.Refresh()      # pinta só a janelinha (não deixa a janela principal, invisível, pintar no meio da busca de capas)
        if ($spPump) { [Windows.Forms.Application]::DoEvents() }
    } catch { $Error.Clear() }
}
function SplashClose {
    $sx = $script:Splash; $script:Splash = $null
    if ($sx) { try { $sx.Form.Close(); $sx.Form.Dispose() } catch { $Error.Clear() } }
}
# Acha a capa de cada jogo e já a entrega ao carregador (as threads decodificam enquanto a busca continua); depois faz a
# primeira pintura da grade (compilação/JIT) com a janela ainda invisível, em paralelo com a decodificação.
# Limite: o que couber em "Memória máxima para capas"; o resto carrega ao rolar, como antes.
function PreloadCovers {
    $pt = $script:Painter; $ldr = $script:Loader; $c = $script:Cfg; $met = $script:Met
    if (-not $c -or -not $met) { return }
    $swp = [Diagnostics.Stopwatch]::StartNew(); $swPath = New-Object Diagnostics.Stopwatch; $swSp = New-Object Diagnostics.Stopwatch
    $script:ImgHit = 0; $script:ImgMiss = 0
    PtSync $pt $c $script:Gx $met
    if (-not [object]::ReferenceEquals($script:PtView, $script:View)) { $pt.SetView([string[]]$script:ViewIds); $script:PtView = $script:View; $script:PtImgGen = $script:ImgGen }
    $vw = $script:View; $nv = $vw.Count
    $pt.Gen = [int]$script:CoverGen
    $per = [long]$met.Cover * $met.Cover * 4; $maxN = [int][Math]::Max(1, [Math]::Floor($script:Lru.Budget / $per))
    $wanted = New-Object 'System.Collections.Generic.List[string]'; $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $pt.NoRetain = $true; $rdy = 0; $msPaths = 0; $msFirst = 0; $msWait = 0
    try {
        for ($pli = 0; $pli -lt $nv; $pli++) {
            $swPath.Start()
            if ($null -eq $pt.Paths[$pli]) { $gm = $vw[$pli]; $pt.Names[$pli] = "$($gm.Name)"; $pt.Paths[$pli] = "$(CoverPath $gm)" }
            $swPath.Stop()
            $cpa = $pt.Paths[$pli]
            if ($cpa -and $wanted.Count -lt $maxN) {      # já pede a capa ao carregador: a decodificação anda junto com a busca
                $ck = $pt.Key($cpa)
                if ($seen.Add($ck)) { $wanted.Add($ck); if (-not $script:Lru.Contains($ck)) { [void]$ldr.Request($ck, $cpa, [int]$met.Cover, "$($c.Fit)", ($wanted.Count -le 64)) } }
            }
            $swSp.Start(); SplashSet "Procurando capas... $($pli + 1) de $nv" (0.05 + 0.25 * ($pli + 1) / [Math]::Max(1, $nv)) $false; $swSp.Stop()
        }
        $msPaths = $swp.ElapsedMilliseconds
        $tot = $wanted.Count; $pks = [string[]]$wanted.ToArray()
        # primeira pintura da grade agora (invisível), enquanto as threads decodificam
        $swf = [Diagnostics.Stopwatch]::StartNew()
        try { $grid.Refresh() } catch { LogEx 'AVISO' "Tela de carregamento: pintura prévia falhou: $($_.Exception.Message)" $_ }
        $msFirst = $swf.ElapsedMilliseconds
        if ($tot) {
            $swv = [Diagnostics.Stopwatch]::StartNew(); $fl = New-Object 'System.Collections.Generic.List[CoverLoader+Res]'
            while ($true) {
                $fl.Clear(); [void]$pt.Drain(0, 30, $fl)
                foreach ($rs in $fl) { CoverWarn $rs.Path $(if ($rs.Missing) { 'arquivo não encontrado' } else { "$($rs.Error)" }) }
                $rdy = $pt.CountReady($pks)
                SplashSet "Carregando capas... $rdy de $tot" (0.3 + 0.7 * $rdy / $tot) $false $true
                if ($rdy -ge $tot -or $ldr.Pending -eq 0) { break }
                if ($swp.ElapsedMilliseconds -gt 120000) { Log 'AVISO' "Tela de carregamento: tempo esgotado (120 s) com $rdy de $tot capas; o resto carrega ao rolar"; break }
                Start-Sleep -Milliseconds 5
            }
            $msWait = $swv.ElapsedMilliseconds
            SplashSet "Carregando capas... $rdy de $tot" 1.0 $true $true
        }
    } finally { $pt.NoRetain = $false }
    $wc = 0; foreach ($cp0 in $pt.Paths) { if ($cp0) { $wc++ } }; $cut = ''; if ($wc -gt $wanted.Count) { $cut = " (limite de memória: as outras carregam ao rolar)" }
    Log 'INFO' ("Tela de carregamento: $($wanted.Count) capa(s) prontas em $($swp.ElapsedMilliseconds) ms | achar capa de cada jogo: $([int]$swPath.ElapsedMilliseconds) ms (guardadas: $script:ImgHit, procuradas: $script:ImgMiss) | janelinha: $([int]$swSp.ElapsedMilliseconds) ms | 1ª pintura da grade: $msFirst ms | espera das capas: $msWait ms | miniaturas: $($ldr.ThumbHits) lidas (soma $($ldr.ThumbMs) ms, maior $($ldr.ThumbMaxMs) ms), $($ldr.ThumbMiss) feitas do original (soma $($ldr.DecodeMs) ms, maior $($ldr.DecodeMaxMs) ms, imagem original média $(if ($ldr.ThumbMiss) { [Math]::Round([double][CoverLoader]::SrcPix / $ldr.ThumbMiss / 1e6, 2) } else { 0 }) MP), gravadas $($ldr.ThumbSaved), erros $($ldr.ThumbSaveErr)/$($ldr.ThumbLoadErr)$cut")
}
$script:JoystickNativeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;

public static class ArqSnesPad {
    [StructLayout(LayoutKind.Sequential)]
    public struct JoyInfo {
        public uint Size, Flags, X, Y, Z, R, U, V, Buttons, ButtonNumber, Pov, Reserved1, Reserved2;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct JoyCaps {
        public ushort Mid, Pid;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name;
        public uint Xmin,Xmax,Ymin,Ymax,Zmin,Zmax,Buttons,PeriodMin,PeriodMax;
        public uint Rmin,Rmax,Umin,Umax,Vmin,Vmax,Caps,MaxAxes,Axes,MaxButtons;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string RegKey;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string Oem;
    }
    public sealed class State { public string Name; public uint Buttons; public int Direction; }
    [DllImport("winmm.dll")] static extern uint joyGetNumDevs();
    [DllImport("winmm.dll")] static extern uint joyGetPosEx(uint id, ref JoyInfo info);
    [DllImport("winmm.dll", CharSet=CharSet.Unicode, EntryPoint="joyGetDevCapsW")]
    static extern uint joyGetDevCaps(UIntPtr id, out JoyCaps caps, uint size);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    static readonly int ProcessId = Process.GetCurrentProcess().Id;
    static readonly Stopwatch Clock = Stopwatch.StartNew();
    static int Device = -1;
    static long NextScan;
    static JoyCaps Caps;
    static bool ReadInfo(uint id, out JoyInfo info) {
        info = new JoyInfo(); info.Size=(uint)Marshal.SizeOf(typeof(JoyInfo)); info.Flags=255; info.Pov=65535;
        return joyGetPosEx(id,ref info)==0;
    }
    public static long OwnWindow() {
        IntPtr window=GetForegroundWindow(); uint process;
        GetWindowThreadProcessId(window,out process);
        return process==(uint)ProcessId ? window.ToInt64() : 0;
    }
    public static int DecodeDirection(uint x,uint y,uint pov,JoyCaps caps) {
        int direction=0;
        if(caps.Xmax>caps.Xmin) {
            double nx=(x-(double)caps.Xmin)/(caps.Xmax-caps.Xmin);
            if(nx<0.25) direction|=1; else if(nx>0.75) direction|=2;
        }
        if(caps.Ymax>caps.Ymin) {
            double ny=(y-(double)caps.Ymin)/(caps.Ymax-caps.Ymin);
            if(ny<0.25) direction|=4; else if(ny>0.75) direction|=8;
        }
        if((caps.Caps&16)!=0 && pov<36000) {
            if(pov>=31500 || pov<=4500) direction|=4;
            if(pov>=4500 && pov<=13500) direction|=2;
            if(pov>=13500 && pov<=22500) direction|=8;
            if(pov>=22500 && pov<=31500) direction|=1;
        }
        return direction;
    }
    public static State Read() {
        JoyInfo info;
        if(Device<0) {
            if(Clock.ElapsedMilliseconds<NextScan) return null;
            NextScan=Clock.ElapsedMilliseconds+2000;
            uint count=Math.Min(16U,joyGetNumDevs());
            for(uint id=0;id<count;id++) {
                JoyCaps candidate;
                if(ReadInfo(id,out info) && joyGetDevCaps((UIntPtr)id,out candidate,(uint)Marshal.SizeOf(typeof(JoyCaps)))==0) {
                    Device=(int)id; Caps=candidate; break;
                }
            }
            if(Device<0) return null;
        }
        if(!ReadInfo((uint)Device,out info)) { Device=-1;NextScan=Clock.ElapsedMilliseconds+1500;return null; }
        return new State { Name=Caps.Name,Buttons=info.Buttons,Direction=DecodeDirection(info.X,info.Y,info.Pov,Caps) };
    }
    public sealed class Events { public uint Pressed; public uint Held; public int Direction; }
    public sealed class Gate {
        uint PreviousButtons; long Window,NextRepeat; int PreviousDirection;
        public Events Update(uint buttons,int direction,long window,long now) {
            Events events=new Events(); events.Held=buttons;
            if(window==0 || Window!=window) {
                Window=window;PreviousButtons=buttons;PreviousDirection=direction;NextRepeat=now+350;return events;
            }
            events.Pressed=buttons&~PreviousButtons;PreviousButtons=buttons;
            if(direction==0) { PreviousDirection=0; return events; }
            if(direction!=PreviousDirection) { events.Direction=direction;PreviousDirection=direction;NextRepeat=now+350; }
            else if(now>=NextRepeat) { events.Direction=direction;NextRepeat=now+120; }
            return events;
        }
    }
    public static bool Button(uint mask,int number) { return number>=1 && number<=32 && (mask & (1U<<(number-1)))!=0; }
}
'@
function JoySendKey($key,$window) {
    if ($window -ne 0 -and [ArqSnesPad]::OwnWindow() -eq $window) { [Windows.Forms.SendKeys]::SendWait($key) }
}
function JoyPageJump([int]$direction) {
    if (-not $script:View.Count) { return }
    $size=[Math]::Max(1,[Math]::Min(50,[int]$S.JoyPageSize))
    $target=[Math]::Max(0,[Math]::Min($script:View.Count-1,[Math]::Max(0,$script:CurIdx)+$direction*$size))
    if ($target -ne $script:CurIdx) { [void]$grid.Focus(); SelectIdx $target 'single'; EnsureVisible $target }
}
function JoyDispatch($events,$window) {
    if ($window -eq 0) { return }
    if($script:TarginoWelcomeDialog -and -not $script:TarginoWelcomeDialog.IsDisposed -and $window -eq $script:TarginoWelcomeDialog.Handle.ToInt64()){
        $helpKey=''
        if([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyBack)){$helpKey='Escape'}
        elseif([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyConfirm) -or [ArqSnesPad]::Button($events.Pressed,[int]$S.JoyStart)){$helpKey='Return'}
        elseif($events.Direction -band 1){$helpKey='Left'}elseif($events.Direction -band 2){$helpKey='Right'}elseif($events.Direction -band 4){$helpKey='Up'}elseif($events.Direction -band 8){$helpKey='Down'}
        if($helpKey){TarginoWelcomeInput $helpKey $script:TarginoWelcomeDialog}
        return
    }
    if($script:HydraRendererDialog -and -not $script:HydraRendererDialog.IsDisposed -and $window -eq $script:HydraRendererDialog.Handle.ToInt64()){
        $rendererKey=''
        if([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyBack)){$rendererKey='Escape'}
        elseif([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyConfirm) -or [ArqSnesPad]::Button($events.Pressed,[int]$S.JoyStart)){$rendererKey='Return'}
        elseif($events.Direction -band 1){$rendererKey='Left'}elseif($events.Direction -band 2){$rendererKey='Right'}elseif($events.Direction -band 4){$rendererKey='Up'}elseif($events.Direction -band 8){$rendererKey='Down'}
        if($rendererKey){HydraRendererInput $rendererKey $script:HydraRendererDialog}
        return
    }
    $menus=($fm.Visible -or $cm.Visible -or $addm.Visible)
    $main=($window -eq $form.Handle.ToInt64() -and -not $menus)
    if($main -and $script:BigPictureEnabled){
        $bpKey=''
        if([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyBack)){$bpKey='Escape'}
        elseif([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyConfirm) -or [ArqSnesPad]::Button($events.Pressed,[int]$S.JoyStart)){$bpKey='Return'}
        elseif($events.Direction -band 1){$bpKey='Left'}elseif($events.Direction -band 2){$bpKey='Right'}elseif($events.Direction -band 4){$bpKey='Up'}elseif($events.Direction -band 8){$bpKey='Down'}
        if($bpKey -and (BigPictureInput $bpKey)){return}
    }
    $searchChord=([ArqSnesPad]::Button($events.Held,[int]$S.JoySearchModifier) -and [ArqSnesPad]::Button($events.Held,[int]$S.JoyFilters))
    $chordPressed=([ArqSnesPad]::Button($events.Pressed,[int]$S.JoySearchModifier) -or [ArqSnesPad]::Button($events.Pressed,[int]$S.JoyFilters))
    if (($main -or $menus) -and $searchChord -and $chordPressed) { ShowSearchDialog; return }
    if ($script:SearchWindow -and $window -eq $script:SearchWindow.Handle.ToInt64()) {
        if ($events.Direction) { SearchKeyboardMove $events.Direction }
        if ([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyBack)) { $script:SearchWindow.DialogResult='Cancel' }
        elseif ([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyStart)) { $script:SearchWindow.DialogResult='OK' }
        elseif ([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyConfirm)) {
            $state=$script:SearchWindow.Tag
            if ($script:SearchWindow.ActiveControl -eq $state.Input) { $script:SearchWindow.DialogResult='OK' }
            else { $state.Keys[$state.Index].PerformClick() }
        }
        return
    }
    if ($main -and [ArqSnesPad]::Button($events.Pressed,[int]$S.JoyActions)) {
        ShowGameMenu $script:CurIdx (New-Object Drawing.Point(([int]($grid.Width/2)),($grid.Height-32)))
        return
    }
    if ($main) {
        $shoulderLeft=[ArqSnesPad]::Button($events.Pressed,[int]$S.JoyPageLeft)
        $shoulderRight=[ArqSnesPad]::Button($events.Pressed,[int]$S.JoyPageRight)
        if ($shoulderLeft -or $shoulderRight) {
            if ($shoulderLeft -and -not $shoulderRight) { JoyPageJump -1 }
            elseif ($shoulderRight -and -not $shoulderLeft) { JoyPageJump 1 }
            return
        }
    }
    $direction=$events.Direction
    if ($direction) {
        if ($main) {
            if ($script:View.Count) {
                $step=0
                if ($direction -band 1) { $step=-1 } elseif ($direction -band 2) { $step=1 }
                elseif ($direction -band 4) { $step=$(if ($S.CinemaMode) {-1} else {-$script:Met.Cols}) }
                elseif ($direction -band 8) { $step=$(if ($S.CinemaMode) {1} else {$script:Met.Cols}) }
                $target=[Math]::Max(0,[Math]::Min($script:View.Count-1,$script:CurIdx+$step))
                if ($target -ne $script:CurIdx) { [void]$grid.Focus(); SelectIdx $target 'single'; EnsureVisible $target }
            }
        } else {
            $key=if($direction -band 1){'{LEFT}'}elseif($direction -band 2){'{RIGHT}'}elseif($direction -band 4){'{UP}'}else{'{DOWN}'}
            JoySendKey $key $window
        }
    }
    if ([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyBack)) {
        if ($main) { if ($q.Text) { $q.Clear() } elseif ($script:HydraSystemCards -and -not $script:HydraHome) { HydraShowSystems }; [void]$grid.Focus() }
        else { JoySendKey '{ESC}' $window }
        return
    }
    $confirm=([ArqSnesPad]::Button($events.Pressed,[int]$S.JoyConfirm) -or [ArqSnesPad]::Button($events.Pressed,[int]$S.JoyStart))
    if ($confirm) {
        if ($main) { $gm=Sel; if ($gm) { Launch $gm } }
        else { JoySendKey '{ENTER}' $window }
        return
    }
    if ($main -and [ArqSnesPad]::Button($events.Pressed,[int]$S.JoyDetails)) { ShowCinemaDetails; return }
    if ($main -and [ArqSnesPad]::Button($events.Pressed,[int]$S.JoyFilters)) { FilterMenuShow }
}
function JoystickTick {
    if (-not $S.JoystickEnabled) {
        [void]$script:JoyGate.Update(0,0,0,$script:JoyClock.ElapsedMilliseconds)
        if ($script:JoyStatusText) { $script:JoyStatusText=''; $hdr.Invalidate() }
        return
    }
    $state=[ArqSnesPad]::Read()
    if (-not $state) {
        [void]$script:JoyGate.Update(0,0,0,$script:JoyClock.ElapsedMilliseconds)
        if ($script:JoyStatusText) { $script:JoyStatusText=''; $hdr.Invalidate() }
        return
    }
    $status='Controle: '+$state.Name
    if ($state.Buttons) {
        $numbers=@(); for($number=1;$number -le 32;$number++){if([ArqSnesPad]::Button($state.Buttons,$number)){$numbers+=$number}}
        $status+=' · botão '+($numbers -join ',')
    }
    if ($status -ne $script:JoyStatusText) { $script:JoyStatusText=$status; $hdr.Invalidate() }
    $window=[ArqSnesPad]::OwnWindow()
    $events=$script:JoyGate.Update($state.Buttons,$state.Direction,$window,$script:JoyClock.ElapsedMilliseconds)
    JoyDispatch $events $window
}
try {
    if (-not ('ArqSnesPad' -as [type])) { Add-Type -TypeDefinition $script:JoystickNativeSource -ErrorAction Stop }
    $script:JoyGate=New-Object ArqSnesPad+Gate
    $script:JoyClock=[Diagnostics.Stopwatch]::StartNew()
    $script:JoyTimer=New-Object Windows.Forms.Timer -Property @{Interval=50}
    $script:JoyTimer.Add_Tick({ try { JoystickTick } catch { $script:JoyTimer.Stop(); LogEx 'AVISO' 'Controle USB desativado após falha' $_ } })
    $script:JoyTimer.Start()
    $form.Add_FormClosed({ $script:JoyTimer.Stop(); $script:JoyTimer.Dispose() })
} catch { LogEx 'AVISO' 'Suporte a controle USB indisponível' $_ }
$script:CinemaTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 50 }
$script:CinemaTimer.Add_Tick({
    if ($S.CinemaMode -and $S.CinemaAnimate -and $script:CurIdx -ge 0) {
        if ($null -eq $script:CinemaPosition) { $script:CinemaPosition = [double]$script:CurIdx }
        $distance = $script:CurIdx-$script:CinemaPosition
        if ([Math]::Abs($distance) -gt 0.01) {
            $script:CinemaPosition += $distance*0.35
            $grid.Invalidate()
        } elseif ($script:CinemaPosition -ne $script:CurIdx) {
            $script:CinemaPosition = [double]$script:CurIdx; $grid.Invalidate()
        }
    }
    if ($S.CinemaMode -and $script:Loader -and $script:Loader.Pending -gt 0) {
        try { CoverDrain } catch { LogEx 'AVISO' 'Falha ao atualizar capas do carrossel' $_ }
    }
})
$script:CinemaTimer.Start()
$form.Add_FormClosed({
    $script:CinemaTimer.Stop(); $script:CinemaTimer.Dispose()
    if ($script:CinemaScene) { $script:CinemaScene.Dispose(); $script:CinemaScene=$null; $script:CinemaSceneSource=$null }
})
$form.Add_Shown({
    TopCenter
    $lsOn = [bool]$S.LoadScreen; $spOn = ($lsOn -or $script:DepsNeed -or $script:UpdOn)
    if ($spOn) { SplashOpen }
    if ($script:UpdOn) {      # atualização automática (UpdateWinPort): aplicou = reabre o launcher já atualizado
        $updDone = $false
        try { $updDone = UpdRun } catch { LogEx 'ERRO' "Atualização: falha inesperada: $($_.Exception.Message)" $_ }
        if ($updDone) { UpdRestart; return }      # abre o launcher de novo, já atualizado
    }
    if ($script:DepsNeed) { try { DepsInstall } catch { LogEx 'ERRO' "Componentes: falha na instalação: $($_.Exception.Message)" $_ } }      # 1ª abertura neste PC
    if ($spOn) { SplashSet 'Lendo o catálogo...' 0.02 $true }
    try {
        InitFilter; CatRefresh; ApplyLayout; Populate
        if ($script:View.Count) { SelectIdx 0 'single' }
        if ($lsOn) { try { PreloadCovers } catch { LogEx 'AVISO' "Tela de carregamento: falha ao carregar as capas: $($_.Exception.Message)" $_ } }
        try { ImgSaveDisk } catch { LogEx 'AVISO' "Falha ao guardar as capas achadas: $($_.Exception.Message)" $_ }      # próxima abertura não precisa procurar de novo
    } finally {
        if ($spOn) { SplashClose; $form.Opacity = 1; $grid.Invalidate(); $form.Activate() }      # agora sim a janela aparece, com as capas prontas
    }
    $script:Ready = $true; [void]$grid.Focus()
    if ($script:HydraSystemCards) { HydraStartArtwork }
    $script:Perf.ReadyMs = $script:T0.ElapsedMilliseconds
    Log 'INFO' "Janela pronta em $($script:Perf.ReadyMs) ms ($(@($script:Games).Count) jogo(s))"
    InstStart      # verificação completa em lotes, em segundo plano (a tela já abriu com o último estado conhecido)
    if ($script:StartMsg) { [void][Windows.Forms.MessageBox]::Show(($script:StartMsg -join "`n`n") + "`n`nDetalhes em TarginoRetroStation\Logs\launcher.log", 'Aviso') }
})
# Envia ao log, a cada 3 s, erros de eventos da interface que não foram tratados
if(Get-Command InitializeTarginoPreferences -ErrorAction SilentlyContinue){InitializeTarginoPreferences}
if([IO.File]::Exists((Join-Path $Arq 'HydraDetails.ps1'))){. (Join-Path $Arq 'HydraDetails.ps1')}
if([IO.File]::Exists((Join-Path $Arq 'TarginoBigPicture.ps1'))){
    . (Join-Path $Arq 'TarginoBigPicture.ps1')
    InitializeBigPicture
    $form.Add_KeyDown({param($sender,$key)
        if($key.Handled -or -not $script:BigPictureEnabled){return}
        if(($grid.Focused -or $script:BigPictureSidebar -or $key.KeyCode -eq 'F1') -and (BigPictureInput ([string]$key.KeyCode))){$key.Handled=$true;$key.SuppressKeyPress=$true}
    })
}
$errTm = New-Object Windows.Forms.Timer -Property @{ Interval = 3000 }
$errTm.Add_Tick({ FlushErrors }); $errTm.Start()
$S.UpdUrl='';$S.UpdPass='' # The legacy arbitrary-URL updater is never used by RetroStation.
$script:DepsNeed = DepsNeeded; $script:UpdOn = $false; UpdCleanup
$welcomeModule=Join-Path $Arq 'TarginoWelcome.ps1'
if([IO.File]::Exists($welcomeModule)){. $welcomeModule;InitializeTarginoWelcome}
if ([bool]$S.LoadScreen -or $script:DepsNeed -or $script:UpdOn) { $form.Opacity = 0 }      # invisível até a tela de carregamento terminar (Shown)
. (Join-Path $Arq 'RetroStationUpdateUI.ps1')
Initialize-RetroStationUpdates
[void]$form.ShowDialog()
$errTm.Stop(); FlushErrors
if ($script:Loader) { try { $script:Loader.Dispose() } catch { $Error.Clear() } }
CacheClear
try { ImgSaveDisk } catch { $Error.Clear() }      # capas achadas durante o uso (jogos novos, capturas vistas)
Log 'INFO' 'Launcher encerrado'
