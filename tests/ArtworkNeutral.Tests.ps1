$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$fixture=Join-Path $project ('build\neutral-art-'+[guid]::NewGuid().ToString('N'))
$app=Join-Path $fixture 'TarginoRetroStation';$data=Join-Path $app 'Dados';$media=Join-Path $app 'Midia'
foreach($d in @($app,$data,(Join-Path $media 'Originais'))){[void][IO.Directory]::CreateDirectory($d)}
Copy-Item (Join-Path $project 'src\*') $app
Add-Type -AssemblyName System.Drawing
$state=@{};$games=@()
foreach($sys in @('snes','genesis')){
    $source='https://example.invalid/'+$sys+'.png'
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    $bitmap=New-Object Drawing.Bitmap(100,50);$g=[Drawing.Graphics]::FromImage($bitmap)
    try{$g.Clear($(if($sys -eq 'snes'){[Drawing.Color]::Purple}else{[Drawing.Color]::Green}));$bitmap.Save((Join-Path $media ('Originais\'+$hash+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$g.Dispose();$bitmap.Dispose()}
    $state['system:'+$sys]=@{Source=$source;Status='downloaded';StyleVersion=2}
    $games+=@{Key=('game:'+ $sys);Kind='game';SystemId=$sys;SystemName=$(if($sys -eq 'snes'){'Super Nintendo'}else{'Sega Genesis'});Name='No official artwork';Repository='';Color='#9966DD';Path=('TarginoRetroStation\Midia\Capas\'+$sys+'.png')}
}
[IO.File]::WriteAllText((Join-Path $data 'hydra-midia-indice.json'),($state|ConvertTo-Json -Depth 5))
[IO.File]::WriteAllText((Join-Path $data 'hydra-midia-pedidos.json'),(@{RootKey=[guid]::NewGuid().ToString('N');Systems=@();Games=$games}|ConvertTo-Json -Depth 6))
& (Join-Path $app 'HydraArtwork.ps1') -Root $fixture
$result=Get-Content (Join-Path $data 'hydra-midia-indice.json') -Raw|ConvertFrom-Json
foreach($sys in @('snes','genesis')){
    $entry=$result.('game:'+$sys)
    if($entry.Status -ne 'fallback' -or $entry.SourceKind -ne 'platform-neutral' -or $entry.StyleVersion -ne 3){throw 'Neutral image mislabeled as official'}
    $image=[Drawing.Bitmap]::FromFile((Join-Path $media ('Capas\'+$sys+'.png')))
    try{$pixel=$image.GetPixel(240,255);if($sys -eq 'snes' -and $pixel.R -le $pixel.G){throw 'Wrong platform icon'};if($sys -eq 'genesis' -and $pixel.G -le $pixel.R){throw 'Wrong platform icon'}}finally{$image.Dispose()}
}
'NEUTRAL_PLATFORM_IMAGES_CORRECT_AND_NOT_OFFICIAL; FIXTURE='+$fixture
