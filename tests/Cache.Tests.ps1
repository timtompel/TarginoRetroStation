$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
. (Join-Path $project 'src\UpdateCache.ps1')
$root=Join-Path $project ('build\cache-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
function Make-Job([int]$age,[string]$extra=''){
    $dir=Join-Path $root ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'completed'),'done')
    [IO.File]::WriteAllText((Join-Path $dir 'release.json'),'{}')
    if($extra){[IO.File]::WriteAllText((Join-Path $dir $extra),'preserve')}
    [IO.Directory]::SetCreationTimeUtc($dir,[datetime]::UtcNow.AddDays(-$age));return $dir
}
$recent=@(Make-Job 1;Make-Job 2;Make-Job 3)
$old=Make-Job 40;$unknown=Make-Job 41 'pessoal.txt';$active=Make-Job 42
[IO.File]::WriteAllText((Join-Path $active 'active.json'),('{"WorkerPid":'+$PID+'}'))
$incomplete=Make-Job 43;[IO.File]::Delete((Join-Path $incomplete 'completed'))
Clear-RetroStationUpdateCache $root
if(Test-Path -LiteralPath $old){throw 'Cache concluido antigo nao foi retirado'}
foreach($dir in @($recent)+@($unknown,$active,$incomplete)){if(-not (Test-Path -LiteralPath $dir)){throw 'Cache protegido removido'}}
'CACHE_RETAINS_RECENT_ACTIVE_UNKNOWN_AND_INCOMPLETE_JOBS_ONLY_OLD_COMPLETED_REMOVED_OK'
