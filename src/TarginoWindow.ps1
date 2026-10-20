# Frontend window state is independent from Hydra's live profile.
function TarginoWindowSave($target){
    if(-not $target -or $target.IsDisposed){return}
    $bounds=if($S.Fullscreen){$script:WindowedBounds}elseif($target.WindowState -eq 'Normal'){$target.Bounds}else{$target.RestoreBounds}
    if(-not $bounds -or $bounds.Width -lt 300 -or $bounds.Height -lt 200){return}
    if(-not $S.Fullscreen){$script:WindowedBounds=$bounds;if($target.WindowState -ne 'Minimized'){$S.Maximized=($target.WindowState -eq 'Maximized')}}
    [void](WriteJson (Join-Path $DataDir 'launcher-janela.json') @{Width=$bounds.Width;Height=$bounds.Height;Fullscreen=[bool]$S.Fullscreen;Maximized=[bool]$S.Maximized} 3)
}
function TarginoWindowRestore($target){
    $state=ReadJson (Join-Path $DataDir 'launcher-janela.json') $false
    if(-not $state){return}
    $width=0;$height=0
    if(-not [int]::TryParse([string]$state.Width,[ref]$width) -or -not [int]::TryParse([string]$state.Height,[ref]$height) -or $width -lt 300 -or $height -lt 200){return}
    $area=[Windows.Forms.Screen]::FromControl($target).WorkingArea
    $scale=[Math]::Min(1,[Math]::Min($area.Width/[double]$width,$area.Height/[double]$height))
    $width=[Math]::Max($target.MinimumSize.Width,[int]($width*$scale));$height=[Math]::Max($target.MinimumSize.Height,[int]($height*$scale))
    $bounds=New-Object Drawing.Rectangle(($area.X+[int](($area.Width-$width)/2)),($area.Y+[int](($area.Height-$height)/2)),$width,$height)
    $script:WindowedBounds=$bounds;$target.StartPosition='Manual';$target.Bounds=$bounds
    if($state.PSObject.Properties['Fullscreen']){$S.Fullscreen=[bool]$state.Fullscreen}
    if($state.PSObject.Properties['Maximized']){$S.Maximized=[bool]$state.Maximized}
}
TarginoWindowRestore $form
$form.Add_ResizeEnd({param($sender,$eventArgs) TarginoWindowSave $sender})
$form.Add_FormClosing({param($sender,$eventArgs) TarginoWindowSave $sender})
