# Zet de PS5-alert bij "Opstarten" van Windows, zodat hij vanzelf start als je inlogt,
# en start hem nu meteen. Opnieuw uitvoeren mag altijd (bijvoorbeeld nadat je de map hebt verplaatst).
# Ongedaan maken: verwijder.cmd
$ErrorActionPreference = 'Stop'
$map = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $map 'ps5-alert.ps1'
$config = Join-Path $map 'config.json'

if (-not (Test-Path -LiteralPath $config)) {
    Copy-Item -LiteralPath (Join-Path $map 'config.voorbeeld.json') -Destination $config
}

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argumenten = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$snelkoppeling = Join-Path ([Environment]::GetFolderPath('Startup')) 'PS5 Pro stock alert.lnk'

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($snelkoppeling)
$lnk.TargetPath = $powershell
$lnk.Arguments = $argumenten
$lnk.WorkingDirectory = $map
$lnk.WindowStyle = 7
$lnk.Description = 'Controleert of de PS5 Pro op voorraad is'
$lnk.Save()

Start-Process -FilePath $powershell -ArgumentList $argumenten -WindowStyle Hidden

Write-Host 'Klaar. De PS5-alert draait nu en start voortaan vanzelf zodra je inlogt.'
Write-Host "Snelkoppeling: $snelkoppeling"
Write-Host ''
Write-Host "Nog niet gedaan? Vul je twee Pushover-sleutels in dit bestand in: $config"
Write-Host 'Dubbelklik daarna op test-melding.cmd om te horen of het alarm aankomt.'
