# Base -> Gym card usage report
# Counts every card in base1/base2/base3/base5/basep/gym1/gym2 across the opponent decks in
# NPC_and_Opponent_Data/Opponent_Deck_Data and writes Spreadsheets/Card_Usage_Base_To_Gym.xlsx.
#
# Columns: CardID, Set, CardName, Type, EnergyType, Rarity, TotalCount, DeckCount,
#          LiveTotalCount, LiveDeckCount (Live = deck named by a "deck" key in an NPC/opponent JSON)
# Sorted by DeckCount, then TotalCount, ascending. Unused cards are included; basic energies are left out.
# Excluded decks: TEST, your_first_deck, Shrimps_deck.
#
# Writes through Excel (COM). If the workbook already exists, only cell VALUES on the first sheet
# are replaced, so the user's formatting (column widths, fills, filters, conditional formats) survives.
# Also prints a legality check (60 cards, max 4 per card name, basic energy exempt).

param (
    [string]$ProjectRoot = "C:\Pokemon TCG Legacy",
    [string]$OutputFile  = ""
)

if (-not $OutputFile) { $OutputFile = Join-Path $ProjectRoot "Spreadsheets\Card_Usage_Base_To_Gym.xlsx" }
$sets    = 'base1','base2','basep','base3','base5','gym1','gym2'
$deckDir = Join-Path $ProjectRoot "NPC_and_Opponent_Data\Opponent_Deck_Data"
$exclude = @('test','your_first_deck','shrimps_deck')

# --- Live deck names: any "deck": "<name>" in NPC/opponent JSONs ---
$live = @{}
Get-ChildItem (Join-Path $ProjectRoot "NPC_and_Opponent_Data") -Recurse -Filter *.json | Where-Object { $_.DirectoryName -ne $deckDir } | ForEach-Object {
    $t = Get-Content $_.FullName -Raw
    foreach ($m in [regex]::Matches($t, '"deck"\s*:\s*"([^"]+)"')) { $live[$m.Groups[1].Value.ToLower()] = $true }
}

# --- One row per card in the Base -> Gym sets ---
$rows = [ordered]@{}
foreach ($s in $sets) {
    $f = Join-Path $ProjectRoot "Card_Set_Data\$s.json"
    if (-not (Test-Path $f)) { continue }
    foreach ($c in (Get-Content $f -Raw | ConvertFrom-Json)) {
        $type = switch ($c.supertype) {
            "Pokémon" { "Pokemon" }
            "Trainer" { "Trainer" }
            "Energy"  { if (@($c.subtypes) -contains "Basic") { "Basic Energy" } else { "Special Energy" } }
            default   { $c.supertype }
        }
        $et = if ($c.supertype -eq "Pokémon" -and $c.types) { @($c.types)[0] } else { "" }
        $rows[$c.id] = [PSCustomObject]@{
            CardID = $c.id; Set = $s; CardName = $c.name; Type = $type; EnergyType = $et; Rarity = "$($c.rarity)"
            TotalCount = 0; DeckCount = 0; LiveTotalCount = 0; LiveDeckCount = 0
        }
    }
}

# --- Count decks ---
$counted = 0; $liveCounted = 0; $illegal = @(); $unassigned = @()
foreach ($file in Get-ChildItem "$deckDir\*.json") {
    $name = $file.BaseName
    if ($exclude -contains $name.ToLower()) { continue }
    $deck   = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $isLive = $live.ContainsKey($name.ToLower())
    $counted++
    if ($isLive) { $liveCounted++ } else { $unassigned += $name }

    $total  = ($deck | Measure-Object count -Sum).Sum
    $byName = @{}
    foreach ($e in $deck) {
        $r = $rows[$e.id]
        if (-not $r) { continue }
        $r.TotalCount += [int]$e.count; $r.DeckCount++
        if ($isLive) { $r.LiveTotalCount += [int]$e.count; $r.LiveDeckCount++ }
        if ($r.Type -ne "Basic Energy") { $byName[$r.CardName] += [int]$e.count }
    }
    $over = $byName.GetEnumerator() | Where-Object { $_.Value -gt 4 } | ForEach-Object { "$($_.Key) x$($_.Value)" }
    if ($total -ne 60 -or $over) { $illegal += "$name : $total cards $($over -join ', ')" }
}

$out = @($rows.Values | Where-Object { $_.Type -ne "Basic Energy" } | Sort-Object DeckCount, TotalCount)

# --- Write workbook via Excel COM ---
$headers = 'CardID','Set','CardName','Type','EnergyType','Rarity','TotalCount','DeckCount','LiveTotalCount','LiveDeckCount'
$data = New-Object 'object[,]' ($out.Count + 1), $headers.Count
for ($c = 0; $c -lt $headers.Count; $c++) { $data[0, $c] = $headers[$c] }
for ($r = 0; $r -lt $out.Count; $r++) {
    for ($c = 0; $c -lt $headers.Count; $c++) { $data[($r + 1), $c] = $out[$r].($headers[$c]) }
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false; $excel.DisplayAlerts = $false
try {
    $isNew = -not (Test-Path $OutputFile)
    $wb = if ($isNew) { $excel.Workbooks.Add() } else { $excel.Workbooks.Open($OutputFile) }
    $ws = $wb.Worksheets.Item(1)
    if (-not $isNew) {
        # An active filter hides rows and scrambles the write, so show everything first
        if ($ws.FilterMode) { $ws.ShowAllData() }
        # Clear old values only (formats stay), so a shorter list leaves no stale rows
        $used = $ws.UsedRange.Rows.Count
        $ws.Range($ws.Cells(1, 1), $ws.Cells([Math]::Max($used, $out.Count + 1), $headers.Count)).ClearContents() | Out-Null
    }
    $ws.Range($ws.Cells(1, 1), $ws.Cells($out.Count + 1, $headers.Count)).Value2 = $data
    if ($isNew) {
        $ws.Name = "Card Usage"
        $ws.Rows(1).Font.Bold = $true
        $ws.Range($ws.Cells(1, 1), $ws.Cells($out.Count + 1, $headers.Count)).AutoFilter() | Out-Null
        $ws.Activate(); $excel.ActiveWindow.SplitRow = 1; $excel.ActiveWindow.FreezePanes = $true
        $ws.UsedRange.Columns.AutoFit() | Out-Null
        $wb.SaveAs($OutputFile, 51)  # 51 = xlOpenXMLWorkbook
    } else {
        $wb.Save()
    }
    $wb.Close($false)
} finally {
    $excel.Quit()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
}

Write-Host "Written: $OutputFile ($(if ($isNew) { 'new workbook' } else { 'values replaced, formatting kept' }))"
Write-Host "Decks counted: $counted (live $liveCounted, unassigned $($counted - $liveCounted))"
Write-Host "Unassigned: $($unassigned -join ', ')"
Write-Host "Rows: $($out.Count); unused non-basic-energy: $(($out | Where-Object { $_.TotalCount -eq 0 -and $_.Type -ne 'Basic Energy' }).Count)"
if ($illegal) { Write-Host "Illegal decks:"; $illegal | ForEach-Object { Write-Host "  $_" } } else { Write-Host "All decks legal." }
