function Receive-HydraMedia([string]$Url,[string]$Destination){
    $uri=$null
    if(-not [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $Url.IndexOfAny([char[]]@('"',"`r","`n")) -ge 0){throw 'Endereco de midia invalido.'}
    if([IO.File]::Exists($Destination)){return}
    $temporary=$Destination+'.'+[guid]::NewGuid().ToString('N')+'.download'
    $errors=New-Object Collections.Generic.List[string]
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    try{
        foreach($transport in @('WebClient','WinHTTP','Curl')){
            try{
                switch($transport){
                    'WebClient'{
                        $web=NewHydraMetadataWebClient
                        try{$web.Headers['User-Agent']='TarginoRetroStation-Media';$web.DownloadFile($Url,$temporary)}finally{$web.Dispose()}
                    }
                    'WinHTTP'{
                        $http=New-Object -ComObject WinHttp.WinHttpRequest.5.1
                        try{
                            $http.SetTimeouts(5000,10000,15000,15000);$http.Option(9)=2048
                            $http.Open('GET',$Url,$false);$http.SetRequestHeader('User-Agent','TarginoRetroStation-Media');$http.Send()
                            if($http.Status -ne 200){throw ('HTTP '+$http.Status)}
                            $body=[byte[]]$http.ResponseBody
                            if($body.Length -gt 16MB){throw 'Midia maior que 16 MiB.'}
                            [IO.File]::WriteAllBytes($temporary,$body)
                        }finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($http)}
                    }
                    'Curl'{
                        $curl=Join-Path $env:SystemRoot 'System32\curl.exe'
                        if(-not [IO.File]::Exists($curl)){throw 'curl do Windows indisponivel.'}
                        $pi=New-Object Diagnostics.ProcessStartInfo -Property @{FileName=$curl;UseShellExecute=$false;CreateNoWindow=$true;RedirectStandardError=$true}
                        $pi.Arguments='--fail --location --proto =https --proto-redir =https --tlsv1.2 --connect-timeout 10 --max-time 25 --max-filesize 16777216 --silent --show-error --output "'+$temporary+'" "'+$Url+'"'
                        $process=[Diagnostics.Process]::Start($pi)
                        try{$message=$process.StandardError.ReadToEnd();$process.WaitForExit();if($process.ExitCode -ne 0){throw ('curl '+$process.ExitCode+': '+$message.Trim())}}finally{$process.Dispose()}
                    }
                }
                $size=(Get-Item -LiteralPath $temporary).Length
                if($size -lt 1 -or $size -gt 16MB){throw 'Tamanho de midia invalido.'}
                [IO.File]::Move($temporary,$Destination);return
            }catch{
                $errors.Add($transport+': '+$_.Exception.Message)
                if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}
                if($_.Exception.Message -match '\b(?:404|410)\b'){break}
            }
        }
        throw ('Falha ao baixar midia. '+($errors -join ' | '))
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
