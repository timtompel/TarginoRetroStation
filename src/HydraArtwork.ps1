param([string]$Root='D:\Games\hydra', [switch]$PrepareOnly)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'HydraArtworkMatching.ps1')
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
    return (Test-HydraArtworkRetryDue $entry)
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
    foreach($key in @(@($requests.Systems)+@($requests.Games)|Where-Object {$_}|ForEach-Object {$_.Key}|Select-Object -Unique)){
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
    Normalize-HydraArtworkTitle $name
}
function Write-Card($item,[string]$imagePath,[bool]$official){
    $neutral=(-not $official -and $item.Kind -eq 'game')
    if($neutral -and -not $imagePath){
        $platform=$state[('system:'+$item.SystemId)]
        if($platform -and $platform.Source){
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$iconHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($platform.Source)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
            $icon=Join-Path $media ('Originais\'+$iconHash+'.png')
            if([IO.File]::Exists($icon)){$imagePath=$icon}
        }
    }
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
            $target=if($neutral){New-Object Drawing.RectangleF(70,130,340,250)}elseif($item.Kind -eq 'system'){New-Object Drawing.RectangleF(50,80,380,520)}else{New-Object Drawing.RectangleF(12,16,456,648)}
            $scale=[Math]::Min($target.Width/$image.Width,$target.Height/$image.Height)
            $w=[single]($image.Width*$scale);$h=[single]($image.Height*$scale)
            $g.DrawImage($image,([single]($target.X+($target.Width-$w)/2)),([single]($target.Y+($target.Height-$h)/2)),$w,$h)
        } else {
            $pen=New-Object Drawing.Pen($color,4)
            $g.DrawEllipse($pen,145,160,190,190)
            $initial=$item.SystemId.ToUpperInvariant()
            $g.DrawString($initial,$font,$textBrush,(New-Object Drawing.RectangleF(130,180,220,150)),$format)
        }
        if($neutral){
            $label=if($item.SystemName){$item.SystemName}else{$item.SystemId.ToUpperInvariant()}
            $g.DrawString($label,$font,$textBrush,(New-Object Drawing.RectangleF(25,410,430,110)),$format)
            $g.DrawString('ARTE DO SISTEMA',$small,$muted,(New-Object Drawing.RectangleF(30,580,420,40)),$format)
        }elseif(-not $official){$g.DrawString('ARTE INDISPONIVEL',$small,$muted,(New-Object Drawing.RectangleF(30,580,420,40)),$format)}
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
        if(([datetime]::UtcNow-[IO.File]::GetLastWriteTimeUtc($indexFile)).TotalDays -ge 1){
            $refresh=$indexFile+'.refresh-'+[guid]::NewGuid().ToString('N')
            try{
                Get-Asset $url $refresh
                [void](ConvertTo-HydraArtworkCatalogue ([IO.File]::ReadAllText($refresh)) $url)
                [IO.File]::Replace($refresh,$indexFile,($indexFile+'.bak'))
            }finally{if([IO.File]::Exists($refresh)){[IO.File]::Delete($refresh)}}
        }
        $catalogues[$sys]=ConvertTo-HydraArtworkCatalogue ([IO.File]::ReadAllText($indexFile)) $url
    }
    return (Find-HydraArtworkCandidate $catalogues[$sys] $item.Name $sys)
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
        if($state.ContainsKey($key) -and (Test-HydraArtworkRetryDue $state[$key] $item.Name)){[void]$state.Remove($key)}
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
            $expectedStyle=Get-HydraArtworkStyleVersion $state[$key]
            if($state[$key].StyleVersion -ne $expectedStyle){
                $cached=''
                if($state[$key].Source){
                    $sha=[Security.Cryptography.SHA256]::Create()
                    try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($state[$key].Source)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                    $candidate=Join-Path $media ('Originais\'+$hash+'.png')
                    if(Test-Path -LiteralPath $candidate){$cached=$candidate}
                }
                Write-Card $item $cached ([bool]$cached)
                $state[$key] | Add-Member NoteProperty StyleVersion $expectedStyle -Force
                Save-State
            }
            $done++;continue
        }
        $status='fallback';$source='';$errorText=''
        try {
            if($item.Kind -eq 'system'){
                $source='https://raw.githubusercontent.com/libretro/retroarch-assets/master/xmb/monochrome/png/'+[Uri]::EscapeDataString($item.Repository)+'.png'
            }else{
                $supplemental=Get-HydraSupplementalArtwork $item.SystemId $item.Name
                try{$source=Find-Boxart $item}catch{if(-not $supplemental){throw}}
                if(-not $source -and $supplemental){$source=$supplemental}
            }
            if($source){
                $sha=[Security.Cryptography.SHA256]::Create()
                try{$name=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                $original=Join-Path $media ('Originais\'+$name+'.png')
                Get-Asset $source $original
                Write-Card $item $original $true
                $status='downloaded'
            }
        }catch{$status='error';$errorText=$_.Exception.Message}
        if($status -ne 'downloaded'){Write-Card $item '' $false}
        $sourceKind=if($status -ne 'downloaded' -and $item.Kind -eq 'game'){'platform-neutral'}elseif($source -like 'https://archive3do.com/*'){'platform-screenshot'}else{'boxart'}
        $state[$key]=@{Status=$status;Path=$item.Path;Source=$source;SourceKind=$sourceKind;Error=$errorText;Checked=[datetime]::UtcNow.ToString('o');StyleVersion=$(if($status -eq 'downloaded'){2}else{3});TransportVersion=$script:assetTransportVersion;MatchingVersion=4;MatchName=(Normalize-Title $item.Name);Reason=$(if($status -eq 'fallback'){'not-in-platform-index'}elseif($sourceKind -eq 'platform-screenshot'){'supplemental-gameplay-image'}else{''})}
        $done++;Save-State;Save-Progress 'Baixando capas e logos' $done $items.Count
    }
    Save-State -Force
    Save-Progress 'Concluido' $items.Count $items.Count
}finally{
    $lock.ReleaseMutex();$lock.Dispose()
}
