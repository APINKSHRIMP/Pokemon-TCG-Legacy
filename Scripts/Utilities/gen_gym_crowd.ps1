$dataPath = "C:\Pokemon TCG Legacy\NPC_and_Opponent_Data"

function Load-J($f)  { Get-Content "$dataPath\$f" -Raw | ConvertFrom-Json }
function Save-J($obj, $f) {
    $json = $obj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$dataPath\$f", $json, [System.Text.Encoding]::UTF8)
}
function npc([string]$name, [string]$sprite, [string]$pat, [int]$x, [int]$y) {
    [PSCustomObject]@{ name=$name; sprite=$sprite; meet_text=""; repeat_text=""; pattern=$pat
                       position=[PSCustomObject]@{x=$x; y=$y} }
}
# filter out named entries
function rmv($npcs, [string[]]$names) { @($npcs | Where-Object { $_.name -notin $names }) }
# append one entry
function app($npcs, $entry) { @($npcs) + @($entry) }
# remove old, add new at different position using old entry's sprite
function swap_npc($npcs, $oldName, $newName, $pat, $x, $y) {
    $old = @($npcs | Where-Object { $_.name -eq $oldName })[0]
    $sp  = if ($old) { $old.sprite } else { "NPC01" }
    $tmp = rmv $npcs @($oldName)
    app $tmp (npc $newName $sp $pat $x $y)
}
function spec_count($npcs) { ($npcs | Where-Object { $_.name -like "Spec *" }).Count }

# ── DAY 9 REVISION ─────────────────────────────────────────────────────────────
# Problem: left/right stands all have their gap at the same row (4-5),
# top stand rows 3 and 4 both missing col 5.
# Fix: spread gaps — left Col1=row2, Col2=row7, Col3=row8, Col4=row3
#                    right Col1=row1, Col2=row6, Col3=row3, Col4=row8
#                    top Row4 gap moves from col5 → col10
Write-Host "Revising Day 9..."
$d = Load-J "Gym_Challenge_Hall_9_Day.json"
$n = $d.npcs

# Left stand gap redistribution
$n = swap_npc $n "Spec L02" "Spec L04" "idle_right"        -14  187   # Col1: gap row4→row2
$n = swap_npc $n "Spec L17" "Spec L14" "idle_right"         19  203   # Col2: gap row7→row4 (wait, we WANT gap at row7: remove L17 which IS at row7, add L14 at row4)

# Actually: original Day9 had gap at row4 for Col1 (L04 missing at y=187) and we want gap at row2.
# swap_npc removes L02 (row2) and adds L04 (row4) using L02s sprite → gap moves to row2. Correct.
# For Col2: original gap was at row4 (L14 missing y=203). We want gap at row7 (y=290).
# swap_npc removes L17 (row7, y=290) and adds L14 (row4, y=203) using L17s sprite → gap at row7. Correct.

$n = swap_npc $n "Spec L35" "Spec L25" "idle_right"         51  248   # Col3: gap row8→row5 (L35 at row8 removed, L25 at row5 added)
$n = swap_npc $n "Spec L10" "Spec L19" "idle_right"         83  268   # Col4: gap row3→row5 wait...
# Col4 original: L10 at y=210 (row3) was present; L19 at y=268 (row5) was MISSING.
# swap removes L10 (row3) and adds L19 (row5) → gap moves from row5 to row3. Correct.

# Top stand: Row4 had gap at col5 (x=350); Row3 also missing col5 → looks patterned
# Move Row4 gap to col10 (x=525)
$n = swap_npc $n "Spec T30" "Spec T25" "idle_down"         350   79   # T30 at x=525 removed, T25 at x=350 added

# Right stand: all 4 cols missing row4 (very obvious). Spread:
# Col1→row1, Col2→row6, Col3→row3, Col4→row8
$n = swap_npc $n "Spec R01" "Spec R04" "idle_left"         605  250   # Col1: gap row4→row1
$n = swap_npc $n "Spec R16" "Spec R14" "idle_left"         637  231   # Col2: gap row4→row6
$n = swap_npc $n "Spec R23" "Spec R24" "idle_left"         669  214   # Col3: gap row3→row4 (R23 at row3 removed, R24 at row4 added)
$n = swap_npc $n "Spec R37" "Spec R19" "idle_left"         700  225   # Col4: gap row5→row8

$d.npcs = $n
Save-J $d "Gym_Challenge_Hall_9_Day.json"
Write-Host "  Day 9 done: $(spec_count $n) spectators"

# ── EVENING 9 REVISION ─────────────────────────────────────────────────────────
# Problems: top stand cols 2&4 entirely absent, cols 7&9 nearly empty;
#           right stand row 8 completely empty; left Col1=Col4 identical pattern, Col3 all-odd
Write-Host "Revising Evening 9..."
$d = Load-J "Gym_Challenge_Hall_9_Evening.json"
$n = $d.npcs

# ─ TOP STAND: full replacement with even distribution ─
# Original: cols 1,3,5,8 all full; cols 2,4 empty; cols 7,9 nearly empty
# New pattern: each row uses 6 different columns, no column entirely absent
# Row1: cols 1,3,5,6,8,9   (x=210,280,350,385,455,490)
# Row2: cols 2,4,6,7,9,10  (x=245,315,385,420,490,525)
# Row3: cols 1,4,5,7,8,10  (x=210,315,350,420,455,525)
# Row4: cols 2,3,6,8,9,10  (x=245,280,385,455,490,525)
# Column totals: cols 1-10 get 2,2,2,2,2,3,2,3,3,3 entries (max 3, no zeros)
$n = @($n | Where-Object { $_.name -notmatch "^Spec T" })
$newT = @(
    # Row 1 (y=-15) — sprites from original Row1
    (npc "Spec T31" "NPC 03"           "idle_down_random" 210 -15),
    (npc "Spec T33" "NPC 07"           "idle_down"        280 -15),
    (npc "Spec T35" "Lass"             "idle_down_random" 350 -15),
    (npc "Spec T36" "NPC 85"           "idle_down"        385 -15),
    (npc "Spec T38" "Beauty"           "idle_down"        455 -15),
    (npc "Spec T39" "NPC 88"           "idle_down"        490 -15),
    # Row 2 (y=15) — sprites from original Row2
    (npc "Spec T02" "Parasollady"      "idle_down"        245  15),
    (npc "Spec T04" "Bugcatcher"       "idle_down"        315  15),
    (npc "Spec T06" "NPC 87"           "idle_down_random" 385  15),
    (npc "Spec T07" "ParasolLady2"     "idle_down"        420  15),
    (npc "Spec T09" "NPC 04"           "idle_down"        490  15),
    (npc "Spec T10" "NPC 09"           "idle_down"        525  15),
    # Row 3 (y=47) — sprites from original Row3
    (npc "Spec T11" "Pokemonbreeder_M" "idle_down_random" 210  47),
    (npc "Spec T14" "NPC 90"           "idle_down"        315  47),
    (npc "Spec T15" "Lass2"            "idle_down"        350  47),
    (npc "Spec T17" "Bugcatcher2"      "idle_down_random" 420  47),
    (npc "Spec T18" "NPC 86"           "idle_down"        455  47),
    (npc "Spec T20" "NPC 05"           "idle_down"        525  47),
    # Row 4 (y=79) — sprites from original Row4
    (npc "Spec T22" "NPC 89"           "idle_down"        245  79),
    (npc "Spec T23" "NPC 06"           "idle_down"        280  79),
    (npc "Spec T26" "Cyclist_M"        "idle_down_random" 385  79),
    (npc "Spec T28" "NPC 02"           "idle_down"        455  79),
    (npc "Spec T29" "Lass3"            "idle_down"        490  79),
    (npc "Spec T30" "NPC 08"           "idle_down"        525  79)
)
$n = @($n) + $newT

# ─ LEFT STAND ─
# Fix Col1=Col4 identical gap pattern, fix Col3 all-odd-rows
$n = swap_npc $n "Spec L06" "Spec L07" "idle_right"        -14  274   # Col1: gap row6→row7
$n = rmv $n @("Spec L15", "Spec L33")
$n = app $n (npc "Spec L16" "NPC22"    "idle_right"          19  261)  # Col2: redistribute
$n = app $n (npc "Spec L34" "Juggler"  "idle_right"          19  348)
$n = swap_npc $n "Spec L21" "Spec L22" "idle_right_random"   51  161   # Col3: row1→row2
$n = swap_npc $n "Spec L19" "Spec L11" "idle_right"          83  239   # Col4: row5→row4

# ─ RIGHT STAND ─
# Fix row 8 completely absent and Col1=Col4 identical pattern
$n = swap_npc $n "Spec R32" "Spec R31" "idle_left_random"   605  366   # Col1: row9→row8
$n = rmv $n @("Spec R34")                                               # Col2: trim to 5
$n = rmv $n @("Spec R18", "Spec R28")
$n = app $n (npc "Spec R19" "Cooltrainer_M2" "idle_left"        700  225) # Col4: row5
$n = app $n (npc "Spec R37" "Supernerd"      "idle_left_random"  700  312) # Col4: row8

$d.npcs = $n
Save-J $d "Gym_Challenge_Hall_9_Evening.json"
Write-Host "  Evening 9 done: $(spec_count $n) spectators"

# ── DAY 10 (Day 9 - 20 spectators, ~20%) ───────────────────────────────────────
Write-Host "Creating Day 10..."
$d = Load-J "Gym_Challenge_Hall_9_Day.json"
$d.npcs = rmv $d.npcs @(
    # Left: 6 removed — spread across cols and different rows
    "Spec L04","Spec L31",       # Col1 rows 4,8
    "Spec L14",                  # Col2 row 4
    "Spec L24","Spec L27",       # Col3 rows 4,7
    "Spec L09",                  # Col4 row 2
    # Top: 7 removed — 2 from each of rows 1-3, 1 from row 4
    "Spec T32","Spec T39",       # Row1 cols 2,9
    "Spec T05","Spec T10",       # Row2 cols 5,10
    "Spec T11","Spec T19",       # Row3 cols 1,9
    "Spec T27",                  # Row4 col 7
    # Right: 7 removed — spread across cols
    "Spec R03","Spec R32",       # Col1 rows 3,9
    "Spec R11","Spec R15",       # Col2 rows 1,5
    "Spec R22","Spec R36",       # Col3 rows 2,9
    "Spec R09"                   # Col4 row 2
)
Save-J $d "Gym_Challenge_Hall_10_Day.json"
Write-Host "  Day 10: $(spec_count $d.npcs) spectators (target ~80)"

# ── DAY 11 (Day 10 - 16 spectators, ~20%) ──────────────────────────────────────
Write-Host "Creating Day 11..."
$d = Load-J "Gym_Challenge_Hall_10_Day.json"
$d.npcs = rmv $d.npcs @(
    # Left: 5 removed
    "Spec L06","Spec L13","Spec L34","Spec L23","Spec L28",
    # Top: 6 removed — spread across all 4 rows
    "Spec T33","Spec T38",       # Row1
    "Spec T01","Spec T08",       # Row2
    "Spec T14",                  # Row3
    "Spec T28",                  # Row4
    # Right: 5 removed
    "Spec R07","Spec R33",       # Col1,2
    "Spec R24","Spec R27",       # Col3
    "Spec R20"                   # Col4
)
Save-J $d "Gym_Challenge_Hall_11_Day.json"
Write-Host "  Day 11: $(spec_count $d.npcs) spectators (target ~64)"

# ── EVENING 10 (Evening 9 - 20 spectators, ~30%) ───────────────────────────────
Write-Host "Creating Evening 10..."
$d = Load-J "Gym_Challenge_Hall_9_Evening.json"
$d.npcs = rmv $d.npcs @(
    # Left: 7 removed
    "Spec L01","Spec L31",       # Col1
    "Spec L16",                  # Col2
    "Spec L23","Spec L27",       # Col3
    "Spec L10","Spec L37",       # Col4
    # Top: 7 removed
    "Spec T35","Spec T38",       # Row1
    "Spec T04","Spec T09",       # Row2
    "Spec T11","Spec T17",       # Row3
    "Spec T30",                  # Row4
    # Right: 6 removed
    "Spec R04","Spec R31",       # Col1
    "Spec R14",                  # Col2
    "Spec R25","Spec R27",       # Col3
    "Spec R20"                   # Col4
)
Save-J $d "Gym_Challenge_Hall_10_Evening.json"
Write-Host "  Evening 10: $(spec_count $d.npcs) spectators (target ~46)"

# ── EVENING 11 (Evening 10 - 14 spectators, ~30%) ──────────────────────────────
Write-Host "Creating Evening 11..."
$d = Load-J "Gym_Challenge_Hall_10_Evening.json"
$d.npcs = rmv $d.npcs @(
    # Left: 5 removed
    "Spec L07","Spec L34","Spec L22","Spec L11","Spec L38",
    # Top: 5 removed
    "Spec T36",                  # Row1
    "Spec T07",                  # Row2
    "Spec T18",                  # Row3
    "Spec T26","Spec T29",       # Row4
    # Right: 4 removed
    "Spec R07",                  # Col1
    "Spec R11",                  # Col2
    "Spec R22",                  # Col3
    "Spec R38"                   # Col4
)
Save-J $d "Gym_Challenge_Hall_11_Evening.json"
Write-Host "  Evening 11: $(spec_count $d.npcs) spectators (target ~32)"

# ── NIGHT 10 (Night 9 - 6 spectators, 50%) ─────────────────────────────────────
Write-Host "Creating Night 10..."
$d = Load-J "Gym_Challenge_Hall_9_Night.json"
$d.npcs = rmv $d.npcs @(
    "Spec L15","Spec L20",       # Left: 2 of 4
    "Spec T07","Spec T18",       # Top: 2 of 4
    "Spec R06","Spec R15"        # Right: 2 of 3
)
Save-J $d "Gym_Challenge_Hall_10_Night.json"
Write-Host "  Night 10: $(spec_count $d.npcs) spectators (target ~5)"

# ── NIGHT 11 (Night 10 - 2 spectators, ~50%) ───────────────────────────────────
Write-Host "Creating Night 11..."
$d = Load-J "Gym_Challenge_Hall_10_Night.json"
$d.npcs = rmv $d.npcs @("Spec L25", "Spec T23")
Save-J $d "Gym_Challenge_Hall_11_Night.json"
Write-Host "  Night 11: $(spec_count $d.npcs) spectators (target ~3)"

Write-Host "`nAll files written successfully."
