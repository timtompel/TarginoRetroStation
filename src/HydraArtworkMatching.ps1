# Pure matching/cache rules shared by the UI and the artwork worker.
function Get-HydraArtworkQueryTitle([string]$name){
    $name=$name -replace '(?i)\.png$',''
    $name=$name -replace '(?i)\s+[—–-]\s+(?:Telegram|TESTE SOB DEMANDA)\s*$',''
    return $name.Trim()
}
function Normalize-HydraArtworkTitle([string]$name){
    $name=Get-HydraArtworkQueryTitle $name
    $name=$name -replace '\([^)]*\)|\[[^]]*\]',' '
    $name=$name -replace '(?i)[_ -]+(?:ptbr|pt-br|traduzid[ao]s?|translation|hack|v\d+\.\d+).*$',''
    $name=$name -replace '(?i)_(?:gg|sms|snes)$',''
    $name=$name.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}',''
    return ($name.ToLowerInvariant() -replace '[^a-z0-9]','')
}
function ConvertTo-HydraArtworkCatalogue([string]$html,[string]$url){
    $exact=@{};$normalized=@{}
    foreach($match in [regex]::Matches($html,'(?i)href="([^"?]+\.png)"')){
        $file=[Net.WebUtility]::HtmlDecode([Uri]::UnescapeDataString($match.Groups[1].Value))
        if($file.IndexOfAny([char[]]@('/','\',':')) -ge 0){continue}
        $exact[$file]=$url+[Uri]::EscapeDataString($file)
        $key=Normalize-HydraArtworkTitle $file
        if(-not $normalized.ContainsKey($key)){$normalized[$key]=New-Object Collections.Generic.List[string]}
        $normalized[$key].Add($file)
    }
    if(-not $exact.Count){throw 'Indice de capas vazio ou invalido; nao e uma ausencia de correspondencia do jogo.'}
    return @{Exact=$exact;Normalized=$normalized}
}
function Find-HydraArtworkCandidate($catalogue,[string]$name){
    $filename=(Get-HydraArtworkQueryTitle $name)+'.png'
    if($catalogue.Exact.ContainsKey($filename)){return $catalogue.Exact[$filename]}
    $key=Normalize-HydraArtworkTitle $name
    $choices=@($catalogue.Normalized[$key]|Where-Object {$_ -and $_ -notmatch '(?i)\((?:Beta|Proto|Demo)'})
    # No prefix guessing: Street Fighter must not become Street Fighter II.
    $choice=$choices|Sort-Object @{Expression={if($_ -match '\(USA'){0}elseif($_ -match '\(World'){1}elseif($_ -match '\(Europe'){2}else{3}}},Length|Select-Object -First 1
    if($choice){return $catalogue.Exact[$choice]}
    return $null
}
function Get-HydraSupplementalArtwork([string]$systemId,[string]$name){
    # Platform-specific gameplay image, never advertised as an official box cover.
    if($systemId -eq '3do' -and (Normalize-HydraArtworkTitle $name) -eq 'pacman'){
        return 'https://archive3do.com/wp-content/uploads/2023/05/capture-4.png'
    }
    return $null
}
function Test-HydraArtworkRetryDue($entry,[string]$name=''){
    if(-not $entry){return $false}
    if($entry.Status -eq 'error'){
        if($entry.TransportVersion -ne 3){return $true}
        $minutes=30
    }elseif($entry.Status -eq 'fallback'){
        if($entry.MatchingVersion -ne 3){return $true}
        if($name -and $entry.MatchName -cne (Normalize-HydraArtworkTitle $name)){return $true}
        $minutes=1440
    }else{return $false}
    $checked=[datetime]::MinValue
    return (-not [datetime]::TryParse([string]$entry.Checked,[ref]$checked) -or ([datetime]::UtcNow-$checked.ToUniversalTime()).TotalMinutes -ge $minutes)
}
