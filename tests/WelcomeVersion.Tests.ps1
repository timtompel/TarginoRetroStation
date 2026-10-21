$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$project=Split-Path $PSScriptRoot
$Arq=Join-Path $project 'src'
foreach($version in @('1.5.4','9.8.7')){
    $AppVer=$version
    . (Join-Path $Arq 'TarginoWelcome.ps1')
    $dialog=New-TarginoWelcomeDialog $null
    try{
        if($script:TarginoWelcomeVersion -cne $version -or $dialog.Text -notlike ('*'+$version+'*')){throw 'Welcome version differs from launcher'}
        $queue=New-Object 'System.Collections.Generic.Queue[System.Windows.Forms.Control]'
        $queue.Enqueue($dialog);$text=''
        while($queue.Count){$control=$queue.Dequeue();$text+=$control.Text+"`n";foreach($child in $control.Controls){$queue.Enqueue($child)}}
        if($text -notlike ('*'+$version+' EST*') -or $text -notlike ('*RetroStation '+$version+'!*')){throw 'Header or welcome body not updated'}
        if($text -match '\{Version\}|1\.5\.3|1\.5\.2'){throw 'Stale presentation text'}
        if($text -notmatch 'ARTE DO SISTEMA'){throw 'Current release notes absent'}
    }finally{$dialog.Dispose()}
}
'WELCOME_VERSION_FROM_LAUNCHER_TITLE_HEADER_BODY_AND_RELEASE_NOTES_OK'
