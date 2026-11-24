"""Move in-game bug reports into Spreadsheets/Issue_Log.xlsx (Game_Issues tab).

The DEL menu's REPORT BUG box (Scripts/Utilities/Bug_Report.gd) appends one JSON line per
report to Spreadsheets/_pending_bug_reports.jsonl and then runs this script. Each pending
report becomes a new row at the bottom of Game_Issues:

    A  #                 the number already pre-filled on that row, else the highest + 1
    D  Issue             the typed text
    G  Status            "New Issue"
    H  Logged            the report's date (DD/MM/YYYY text, like the rest of the sheet)
    K  Report Context    the game snapshot -- a HIDDEN column, for Claude, not the user

Category / Sub Cat are left blank for "fix issues" to fill in.

The pending file is emptied only after the workbook saved, so a report made while Excel
has the file open stays queued for the next run. Also run at the start of "fix issues":

    py -3 Scripts/Utilities/bug_report_import.py

Exit codes: 0 done (prints "ADDED #n" per row, or "NOTHING PENDING"), 3 workbook locked
(open in Excel), 1 anything else.
"""
import json
import os
import sys

import openpyxl

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
XLSX = os.path.join(ROOT, "Spreadsheets", "Issue_Log.xlsx")
PENDING = os.path.join(ROOT, "Spreadsheets", "_pending_bug_reports.jsonl")
SHEET = "Game_Issues"
COL_NUM, COL_ISSUE, COL_STATUS, COL_LOGGED, COL_CONTEXT = 1, 4, 7, 8, 11
CONTEXT_HEADER = "Report Context"
MAX_CELL = 32000


def main() -> int:
    if not os.path.exists(PENDING):
        print("NOTHING PENDING")
        return 0
    with open(PENDING, encoding="utf-8") as f:
        raw = [line for line in f.read().splitlines() if line.strip()]
    entries = []
    for line in raw:
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError as e:
            print(f"SKIPPED unreadable line: {e}")
    if not entries:
        open(PENDING, "w", encoding="utf-8").close()
        print("NOTHING PENDING")
        return 0

    wb = openpyxl.load_workbook(XLSX)
    ws = wb[SHEET]
    if ws.cell(1, COL_CONTEXT).value != CONTEXT_HEADER:
        ws.cell(1, COL_CONTEXT).value = CONTEXT_HEADER
    ws.column_dimensions["K"].hidden = True

    added = []
    for entry in entries:
        filled = [r for r in range(2, ws.max_row + 1) if ws.cell(r, COL_ISSUE).value not in (None, "")]
        row = (max(filled) if filled else 1) + 1
        used = [ws.cell(r, COL_NUM).value for r in filled]
        top = max([n for n in used if isinstance(n, (int, float))] or [0])
        pre = ws.cell(row, COL_NUM).value
        num = int(pre) if isinstance(pre, (int, float)) and pre > top else int(top) + 1
        ws.cell(row, COL_NUM).value = num
        ws.cell(row, COL_ISSUE).value = str(entry.get("text", "")).strip()
        ws.cell(row, COL_STATUS).value = "New Issue"
        ws.cell(row, COL_LOGGED).value = str(entry.get("logged", ""))
        ws.cell(row, COL_CONTEXT).value = str(entry.get("context", ""))[:MAX_CELL]
        added.append(num)

    try:
        wb.save(XLSX)
    except PermissionError:
        print("LOCKED: Issue_Log.xlsx is open in another program; reports kept in the pending file")
        return 3
    open(PENDING, "w", encoding="utf-8").close()
    for num in added:
        print(f"ADDED #{num}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001 - one line back to the game is all that's needed
        print(f"ERROR: {type(e).__name__}: {e}")
        sys.exit(1)
