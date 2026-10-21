$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
Add-Type -Path (Join-Path $project 'installer\AtomicInstall.cs')
Add-Type -TypeDefinition @'
using System;using System.IO;
public class BrokenInput : MemoryStream {
    public BrokenInput():base(new byte[]{1,2,3,4,5,6,7,8}){}
    public override int Read(byte[] buffer,int offset,int count){if(Position>0)throw new IOException("Simulated disk/source failure");return base.Read(buffer,offset,Math.Min(4,count));}
}
'@
$dir=Join-Path $project ('build\atomic-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$file=Join-Path $dir 'original.txt';[IO.File]::WriteAllText($file,'PRESERVAR')
$hash=[AtomicInstall]::Hash($file)
$input=New-Object BrokenInput
try{$failed=$false;try{[AtomicInstall]::Write($input,$file,('a'*64))}catch{$failed=$true};if(-not $failed){throw 'Falha simulada nao ocorreu'}}finally{$input.Dispose()}
if([AtomicInstall]::Hash($file) -ne $hash){throw 'Falha de escrita danificou original'}
$input=New-Object IO.MemoryStream(,[byte[]]@(1,2,3,4))
try{$failed=$false;try{[AtomicInstall]::Write($input,$file,('a'*64))}catch{$failed=$true};if(-not $failed){throw 'Hash incorreto aceito'}}finally{$input.Dispose()}
if([AtomicInstall]::Hash($file) -ne $hash){throw 'Hash incorreto danificou original'}
$input=[IO.File]::OpenRead($file);$copy=Join-Path $dir 'copy.txt'
try{[AtomicInstall]::Write($input,$copy,$hash)}finally{$input.Dispose()}
if([AtomicInstall]::Hash($copy) -ne $hash){throw 'Escrita valida falhou'}
$input=[IO.File]::OpenRead($copy)
try{[AtomicInstall]::Write($input,$file,$hash)}finally{$input.Dispose()}
if([AtomicInstall]::Hash($file) -ne $hash){throw 'Substituicao valida falhou'}
if(@(Get-ChildItem -LiteralPath $dir -Filter '*.installing').Count){throw 'Temporarios abandonados'}
$failed=$false;try{[AtomicInstall]::AssertLocalParents($dir,(Join-Path (Split-Path $dir) 'fora.txt'))}catch{$failed=$true};if(-not $failed){throw 'Path escape aceito'}
'PARTIAL_IO_AND_BAD_HASH_PRESERVE_ORIGINAL_VALID_COPY_NO_TEMP_AND_PATH_ESCAPE_OK'
