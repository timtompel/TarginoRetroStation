param([string]$FrontendDir=$PSScriptRoot)
$ErrorActionPreference='Stop'
try {
    if($PSVersionTable.PSVersion.Major -lt 5){throw 'E necessario Windows PowerShell 5.1 ou superior.'}
    if(-not [Environment]::Is64BitProcess){throw 'Use o Windows PowerShell de 64 bits.'}
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing
    $provider=New-Object Microsoft.CSharp.CSharpCodeProvider
    $provider.Dispose()
    foreach($name in @('Dados','Cache','Logs','Midia')){[void][IO.Directory]::CreateDirectory((Join-Path $FrontendDir $name))}
    Write-Output 'OK: PowerShell, .NET Framework, Windows Forms, System.Drawing e compilador C# disponiveis.'
    exit 0
}catch{Write-Output $_.Exception.Message;exit 1}
