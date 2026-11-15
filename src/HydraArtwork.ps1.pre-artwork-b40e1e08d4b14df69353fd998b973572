param([string]$Root='D:\Games\hydra', [switch]$PrepareOnly)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$metadataModule=Join-Path $PSScriptRoot 'HydraMetadata.ps1'
if([IO.File]::Exists($metadataModule)){. $metadataModule}
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$media=Join-Path $Root 'TarginoRetroStation\Midia'
$data=Join-Path $Root 'TarginoRetroStation\Dados'
foreach($dir in @($media,(Join-Path $media 'Sistemas'),(Join-Path $media 'Capas'),(Join-Path $media 'Originais'),(Join-Path $media 'Indices'))){[void][IO.Directory]::CreateDirectory($dir)}
$requests=Get-Content -LiteralPath (Join-Path $data 'hydra-midia-pedidos.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$indexPath=Join-Path $data 'hydra-midia-indice.json'
$state=@{}; $status=@{}
$script:downloads=0; $script:assetTransportVersion=3
$script:stateWriteClock=[Diagnostics.Stopwatch]::StartNew()
$script:progressWriteClock=[Diagnostics.Stopwatch]::StartNew()
function Asset-RetryDue($entry){
    if(-not $entry -or $entry.Status -ne 'error'){return $false}
    if($entry.TransportVersion -ne $script:assetTransportVersion){return $true}
    $checked=[datetime]::MinValue
    return (-not [datetime]::TryParse([string]$entry.Checked,[ref]$checked) -or ([datetime]::UtcNow-$checked.ToUniversalTime()).TotalMinutes -ge 30)
}
$lock=New-Object Threading.Mutex($false,('Local\HydraMedia-'+$requests.RootKey))
if(-not $lock.WaitOne(0)){ $lock.Dispose(); exit }
if(Test-Path -LiteralPath $indexPath){
    $stream=[IO.File]::Open($indexPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{$reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true);try{$old=$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose()}}finally{$stream.Dispose()}
    foreach($p in $old.PSObject.Properties){$state[$p.Name]=$p.Value}
}
function Save-State([switch]$Force) {
    if(-not $Force -and $script:stateWriteClock.ElapsedMilliseconds -lt 500){return}
    $tmp=$indexPath+'.tmp'
    [IO.File]::WriteAllText($tmp,(ConvertTo-Json $state -Depth 6),(New-Object Text.UTF8Encoding($false)))
    if([IO.File]::Exists($indexPath)){
        for($attempt=0;$attempt -lt 4;$attempt++){
            try{[IO.File]::Replace($tmp,$indexPath,($indexPath+'.bak'));break}
            catch{if($attempt -eq 3){throw};Start-Sleep -Milliseconds 40}
        }
    }else{[IO.File]::Move($tmp,$indexPath)}
    $script:stateWriteClock.Restart()
}
function Save-Progress([string]$phase,[int]$done,[int]$total){
    if($phase -ne 'Concluido' -and $phase -ne 'Artes locais prontas' -and $script:progressWriteClock.ElapsedMilliseconds -lt 250){return}
    $obj=@{Phase=$phase;Done=$done;Total=$total;Downloads=$script:downloads;Time=(Get-Date).ToString('s')}
    $obj.Saved=0;$obj.Failed=0;$obj.NotFound=0
    foreach($key in @($state.Keys | Where-Object {-not $_.StartsWith('index:')})){
        switch($state[$key].Status){'downloaded'{$obj.Saved++}'error'{$obj.Failed++}'fallback'{$obj.NotFound++}}
    }
    [IO.File]::WriteAllText((Join-Path $data 'hydra-midia-progresso.json'),(ConvertTo-Json $obj),(New-Object Text.UTF8Encoding($false)))
    $script:progressWriteClock.Restart()
}
function Get-Asset([string]$url,[string]$path){
    if([IO.File]::Exists($path)){return}
    Receive-HydraMedia $url $path
    $script:downloads++
}
function Normalize-Title([string]$name){
    $name=$name -replace '\.[^.]+$',''
    $name=$name -replace '\([^)]*\)|\[[^]]*\]',' '
    $name=$name -replace '(?i)[_ -]+(?:ptbr|pt-br|traduzid[ao]s?|translation|hack|v\d+\.\d+).*$',''
    $name=$name -replace '(?i)_(?:gg|sms|snes)$',''
    $name=$name.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}',''
    ($name.ToLowerInvariant() -replace '[^a-z0-9]','')
}
function Write-Card($item,[string]$imagePath,[bool]$official){
    $dest=Join-Path $Root $item.Path
    $bitmap=New-Object Drawing.Bitmap(480,680)
    $g=[Drawing.Graphics]::FromImage($bitmap)
    $brush=$null;$font=$null;$small=$null;$format=$null;$pen=$null;$image=$null;$textBrush=$null;$muted=$null;$accent=$null
    try {
        $color=[Drawing.ColorTranslator]::FromHtml($item.Color)
        $rect=New-Object Drawing.Rectangle(0,0,480,680)
        $brush=New-Object Drawing.Drawing2D.LinearGradientBrush($rect,[Drawing.Color]::FromArgb(27,37,60),[Drawing.Color]::FromArgb(8,13,24),90)
        $g.FillRectangle($brush,$rect);$g.SmoothingMode='AntiAlias';$g.InterpolationMode='HighQualityBicubic'
        $accent=New-Object Drawing.SolidBrush($color);$g.FillRectangle($accent,0,0,480,8)
        $textBrush=New-Object Drawing.SolidBrush([Drawing.Color]::White)
        $muted=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(163,181,205))
        $font=New-Object Drawing.Font('Segoe UI',26,[Drawing.FontStyle]::Bold)
        $small=New-Object Drawing.Font('Segoe UI',12,[Drawing.FontStyle]::Bold)
        $format=New-Object Drawing.StringFormat;$format.Alignment='Center';$format.LineAlignment='Center';$format.Trimming='EllipsisWord'
        # Titles and system labels belong to the UI, not baked into artwork.
        if($imagePath -and (Test-Path -LiteralPath $imagePath)){
            $image=[Drawing.Image]::FromFile($imagePath)
            $target=if($item.Kind -eq 'system'){New-Object Drawing.RectangleF(50,80,380,520)}else{New-Object Drawing.RectangleF(12,16,456,648)}
            $scale=[Math]::Min($target.Width/$image.Width,$target.Height/$image.Height)
            $w=[single]($image.Width*$scale);$h=[single]($image.Height*$scale)
            $g.DrawImage($image,([single]($target.X+($target.Width-$w)/2)),([single]($target.Y+($target.Height-$h)/2)),$w,$h)
        } else {
            $pen=New-Object Drawing.Pen($color,4)
            $g.DrawEllipse($pen,145,160,190,190)
            $initial=if($item.Kind -eq 'system'){$item.SystemId.ToUpperInvariant()}else{'ROM'}
            $g.DrawString($initial,$font,$textBrush,(New-Object Drawing.RectangleF(130,180,220,150)),$format)
        }
        if(-not $official){$g.DrawString('ARTE INDISPONIVEL',$small,$muted,(New-Object Drawing.RectangleF(30,580,420,40)),$format)}
        $tmp=$dest+'.tmp';$bitmap.Save($tmp,[Drawing.Imaging.ImageFormat]::Png)
        [IO.File]::Copy($tmp,$dest,$true);[IO.File]::Delete($tmp)
    } finally {
        foreach($resource in @($image,$pen,$format,$small,$font,$brush,$textBrush,$muted,$accent,$g,$bitmap)){if($resource){$resource.Dispose()}}
    }
}
$catalogues=@{}
function Find-Boxart($item){
    $sys=$item.SystemId
    if(-not $item.Repository){return $null}
    if(-not $catalogues.ContainsKey($sys)){
        $indexFile=Join-Path $media ('Indices\'+$sys+'.html')
        $url='https://thumbnails.libretro.com/'+[Uri]::EscapeDataString($item.Repository)+'/Named_Boxarts/'
        if($state.ContainsKey('index:'+$sys) -and (Asset-RetryDue $state['index:'+$sys])){[void]$state.Remove('index:'+$sys)}
        if($state.ContainsKey('index:'+$sys) -and -not (Test-Path -LiteralPath $indexFile)) { throw 'Indice de capas indisponivel; aguarde 30 minutos ou use Tentar novamente artes pendentes.' }
        try {Get-Asset $url $indexFile} catch {$state['index:'+$sys]=@{Status='error';Error=$_.Exception.Message;TransportVersion=$script:assetTransportVersion;Checked=[datetime]::UtcNow.ToString('o')};Save-State;throw}
        $html=[IO.File]::ReadAllText($indexFile)
        $exact=@{};$normalized=@{}
        foreach($match in [regex]::Matches($html,'href="([^"?]+\.png)"')){
            $file=[Net.WebUtility]::HtmlDecode([Uri]::UnescapeDataString($match.Groups[1].Value))
            $exact[$file]=$url+[Uri]::EscapeDataString($file)
            $key=Normalize-Title $file
            if(-not $normalized.ContainsKey($key)){$normalized[$key]=New-Object Collections.Generic.List[string]}
            $normalized[$key].Add($file)
        }
        $catalogues[$sys]=@{Exact=$exact;Normalized=$normalized}
    }
    $cat=$catalogues[$sys];$filename=$item.Name+'.png'
    if($cat.Exact.ContainsKey($filename)){return $cat.Exact[$filename]}
    $key=Normalize-Title ($item.Name+'.png')
    $choices=@($cat.Normalized[$key] | Where-Object {$_})
    if(-not $choices.Count -and $key.Length -ge 12){
        $prefixes=@($cat.Normalized.Keys | Where-Object {$_.StartsWith($key)})
        if($prefixes.Count -eq 1){$choices=@($cat.Normalized[$prefixes[0]])}
    }
    $choice=$choices | Where-Object {$_ -and $_ -notmatch '\((?:Beta|Proto|Demo)'} | Sort-Object @{Expression={if($_ -match '\(USA'){0}elseif($_ -match '\(World'){1}elseif($_ -match '\(Europe'){2}else{3}}},Length | Select-Object -First 1
    if($choice){return $cat.Exact[$choice]}
    return $null
}
try {
    $items=@($requests.Systems)+@($requests.Games)
    $recover=@{}
    $done=0
    foreach($item in $items){
        $dest=Join-Path $Root $item.Path
        if(-not(Test-Path -LiteralPath $dest)){
            $original='';$entry=$state[$item.Key]
            if($entry -and $entry.Source){
                $sha=[Security.Cryptography.SHA256]::Create()
                try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($entry.Source)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                $candidate=Join-Path $media ('Originais\'+$hash+'.png')
                if(Test-Path -LiteralPath $candidate){$original=$candidate}
            }
            Write-Card $item $original ([bool]$original)
            if(-not $original -and $entry -and $entry.Status -eq 'downloaded' -and $entry.Source){$recover[$item.Key]=$entry.Source}
        }
        $done++;if(($done % 25)-eq 0){Save-Progress 'Preparando artes locais' $done $items.Count}
    }
    if($PrepareOnly){Save-Progress 'Artes locais prontas' $items.Count $items.Count;return}
    $done=0
    foreach($item in $items){
        $key=$item.Key;$dest=Join-Path $Root $item.Path
        if($state.ContainsKey($key) -and (Asset-RetryDue $state[$key])){[void]$state.Remove($key)}
        if($state.ContainsKey($key) -and (Test-Path -LiteralPath $dest)){
            if($recover.ContainsKey($key)){
                try{
                    $sha=[Security.Cryptography.SHA256]::Create()
                    try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($recover[$key])))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                    $recovered=Join-Path $media ('Originais\'+$hash+'.png')
                    Get-Asset $recover[$key] $recovered
                    Write-Card $item $recovered $true
                }catch{
                    $state[$key].Status='error'
                    $state[$key] | Add-Member NoteProperty Error $_.Exception.Message -Force
                    $state[$key] | Add-Member NoteProperty TransportVersion $script:assetTransportVersion -Force
                    $state[$key] | Add-Member NoteProperty Checked ([datetime]::UtcNow.ToString('o')) -Force
                }
                Save-State
            }
            if($state[$key].StyleVersion -ne 2){
                $cached=''
                if($state[$key].Source){
                    $sha=[Security.Cryptography.SHA256]::Create()
                    try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($state[$key].Source)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                    $candidate=Join-Path $media ('Originais\'+$hash+'.png')
                    if(Test-Path -LiteralPath $candidate){$cached=$candidate}
                }
                Write-Card $item $cached ([bool]$cached)
                $state[$key] | Add-Member NoteProperty StyleVersion 2 -Force
                Save-State
            }
            $done++;continue
        }
        $status='fallback';$source='';$errorText=''
        try {
            if($item.Kind -eq 'system'){
                $source='https://raw.githubusercontent.com/libretro/retroarch-assets/master/xmb/monochrome/png/'+[Uri]::EscapeDataString($item.Repository)+'.png'
            }else{$source=Find-Boxart $item}
            if($source){
                $sha=[Security.Cryptography.SHA256]::Create()
                try{$name=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                $original=Join-Path $media ('Originais\'+$name+'.png')
                Get-Asset $source $original
                Write-Card $item $original $true
                $status='downloaded'
            }
        }catch{$status='error';$errorText=$_.Exception.Message}
        $state[$key]=@{Status=$status;Path=$item.Path;Source=$source;Error=$errorText;Checked=[datetime]::UtcNow.ToString('o');StyleVersion=2;TransportVersion=$script:assetTransportVersion}
        $done++;Save-State;Save-Progress 'Baixando capas e logos' $done $items.Count
    }
    Save-State -Force
    Save-Progress 'Concluido' $items.Count $items.Count
}finally{
    $lock.ReleaseMutex();$lock.Dispose()
}
