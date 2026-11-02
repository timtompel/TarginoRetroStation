# Only opens official links on an explicit click; never downloads/runs Hydra.
function New-HydraInstallHelpDialog([string]$root){
    $dialog=New-Object Windows.Forms.Form -Property @{Text='Hydra nao encontrado';ClientSize='680,360';StartPosition='CenterScreen';FormBorderStyle='FixedDialog';MaximizeBox=$false;MinimizeBox=$false;Font=(New-Object Drawing.Font('Segoe UI',10))}
    $message=New-Object Windows.Forms.Label -Property @{Text="O TarginoRetroStation e um complemento do Hydra.`r`nNao encontramos hydra.exe na pasta raiz:";Left=20;Top=18;Width=640;Height=48}
    $path=New-Object Windows.Forms.TextBox -Property @{Text=$root;ReadOnly=$true;Left=20;Top=74;Width=640}
    $dialog.Controls.AddRange(@($message,$path))
    foreach($item in @(@('https://hydrafrontend.com/',118),@('https://hydrafrontend.com/hydra.exe',152))){
        $link=New-Object Windows.Forms.LinkLabel -Property @{Text=$item[0];Tag=$item[0];Left=20;Top=[int]$item[1];Width=640;Height=24}
        $link.Add_LinkClicked({param($sender,$eventArgs)
            try{[void][Diagnostics.Process]::Start((New-Object Diagnostics.ProcessStartInfo -Property @{FileName=[string]$sender.Tag;UseShellExecute=$true}))}
            catch{[void][Windows.Forms.MessageBox]::Show(('Abra este endereco no navegador: '+$sender.Tag),'Site oficial do Hydra')}
        })
        $dialog.Controls.Add($link)
    }
    $hint=New-Object Windows.Forms.Label -Property @{Text="Baixe e execute o Hydra nessa pasta para concluir a instalacao inicial.`r`nDepois clique em Verificar novamente. ROMs e BIOS sao por sua conta.`r`nO launcher nao baixa nem executa o Hydra automaticamente.";Left=20;Top=195;Width=640;Height=70}
    $status=New-Object Windows.Forms.Label -Property @{Left=20;Top=267;Width=640;Height=24}
    $retry=New-Object Windows.Forms.Button -Property @{Text='Verificar novamente';Left=300;Top=310;Width=195;Height=32}
    $close=New-Object Windows.Forms.Button -Property @{Text='Fechar';Left=505;Top=310;Width=155;Height=32;DialogResult='Cancel'}
    $dialog.Controls.AddRange(@($hint,$status,$retry,$close));$dialog.CancelButton=$close
    $dialog.Tag=@{Root=$root;Status=$status;Retry=$retry}
    $retry.Add_Click({param($sender,$eventArgs)
        $win=$sender.FindForm()
        if([IO.File]::Exists((Join-Path $win.Tag.Root 'hydra.exe'))){$win.DialogResult='OK';$win.Close()}
        else{$win.Tag.Status.Text='hydra.exe ainda nao foi encontrado na pasta indicada.'}
    })
    return $dialog
}
function Show-HydraInstallHelp([string]$root){
    $dialog=New-HydraInstallHelpDialog $root
    try{return ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK)}finally{$dialog.Dispose()}
}
