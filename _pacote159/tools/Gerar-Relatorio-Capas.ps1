<#
 Gera um relatorio dos jogos SEM capa confirmada, com os nomes mais parecidos do indice
 Libretro (Named_Boxarts) do MESMO console. Nada e aplicado automaticamente: voce decide.

 Uso:
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File Gerar-Relatorio-Capas.ps1 -Root "D:\Games\hydra"

 Saidas (na pasta TarginoRetroStation\Dados):
   Relatorio-Capas-Sem-Correspondencia.md   -> lista legivel com as sugestoes
   hydra-capas-aliases.modelo.json          -> modelo para preencher

 Como aplicar: copie o nome certo para o modelo, salve como hydra-capas-aliases.json
 (mesma pasta). Na proxima execucao do worker de capas, os jogos sem capa sao consultados
 de novo automaticamente. Valores vazios sao ignorados.
#>
param(
    [Parameter(Mandatory)][string]$Root,
    [int]$Top=3,
    [double]$MinScore=0.30,
    [string]$MatchingModule=''
)
$ErrorActionPreference='Stop'
$app=Join-Path $Root 'TarginoRetroStation'
$data=Join-Path $app 'Dados'
$media=Join-Path $app 'Midia'
if(-not $MatchingModule){$MatchingModule=Join-Path $app 'HydraArtworkMatching.ps1'}
if(-not [IO.File]::Exists($MatchingModule)){throw "Modulo nao encontrado: $MatchingModule (use -MatchingModule)."}
. $MatchingModule

function Get-Tokens([string]$text){
    $text=Get-HydraArtworkQueryTitle $text
    $text=$text -replace '\([^)]*\)|\[[^]]*\]',' '
    $text=$text -replace '(?i)[_ -]+(?:ptbr|pt-br|traduzid[ao]s?|translation|hack|v\d+\.\d+).*$',''
    $text=$text.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}',''
    $set=New-Object Collections.Generic.HashSet[string]
    foreach($t in ($text.ToLowerInvariant() -split '[^a-z0-9]+')){
        if($t -and $t -notin @('the','and','of','a','no','to')){[void]$set.Add($t)}
    }
    return ,$set
}
function Get-Dice($a,$b){
    if($a.Count -eq 0 -or $b.Count -eq 0){return 0.0}
    $common=0
    foreach($t in $a){if($b.Contains($t)){$common++}}
    return (2.0*$common)/($a.Count+$b.Count)
}

$requests=[IO.File]::ReadAllText((Join-Path $data 'hydra-midia-pedidos.json'))|ConvertFrom-Json
$state=[IO.File]::ReadAllText((Join-Path $data 'hydra-midia-indice.json'))|ConvertFrom-Json
$pool=@{}   # sistema -> lista de candidatos (titulo limpo, arquivo, tokens)
function Get-Pool([string]$systemId){
    if($pool.ContainsKey($systemId)){return $pool[$systemId]}
    $file=Join-Path $media ('Indices\'+$systemId+'.html')
    if(-not [IO.File]::Exists($file)){$pool[$systemId]=@();return $pool[$systemId]}
    $catalogue=ConvertTo-HydraArtworkCatalogue ([IO.File]::ReadAllText($file)) 'https://thumbnails.libretro.com/'
    $seen=@{};$list=New-Object Collections.Generic.List[object]
    foreach($name in ($catalogue.Exact.Keys|Sort-Object)){
        if($name -match '(?i)\((?:Beta|Proto|Demo)'){continue}
        $clean=([IO.Path]::GetFileNameWithoutExtension($name) -replace '\s*\([^)]*\)','').Trim()
        if($seen.ContainsKey($clean)){continue}
        $seen[$clean]=$true
        $list.Add([pscustomobject]@{Title=$clean;File=$name;Tokens=(Get-Tokens $clean)})
    }
    $pool[$systemId]=$list
    return $list
}

$md=New-Object Text.StringBuilder
$model=[ordered]@{}
$total=0;$withSuggestion=0
[void]$md.AppendLine('# Jogos sem capa confirmada');[void]$md.AppendLine()
[void]$md.AppendLine('Gerado em '+(Get-Date -Format 's')+'. Sugestoes por similaridade de palavras, restritas ao mesmo console. Confirme cada uma antes de usar.');[void]$md.AppendLine()
$games=@($requests.Games|Where-Object {$_ -and $state.($_.Key) -and $state.($_.Key).Status -eq 'fallback'}|Sort-Object SystemId,Name)
foreach($group in ($games|Group-Object SystemId)){
    [void]$md.AppendLine('## '+$(if($group.Group[0].SystemName){$group.Group[0].SystemName}else{$group.Name})+' (`'+$group.Name+'`)');[void]$md.AppendLine()
    $model[$group.Name]=[ordered]@{}
    $candidates=@(Get-Pool $group.Name)
    foreach($game in $group.Group){
        $total++
        $tokens=Get-Tokens $game.Name
        $ranked=@($candidates|ForEach-Object {[pscustomobject]@{Score=(Get-Dice $tokens $_.Tokens);Title=$_.Title;File=$_.File}}|Where-Object {$_.Score -ge $MinScore}|Sort-Object @{Expression='Score';Descending=$true},Title|Select-Object -First $Top)
        [void]$md.AppendLine('- **'+$game.Name+'**')
        if($ranked.Count){
            $withSuggestion++
            foreach($r in $ranked){[void]$md.AppendLine(('    - {0:P0} - {1}' -f $r.Score,$r.Title))}
        }else{[void]$md.AppendLine('    - (sem sugestao parecida; provavelmente nao existe nesta fonte)')}
        $model[$group.Name][[string]$game.Name]=''
    }
    [void]$md.AppendLine()
}
$header=('<!-- {0} jogos sem capa; {1} com sugestao -->' -f $total,$withSuggestion)+[Environment]::NewLine
[void]$md.Insert(0,$header)
$utf8=New-Object Text.UTF8Encoding($true)
$mdPath=Join-Path $data 'Relatorio-Capas-Sem-Correspondencia.md'
$jsonPath=Join-Path $data 'hydra-capas-aliases.modelo.json'
[IO.File]::WriteAllText($mdPath,$md.ToString(),$utf8)
[IO.File]::WriteAllText($jsonPath,($model|ConvertTo-Json -Depth 4),$utf8)
Write-Host ("{0} jogos sem capa; {1} com sugestao." -f $total,$withSuggestion)
Write-Host $mdPath;Write-Host $jsonPath
