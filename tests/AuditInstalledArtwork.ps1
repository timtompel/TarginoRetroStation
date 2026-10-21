param([string]$Root='D:\Games\hydra')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'src\HydraArtworkMatching.ps1')
$app=Join-Path $Root 'TarginoRetroStation'
$state=Get-Content (Join-Path $app 'Dados\hydra-midia-indice.json') -Raw|ConvertFrom-Json
$requests=Get-Content (Join-Path $app 'Dados\hydra-midia-pedidos.json') -Raw|ConvertFrom-Json
$catalogues=@{};$fixed=0;$missing=0
foreach($item in $requests.Games){
    if($state.($item.Key).Status -ne 'fallback'){continue}
    $sys=$item.SystemId
    if(-not $catalogues.ContainsKey($sys)){
        $index=Join-Path $app ('Midia\Indices\'+$sys+'.html')
        $url='https://thumbnails.libretro.com/'+[Uri]::EscapeDataString($item.Repository)+'/Named_Boxarts/'
        $catalogues[$sys]=ConvertTo-HydraArtworkCatalogue ([IO.File]::ReadAllText($index)) $url
    }
    $source=Find-HydraArtworkCandidate $catalogues[$sys] $item.Name $sys
    if($source){$fixed++;'FOUND: '+$sys+' | '+$item.Name+' => '+[Uri]::UnescapeDataString(($source -split '/')[-1])}else{$missing++}
}
'RECOVERABLE='+$fixed+'; REMAINING='+$missing
