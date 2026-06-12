# md_to_pdf.ps1 — convert a markdown file to PDF via HTML + headless Edge.
# Usage: .\md_to_pdf.ps1 -MarkdownPath "C:\path\file.md" [-PdfPath "C:\path\file.pdf"]
# Supports: # headers, tables (with \| escapes), fenced code blocks, inline code,
# bold/italic, blockquotes, bullet/numbered lists, horizontal rules.

param(
	[Parameter(Mandatory = $true)][string]$MarkdownPath,
	[string]$PdfPath = ""
)

if ($PdfPath -eq "") {
	$PdfPath = [System.IO.Path]::ChangeExtension($MarkdownPath, ".pdf")
}
$htmlPath = [System.IO.Path]::ChangeExtension($MarkdownPath, ".tmp.html")

function Escape-Html([string]$s) {
	return $s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
}

# Inline markdown -> HTML (run on already-escaped text).
function Convert-Inline([string]$s) {
	# Protect inline code spans first so ** and * inside them are untouched
	$codeSpans = @()
	$s = [regex]::Replace($s, '`([^`]+)`', {
		param($m)
		$script:codeSpans += "<code>$($m.Groups[1].Value)</code>"
		"`u{E000}$($script:codeSpans.Count - 1)`u{E001}"
	})
	$s = [regex]::Replace($s, '\*\*(.+?)\*\*', '<strong>$1</strong>')
	$s = [regex]::Replace($s, '(?<!\*)\*([^*]+)\*(?!\*)', '<em>$1</em>')
	# Restore code spans
	$s = [regex]::Replace($s, "`u{E000}(\d+)`u{E001}", {
		param($m)
		$script:codeSpans[[int]$m.Groups[1].Value]
	})
	return $s
}

$lines = Get-Content -Path $MarkdownPath -Encoding UTF8
$out = New-Object System.Collections.Generic.List[string]

$inCode = $false
$inTable = $false
$inList = ""   # "", "ul" or "ol"
$inQuote = $false
$paraBuf = @()

function Flush-Para {
	if ($script:paraBuf.Count -gt 0) {
		$joined = ($script:paraBuf -join " ")
		$script:out.Add("<p>" + (Convert-Inline $joined) + "</p>")
		$script:paraBuf = @()
	}
}
function Close-Blocks {
	Flush-Para
	if ($script:inTable) { $script:out.Add("</table>"); $script:inTable = $false }
	if ($script:inList -ne "") { $script:out.Add("</$($script:inList)>"); $script:inList = "" }
	if ($script:inQuote) { $script:out.Add("</blockquote>"); $script:inQuote = $false }
}

foreach ($raw in $lines) {
	$line = $raw

	# ── fenced code blocks ──
	if ($line -match '^\s*```') {
		if ($inCode) { $out.Add("</code></pre>"); $inCode = $false }
		else { Close-Blocks; $out.Add("<pre><code>"); $inCode = $true }
		continue
	}
	if ($inCode) { $out.Add((Escape-Html $line)); continue }

	# ── blank line ──
	if ($line.Trim() -eq "") { Close-Blocks; continue }

	# ── horizontal rule ──
	if ($line -match '^\s*---+\s*$') { Close-Blocks; $out.Add("<hr/>"); continue }

	# ── headers ──
	if ($line -match '^(#{1,6})\s+(.*)$') {
		Close-Blocks
		$level = $Matches[1].Length
		$text = Convert-Inline (Escape-Html $Matches[2])
		$out.Add("<h$level>$text</h$level>")
		continue
	}

	# ── blockquote ──
	if ($line -match '^\s*>\s?(.*)$') {
		Flush-Para
		if ($inTable) { $out.Add("</table>"); $inTable = $false }
		if ($inList -ne "") { $out.Add("</$inList>"); $inList = "" }
		if (-not $inQuote) { $out.Add("<blockquote>"); $inQuote = $true }
		$out.Add("<p>" + (Convert-Inline (Escape-Html $Matches[1])) + "</p>")
		continue
	}
	if ($inQuote) { $out.Add("</blockquote>"); $inQuote = $false }

	# ── tables ──
	if ($line -match '^\s*\|') {
		Flush-Para
		if ($inList -ne "") { $out.Add("</$inList>"); $inList = "" }
		# separator row |---|---|
		if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }
		$isHeader = -not $inTable
		if (-not $inTable) { $out.Add("<table>"); $inTable = $true }
		# protect escaped pipes, then split cells
		$work = $line.Trim().Trim('|')
		$work = $work.Replace('\|', "`u{E002}")
		$cells = $work -split '\|'
		$tag = if ($isHeader) { "th" } else { "td" }
		$row = "<tr>"
		foreach ($c in $cells) {
			$cellText = $c.Trim().Replace("`u{E002}", "|")
			$row += "<$tag>" + (Convert-Inline (Escape-Html $cellText)) + "</$tag>"
		}
		$row += "</tr>"
		$out.Add($row)
		continue
	}
	if ($inTable) { $out.Add("</table>"); $inTable = $false }

	# ── lists ──
	if ($line -match '^\s*[-*]\s+(.*)$') {
		Flush-Para
		if ($inList -eq "ol") { $out.Add("</ol>"); $inList = "" }
		if ($inList -eq "") { $out.Add("<ul>"); $inList = "ul" }
		$out.Add("<li>" + (Convert-Inline (Escape-Html $Matches[1])) + "</li>")
		continue
	}
	if ($line -match '^\s*\d+\.\s+(.*)$') {
		Flush-Para
		if ($inList -eq "ul") { $out.Add("</ul>"); $inList = "" }
		if ($inList -eq "") { $out.Add("<ol>"); $inList = "ol" }
		$out.Add("<li>" + (Convert-Inline (Escape-Html $Matches[1])) + "</li>")
		continue
	}
	if ($inList -ne "") { $out.Add("</$inList>"); $inList = "" }

	# ── plain paragraph text (soft-wrapped) ──
	$paraBuf += (Escape-Html $line.Trim())
}
Close-Blocks
if ($inCode) { $out.Add("</code></pre>") }

$style = @'
<style>
  body { font-family: "Segoe UI", Arial, sans-serif; font-size: 10.5pt; color: #1a1a1a;
         max-width: 100%; margin: 0; line-height: 1.45; }
  h1 { font-size: 20pt; border-bottom: 3px solid #2c5f8a; padding-bottom: 6px; color: #1c3d5a; }
  h2 { font-size: 15pt; border-bottom: 1.5px solid #b8cfe0; padding-bottom: 4px;
       color: #1c3d5a; margin-top: 26px; page-break-after: avoid; }
  h3 { font-size: 12pt; color: #2c5f8a; margin-top: 18px; page-break-after: avoid; }
  code { font-family: Consolas, "Courier New", monospace; font-size: 9pt;
         background: #f0f3f6; padding: 1px 4px; border-radius: 3px; }
  pre { background: #f6f8fa; border: 1px solid #d8dee4; border-radius: 5px;
        padding: 10px 12px; overflow-x: auto; page-break-inside: avoid; }
  pre code { background: none; padding: 0; font-size: 8.5pt; white-space: pre; }
  table { border-collapse: collapse; width: 100%; margin: 10px 0; page-break-inside: avoid; }
  th, td { border: 1px solid #c4ced6; padding: 5px 8px; text-align: left;
           vertical-align: top; font-size: 9.5pt; }
  th { background: #e8eef4; color: #1c3d5a; }
  tr:nth-child(even) td { background: #f7f9fb; }
  blockquote { border-left: 4px solid #2c5f8a; background: #eef4f9;
               margin: 10px 0; padding: 6px 14px; }
  hr { border: none; border-top: 1px solid #c4ced6; margin: 22px 0; }
  @page { margin: 18mm 14mm; }
</style>
'@

$html = "<!DOCTYPE html><html><head><meta charset=`"utf-8`">$style</head><body>" + ($out -join "`n") + "</body></html>"
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding $false))

$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
$fileUrl = "file:///" + $htmlPath.Replace("\", "/").Replace(" ", "%20")
& $edge --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="$PdfPath" $fileUrl | Out-Null
Start-Sleep -Seconds 2

Remove-Item $htmlPath -Force -Confirm:$false
if (Test-Path $PdfPath) {
	$size = (Get-Item $PdfPath).Length
	Write-Output "PDF written: $PdfPath ($([math]::Round($size/1KB)) KB)"
} else {
	Write-Error "PDF was not produced."
}
