param(
  [string]$FontPath = 'C:\Windows\Fonts\msyh.ttc',
  [string]$NodePath = $env:NODE_EXE,
  [string]$ConverterPath = $env:LV_FONT_CONV_JS
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$charsetScript = Join-Path $scriptDir 'refresh_common_4000_charset.py'
$charsetPath = Join-Path $scriptDir 'msyh_cn_4000_charset.txt'
$smallOutputPath = Join-Path $scriptDir 'msyh_cn_13.bin'
$bigOutputPath = Join-Path $scriptDir '18chinese.bin'

if (-not (Test-Path -LiteralPath $FontPath)) {
  throw "Missing Microsoft YaHei source font: $FontPath"
}

$actualFontPath = $FontPath
if ([System.IO.Path]::GetExtension($FontPath).ToLowerInvariant() -eq '.ttc') {
  $tempDir = Join-Path $env:TEMP 'music_player_font_build'
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  $actualFontPath = Join-Path $tempDir 'msyh_face0.ttf'
  $extractScript = @'
import sys
from fontTools.ttLib import TTFont

src, dst = sys.argv[1], sys.argv[2]
font = TTFont(src, fontNumber=0)
font.save(dst)
'@
  $extractScript | python - $FontPath $actualFontPath
  if (-not (Test-Path -LiteralPath $actualFontPath)) {
    throw "Failed to extract TTF from TTC: $FontPath"
  }
}

python $charsetScript

if (-not (Test-Path -LiteralPath $charsetPath)) {
  throw "Charset file was not generated: $charsetPath"
}

$symbols = [System.IO.File]::ReadAllText($charsetPath, [System.Text.UTF8Encoding]::new($false)).TrimEnd()
$nonAsciiSymbols = -join ($symbols.ToCharArray() | Where-Object { [int]$_ -gt 127 })
if ([string]::IsNullOrEmpty($nonAsciiSymbols)) {
  throw "Filtered non-ASCII symbols are empty: $charsetPath"
}

if ([string]::IsNullOrWhiteSpace($NodePath)) {
  $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
  if ($nodeCommand) {
    $NodePath = $nodeCommand.Source
  }
}

if ([string]::IsNullOrWhiteSpace($ConverterPath)) {
  $localConverter = Join-Path $scriptDir 'node_modules\lv_font_conv\lv_font_conv.js'
  if (Test-Path -LiteralPath $localConverter) {
    $ConverterPath = $localConverter
  }
}

if ([string]::IsNullOrWhiteSpace($NodePath) -or -not (Test-Path -LiteralPath $NodePath)) {
  throw "Missing node.exe. Set NODE_EXE or put node on PATH."
}
if ([string]::IsNullOrWhiteSpace($ConverterPath) -or -not (Test-Path -LiteralPath $ConverterPath)) {
  throw "Missing lv_font_conv.js. Set LV_FONT_CONV_JS or install lv_font_conv under this font directory."
}

function Build-Font {
  param(
    [int]$Size,
    [string]$OutputPath
  )

  Write-Host "[font] font   = $FontPath"
  Write-Host "[font] actual = $actualFontPath"
  Write-Host "[font] output = $OutputPath"
  Write-Host "[font] size   = $Size"
  Write-Host "[font] chars  = $($symbols.Length)"

  & $NodePath $ConverterPath `
    --size $Size `
    --bpp 2 `
    --format bin `
    --font $actualFontPath `
    -r 0x20-0x7F `
    --symbols $nonAsciiSymbols `
    --no-kerning `
    -o $OutputPath

  if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "Font build failed, output file missing: $OutputPath"
  }

  $item = Get-Item -LiteralPath $OutputPath
  Write-Host "[font] done = $($item.FullName)"
  Write-Host "[font] size = $($item.Length) bytes"
}

Build-Font -Size 13 -OutputPath $smallOutputPath
Build-Font -Size 16 -OutputPath $bigOutputPath
