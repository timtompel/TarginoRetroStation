# Pure matching/cache rules shared by the UI and the artwork worker.
function Get-HydraArtworkQueryTitle([string]$name){
    $name=$name -replace '(?i)\.png$',''
    $name=$name -replace '(?i)\s*\.(?:sfc|smc|sms|nes|md|bin)\s*$',''
    $name=$name -replace '(?i)\s+[—–-]\s+(?:Telegram|TESTE SOB DEMANDA)\s*$',''
    return $name.Trim()
}
function Normalize-HydraArtworkTitle([string]$name){
    $name=Get-HydraArtworkQueryTitle $name
    $name=$name -replace '\([^)]*\)|\[[^]]*\]',' '
    $name=$name -replace '(?i)[_ -]+(?:ptbr|pt-br|traduzid[ao]s?|translation|hack|v\d+\.\d+).*$',''
    $name=$name -replace '(?i)_(?:gg|sms|snes)$',''
    $name=$name -replace '(?i)[_ ]+(?:USA|US|Europe|EU)\s*$',''
    # Article order and filename-safe ampersands differ between dump sets.
    $name=$name -replace '(?i)\b(?:the|and)\b',' '
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
function Get-HydraArtworkAlias([string]$systemId,[string]$name){
    $key=Normalize-HydraArtworkTitle $name
    $aliases=@{
        'sms|columns'='Columns _ Shapes and Columns';
        'sms|eswatcityundersiege'='E-SWAT';
        'sms|summergames'='Summer Games _ Jogos Olimpicos';
        'sms|worldcupitalia90'="World Cup Italia '90 _ Super Futebol II";
        'snes|spawn'="Todd McFarlane's Spawn - The Video Game";
        'snes|mahoukishirayearth'='Magic Knight Rayearth';
        'snes|treasureofrudras'='Rudra no Hihou';
        'snes|disneyspinocchio'='Pinocchio';
        'snes|frontmissiongunhazard'='Front Mission Series - Gun Hazard';
        'snes|princeofpersia2shadowflame'='Prince of Persia 2';
        'snes|streetfighteriiturbohyperfighting'='Street Fighter II Turbo';
        'snes|joeemac2lostintropics'='Joe _ Mac 2 - Lost in the Tropics';
        'snes|tomejerry'='Tom and Jerry';
        'snes|marvelous'='Marvelous - Mouhitotsu no Takara-jima';
        'snes|marvelousanothertreasureisland'='Marvelous - Mouhitotsu no Takara-jima';
        'snes|secretofstars'='Tecmo Secret of the Stars';
        'snes|sailormoonanotherstory'='Bishoujo Senshi Sailor Moon - Another Story';
        'snes|assaultsuitsvalken'='Juusou Kihei Valken';
        'snes|fantasticparodius'='Gokujou Parodius';
        'snes|chattingparodiuslive'='Jikkyou Oshaberi Parodius';
        'snes|mickeydonaldmagicaladventure3'='Mickey to Donald - Magical Adventure 3';
        'snes|mobilesuitgundamwingendlessduel'='Shin Kidou Senki Gundam W - Endless Duel';
        'snes|flyingherobugyurusadventure'='Flying Hero - Bugyuru no Daibouken';
        'snes|racoonrascal'='Araiguma Rascal';
        'snes|tomorrowsjoe'='Ashita no Joe';
        'snes|sdgreatbattleanewchallenge'='SD The Great Battle - Aratanaru Chousen';
        'snes|supernaxatopenspikemcfanggolf'='Super Naxat Open - Golf de Shoubu da Dorabocchan';
        'snes|ganbaregoemonrescueofprincessyuki'='Ganbare Goemon - Yuki Hime Kyuushutsu Emaki';
        'snes|goforitgoemonrescueofprincessyuki'='Ganbare Goemon - Yuki Hime Kyuushutsu Emaki';
        'snes|goemon2oestranhogeneralmacguiness'='Ganbare Goemon 2 - Kiteretsu Shougun Magginesu';
        'snes|getgoingebisumarumechanicalmazemysteryofmissinggoemon'='Soreyuke Ebisumaru Karakuri Meiro - Kieta Goemon no Nazo!!';
        'snes|soreyukeebisumarumechanicalmazemysteryofmissinggoemon'='Soreyuke Ebisumaru Karakuri Meiro - Kieta Goemon no Nazo!!';
        'nes|simpsonsbartvsspacemutants'='Simpsons, The - Bart vs. the Space Mutants';
        'nes|addams'='Addams Family, The'
    }
    if($systemId -eq 'nes' -and $name -match '^Simpsons_PT-BR_v\d+_DEBUG_Fase_[1-5]_(?:Springfield|Shopping|Krustyland|Museu|Usina)$'){
        return 'Simpsons, The - Bart vs. the Space Mutants'
    }
    return $aliases[($systemId+'|'+$key)]
}
function Find-HydraArtworkCandidate($catalogue,[string]$name,[string]$systemId=''){
    $filename=(Get-HydraArtworkQueryTitle $name)+'.png'
    if($catalogue.Exact.ContainsKey($filename)){return $catalogue.Exact[$filename]}
    $key=Normalize-HydraArtworkTitle $name
    $alias=Get-HydraArtworkAlias $systemId $name
    if($alias){$key=Normalize-HydraArtworkTitle $alias}
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
        if($entry.MatchingVersion -ne 4){return $true}
        if($name -and $entry.MatchName -cne (Normalize-HydraArtworkTitle $name)){return $true}
        $minutes=1440
    }else{return $false}
    $checked=[datetime]::MinValue
    return (-not [datetime]::TryParse([string]$entry.Checked,[ref]$checked) -or ([datetime]::UtcNow-$checked.ToUniversalTime()).TotalMinutes -ge $minutes)
}
function Get-HydraArtworkStyleVersion($entry){
    if($entry -and $entry.Status -eq 'downloaded'){return 2}
    return 3
}
