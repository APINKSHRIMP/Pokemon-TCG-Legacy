$colMap = [ordered]@{
    'Celeste_Harbour_1_Day.json'      = 'CH1 Day'
    'Celeste_Harbour_1_Evening.json'  = 'CH1 Eve'
    'Celeste_Harbour_1_Night.json'    = 'CH1 Nite'
    'Celeste_Harbour_2_Day.json'      = 'CH2 Day'
    'Celeste_Harbour_2_Evening.json'  = 'CH2 Eve'
    'Celeste_Harbour_2_Night.json'    = 'CH2 Nite'
    'Celeste_Harbour_3_Day.json'      = 'CH3 Day'
    'Celeste_Harbour_3_Evening.json'  = 'CH3 Eve'
    'Celeste_Harbour_3_Night.json'    = 'CH3 Nite'
    'Celeste_Harbour_4_Day.json'      = 'CH4 Day'
    'Celeste_Harbour_4_Evening.json'  = 'CH4 Eve'
    'Celeste_Harbour_4_Night.json'    = 'CH4 Nite'
    'Verdant_Forest_4_Day.json'       = 'VF4 Day'
    'Verdant_Forest_4_Evening.json'   = 'VF4 Eve'
    'Verdant_Forest_4_Night.json'     = 'VF4 Nite'
    'Verdant_Forest_5_Day.json'       = 'VF5 Day'
    'Verdant_Forest_5_Evening.json'   = 'VF5 Eve'
    'Verdant_Forest_5_Night.json'     = 'VF5 Nite'
}

$root = 'C:\Pokemon TCG Legacy\NPC_and_Opponent_Data'
$outCsv = 'C:\Pokemon TCG Legacy\Spreadsheets\NPC_Opponent_Schedule.csv'

$npcMatrix = @{}
$oppMatrix = @{}

foreach ($file in $colMap.Keys) {
    $col  = $colMap[$file]
    $path = Join-Path $root $file
    $data = Get-Content $path -Raw | ConvertFrom-Json
    if ($data.npcs) {
        foreach ($n in $data.npcs) {
            if (-not $npcMatrix.ContainsKey($n.name)) { $npcMatrix[$n.name] = @{} }
            $npcMatrix[$n.name][$col] = $true
        }
    }
    if ($data.opponents) {
        foreach ($o in $data.opponents) {
            if (-not $oppMatrix.ContainsKey($o.name)) { $oppMatrix[$o.name] = @{} }
            $oppMatrix[$o.name][$col] = $true
        }
    }
}

$cols = @($colMap.Values)

$csvLines = New-Object System.Collections.Generic.List[string]
$csvLines.Add('Type,Name,' + ($cols -join ','))

foreach ($name in ($npcMatrix.Keys | Sort-Object)) {
    $cells = foreach ($c in $cols) { if ($npcMatrix[$name].ContainsKey($c)) { 'X' } else { '' } }
    $csvLines.Add(('NPC,"' + $name + '",' + ($cells -join ',')))
}
foreach ($name in ($oppMatrix.Keys | Sort-Object)) {
    $cells = foreach ($c in $cols) { if ($oppMatrix[$name].ContainsKey($c)) { 'X' } else { '' } }
    $csvLines.Add(('OPP,"' + $name + '",' + ($cells -join ',')))
}

$csvLines -join "`n" | Out-File -Encoding utf8 $outCsv
Write-Output ('Wrote CSV: ' + $outCsv)
Write-Output ('  NPCs unique:      ' + $npcMatrix.Count)
Write-Output ('  Opponents unique: ' + $oppMatrix.Count)
Write-Output ('  Columns:          ' + $cols.Count)
