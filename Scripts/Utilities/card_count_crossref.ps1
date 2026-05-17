# Card Count Cross-Reference Script
# Reads all opponent deck JSONs, counts card usage, cross-references names from card set data,
# and outputs a sorted CSV to Spreadsheets/Card_Usage_Report.csv
#
# Trigger phrase: "Do a total card count cross reference"
# Columns: CardID, CardName, Type, EnergyType (Pokemon only), TotalCount, DeckCount
# Basic energies (Fire/Water/Grass/Lightning/Psychic/Fighting) are excluded from the report.

param (
    [string]$ProjectRoot = "C:\Pokemon TCG Legacy",
    [string]$OutputFile  = ""
)

if (-not $OutputFile) {
    $OutputFile = Join-Path $ProjectRoot "Spreadsheets\Card_Usage_Report.csv"
}

$deckFolder    = Join-Path $ProjectRoot "NPC_and_Opponent_Data\Opponent_Deck_Data"
$cardSetFolder = Join-Path $ProjectRoot "Card_Set_Data"

# --- Build card data lookup (name + supertype + subtypes + types) ---
Write-Host "Loading card set data..."
$cardData = @{}
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
        }
    }
}
Write-Host "  Loaded $($cardData.Count) unique card definitions."

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
Write-Host ""
Write-Host "Done! CSV written to: $OutputFile"
Write-Host "Unique card IDs (excl. basic energy) : $($rows.Count)"
Write-Host "Total decks processed                : $($deckFiles.Count)"
$unknownCount = ($rows | Where-Object { $_.Type -eq "UNKNOWN" }).Count
if ($unknownCount -gt 0) {
    Write-Host "WARNING: $unknownCount card IDs had no matching name in card set data."
}
