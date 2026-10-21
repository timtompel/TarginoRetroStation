# Local-first metadata. No credentials ship with the launcher.
. (Join-Path $PSScriptRoot 'MediaTransport.ps1')
function NewHydraMetadataWebClient {
    if(-not ('TarginoTimedWebClient' -as [type])){
        Add-Type -TypeDefinition @'
public sealed class TarginoTimedWebClient : System.Net.WebClient {
    protected override System.Net.WebRequest GetWebRequest(System.Uri address) {
        var request = base.GetWebRequest(address);
        request.Timeout = 15000;
        var http = request as System.Net.HttpWebRequest;
        if (http != null) http.ReadWriteTimeout = 15000;
        return request;
    }
}
'@
    }
    return (New-Object TarginoTimedWebClient)
}
function HydraMetadataConfig([string]$addon){
    $config=@{Enabled=$false;Key=''};$path=Join-Path $addon 'Dados\fontes-dados.json'
    try{if([IO.File]::Exists($path)){
        $saved=[IO.File]::ReadAllText($path) | ConvertFrom-Json
        if($saved.Enabled -and $saved.ProtectedKey){
            Add-Type -AssemblyName System.Security
            $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($saved.ProtectedKey),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
            $config.Key=[Text.Encoding]::UTF8.GetString($bytes);$config.Enabled=$true
        }
    }}catch{ }
    return $config
}
function ShowHydraMetadataSettings {
    param($Owner)
    if(-not $Owner){$Owner=$form}
    $settings=HydraMetadataConfig $Arq
    $win=New-Object Windows.Forms.Form -Property @{Text='Fontes de dados';Size='580,355';StartPosition='CenterParent';FormBorderStyle='FixedDialog';MaximizeBox=$false;MinimizeBox=$false}
    $info=New-Object Windows.Forms.Label -Property @{Text='Libretro e cache local: sempre ativos. O TheGamesDB e opcional e complementa os detalhes ausentes. Dados salvos nao sao buscados novamente.';Location='20,18';Size='530,66'}
    $enabled=New-Object Windows.Forms.CheckBox -Property @{Text='Usar TheGamesDB para complementar os detalhes';Checked=$settings.Enabled;Location='20,94';Size='530,30'}
    $label=New-Object Windows.Forms.Label -Property @{Text='Chave publica da API (salva somente neste usuario do Windows):';Location='20,137';Size='530,24'}
    $keyBox=New-Object Windows.Forms.TextBox -Property @{Text=$settings.Key;UseSystemPasswordChar=$true;Location='20,166';Size='520,25'}
    $note=New-Object Windows.Forms.Label -Property @{Text='Nao informe a senha da conta. Depois de ativar, use Atualizar dados nos detalhes de um jogo ja consultado.';Location='20,205';Size='530,44'}
    $save=New-Object Windows.Forms.Button -Property @{Text='Salvar';Location='330,267';Size='100,32'}
    $cancel=New-Object Windows.Forms.Button -Property @{Text='Cancelar';Location='440,267';Size='100,32';DialogResult='Cancel'}
    $win.Controls.AddRange(@($info,$enabled,$label,$keyBox,$note,$save,$cancel));$win.AcceptButton=$save;$win.CancelButton=$cancel
    $save.Add_Click({
        if($enabled.Checked -and $keyBox.Text.Trim() -notmatch '^[a-fA-F0-9]{32,128}$'){[void][Windows.Forms.MessageBox]::Show($win,'Informe uma chave publica valida.');return}
        try{
            Add-Type -AssemblyName System.Security
            $protected=''
            if($keyBox.Text.Trim()){$protected=[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($keyBox.Text.Trim()),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))}
            if(WriteJson (Join-Path $DataDir 'fontes-dados.json') @{Enabled=$enabled.Checked;ProtectedKey=$protected} 3){$win.DialogResult='OK';$win.Close()}
        }catch{[void][Windows.Forms.MessageBox]::Show($win,'Nao foi possivel salvar neste usuario do Windows.')}
    }.GetNewClosure())
    try{[void]$win.ShowDialog($Owner)}finally{$keyBox.Clear();$win.Dispose();if($Owner -eq $form){[void]$grid.Focus()}else{[void]$Owner.Activate()}}
}
function HydraMetadataNormalize([string]$title){
    $title=$title -replace '\([^)]*\)|\[[^]]*\]',' '
    ($title.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLowerInvariant() -replace '[^a-z0-9]',''
}
function HydraMetadataJson([string]$route,[hashtable]$parameters,[string]$destination,[string]$apiKey){
    $query=@('apikey='+[Uri]::EscapeDataString($apiKey))
    foreach($name in $parameters.Keys){$query+=([Uri]::EscapeDataString($name)+'='+[Uri]::EscapeDataString([string]$parameters[$name]))}
    # Fetch-Details reuses the local JSON. Never store the authenticated URL.
    Fetch-Details ('https://api.thegamesdb.net/'+$route+'?'+($query -join '&')) $destination
    $json=[IO.File]::ReadAllText($destination) | ConvertFrom-Json
    if($json.code -and $json.code -ne 200){throw 'TheGamesDB indisponivel ou cota esgotada.'}
    return $json
}
function HydraMetadataComplement($result,$request,[string]$addon){
    $config=HydraMetadataConfig $addon
    if(-not $config.Enabled -or -not $config.Key){return}
    if($result.Fields.Count -ge 5 -and $result.Snapshot -and $result.Overview){return}
    $names=@{'ps2'='Sony Playstation 2';'psx'='Sony Playstation';'snes'='Super Nintendo (SNES)';'nes'='Nintendo Entertainment System (NES)';'n64'='Nintendo 64';'gba'='Nintendo Game Boy Advance';'gameboy'='Nintendo Game Boy';'gameboycolor'='Nintendo Game Boy Color';'gamegear'='Sega Game Gear';'sms'='Sega Master System';'genesis'='Sega Genesis';'dreamcast'='Sega Dreamcast';'saturn'='Sega Saturn';'gamecube'='Nintendo GameCube';'neogeo'='Neo Geo';'pce'='TurboGrafx 16';'3do'='3DO';'megacd'='Sega CD';'atari2600'='Atari 2600'}
    if(-not $names.ContainsKey([string]$request.SystemId)){return}
    $folder=Join-Path $addon 'Dados\Detalhes\Fontes\TheGamesDB';[void][IO.Directory]::CreateDirectory($folder)
    $pause=Join-Path $folder 'pausa-ate.txt'
    if([IO.File]::Exists($pause)){
        $until=[datetimeoffset]::MinValue
        if([datetimeoffset]::TryParse([IO.File]::ReadAllText($pause),[ref]$until) -and $until.UtcDateTime -gt [datetime]::UtcNow){$result.Errors+='TheGamesDB em espera apos falha de rede ou limite de consultas.';return}
    }
    try{
        $platforms=HydraMetadataJson 'v1/Platforms/ByPlatformName' @{name=$names[$request.SystemId]} (Join-Path $folder ($request.SystemId+'-platform.json')) $config.Key
        $platform=@($platforms.data.platforms | Where-Object {(HydraMetadataNormalize $_.name) -eq (HydraMetadataNormalize $names[$request.SystemId])})
        if($platform.Count -ne 1){return}
        $platformId=$platform[0].id
        $games=HydraMetadataJson 'v1.1/Games/ByGameName' @{name=$request.Name;'filter[platform]'=[string]$platformId;fields='overview,players,genres,publishers,platform'} (Join-Path $folder ($request.Key+'-games.json')) $config.Key
        $desired=HydraMetadataNormalize $request.Name
        $candidates=@($games.data.games | Where-Object {[string]$_.platform -eq [string]$platformId -and (HydraMetadataNormalize $_.game_title) -eq $desired})
        if(-not $candidates.Count){return}
        # Prefer a complete duplicate record, never a different game or platform.
        $game=$candidates | Sort-Object @{Expression={([string]$_.overview).Length};Descending=$true},id | Select-Object -First 1
        $result.TheGamesDBId=$game.id
        if(-not $result.Overview -and $game.overview){$result.Overview=[string]$game.overview}
        if(-not $result.Fields['releaseyear'] -and $game.release_date){$result.Fields['releaseyear']=([string]$game.release_date).Substring(0,4)}
        if(-not $result.Fields['maxusers'] -and $game.players){$result.Fields['maxusers']=[string]$game.players}
        $result.Sources+=@{Kind='TheGamesDB';Url=('https://thegamesdb.net/game.php?id='+$game.id)}
        if(-not $result.Snapshot){
            $images=HydraMetadataJson 'v1/Games/Images' @{games_id=[string]$game.id;'filter[type]'='screenshot'} (Join-Path $folder ($game.id.ToString()+'-images.json')) $config.Key
            $property=$images.data.images.PSObject.Properties[[string]$game.id]
            $image=@($property.Value | Where-Object {$_.type -eq 'screenshot'} | Select-Object -First 1)
            if($image.Count -and $image[0].filename){
                $url=[string]$images.data.base_url.original+[string]$image[0].filename;$uri=$null
                if([Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -eq 'https' -and ($uri.Host -eq 'thegamesdb.net' -or $uri.Host.EndsWith('.thegamesdb.net'))){
                    $snap=Join-Path $addon ('Midia\Capturas\'+$request.Key+'-tgdb.png')
                    Fetch-Details $url $snap
                    Add-Type -AssemblyName System.Drawing
                    $check=[Drawing.Image]::FromFile($snap);$check.Dispose()
                    $result.Snapshot='Midia\Capturas\'+$request.Key+'-tgdb.png';$result.SnapshotSource=$url
                }
            }
        }
    }catch{
        # Raw exceptions can contain a URL with the key; do not persist them.
        $result.Errors+='TheGamesDB indisponivel; dados locais e Libretro preservados. Nova tentativa online em 30 minutos.'
        [IO.File]::WriteAllText($pause,[datetime]::UtcNow.AddMinutes(30).ToString('o'))
    }
}
