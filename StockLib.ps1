# StockLib.ps1 - de logica van de PS5 Pro stock alert.
# Wordt ingeladen door ps5-alert.ps1 en door tests\Run-Tests.ps1.
# Werkt in Windows PowerShell 5.1 (laptop) en PowerShell 7 (cloud).
# Let op: dit bestand bewust alleen ASCII (PowerShell 5.1 leest .ps1 zonder BOM als ANSI).

$script:StandaardNaamPatroon = '(?i)(playstation|ps)\W{0,3}5\W{0,3}pro'
$script:StandaardMinPrijs = 500
$script:TeKoopStatussen = @('InStock', 'LimitedAvailability', 'OnlineOnly', 'PreOrder', 'BackOrder')
$script:PauzeNaMinuten = 30

# ---------- kleine hulpjes ----------

function Get-Eigenschap($Object, [string]$Naam, $Standaard = $null) {
    if ($null -eq $Object) { return $Standaard }
    $p = $Object.PSObject.Properties[$Naam]
    if ($null -eq $p -or $null -eq $p.Value) { return $Standaard }
    return $p.Value
}

function ConvertTo-Prijs($Waarde) {
    if ($null -eq $Waarde) { return $null }
    if ($Waarde -is [string]) {
        $t = $Waarde -replace '[^0-9.,]', ''
        if ($t -match '^\d{1,3}(\.\d{3})+(,\d+)?$') { $t = $t.Replace('.', '').Replace(',', '.') }   # 1.299,00
        elseif ($t -match '^\d+,\d+$') { $t = $t.Replace(',', '.') }                                  # 949,99
        if ($t -notmatch '^\d+(\.\d+)?$') { return $null }
        return [decimal]::Parse($t, [Globalization.CultureInfo]::InvariantCulture)
    }
    try { return [decimal]$Waarde } catch { return $null }
}

function Format-Prijs($Prijs) {
    $nl = [Globalization.CultureInfo]::GetCultureInfo('nl-NL')
    ([string][char]0x20AC) + ([decimal]$Prijs).ToString('0.00', $nl)
}

function ConvertTo-Tijd($Waarde) {
    if ($Waarde -is [datetime]) { return $Waarde }
    [datetime]::Parse([string]$Waarde, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
}

function New-Status([string]$Status, $Prijs, [string]$Reden) {
    [pscustomobject]@{ Status = $Status; Prijs = $Prijs; Reden = $Reden }
}

# Geeft een reden terug als de prijs niet goed is, anders niets.
function Get-PrijsBezwaar($Prijs, $Winkel, [decimal]$MaxPrijs) {
    if ($null -eq $Prijs) { return 'prijs onbekend' }
    if ($Prijs -lt [decimal](Get-Eigenschap $Winkel 'minPrijs' $script:StandaardMinPrijs)) { return "prijs onrealistisch laag ($(Format-Prijs $Prijs))" }
    if ($Prijs -gt $MaxPrijs) { return "te duur ($(Format-Prijs $Prijs))" }
    return $null
}

# ---------- pagina's uitlezen ----------

function Test-IsProduct($Object) {
    $types = @(Get-Eigenschap $Object '@type')
    ($types -contains 'Product') -or ($types -contains 'ProductGroup')
}

# De hoofdproducten uit de JSON-LD blokken van een pagina.
# Varianten en verwante producten verderop in de pagina tellen bewust niet mee.
function Get-HoofdProducten([string]$Html) {
    $uit = @()
    $blokken = [regex]::Matches($Html, '(?is)<script[^>]*type\s*=\s*["'']application/ld\+json["''][^>]*>(.*?)</script>')
    foreach ($blok in $blokken) {
        $json = $null
        try { $json = $blok.Groups[1].Value | ConvertFrom-Json } catch { continue }
        $kandidaten = @()
        foreach ($k in @($json)) {
            $graph = Get-Eigenschap $k '@graph'
            if ($graph) { $kandidaten += @($graph) } else { $kandidaten += $k }
        }
        foreach ($k in $kandidaten) {
            foreach ($veld in @('object', 'mainEntity')) {   # MediaMarkt: BuyAction.object
                $binnen = Get-Eigenschap $k $veld
                if ($binnen -and (Test-IsProduct $binnen)) { $k = $binnen }
            }
            if ((Test-IsProduct $k) -and (Get-Eigenschap $k 'offers')) { $uit += $k }
        }
    }
    $uit
}

# Beoordeelt een aanbieding: te koop, nieuw, van de winkel zelf en binnen de prijsgrenzen?
function Get-AanbiedingBezwaar($Aanbieding, $Winkel, [decimal]$MaxPrijs) {
    $status = ([string](Get-Eigenschap $Aanbieding 'availability' '')) -replace '^.*/', ''
    if ($script:TeKoopStatussen -notcontains $status) { return "niet te koop ($status)" }

    $conditie = [string](Get-Eigenschap $Aanbieding 'itemCondition' '')
    if ($conditie -and $conditie -notmatch 'NewCondition') { return 'niet nieuw' }

    $verkoper = Get-Eigenschap $Aanbieding 'seller'
    $verkoperNaam = if ($verkoper -is [string]) { $verkoper } else { [string](Get-Eigenschap $verkoper 'name' '') }
    if ($verkoperNaam) {
        $eigen = Get-Eigenschap $Winkel 'verkoperPatroon'
        if (-not $eigen -or $verkoperNaam -notmatch $eigen) { return "externe verkoper ($verkoperNaam)" }
    }

    return (Get-PrijsBezwaar (ConvertTo-Prijs (Get-Eigenschap $Aanbieding 'price')) $Winkel $MaxPrijs)
}

function Get-JsonLdStatus([string]$Html, $Winkel, [decimal]$MaxPrijs) {
    $patroon = Get-Eigenschap $Winkel 'naamPatroon' $script:StandaardNaamPatroon
    $product = Get-HoofdProducten $Html | Where-Object { ([string](Get-Eigenschap $_ 'name' '')) -match $patroon } | Select-Object -First 1
    if (-not $product) { return (New-Status 'onleesbaar' $null 'PS5 Pro niet gevonden op de pagina') }

    $eersteBezwaar = $null
    $eerstePrijs = $null
    foreach ($aanbieding in @(Get-Eigenschap $product 'offers')) {
        $prijs = ConvertTo-Prijs (Get-Eigenschap $aanbieding 'price')
        $bezwaar = Get-AanbiedingBezwaar $aanbieding $Winkel $MaxPrijs
        if (-not $bezwaar) { return (New-Status 'hit' $prijs 'te koop') }
        if (-not $eersteBezwaar) { $eersteBezwaar = $bezwaar; $eerstePrijs = $prijs }
    }
    New-Status 'geen' $eerstePrijs $eersteBezwaar
}

function Get-AmazonStatus([string]$Html, $Winkel, [decimal]$MaxPrijs) {
    if ($Html -notmatch 'id="productTitle"') { return (New-Status 'onleesbaar' $null 'geen productpagina (captcha of blokkade)') }
    if ($Html -notmatch 'id="add-to-cart-button"') { return (New-Status 'geen' $null 'geen koopknop') }

    $veld = [regex]::Match($Html, '<input[^>]*id="merchantID"[^>]*>').Value
    $verkoper = [regex]::Match($veld, 'value="([^"]*)"').Groups[1].Value
    $prijs = ConvertTo-Prijs ([regex]::Match($Html, '"priceAmount":\s*([0-9.]+)').Groups[1].Value)
    if (@(Get-Eigenschap $Winkel 'verkoperIds') -notcontains $verkoper) { return (New-Status 'geen' $prijs "externe verkoper ($verkoper)") }

    $bezwaar = Get-PrijsBezwaar $prijs $Winkel $MaxPrijs
    if ($bezwaar) { return (New-Status 'geen' $prijs $bezwaar) }
    New-Status 'hit' $prijs 'te koop'
}

# Status van een winkelpagina: 'hit' (te koop binnen de grenzen), 'geen' of 'onleesbaar'.
function Get-WinkelStatus([string]$Html, $Winkel, [decimal]$MaxPrijs) {
    if ($Winkel.type -eq 'amazon') { return (Get-AmazonStatus $Html $Winkel $MaxPrijs) }
    Get-JsonLdStatus $Html $Winkel $MaxPrijs
}

# ---------- wanneer melden ----------

# Werkt de onthouden staat van een winkel bij en zegt welke meldingen eruit moeten:
# 'alarm' (nieuw op voorraad), 'storing' (al lang onleesbaar) of 'hersteld'.
function Update-WinkelStaat($Staat, $Resultaat, [datetime]$Nu, [int]$StoringNaMinuten = 60) {
    $nieuw = [pscustomobject]@{
        OpVoorraad    = [bool](Get-Eigenschap $Staat 'OpVoorraad' $false)
        MisluktSinds  = Get-Eigenschap $Staat 'MisluktSinds'
        StoringGemeld = [bool](Get-Eigenschap $Staat 'StoringGemeld' $false)
        LaatsteCheck  = $Nu.ToString('o')
        LaatsteStatus = $Resultaat.Status
        LaatstePrijs  = $Resultaat.Prijs
    }
    $meldingen = @()

    if ($Resultaat.Status -eq 'onleesbaar') {
        # OpVoorraad blijft staan: een korte leesfout mag geen tweede alarm opleveren.
        # Na een lange pauze (laptop uit of in slaap) begint de storingstijd opnieuw,
        # anders lijkt een nacht dichtgeklapt op een urenlange storing.
        $vorigeCheck = Get-Eigenschap $Staat 'LaatsteCheck'
        $langePauze = $vorigeCheck -and (($Nu - (ConvertTo-Tijd $vorigeCheck)).TotalMinutes -gt $script:PauzeNaMinuten)
        if (-not $nieuw.MisluktSinds -or $langePauze) { $nieuw.MisluktSinds = $Nu.ToString('o') }
        $duurt = ($Nu - (ConvertTo-Tijd $nieuw.MisluktSinds)).TotalMinutes
        if (-not $nieuw.StoringGemeld -and $duurt -ge $StoringNaMinuten) {
            $nieuw.StoringGemeld = $true
            $meldingen += 'storing'
        }
    }
    else {
        if ($nieuw.StoringGemeld) { $meldingen += 'hersteld' }
        $nieuw.MisluktSinds = $null
        $nieuw.StoringGemeld = $false
        $isHit = ($Resultaat.Status -eq 'hit')
        if ($isHit -and -not $nieuw.OpVoorraad) { $meldingen += 'alarm' }
        $nieuw.OpVoorraad = $isHit
    }

    [pscustomobject]@{ Staat = $nieuw; Meldingen = $meldingen }
}

function Test-AanDeBeurt($LaatsteCheck, [int]$ElkeMinuten, [datetime]$Nu) {
    if (-not $LaatsteCheck) { return $true }
    ($Nu - (ConvertTo-Tijd $LaatsteCheck)).TotalSeconds -ge ($ElkeMinuten * 60)
}

# Haalt een winkelpagina op (via -Ophalen), beoordeelt hem, werkt de staat bij en verstuurt meldingen.
# -Ophalen krijgt de url en geeft een object met Code (HTTP-status) en Html terug.
# -Melden krijgt de soort melding en het bericht, en geeft $true terug als het verstuurd is.
function Invoke-WinkelControle($Winkel, $Staat, [scriptblock]$Ophalen, [decimal]$MaxPrijs, [datetime]$Nu, [int]$StoringNaMinuten = 60, [scriptblock]$Melden = $null) {
    $resultaat = $null
    try {
        $pagina = & $Ophalen $Winkel.url
        if ($pagina.Code -ne 200 -or -not $pagina.Html) { $resultaat = New-Status 'onleesbaar' $null "HTTP $($pagina.Code)" }
        else { $resultaat = Get-WinkelStatus -Html $pagina.Html -Winkel $Winkel -MaxPrijs $MaxPrijs }
    }
    catch {
        $resultaat = New-Status 'onleesbaar' $null "fout: $($_.Exception.Message)"
    }
    $update = Update-WinkelStaat -Staat $Staat -Resultaat $resultaat -Nu $Nu -StoringNaMinuten $StoringNaMinuten
    if ($Melden) {
        foreach ($soort in $update.Meldingen) {
            $verstuurd = $false
            try { $verstuurd = [bool](& $Melden $soort (New-PushoverBericht -Soort $soort -Winkel $Winkel -Resultaat $resultaat)) } catch { $verstuurd = $false }
            # Een alarm dat niet aankwam mag niet verloren gaan: bij de volgende controle opnieuw proberen.
            if ($soort -eq 'alarm' -and -not $verstuurd) { $update.Staat.OpVoorraad = $false }
            # Een storing die niet gemeld kon worden (meestal: geen internet) hoeft later ook geen "werkt weer".
            if ($soort -eq 'storing' -and -not $verstuurd) { $update.Staat.StoringGemeld = $false }
        }
    }
    [pscustomobject]@{ Staat = $update.Staat; Meldingen = $update.Meldingen; Resultaat = $resultaat }
}

# Leesbare regel per winkel voor het statusoverzicht.
function Get-StatusRegels($Winkels, [hashtable]$Staat, [datetime]$Nu) {
    $woorden = @{ hit = 'OP VOORRAAD'; geen = 'niet te koop'; onleesbaar = 'niet uit te lezen' }
    foreach ($w in $Winkels) {
        $s = $Staat[$w.id]
        if (-not $s) { "$($w.naam): nog niet gecontroleerd"; continue }
        $regel = "$($w.naam): $($woorden[[string]$s.LaatsteStatus])"
        $prijs = Get-Eigenschap $s 'LaatstePrijs'
        if ($null -ne $prijs) { $regel += ", $(Format-Prijs $prijs)" }
        $minuten = [int][math]::Floor(($Nu - (ConvertTo-Tijd $s.LaatsteCheck)).TotalMinutes)
        "$regel ($minuten min geleden)"
    }
}

# ---------- melding ----------

# De velden voor een Pushover-bericht (zonder de sleutels).
function New-PushoverBericht([string]$Soort, $Winkel = $null, $Resultaat = $null) {
    $b = @{ priority = 0 }
    if ($Winkel) {
        $b.url = $Winkel.url
        $b.url_title = "Open $($Winkel.naam)"
    }
    switch ($Soort) {
        'alarm' {
            $prijs = Format-Prijs $Resultaat.Prijs
            $b.title = "PS5 Pro op voorraad: $($Winkel.naam) $prijs"
            $b.message = "Nu te koop bij $($Winkel.naam) voor $prijs. Tik op de link en bestel direct, het is vaak snel weer op."
            if (Get-Eigenschap $Winkel 'buitenland' $false) { $b.message += ' Controleer bij het afrekenen of bezorging naar Nederland kan.' }
        }
        'test' {
            $b.title = 'PS5-alert: testmelding'
            $b.message = 'Dit is een test. Zo klinkt het alarm als de PS5 Pro op voorraad is.'
        }
        'storing' {
            $b.title = "PS5-alert: $($Winkel.naam) niet uit te lezen"
            $b.message = "$($Winkel.naam) is al een tijd niet te controleren ($($Resultaat.Reden)). De andere winkels worden gewoon gevolgd."
        }
        'hersteld' {
            $b.title = "PS5-alert: $($Winkel.naam) werkt weer"
            $b.message = "$($Winkel.naam) wordt weer gecontroleerd."
        }
    }
    if ($Soort -eq 'alarm' -or $Soort -eq 'test') {
        # Noodmelding: blijft elke 30 seconden afgaan tot je tikt, maximaal een uur.
        $b.priority = 2
        $b.retry = 30
        $b.expire = 3600
        $b.sound = 'persistent'
    }
    $b
}

# ---------- onthouden en instellingen ----------

function Read-Staat([string]$Pad) {
    $staat = @{}
    if (-not (Test-Path -LiteralPath $Pad)) { return $staat }
    try {
        $json = [IO.File]::ReadAllText($Pad, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $staat[$p.Name] = $p.Value }
    }
    catch { $staat = @{} }
    return $staat
}

function Save-Staat([string]$Pad, [hashtable]$Staat) {
    $json = $Staat | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($Pad, $json, (New-Object Text.UTF8Encoding $false))
}

# Instellingen uit config.json; sleutels uit de omgeving (cloud) gaan voor.
function Get-Instellingen([string]$ConfigPad, [hashtable]$Omgeving) {
    $config = $null
    if (Test-Path -LiteralPath $ConfigPad) {
        $config = [IO.File]::ReadAllText($ConfigPad, [Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    $user = [string](Get-Eigenschap $config 'pushoverUserKey' '')
    $token = [string](Get-Eigenschap $config 'pushoverAppToken' '')
    if ($Omgeving['PUSHOVER_USER_KEY']) { $user = [string]$Omgeving['PUSHOVER_USER_KEY'] }
    if ($Omgeving['PUSHOVER_APP_TOKEN']) { $token = [string]$Omgeving['PUSHOVER_APP_TOKEN'] }
    [pscustomobject]@{
        MaxPrijs         = [decimal](Get-Eigenschap $config 'maxPrijs' 1000)
        StoringNaMinuten = [int](Get-Eigenschap $config 'storingNaMinuten' 60)
        PushoverUserKey  = $user.Trim()
        PushoverAppToken = $token.Trim()
        KanMelden        = [bool]($user.Trim() -and $token.Trim())
    }
}
