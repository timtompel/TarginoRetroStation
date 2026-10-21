$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
. (Join-Path $project 'src\HydraArtworkMatching.ps1')
$url='https://example.invalid/3do/'
$cat=ConvertTo-HydraArtworkCatalogue '<a href="Pac-Man%20(USA).png">cover</a><a href="Street%20Fighter%20II%20(USA).png">cover</a><a href="Game%20(Beta).png">cover</a>' $url
foreach($name in @('PacMan (US)','Pac Man (USA)','PAC-MAN','Pac Man (US) — Telegram')){
    if((Find-HydraArtworkCandidate $cat $name) -ne ($url+[Uri]::EscapeDataString('Pac-Man (USA).png'))){throw ('Nome nao reconhecido: '+$name)}
}
if(Find-HydraArtworkCandidate $cat 'Street Fighter'){throw 'Outra sequencia atribuida por prefixo'}
if(Find-HydraArtworkCandidate $cat 'Game'){throw 'Beta usado como jogo final'}
$bad=$false;try{[void](ConvertTo-HydraArtworkCatalogue '<html>Service unavailable</html>' $url)}catch{$bad=$true};if(-not $bad){throw 'HTML invalido tratado como jogo ausente'}
$entry=[pscustomobject]@{Status='fallback';MatchingVersion=4;MatchName='pacman';Checked=[datetime]::UtcNow.ToString('o')}
if(Test-HydraArtworkRetryDue $entry 'Pac Man (US)'){throw 'Cache negativo recente nao respeitado'}
$entry.Checked=[datetime]::UtcNow.AddDays(-2).ToString('o')
if(-not (Test-HydraArtworkRetryDue $entry 'PacMan')){throw 'Cache negativo continua permanente'}
if(-not (Test-HydraArtworkRetryDue ([pscustomobject]@{Status='fallback'}) 'PacMan')){throw 'Cache antigo nao migrou'}
if(Test-HydraArtworkRetryDue ([pscustomobject]@{Status='error';TransportVersion=3;Checked=[datetime]::UtcNow.ToString('o')})){throw 'UI/worker discordam da versao de transporte'}
$fixture=Join-Path $project ('build\artwork-matching-'+[guid]::NewGuid().ToString('N'))
$addon=Join-Path $fixture 'TarginoRetroStation';$media=Join-Path $addon 'Midia';$data=Join-Path $addon 'Dados'
foreach($dir in @($data,(Join-Path $media 'Indices'),(Join-Path $media 'Originais'))){[void][IO.Directory]::CreateDirectory($dir)}
Copy-Item (Join-Path $project 'src\*') $addon
$item=@{Key='game:pacman';Kind='game';SystemId='3do';SystemName='3DO';Name='Pac Man (US)';Repository='fixture';Color='#49C4E5';Path='TarginoRetroStation\Midia\Capas\pacman.png'}
[IO.File]::WriteAllText((Join-Path $data 'hydra-midia-pedidos.json'),(@{RootKey=[guid]::NewGuid().ToString('N');Systems=@();Games=@($item)}|ConvertTo-Json -Depth 6))
$indexHtml='<a href="Pac-Man%20(USA).png">cover</a>'
[IO.File]::WriteAllText((Join-Path $media 'Indices\3do.html'),$indexHtml)
$source='https://thumbnails.libretro.com/fixture/Named_Boxarts/'+[Uri]::EscapeDataString('Pac-Man (USA).png')
$sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
Add-Type -AssemblyName System.Drawing
$image=New-Object Drawing.Bitmap(20,30);try{$image.Save((Join-Path $media ('Originais\'+$hash+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$image.Dispose()}
[IO.File]::WriteAllText((Join-Path $data 'hydra-midia-indice.json'),(@{'game:pacman'=@{Status='fallback';Path=$item.Path};'game:removed'=@{Status='fallback'}}|ConvertTo-Json -Depth 4))
& (Join-Path $addon 'HydraArtwork.ps1') -Root $fixture
$state=Get-Content (Join-Path $data 'hydra-midia-indice.json') -Raw|ConvertFrom-Json
$progress=Get-Content (Join-Path $data 'hydra-midia-progresso.json') -Raw|ConvertFrom-Json
if($state.'game:pacman'.Status -ne 'downloaded'){throw 'Worker nao recuperou correspondencia antiga'}
if($progress.Saved -ne 1 -or $progress.NotFound -ne 0){throw 'Contador inclui jogo removido'}
'ARTWORK_NORMALIZATION_NEGATIVE_CACHE_TRANSPORT_VERSION_AND_WORKER_COUNTS_OK'
