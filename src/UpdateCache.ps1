function Clear-RetroStationUpdateCache([string]$Folder){
    if(-not [IO.Directory]::Exists($Folder)){return}
    $base=Get-Item -LiteralPath $Folder
    if($base.Attributes -band [IO.FileAttributes]::ReparsePoint){return}
    $jobs=@(Get-ChildItem -LiteralPath $Folder -Directory | Where-Object {$_.Name -match '^[a-f0-9]{32}$'} | Sort-Object CreationTimeUtc -Descending)
    foreach($job in @($jobs | Select-Object -Skip 3)){
        if($job.CreationTimeUtc -gt [datetime]::UtcNow.AddDays(-30) -or ($job.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
        $items=@(Get-ChildItem -LiteralPath $job.FullName -Force)
        if(@($items|Where-Object {$_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $_.Name -notmatch '^(release\.json|update\.json|error\.txt|ready-to-install|completed|active\.json|cancel|status\.json(?:\.bak|\.tmp)?|BootstrapWorker\.ps1|FrontendUpdate\.ps1|Hashing\.ps1|UpdateCache\.ps1|UpdatePublicKey\.xml|TarginoRetroStation-\d+\.\d+\.\d+-Setup\.exe)$'}).Count){continue}
        # Unknown/legacy jobs are retained unless a completion marker exists.
        if(-not [IO.File]::Exists((Join-Path $job.FullName 'completed'))){continue}
        $running=$false
        foreach($name in @('active.json','ready-to-install')){
            $path=Join-Path $job.FullName $name
            if([IO.File]::Exists($path)){
                try{$state=[IO.File]::ReadAllText($path)|ConvertFrom-Json;foreach($idValue in @($state.WorkerPid,$state.InstallerPid)){if($idValue -and (Get-Process -Id ([int]$idValue) -ErrorAction SilentlyContinue)){$running=$true}}}catch{$running=$true}
            }
        }
        if($running){continue}
        try{foreach($item in $items){[IO.File]::Delete($item.FullName)};[IO.Directory]::Delete($job.FullName,$false)}catch{Write-Verbose 'Cache em uso foi preservado.'}
    }
}
