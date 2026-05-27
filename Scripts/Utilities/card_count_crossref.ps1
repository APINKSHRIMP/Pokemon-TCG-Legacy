# Card Count Cross-Reference Script
# Reads all opponent deck JSONs, counts card usage, cross-references names from card set data,
# and outputs a sorted CSV to Spreadsheets/Card_Usage_Report.csv
#
# Trigger phrase: "Do a total card count cross reference"
# Columns: CardID, Set, CardName, Type, EnergyType (Pokemon only), TotalCount, DeckCount
# Basic energies (Fire/Water/Grass/Lightning/Psychic/Fighting) are excluded from the report.
#
# For any card set that has AT LEAST ONE card used in some deck, ALL remaining cards
# from that same set are also included in the CSV with TotalCount = 0 and DeckCount = 0.
# This surfaces unused/underused cards so new decks can be designed around them.
# Sets with zero usage anywhere are entirely omitted (they aren't in scope yet).

param (
    [string]$ProjectRoot = "C:\Pokemon TCG Legacy",
    [string]$OutputFile  = ""
)

if (-not $OutputFile) {
    $OutputFile = Join-Path $ProjectRoot "Spreadsheets\Card_Usage_Report.csv"
}

$deckFolder    = Join-Path $ProjectRoot "NPC_and_Opponent_Data\Opponent_Deck_Data"
$cardSetFolder = Join-Path $ProjectRoot "Card_Set_Data"

# Extract set prefix from a card ID like "base1-23" -> "base1"
function Get-SetPrefix([string]$cardId) {
    $idx = $cardId.LastIndexOf('-')
    if ($idx -lt 0) { return $cardId }
    return $cardId.Substring(0, $idx)
}

# --- Build card data lookup + per-set membership ---
Write-Host "Loading card set data..."
$cardData = @{}
$setCards = @{}  # set_prefix -> ArrayList of card IDs
Get-ChildItem "$cardSetFolder\*.json" | Where-Object { $_.Name -ne "pack_prices.json" } | ForEach-Object {
    $cards = Get-Content $_.FullName -Raw | ConvertFrom-Json
    foreach ($card in $cards) {
        if ($card.id -and $card.name) {
            $cardData[$card.id] = [PSCustomObject]@{
                Name      = $card.name
                Supertype = $card.supertype
                Subtypes  = $card.subtypes
                Types     = $card.types
            }
            $prefix = Get-SetPrefix $card.id
            if (-not $setCards.ContainsKey($prefix)) {
                $setCards[$prefix] = New-Object System.Collections.ArrayList
            }
            [void]$setCards[$prefix].Add($card.id)
        }
    }
}
Write-Host "  Loaded $($cardData.Count) unique card definitions across $($setCards.Count) sets."

# --- Process deck files ---
Write-Host "Processing deck files..."
$cardStats = @{}
$deckFiles = Get-ChildItem "$deckFolder\*.json"
foreach ($file in $deckFiles) {
    $deck = Get-Content $file.FullName -Raw | ConvertFrom-Json
    foreach ($entry in $deck) {
        $id    = $entry.id
        $count = [int]$entry.count
        if (-not $cardStats.ContainsKey($id)) {
            $cardStats[$id] = [PSCustomObject]@{
                TotalCount = 0
                DeckCount  = 0
            }
        }
        $cardStats[$id].TotalCount += $count
        $cardStats[$id].DeckCount  += 1
    }
}
Write-Host "  Processed $($deckFiles.Count) decks."

# --- Determine which sets have at least one used card ---
$activeSets = @{}
foreach ($id in $cardStats.Keys) {
    $prefix = Get-SetPrefix $id
    $activeSets[$prefix] = $true
}

# --- Add zero-usage entries for unused cards in active sets ---
$addedZero = 0
foreach ($prefix in $activeSets.Keys) {
    if (-not $setCards.ContainsKey($prefix)) { continue }
    foreach ($cardId in $setCards[$prefix]) {
        if (-not $cardStats.ContainsKey($cardId)) {
            $cardStats[$cardId] = [PSCustomObject]@{
                TotalCount = 0
                DeckCount  = 0
            }
            $addedZero++
        }
    }
}
Write-Host "  Added $addedZero unused cards from $($activeSets.Count) active sets."

# --- Build output rows, filtering out basic energies ---
$rows = foreach ($id in $cardStats.Keys) {
    $info = $cardData[$id]

    if ($info) {
        $supertype = $info.Supertype
        $subtypes  = @($info.Subtypes)

        # Skip basic energies
        if ($supertype -eq "Energy" -and $subtypes -contains "Basic") { continue }

        # Determine Type column
        $type = switch ($supertype) {
            "Pokémon" { "Pokemon" }
            "Trainer" { "Trainer" }
            "Energy"  { "Special Energy" }
            default   { $supertype }
        }

        # Energy Type only for Pokemon
        $energyType = if ($supertype -eq "Pokémon" -and $info.Types -and $info.Types.Count -gt 0) {
            $info.Types[0]
        } else {
            ""
        }

        [PSCustomObject]@{
            CardID     = $id
            Set        = Get-SetPrefix $id
            CardName   = $info.Name
            Type       = $type
            EnergyType = $energyType
            TotalCount = $cardStats[$id].TotalCount
            DeckCount  = $cardStats[$id].DeckCount
        }
    } else {
        # ID not found in any card set — include with unknowns flagged
        [PSCustomObject]@{
            CardID     = $id
            Set        = Get-SetPrefix $id
            CardName   = "UNKNOWN - $id"
            Type       = "UNKNOWN"
            EnergyType = ""
            TotalCount = $cardStats[$id].TotalCount
            DeckCount  = $cardStats[$id].DeckCount
        }
    }
}

$rows = $rows | Sort-Object -Property TotalCount -Descending

# --- Export CSV ---
$rows | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
$unusedCount = ($rows | Where-Object { $_.TotalCount -eq 0 }).Count
Write-Host ""
Write-Host "Done! CSV written to: $OutputFile"
Write-Host "Total card IDs reported               : $($rows.Count)"
Write-Host "  Of which unused (count = 0)         : $unusedCount"
Write-Host "Total decks processed                 : $($deckFiles.Count)"
Write-Host "Active sets (>= 1 used card)          : $($activeSets.Count)"
$unknownCount = ($rows | Where-Object { $_.Type -eq "UNKNOWN" }).Count
if ($unknownCount -gt 0) {
    Write-Host "WARNING: $unknownCount card IDs had no matching name in card set data."
}
