param([Parameter(Mandatory=$true)][string]$RequestFile,[switch]$Force)
$ErrorActionPreference='Stop'
$request=Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json
$addon=[IO.Path]::GetFullPath($request.Addon)
$metadataModule=Join-Path $addon 'HydraMetadata.ps1'
if([IO.File]::Exists($metadataModule)){. $metadataModule}
$store=Join-Path $addon 'Dados\Detalhes';$sources=Join-Path $store 'Fontes';$snaps=Join-Path $addon 'Midia\Capturas'
foreach($folder in @($store,$sources,$snaps)){[void][IO.Directory]::CreateDirectory($folder)}
$cache=Join-Path $store ($request.Key+'.json')
$mutex=New-Object Threading.Mutex($false,('Local\TarginoDetails-'+$request.Key+'-'+([Math]::Abs($addon.GetHashCode()))))
if(-not $mutex.WaitOne(0)){$mutex.Dispose();exit}
$script:transport=$null;$script:pythonOnly=$false;$script:downloads=0
function Save-Details($object){
    $temporary=$cache+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temporary,(ConvertTo-Json $object -Depth 6),(New-Object Text.UTF8Encoding($false)))
    # Copy fallback works on filesystems which do not support File.Replace.
    if([IO.File]::Exists($cache)){try{[IO.File]::Replace($temporary,$cache,$null)}catch{[IO.File]::Copy($temporary,$cache,$true);[IO.File]::Delete($temporary)}}else{[IO.File]::Move($temporary,$cache)}
}
function Fetch-Details([string]$url,[string]$path){
    if([IO.File]::Exists($path)){return}
    $tmp=$path+'.download'
    if(-not $script:pythonOnly){
        $web=if(Get-Command NewHydraMetadataWebClient -ErrorAction SilentlyContinue){NewHydraMetadataWebClient}else{New-Object Net.WebClient}
        $web.Headers['User-Agent']='TarginoRetroStation/1.3 (+libretro metadata)'
        try{$web.DownloadFile($url,$tmp);[IO.File]::Move($tmp,$path);$script:downloads++;return}
        catch{if($_.Exception.InnerException -and $_.Exception.InnerException.Response){throw};$script:pythonOnly=$true}
        finally{$web.Dispose()}
    }
    if(-not $script:transport){
        $python=Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        $pythonPath=if($python){$python.Source}else{Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'}
        if(-not [IO.File]::Exists($pythonPath)){throw 'Conexao HTTPS indisponivel neste Windows.'}
        $pi=New-Object Diagnostics.ProcessStartInfo
        $pi.FileName=$pythonPath;$pi.Arguments='-u "'+(Join-Path $addon 'hydra-media-transport.py')+'"'
        $pi.UseShellExecute=$false;$pi.CreateNoWindow=$true;$pi.RedirectStandardInput=$true;$pi.RedirectStandardOutput=$true
        $script:transport=[Diagnostics.Process]::Start($pi)
    }
    $script:transport.StandardInput.WriteLine((ConvertTo-Json @{url=$url;path=$tmp} -Compress));$script:transport.StandardInput.Flush()
    $line=$script:transport.StandardOutput.ReadLine();if(-not $line){throw 'Transporte HTTPS encerrado.'}
    $reply=$line | ConvertFrom-Json;if(-not $reply.ok){throw "HTTP $($reply.status): $($reply.error)"}
    [IO.File]::Move($tmp,$path);$script:downloads++
}
function Details-Normalize([string]$title){
    $title=$title -replace '\([^)]*\)|\[[^]]*\]',' '
    $title=$title -replace '(?i)[_ -]+(?:ptbr|pt-br|traduzid[ao]s?|translation|hack|v\d+\.\d+).*$',''
    $title=$title -replace '(?i)_(?:gg|sms|snes)$',''
    $title=$title -replace '(?i),\s*(The|A|An)\s*$',''
    $title=$title.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}',''
    ($title.ToLowerInvariant() -replace '[^a-z0-9]','')
}
function Pick-Details($choices){
    $desiredRegion=[regex]::Match($request.Name,'\((USA|Europe|Japan|World)(?:[, )])').Groups[1].Value
    @($choices | Sort-Object @{Expression={if(($_.Title -replace '\.png$','') -eq $request.Name){0}elseif($desiredRegion -and $_.Title.Contains('('+$desiredRegion)){1}elseif($_.Title -match '\(USA'){2}elseif($_.Title -match '\(World'){3}elseif($_.Title -match '\(Europe'){4}else{5}}},@{Expression={$_.Title.Length}} | Select-Object -First 1)[0]
}
try{
    if([IO.File]::Exists($cache) -and -not $Force){
        $saved=[IO.File]::ReadAllText($cache) | ConvertFrom-Json
        if($saved.Snapshot -and $saved.SnapshotSource){
            $target=[IO.Path]::GetFullPath((Join-Path $addon $saved.Snapshot));$uri=$null
            if(-not [IO.File]::Exists($target) -and $target.StartsWith(($addon.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase) -and [Uri]::TryCreate($saved.SnapshotSource,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -eq 'https'){
                try{Fetch-Details $saved.SnapshotSource $target;'CACHE_IMAGE_REPAIRED'}catch{[IO.File]::WriteAllText(($cache+'.snapshot.failed'),[datetime]::UtcNow.ToString('o'));'CACHE_IMAGE_UNAVAILABLE'}
                exit
            }
        }
        'CACHE_HIT';exit
    }
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $result=[ordered]@{Id=$request.Id;SystemId=$request.SystemId;Name=$request.Name;Fields=@{};MatchedName='';Snapshot='';SnapshotSource='';Sources=@();Errors=@();Status='loading';Checked=(Get-Date).ToString('s');Downloads=0}
    $key=Details-Normalize $request.Name
    if(-not $request.Repository){$result.Status='notfound';Save-Details $result;exit}
    $system=[Uri]::EscapeDataString($request.Repository)
    foreach($field in @('developer','publisher','genre','releaseyear','maxusers')){
        $path=Join-Path $sources ($request.SystemId+'-'+$field+'.dat')
        $failure=$path+'.failed'
        if($Force -and [IO.File]::Exists($failure)){[IO.File]::Delete($failure)}
        if([IO.File]::Exists($failure)){continue}
        $url='https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/'+$field+'/'+$system+'.dat'
        try{
            Fetch-Details $url $path
            $text=[IO.File]::ReadAllText($path)
            $candidates=New-Object Collections.Generic.List[object]
            foreach($block in [regex]::Matches($text,'(?ms)^game\s*\(\s*(.*?)^\)')){
                $title=[regex]::Match($block.Groups[1].Value,'(?m)^\s*(?:comment|name)\s+"([^"]+)"').Groups[1].Value
                if(-not $title -or (Details-Normalize $title) -ne $key -or $title -match '\((?:Beta|Proto|Demo|Sample)'){continue}
                $datField=if($field -eq 'maxusers'){'users'}else{$field}
                $value=[regex]::Match($block.Groups[1].Value,('(?m)^\s*'+$datField+'\s+"?([^"\r\n]+)')).Groups[1].Value.Trim()
                if($value){$candidates.Add([pscustomobject]@{Title=$title;Value=$value})}
            }
            $match=Pick-Details $candidates
            if($match){$result.Fields[$field]=$match.Value;$result.MatchedName=$match.Title;$result.Sources+=@{Kind=$field;Url=$url}}
        }catch{$result.Errors+=($field+': '+$_.Exception.Message);[IO.File]::WriteAllText($failure,$_.Exception.Message)}
    }
    Save-Details $result
    try{
        $index=Join-Path $sources ($request.SystemId+'-snaps.html');$failure=$index+'.failed'
        if($Force -and [IO.File]::Exists($failure)){[IO.File]::Delete($failure)}
        if([IO.File]::Exists($failure)){throw 'Indice de capturas indisponivel; use Atualizar dados para tentar novamente.'}
        $base='https://thumbnails.libretro.com/'+$system+'/Named_Snaps/'
        try{Fetch-Details $base $index}catch{[IO.File]::WriteAllText($failure,$_.Exception.Message);throw}
        $choices=New-Object Collections.Generic.List[object]
        foreach($link in [regex]::Matches([IO.File]::ReadAllText($index),'href="([^"?]+\.png)"')){
            $filename=[Net.WebUtility]::HtmlDecode([Uri]::UnescapeDataString($link.Groups[1].Value))
            if((Details-Normalize ([IO.Path]::GetFileNameWithoutExtension($filename))) -eq $key -and $filename -notmatch '\((?:Beta|Proto|Demo|Sample)'){$choices.Add([pscustomobject]@{Title=$filename;Value=$base+[Uri]::EscapeDataString($filename)})}
        }
        $choice=Pick-Details $choices
        if($choice){
            $snap=Join-Path $snaps ($request.Key+'.png');Fetch-Details $choice.Value $snap
            Add-Type -AssemblyName System.Drawing
            $image=[Drawing.Image]::FromFile($snap);$image.Dispose()
            $result.Snapshot='Midia\Capturas\'+$request.Key+'.png';$result.SnapshotSource=$choice.Value
        }
    }catch{$result.Errors+=('snapshot: '+$_.Exception.Message)}
    if(Get-Command HydraMetadataComplement -ErrorAction SilentlyContinue){HydraMetadataComplement $result $request $addon}
    $result.Status=if($result.Fields.Count -or $result.Snapshot -or $result.Overview){'ready'}elseif($result.Errors.Count){'error'}else{'notfound'}
    $result.Downloads=$script:downloads;Save-Details $result
    'DETAILS_READY '+$result.Status+' downloads='+$script:downloads
}catch{
    if($result){$result.Status='error';$result.Errors+= $_.Exception.Message;$result.Downloads=$script:downloads;Save-Details $result}
    Write-Error $_
}finally{
    if($script:transport){$script:transport.StandardInput.Close();if(-not $script:transport.WaitForExit(1500)){$script:transport.Kill()};$script:transport.Dispose()}
    $mutex.ReleaseMutex();$mutex.Dispose()
}
