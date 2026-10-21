$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'src\HydraArtworkMatching.ps1')
$url='https://example.invalid/snes/'
$html='<a href="Adventures%20of%20Batman%20_%20Robin,%20The%20(USA).png">x</a><a href="Todd%20McFarlane%27s%20Spawn%20-%20The%20Video%20Game%20(USA).png">x</a><a href="Magic%20Knight%20Rayearth%20(Japan).png">x</a><a href="Street%20Fighter%20II%20Turbo%20(USA).png">x</a><a href="Simpsons,%20The%20-%20Bart%20vs.%20the%20Space%20Mutants%20(USA).png">x</a>'
$cat=ConvertTo-HydraArtworkCatalogue $html $url
foreach($pair in @(@('snes','The Adventures of Batman & Robin'),@('snes','Spawn'),@('snes','Mahou Kishi Rayearth'),@('snes','Street Fighter II Turbo Hyper Fighting'),@('nes','Simpsons_Bart_vs_Space_Mutants_USA_PT-BR_v14'),@('nes','Simpsons_PT-BR_v13_DEBUG_Fase_3_Krustyland'))){
    if(-not (Find-HydraArtworkCandidate $cat $pair[1] $pair[0])){throw ('Alias not resolved: '+$pair[1])}
}
if(Find-HydraArtworkCandidate $cat 'Spawn' 'genesis'){throw 'Alias crossed platforms'}
if(Find-HydraArtworkCandidate $cat 'Street Fighter' 'snes'){throw 'Sequel guessed'}
if(Find-HydraArtworkCandidate $cat 'Spawn 2' 'snes'){throw 'Alias crossed sequel'}
if(-not (Test-HydraArtworkRetryDue ([pscustomobject]@{Status='fallback';MatchingVersion=3;Checked=[datetime]::UtcNow.ToString('o')}) 'Spawn')){throw 'Old misses not retried'}
'ARTWORK_ALIASES_ARTICLES_CONNECTORS_PLATFORM_AND_SEQUEL_GUARDS_OK'
