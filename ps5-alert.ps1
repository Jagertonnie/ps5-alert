<#
PS5 Pro stock alert

  ps5-alert.ps1            blijft draaien en controleert de winkels (laptop)
  ps5-alert.ps1 -Once      controleert alle winkels een keer en stopt (cloud)
  ps5-alert.ps1 -Test      stuurt een testalarm naar je telefoon
  ps5-alert.ps1 -Status    laat zien of hij draait en wat de laatste uitkomsten zijn

Instellingen staan in config.json, de winkels in winkels.json.
Let op: dit bestand bewust alleen ASCII (Windows PowerShell 5.1 leest .ps1 zonder BOM als ANSI).
#>
param(
    [switch]$Once,
    [switch]$Test,
    [switch]$Status,
    [string]$StateDir,
    [string]$WinkelsPad
)

$ErrorActionPreference = 'Stop'
$map = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $map 'StockLib.ps1')

$opWindows = ($env:OS -eq 'Windows_NT')
if (-not $StateDir) {
    if ($opWindows) { $StateDir = Join-Path $env:LOCALAPPDATA 'ps5-alert' } else { $StateDir = Join-Path $map 'state' }
}
if (-not (Test-Path -LiteralPath $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
if (-not $WinkelsPad) { $WinkelsPad = Join-Path $map 'winkels.json' }

$staatPad = Join-Path $StateDir 'staat.json'
$logPad = Join-Path $StateDir 'ps5-alert.log'
$configPad = Join-Path $map 'config.json'
$mutexNaam = 'Local\ps5-alert-stock'
$curl = if ($opWindows) { Join-Path $env:SystemRoot 'System32\curl.exe' } else { 'curl' }
$userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Write-Log([string]$Tekst) {
    $regel = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Tekst"
    Write-Host $regel
    try {
        if ((Test-Path -LiteralPath $logPad) -and (Get-Item -LiteralPath $logPad).Length -gt 1MB) {
            Move-Item -LiteralPath $logPad -Destination "$logPad.oud" -Force
        }
        Add-Content -LiteralPath $logPad -Value $regel -Encoding UTF8
    }
    catch { }
}

$script:instellingen = $null
function Update-Instellingen {
    $omgeving = @{ PUSHOVER_USER_KEY = $env:PUSHOVER_USER_KEY; PUSHOVER_APP_TOKEN = $env:PUSHOVER_APP_TOKEN }
    try { $script:instellingen = Get-Instellingen -ConfigPad $configPad -Omgeving $omgeving }
    catch {
        # Tijdens het bewerken kan config.json even ongeldig zijn: dan de vorige instellingen aanhouden.
        if (-not $script:instellingen) { throw "config.json is niet leesbaar: $($_.Exception.Message)" }
    }
}

# Haalt een pagina op met het curl dat standaard op Windows en Linux staat.
function Get-Pagina([string]$Url) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        $code = & $curl -s -L --compressed --max-time 30 -A $userAgent -H 'Accept-Language: nl-NL,nl;q=0.9,en;q=0.8' -o $tmp -w '%{http_code}' $Url
        [pscustomobject]@{ Code = [int]("$code".Trim()); Html = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8) }
    }
    finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}

# Verstuurt een bericht via Pushover. Geeft $true terug als het gelukt is.
function Send-Melding($Bericht) {
    if (-not $script:instellingen.KanMelden) {
        Write-Log "NIET VERSTUURD (Pushover-sleutels ontbreken in config.json): $($Bericht.title)"
        return $false
    }
    $velden = @{ token = $script:instellingen.PushoverAppToken; user = $script:instellingen.PushoverUserKey }
    foreach ($k in $Bericht.Keys) { $velden[$k] = $Bericht[$k] }
    try {
        Invoke-RestMethod -Method Post -Uri 'https://api.pushover.net/1/messages.json' -Body $velden -TimeoutSec 30 | Out-Null
        Write-Log "Melding verstuurd: $($Bericht.title)"
        return $true
    }
    catch {
        Write-Log "Melding MISLUKT: $($Bericht.title) - $($_.Exception.Message)"
        return $false
    }
}

$winkels = @(([IO.File]::ReadAllText($WinkelsPad, [Text.Encoding]::UTF8) | ConvertFrom-Json).winkels)
# Op GitHub alleen de winkels die de servers daar toelaten; Amazon en MediaMarkt volgt alleen de laptop.
$winkels = @(Select-Winkels -Winkels $winkels -InCloud ($env:GITHUB_ACTIONS -eq 'true'))
Update-Instellingen

if ($Test) {
    if (-not $script:instellingen.KanMelden) {
        Write-Host 'Vul eerst pushoverUserKey en pushoverAppToken in config.json in.'
        exit 1
    }
    if (Send-Melding (New-PushoverBericht -Soort 'test')) {
        Write-Host 'Testalarm verstuurd. Je telefoon gaat nu af; open de melding in de Pushover-app om hem te stoppen.'
        exit 0
    }
    exit 1
}

if ($Status) {
    $draait = $false
    if ($opWindows) {
        $bestaand = $null
        $draait = [Threading.Mutex]::TryOpenExisting($mutexNaam, [ref]$bestaand)
    }
    Write-Host ('Script draait:            ' + $(if ($draait) { 'ja' } else { 'NEE (dubbelklik installeer.cmd)' }))
    Write-Host ('Melding naar telefoon:    ' + $(if ($script:instellingen.KanMelden) { 'ingesteld' } else { 'NOG NIET ingesteld (vul config.json in)' }))
    Write-Host ('Maximumprijs:             ' + (Format-Prijs $script:instellingen.MaxPrijs))
    Write-Host ''
    Get-StatusRegels -Winkels $winkels -Staat (Read-Staat -Pad $staatPad) -Nu (Get-Date) | ForEach-Object { Write-Host "  $_" }
    Write-Host ''
    Write-Host "Logboek: $logPad"
    exit 0
}

if (-not $Once -and $opWindows) {
    # Nooit twee keer tegelijk draaien op dezelfde laptop.
    $mutex = New-Object Threading.Mutex($false, $mutexNaam)
    $vrij = $false
    try { $vrij = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $vrij = $true }
    if (-not $vrij) {
        Write-Host 'De PS5-alert draait al.'
        exit 0
    }
}

$staat = Read-Staat -Pad $staatPad
$laatsteRegel = @{}
$ophalen = { param($url) Get-Pagina $url }
$melden = { param($soort, $bericht) Send-Melding $bericht }

$meldingTekst = if ($script:instellingen.KanMelden) { 'ingesteld' } else { 'NOG NIET ingesteld (vul config.json in)' }
Write-Log "Gestart: $($winkels.Count) winkelpagina's, maximum $(Format-Prijs $script:instellingen.MaxPrijs), melding naar telefoon $meldingTekst"

# Op de laptop begint de storingstijd opnieuw na een pauze van een half uur (dichtgeklapt).
# In de cloud niet: daar zit soms een uur tussen twee controles.
$pauzeNaMinuten = if ($Once) { 0 } else { 30 }
$uitkomsten = @()

while ($true) {
    try { Update-Instellingen } catch { Write-Log $_.Exception.Message }

    foreach ($winkel in $winkels) {
        $vorige = $staat[$winkel.id]
        if (-not $Once -and -not (Test-AanDeBeurt (Get-Eigenschap $vorige 'LaatsteCheck') $winkel.elkeMinuten (Get-Date))) { continue }
        try {
            $r = Invoke-WinkelControle -Winkel $winkel -Staat $vorige -Ophalen $ophalen -Melden $melden -MaxPrijs $script:instellingen.MaxPrijs -Nu (Get-Date) -StoringNaMinuten $script:instellingen.StoringNaMinuten -PauzeNaMinuten $pauzeNaMinuten
            $staat[$winkel.id] = $r.Staat
            Save-Staat -Pad $staatPad -Staat $staat
            if ($Once) { $uitkomsten += [pscustomobject]@{ Winkel = $winkel; Resultaat = $r.Resultaat } }

            # Alleen loggen als er iets verandert, anders loopt het logboek vol.
            $regel = "$($winkel.naam): $($r.Resultaat.Status) - $($r.Resultaat.Reden)"
            if ($null -ne $r.Resultaat.Prijs) { $regel += " - $(Format-Prijs $r.Resultaat.Prijs)" }
            if ($laatsteRegel[$winkel.id] -ne $regel) {
                Write-Log $regel
                $laatsteRegel[$winkel.id] = $regel
            }
        }
        catch { Write-Log "Onverwachte fout bij $($winkel.naam): $($_.Exception.Message)" }
    }

    if ($Once) {
        $samenvatting = Get-RondeSamenvatting -Uitkomsten $uitkomsten
        Write-Log "Ronde klaar. $samenvatting"
        # Op GitHub: de samenvatting als notitie bij de run zetten, zodat je hem ziet zonder het logboek te openen.
        if ($env:GITHUB_ACTIONS -eq 'true') {
            Write-Host ('::notice title=PS5-alert::' + $samenvatting.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A'))
        }
        break
    }
    Start-Sleep -Seconds 15
}
