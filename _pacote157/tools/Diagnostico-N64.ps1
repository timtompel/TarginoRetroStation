<#
 Coleta, SEM alterar nada, as informacoes necessarias para criar a escolha de renderizador do N64:
   - manifesto do N64 dentro do hydra.exe
   - placa de video e versao do driver
   - se o Windows tem a biblioteca do Vulkan
 Gera o arquivo n64-diagnostico.txt na Area de Trabalho. Envie esse arquivo.

 Uso (clique direito > "Executar com o PowerShell"), ou:
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File Diagnostico-N64.ps1 -Root "D:\Games\hydra"
#>
param([string]$Root='D:\Games\hydra')
$ErrorActionPreference='Stop'
$exe=Join-Path $Root 'hydra.exe'
if(-not (Test-Path -LiteralPath $exe)){throw "hydra.exe nao encontrado em $Root. Use -Root com a pasta onde ele esta."}
$out=Join-Path ([Environment]::GetFolderPath('Desktop')) 'n64-diagnostico.txt'
$txt=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($exe))
$manifest=@([regex]::Matches($txt,'(?s)\{\s*"manifest_version"[^\x00]+')|Where-Object {$_.Value -match '"id"\s*:\s*"n64"'}|ForEach-Object {$_.Value.Trim()})
$gpu=(Get-CimInstance Win32_VideoController|Select-Object Name,DriverVersion|Out-String).Trim()
$vk=Test-Path 'C:\Windows\System32\vulkan-1.dll'
$vkDrv=''
try{$vkDrv=(Get-ItemProperty 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers' -ErrorAction Stop|Get-Member -MemberType NoteProperty|Where-Object {$_.Name -notlike 'PS*'}|ForEach-Object {$_.Name}) -join "`r`n"}catch{$vkDrv='(nenhum driver Vulkan registrado)'}
$cores=''
try{$cores=(Get-ChildItem (Join-Path $Root 'cores') -Recurse -Filter '*mupen*' -ErrorAction SilentlyContinue|ForEach-Object {$_.FullName}) -join "`r`n"}catch{}
$lines=@(
 "== VULKAN ==","vulkan-1.dll no Windows: $vk","Drivers registrados:",$vkDrv,"",
 "== PLACA DE VIDEO ==",$gpu,"",
 "== ARQUIVOS DO CORE N64 ==",$cores,"",
 "== MANIFESTO N64 ($($manifest.Count) encontrado(s)) ==")+$manifest
[IO.File]::WriteAllText($out,($lines -join "`r`n"),(New-Object Text.UTF8Encoding($true)))
Write-Host "Pronto: $out"
