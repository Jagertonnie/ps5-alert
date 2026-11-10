# Stopt de PS5-alert op deze laptop en haalt hem weg bij "Opstarten".
# De map zelf en je instellingen blijven staan.
$ErrorActionPreference = 'Stop'

$snelkoppeling = Join-Path ([Environment]::GetFolderPath('Startup')) 'PS5 Pro stock alert.lnk'
if (Test-Path -LiteralPath $snelkoppeling) {
    Remove-Item -LiteralPath $snelkoppeling
    Write-Host 'Weggehaald bij Opstarten.'
}

$processen = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*ps5-alert.ps1*' }
foreach ($p in $processen) {
    Stop-Process -Id $p.ProcessId -Force
    Write-Host "Gestopt (proces $($p.ProcessId))."
}

Write-Host 'Klaar. De PS5-alert draait niet meer op deze laptop.'
