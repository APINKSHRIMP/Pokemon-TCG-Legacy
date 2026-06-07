$dataPath = "C:\Pokemon TCG Legacy\NPC_and_Opponent_Data"
function Load-J($f)  { Get-Content "$dataPath\$f" -Raw | ConvertFrom-Json }
function Save-J($obj, $f) {
    $json = $obj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$dataPath\$f", $json, [System.Text.Encoding]::UTF8)
}

# Remove $removeCount spectators from $specGroup, spread evenly across columns (x)
# or rows (y), keeping at least $minPerGroup per group. Returns the kept entries.
function Remove-Balanced {
    param($specGroup, [int]$removeCount, [string]$groupBy, [int]$minPerGroup)

    $grouped = @{}
    foreach ($s in $specGroup) {
        $key = if ($groupBy -eq "y") { $s.position.y } else { $s.position.x }
        if (-not $grouped.ContainsKey($key)) { $grouped[$key] = [System.Collections.Generic.List[object]]::new() }
        $grouped[$key].Add($s)
    }

    $removed = [System.Collections.Generic.HashSet[string]]::new()
    $remaining = $removeCount

    # Round-robin across shuffled groups until quota met or can't remove more
    for ($pass = 0; $pass -lt 20 -and $remaining -gt 0; $pass++) {
        $keys = @($grouped.Keys | Sort-Object { Get-Random })
        foreach ($k in $keys) {
            if ($remaining -le 0) { break }
            $avail = @($grouped[$k] | Where-Object { -not $removed.Contains($_.name) })
            if (($avail.Count - 1) -ge $minPerGroup) {
                $pick = $avail | Get-Random
                $null = $removed.Add($pick.name)
                $remaining--
            }
        }
    }
    return @($specGroup | Where-Object { -not $removed.Contains($_.name) })
}

# Remove $totalRemove spectators from $allNpcs, proportionally across L/T/R sections.
# minL/minT/minR = minimum to keep per column/row within each section.
function Remove-Spectators {
    param($allNpcs, [int]$totalRemove, [int]$minL=3, [int]$minT=4, [int]$minR=3)

    $l     = @($allNpcs | Where-Object { $_.name -like "Spec L*" })
    $t     = @($allNpcs | Where-Object { $_.name -like "Spec T*" })
    $r     = @($allNpcs | Where-Object { $_.name -like "Spec R*" })
    $other = @($allNpcs | Where-Object { $_.name -notlike "Spec *" })
    $total = $l.Count + $t.Count + $r.Count

    $removeL = [Math]::Round($totalRemove * $l.Count / $total)
    $removeT = [Math]::Round($totalRemove * $t.Count / $total)
    $removeR = $totalRemove - $removeL - $removeT

    $newL = Remove-Balanced $l $removeL "x" $minL
    $newT = Remove-Balanced $t $removeT "y" $minT
    $newR = Remove-Balanced $r $removeR "x" $minR

    return @($other) + @($newL) + @($newT) + @($newR)
}

function Spec-Count($npcs) { ($npcs | Where-Object { $_.name -like "Spec *" }).Count }

# ── DAY 10 (Day 9 – 20 spectators, ~20%) ──────────────────────────────────────
Write-Host "Creating Day 10..."
$d = Load-J "Gym_Challenge_Hall_9_Day.json"
$d.npcs = Remove-Spectators $d.npcs 20 -minL 5 -minT 5 -minR 5
Save-J $d "Gym_Challenge_Hall_10_Day.json"
Write-Host "  Day 10: $(Spec-Count $d.npcs) spectators (target ~80)"

# ── DAY 11 (Day 10 – ~16 spectators, ~20%) ────────────────────────────────────
Write-Host "Creating Day 11..."
$d = Load-J "Gym_Challenge_Hall_10_Day.json"
$d.npcs = Remove-Spectators $d.npcs 16 -minL 3 -minT 3 -minR 3
Save-J $d "Gym_Challenge_Hall_11_Day.json"
Write-Host "  Day 11: $(Spec-Count $d.npcs) spectators (target ~64)"

# ── EVENING 10 (Evening 9 – 20 spectators, ~30%) ──────────────────────────────
Write-Host "Creating Evening 10..."
$d = Load-J "Gym_Challenge_Hall_9_Evening.json"
$d.npcs = Remove-Spectators $d.npcs 20 -minL 2 -minT 3 -minR 2
Save-J $d "Gym_Challenge_Hall_10_Evening.json"
Write-Host "  Evening 10: $(Spec-Count $d.npcs) spectators (target ~46)"

# ── EVENING 11 (Evening 10 – ~14 spectators, ~30%) ────────────────────────────
Write-Host "Creating Evening 11..."
$d = Load-J "Gym_Challenge_Hall_10_Evening.json"
$d.npcs = Remove-Spectators $d.npcs 14 -minL 1 -minT 2 -minR 1
Save-J $d "Gym_Challenge_Hall_11_Evening.json"
Write-Host "  Evening 11: $(Spec-Count $d.npcs) spectators (target ~32)"

Write-Host "`nDone."
