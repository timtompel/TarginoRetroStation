function Get-TarginoFileSHA256([string]$Path) {
    $stream=$null;$algorithm=$null
    try{
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $algorithm=[Security.Cryptography.SHA256]::Create()
        return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','')
    }finally{if($algorithm){$algorithm.Dispose()};if($stream){$stream.Dispose()}}
}
