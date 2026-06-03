###############################################################################################
# set_audit.ps1
# Cross-references card data JSON against implemented attack/trainer/power dispatch entries.
#
# Usage: pwsh Scripts\Utilities\set_audit.ps1
# Output: Spreadsheets\Set_Audit_Report.txt  +  console
###############################################################################################

$ErrorActionPreference = "Stop"

# ── Paths ──────────────────────────────────────────────────────────────────────
$Root           = "C:\Pokemon TCG Legacy"
$CardDataDir    = Join-Path $Root "Card_Set_Data"
$AttackGd       = Join-Path $Root "Scripts\Main_Match_Gameplay_Scripts\Attack_Effects.gd"
$TrainerGd      = Join-Path $Root "Scripts\Main_Match_Gameplay_Scripts\Trainer_Effects.gd"
$PowerGd        = Join-Path $Root "Scripts\Main_Match_Gameplay_Scripts\Powers_And_Bodies_Effects.gd"
$StadiumGd      = Join-Path $Root "Scripts\Main_Match_Gameplay_Scripts\Stadium_Ids.gd"
$SpreadsheetDir = Join-Path $Root "Spreadsheets"
$OutputFile     = Join-Path $SpreadsheetDir "Set_Audit_Report.txt"

$Sets = @("base1","base2","base3","base5","gym1","gym2","si1")

# ── Ensure output directory ────────────────────────────────────────────────────
if (-not (Test-Path $SpreadsheetDir)) {
    New-Item -ItemType Directory -Path $SpreadsheetDir | Out-Null
    Write-Host "Created directory: $SpreadsheetDir"
}

# ── Helper: emit to both console and file ─────────────────────────────────────
$OutputLines = [System.Collections.Generic.List[string]]::new()

function Out {
    param([string]$Line = "")
    Write-Host $Line
    $OutputLines.Add($Line)
}

# ── 1. Parse Attack_Effects.gd ────────────────────────────────────────────────
$AttackGdText = Get-Content $AttackGd -Raw

# Extract keys from  _attack_dispatch["some name"]  entries
$AttackDispatchKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$AttackKeyMatches = [regex]::Matches($AttackGdText, '_attack_dispatch\["([^"]+)"\]')
foreach ($m in $AttackKeyMatches) {
    $AttackDispatchKeys.Add($m.Groups[1].Value.ToLower()) | Out-Null
}

# Extract func execute_<name>(...) signatures — normalise name (spaces/special→underscore)
$AttackFuncNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$AttackFuncMatches = [regex]::Matches($AttackGdText, 'func execute_([A-Za-z0-9_]+)\s*\(')
foreach ($m in $AttackFuncMatches) {
    $AttackFuncNames.Add($m.Groups[1].Value.ToLower()) | Out-Null
}

# ── 2. Parse Trainer_Effects.gd ───────────────────────────────────────────────
$TrainerGdText = Get-Content $TrainerGd -Raw
$MainGdText    = Get-Content (Join-Path $Root "Scripts\Main_Match_Gameplay_Scripts\Main_Match_Core_Gameplay_Script.gd") -Raw

$TrainerDispatchKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$TrainerKeyMatches = [regex]::Matches($TrainerGdText, '_trainer_dispatch\["([^"]+)"\]')
foreach ($m in $TrainerKeyMatches) {
    $TrainerDispatchKeys.Add($m.Groups[1].Value.ToLower()) | Out-Null
}

# Attached trainers routed through resolve_attached_trainer (not in _trainer_dispatch)
$AttachedTrainerUids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($uid in @("gym1-99","gym1-117","gym2-101","gym2-115")) {
    $AttachedTrainerUids.Add($uid) | Out-Null
}
# PlusPower/Defender identified by card name (multiple set printings)
$AttachedTrainerNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($n in @("pluspower","defender")) { $AttachedTrainerNames.Add($n) | Out-Null }

# Bench token trainers: Clefairy Doll, Mysterious Fossil (identified by HP field + rules text in JSON)
# We detect these dynamically below by inspecting card data, so no static list needed here.

# ── 3. Parse Powers_And_Bodies_Effects.gd ─────────────────────────────────────
$PowerGdText = Get-Content $PowerGd -Raw

$PowerDispatchKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$PowerKeyMatches = [regex]::Matches($PowerGdText, '_power_dispatch\["([^"]+)"\]')
foreach ($m in $PowerKeyMatches) {
    $PowerDispatchKeys.Add($m.Groups[1].Value) | Out-Null
}
$PowerDispatchKeysCI = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($k in $PowerDispatchKeys) { $PowerDispatchKeysCI.Add($k) | Out-Null }

# Powers implemented as passive checks — search both Powers.gd and Main.gd for the ability name as a string.
# If it appears there, it's handled even if not in _power_dispatch.
function IsPowerImplementedPassively([string]$abilName) {
    $escaped = [regex]::Escape($abilName)
    # Look for the name as a quoted string in Powers or Main
    if ($PowerGdText  -match ('"' + $escaped + '"')) { return $true }
    if ($MainGdText   -match ('"' + $escaped + '"')) { return $true }
    return $false
}

# ── 4. Parse Stadium_Ids.gd for handled stadium UIDs ─────────────────────────
$StadiumHandledIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if (Test-Path $StadiumGd) {
    $StadiumText = Get-Content $StadiumGd -Raw
    # Match: const SOMETHING = "gym1-103"
    $StadiumMatches = [regex]::Matches($StadiumText, 'const\s+\w+\s*=\s*"([^"]+)"')
    foreach ($m in $StadiumMatches) {
        $StadiumHandledIds.Add($m.Groups[1].Value.ToLower()) | Out-Null
    }
} else {
    Write-Warning "Stadium_Ids.gd not found at: $StadiumGd"
}

# ── 5. Helper: normalise attack name to func-name form ────────────────────────
function NormalizeToFuncName([string]$name) {
    # lowercase, replace any non-alphanumeric run with underscore, trim trailing underscores
    $n = $name.ToLower()
    $n = [regex]::Replace($n, "[^a-z0-9]+", "_")
    $n = $n.Trim("_")
    return $n
}

# ── 6. Helper: does attack text look generic enough to probably work? ─────────
$GenericPatterns = @(
    "flip a coin",
    "flips a coin",
    "does \d+ damage",
    "remove \d+ damage counter",
    "\basleep\b",
    "\bconfused\b",
    "\bparalyzed\b",
    "\bpoisoned\b",
    "this attack does",
    "damage to each",
    "damage counter",
    # Text parser handles these automatically:
    "discard.*energy.*attached to",    # energy_discard_self
    "choose 1 of them and discard it", # energy_discard_defender (Hyper Beam, Whirlpool)
    "switches it with.*bench",         # force_switch (Whirlwind, Lure)
    "switch it with.*bench",           # force_switch
    "switch it with his or her active",# force_switch (Lure)
    "or less damage is done to",       # shielded_damage (Harden)
    "damage done.*reduced by",         # damage_reduction (Minimize, Pounce)
    "can't retreat.*defending",        # retreat_lock (Clutch, Spook)
    "can't play trainer",              # trainer_lock (Headache)
    "knocks out.*knock out that",      # destiny_bond
    "prevent all effects",             # invincible (Barrier)
    "tries to attack.*does nothing"    # flip_attack_block (Sand-attack, Smokescreen)
)

function IsLikelyGeneric([string]$text) {
    # No text at all = pure damage attack, handled by base damage path
    if ([string]::IsNullOrWhiteSpace($text)) { return $true }
    $tl = $text.ToLower().Trim()
    # Very short text = typically just damage flavour, handled generically
    if ($tl.Length -lt 15) { return $true }
    foreach ($pat in $GenericPatterns) {
        if ($tl -match $pat) { return $true }
    }
    # Multi-keyword checks (order-independent, mirrors the GDScript text parser)
    if (($tl -match "switches it with" -or $tl -match "switch it with") -and ($tl -match "bench")) { return $true }  # force_switch
    if ($tl -match "switch" -and $tl -match "with 1 of your benched") { return $true }  # self_switch (Teleport)
    if ($tl -match "can't retreat" -and $tl -match "defending") { return $true }  # retreat_lock
    if ($tl -match "or less damage is done to" -and $tl -match "prevent that damage") { return $true }  # shielded_damage
    if ($tl -match "damage done" -and $tl -match "reduced by") { return $true }  # damage_reduction
    if ($tl -match "can't play trainer" -and $tl -match "next turn") { return $true }  # trainer_lock
    if ($tl -match "knocks out" -and $tl -match "knock out that") { return $true }  # destiny_bond
    if ($tl -match "prevent all effects" -and $tl -match "attacks") { return $true }  # invincible (Barrier)
    if ($tl -match "tries to attack" -and $tl -match "does nothing") { return $true }  # flip_attack_block
    if ($tl -match "discard" -and $tl -match "energy" -and $tl -match "attached to") { return $true }  # energy_discard
    return $false
}

# ── 7. Grand totals accumulator ───────────────────────────────────────────────
$GrandTotal = @{
    TotalAttacks   = 0; ImplAttacks   = 0; MissAttacks   = 0; GenericAttacks = 0
    TotalTrainers  = 0; ImplTrainers  = 0; MissTrainers  = 0
    TotalPowers    = 0; ImplPowers    = 0; MissPowers    = 0
}

# Collect per-set summary rows for table
$SummaryRows = [System.Collections.Generic.List[object]]::new()
# Collect missing items per set
$MissingItems = [System.Collections.Generic.List[string]]::new()

# ── 8. Per-set processing ─────────────────────────────────────────────────────
foreach ($Set in $Sets) {
    $JsonFile = Join-Path $CardDataDir "$Set.json"
    if (-not (Test-Path $JsonFile)) {
        Write-Warning "JSON not found: $JsonFile — skipping"
        continue
    }
    $Cards = Get-Content $JsonFile -Raw | ConvertFrom-Json

    $SetStats = @{
        TotalAttacks   = 0; ImplAttacks   = 0; MissAttacks   = 0; GenericAttacks = 0
        TotalTrainers  = 0; ImplTrainers  = 0; MissTrainers  = 0
        TotalPowers    = 0; ImplPowers    = 0; MissPowers    = 0
    }
    $SetMissing = [System.Collections.Generic.List[string]]::new()

    foreach ($Card in $Cards) {
        $SuperType = $Card.supertype

        # ── Energy: skip ──────────────────────────────────────────────────────
        if ($SuperType -eq "Energy") { continue }

        # ── Pokémon cards ──────────────────────────────────────────────────────
        if ($SuperType -eq "Pokémon" -or $SuperType -eq "Pokemon") {

            # Attacks
            if ($Card.PSObject.Properties["attacks"] -and $Card.attacks) {
                foreach ($Atk in $Card.attacks) {
                    $AtkName = $Atk.name
                    if (-not $AtkName) { continue }
                    $AtkNameLower = $AtkName.ToLower()
                    $AtkNameNorm  = NormalizeToFuncName $AtkName
                    $AtkText      = if ($Atk.PSObject.Properties["text"]) { $Atk.text } else { "" }

                    $SetStats.TotalAttacks++

                    $inDispatch = $AttackDispatchKeys.Contains($AtkNameLower)
                    $inFunc     = $AttackFuncNames.Contains($AtkNameNorm)

                    if ($inDispatch -or $inFunc) {
                        $SetStats.ImplAttacks++
                    } else {
                        if (IsLikelyGeneric $AtkText) {
                            $SetStats.GenericAttacks++
                            $SetMissing.Add("  [ATTACK ? generic] $($Card.name) ($($Card.id)) — ""$AtkName""")
                        } else {
                            $SetStats.MissAttacks++
                            $SetMissing.Add("  [ATTACK MISSING  ] $($Card.name) ($($Card.id)) — ""$AtkName""")
                        }
                    }
                }
            }

            # Powers / Bodies
            if ($Card.PSObject.Properties["abilities"] -and $Card.abilities) {
                foreach ($Abil in $Card.abilities) {
                    $AbilType = $Abil.type
                    if ($AbilType -ne "Pokémon Power" -and $AbilType -ne "Poké-Body" -and
                        $AbilType -ne "Pokemon Power"  -and $AbilType -ne "Poke-Body") {
                        continue
                    }
                    $AbilName = $Abil.name
                    if (-not $AbilName) { continue }

                    $SetStats.TotalPowers++

                    if ($PowerDispatchKeysCI.Contains($AbilName) -or (IsPowerImplementedPassively $AbilName)) {
                        $SetStats.ImplPowers++
                    } else {
                        $SetStats.MissPowers++
                        $SetMissing.Add("  [POWER  MISSING  ] $($Card.name) ($($Card.id)) — ""$AbilName"" ($AbilType)")
                    }
                }
            }
        }

        # ── Trainer cards ──────────────────────────────────────────────────────
        if ($SuperType -eq "Trainer") {
            $Uid = $Card.id
            if (-not $Uid) { continue }
            $UidLower = $Uid.ToLower()

            # Determine if it's a Stadium card handled via Stadium_Ids.gd
            $IsStadium = $false
            if ($Card.PSObject.Properties["subtypes"] -and $Card.subtypes -contains "Stadium") {
                $IsStadium = $true
            }

            $SetStats.TotalTrainers++

            # Check if it's a bench-token trainer (Clefairy Doll, Mysterious Fossil):
            # has HP > 0 and rules text containing "as if it were a basic"
            $IsBenchToken = $false
            if ($Card.PSObject.Properties["hp"] -and [int]($Card.hp) -gt 0) {
                if ($Card.PSObject.Properties["rules"] -and $Card.rules) {
                    foreach ($rule in $Card.rules) {
                        if ($rule -match "as if it were a basic") { $IsBenchToken = $true; break }
                    }
                }
            }
            # Attached trainers by UID or card name
            $CardNameLower = if ($Card.PSObject.Properties["name"]) { $Card.name.ToLower() } else { "" }
            $IsAttached = $AttachedTrainerUids.Contains($UidLower) -or $AttachedTrainerNames.Contains($CardNameLower)

            if ($TrainerDispatchKeys.Contains($UidLower)) {
                $SetStats.ImplTrainers++
            } elseif ($IsStadium -and $StadiumHandledIds.Contains($UidLower)) {
                $SetStats.ImplTrainers++
            } elseif ($IsBenchToken -or $IsAttached) {
                # Handled by special routing in resolve_bench_token_trainer / resolve_attached_trainer
                $SetStats.ImplTrainers++
            } else {
                $SetStats.MissTrainers++
                $StadiumNote = if ($IsStadium) { " [Stadium]" } else { "" }
                $SetMissing.Add("  [TRAINER MISSING ] $($Card.name) ($Uid)$StadiumNote")
            }
        }
    }

    # Accumulate grand totals (copy keys to array first to avoid modification-during-enumeration)
    $KeysCopy = @($GrandTotal.Keys)
    foreach ($Key in $KeysCopy) { $GrandTotal[$Key] += $SetStats[$Key] }

    # Store for summary table
    $SummaryRows.Add([PSCustomObject]@{
        Set            = $Set
        AtkTotal       = $SetStats.TotalAttacks
        AtkImpl        = $SetStats.ImplAttacks
        AtkGeneric     = $SetStats.GenericAttacks
        AtkMiss        = $SetStats.MissAttacks
        TrnTotal       = $SetStats.TotalTrainers
        TrnImpl        = $SetStats.ImplTrainers
        TrnMiss        = $SetStats.MissTrainers
        PwrTotal       = $SetStats.TotalPowers
        PwrImpl        = $SetStats.ImplPowers
        PwrMiss        = $SetStats.MissPowers
    })

    # Store missing items with set header
    if ($SetMissing.Count -gt 0) {
        $MissingItems.Add("")
        $MissingItems.Add("=== $($Set.ToUpper()) missing items ===")
        foreach ($Line in $SetMissing) { $MissingItems.Add($Line) }
    }
}

# ── 9. Render output ──────────────────────────────────────────────────────────
$TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Out "Pokemon TCG Legacy — Set Audit Report"
Out "Generated: $TimeStamp"
Out "Sets audited: $($Sets -join ', ')"
Out ""
Out ("=" * 100)
Out "SUMMARY TABLE"
Out ("=" * 100)

# Header
$H = "{0,-8}  {1,8} {2,8} {3,9} {4,8}    {5,8} {6,8} {7,8}    {8,8} {9,8} {10,8}" -f `
    "Set","Atk Tot","Atk Impl","Atk ?Gen","Atk Miss","Trn Tot","Trn Impl","Trn Miss","Pwr Tot","Pwr Impl","Pwr Miss"
Out $H
Out ("-" * 100)

foreach ($Row in $SummaryRows) {
    $Line = "{0,-8}  {1,8} {2,8} {3,9} {4,8}    {5,8} {6,8} {7,8}    {8,8} {9,8} {10,8}" -f `
        $Row.Set,
        $Row.AtkTotal, $Row.AtkImpl, $Row.AtkGeneric, $Row.AtkMiss,
        $Row.TrnTotal, $Row.TrnImpl, $Row.TrnMiss,
        $Row.PwrTotal, $Row.PwrImpl, $Row.PwrMiss
    Out $Line
}

Out ("-" * 100)
# Grand total row
$GTLine = "{0,-8}  {1,8} {2,8} {3,9} {4,8}    {5,8} {6,8} {7,8}    {8,8} {9,8} {10,8}" -f `
    "TOTAL",
    $GrandTotal.TotalAttacks, $GrandTotal.ImplAttacks, $GrandTotal.GenericAttacks, $GrandTotal.MissAttacks,
    $GrandTotal.TotalTrainers, $GrandTotal.ImplTrainers, $GrandTotal.MissTrainers,
    $GrandTotal.TotalPowers, $GrandTotal.ImplPowers, $GrandTotal.MissPowers
Out $GTLine
Out ("=" * 100)

Out ""
Out "LEGEND:"
Out "  Atk Impl   = dispatch key OR func execute_ found"
Out "  Atk ?Gen   = not in dispatch but text contains generic patterns (flip/status/damage counters)"
Out "  Atk Miss   = not in dispatch and not obviously generic — likely needs an execute_ function"
Out "  Trn Impl   = _trainer_dispatch[uid] found OR Stadium card found in Stadium_Ids.gd"
Out "  Trn Miss   = no dispatch entry and not a handled Stadium"
Out "  Pwr Impl   = _power_dispatch[name] found"
Out "  Pwr Miss   = power/body name not registered in _power_dispatch"
Out ""
Out "NOTE: 'Atk ?Gen' entries may still work via the generic text parser — review individually."
Out ""
Out ("=" * 100)
Out "MISSING ITEMS DETAIL"
Out ("=" * 100)

foreach ($Line in $MissingItems) { Out $Line }

Out ""
Out ("=" * 100)
Out "DISPATCH REGISTRY SIZES (for reference)"
Out ("=" * 100)
Out ("  _attack_dispatch keys   : {0}" -f $AttackDispatchKeys.Count)
Out ("  execute_ func names     : {0}" -f $AttackFuncNames.Count)
Out ("  _trainer_dispatch keys  : {0}" -f $TrainerDispatchKeys.Count)
Out ("  Stadium_Ids constants   : {0}" -f $StadiumHandledIds.Count)
Out ("  _power_dispatch keys    : {0}" -f $PowerDispatchKeys.Count)
Out ""

# ── 10. Write file ────────────────────────────────────────────────────────────
[System.IO.File]::WriteAllLines($OutputFile, $OutputLines, [System.Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host "Report written to: $OutputFile"
