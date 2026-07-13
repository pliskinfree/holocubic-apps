param(
  [string]$ConverterPath = 'E:\cubicsrc\cubic_lua\cubic_arduino\cubic-develop\.tools\lv_font_conv\node_modules\lv_font_conv\lv_font_conv.js'
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$node = (Get-Command node -ErrorAction Stop).Source
$temp = Join-Path $env:TEMP 'cubic_i18n_fonts'
New-Item -ItemType Directory -Force -Path $temp | Out-Null

if (-not (Test-Path -LiteralPath $ConverterPath)) {
  throw "Missing LVGL font converter: $ConverterPath"
}

python (Join-Path $PSScriptRoot 'generate_i18n_charsets.py')

function Get-NotoFont {
  param([string]$Name, [string]$Url)
  $output = Join-Path $temp $Name
  if (-not (Test-Path -LiteralPath $output)) {
    Write-Host "[font] download $Name"
    Invoke-WebRequest -Uri $Url -OutFile $output
  }
  return $output
}

$rawRoot = 'https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF'
$scFont = Get-NotoFont 'NotoSansCJKsc-Medium.otf' "$rawRoot/SimplifiedChinese/NotoSansCJKsc-Medium.otf"
$twFont = Get-NotoFont 'NotoSansCJKtc-Medium.otf' "$rawRoot/TraditionalChinese/NotoSansCJKtc-Medium.otf"
$jaFont = Get-NotoFont 'NotoSansCJKjp-Medium.otf' "$rawRoot/Japanese/NotoSansCJKjp-Medium.otf"
$licensePath = Join-Path $temp 'OFL-NotoSansCJK.txt'
if (-not (Test-Path -LiteralPath $licensePath)) {
  Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE' -OutFile $licensePath
}
foreach ($fontDir in @('launcher\package\font', 'BTC\package\font', 'weather\package\font')) {
  Copy-Item -LiteralPath $licensePath -Destination (Join-Path $root "$fontDir\OFL-NotoSansCJK.txt") -Force
}

$fonts = @{
  zh_cn = $scFont
  zh_tw = $twFont
  ja = $jaFont
}

$targets = @(
  @{ Locale='zh_cn'; Size=16; Output='launcher\package\font\launcher_ui_zh_cn_16.bin' },
  @{ Locale='zh_tw'; Size=16; Output='launcher\package\font\launcher_ui_zh_tw_16.bin' },
  @{ Locale='ja'; Size=16; Output='launcher\package\font\launcher_ui_ja_16.bin' },
  @{ Locale='zh_cn'; Size=12; Output='BTC\package\font\btc_ui_zh_cn_12.bin' },
  @{ Locale='zh_tw'; Size=12; Output='BTC\package\font\btc_ui_zh_tw_12.bin' },
  @{ Locale='ja'; Size=12; Output='BTC\package\font\btc_ui_ja_12.bin' },
  @{ Locale='zh_cn'; Size=12; Output='weather\package\font\weather_ui_zh_cn_12.bin' },
  @{ Locale='zh_cn'; Size=16; Output='weather\package\font\weather_ui_zh_cn_16.bin' },
  @{ Locale='zh_tw'; Size=12; Output='weather\package\font\weather_ui_zh_tw_12.bin' },
  @{ Locale='zh_tw'; Size=16; Output='weather\package\font\weather_ui_zh_tw_16.bin' },
  @{ Locale='ja'; Size=12; Output='weather\package\font\weather_ui_ja_12.bin' },
  @{ Locale='ja'; Size=16; Output='weather\package\font\weather_ui_ja_16.bin' }
)

foreach ($target in $targets) {
  $charset = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot ("charset_{0}.txt" -f $target.Locale)), [System.Text.UTF8Encoding]::new($false))
  $output = Join-Path $root $target.Output
  Write-Host "[font] $($target.Locale) $($target.Size)px -> $output"
  & $node $ConverterPath `
    --size $target.Size `
    --bpp 2 `
    --format bin `
    --font $fonts[$target.Locale] `
    -r 0x20-0x7F `
    --symbols $charset `
    --no-kerning `
    -o $output
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) {
    throw "Font build failed: $output"
  }
}

Get-Item ($targets | ForEach-Object { Join-Path $root $_.Output }) | Select-Object Name,Length,FullName
