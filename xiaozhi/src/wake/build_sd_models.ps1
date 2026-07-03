param(
    [string]$EspSrPath = "",
    [string]$OutDir = "build_sd/srmodels"
)

$ErrorActionPreference = "Stop"

function Resolve-OptionalPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Path))
}

if ([string]::IsNullOrWhiteSpace($EspSrPath)) {
    $candidates = @(
        (Join-Path $PSScriptRoot "managed_components/espressif__esp-sr"),
        (Join-Path $PSScriptRoot "../../../managed_components/espressif__esp-sr")
    )
    if (-not [string]::IsNullOrWhiteSpace($env:ESP_SR_PATH)) {
        $candidates += $env:ESP_SR_PATH
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "model/wakenet_model/wn9s_nihaoxiaozhi/_MODEL_INFO_")) {
            $EspSrPath = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($EspSrPath)) {
    throw "ESP-SR component not found. Run IDF component install/reconfigure in xiaozhi/src/wake, or pass -EspSrPath."
}

$espSrFull = [System.IO.Path]::GetFullPath($EspSrPath)
$modelSrc = Join-Path $espSrFull "model/wakenet_model/wn9s_nihaoxiaozhi"
if (-not (Test-Path -LiteralPath (Join-Path $modelSrc "_MODEL_INFO_"))) {
    throw "wn9s_nihaoxiaozhi model not found under $modelSrc"
}

$outFull = Resolve-OptionalPath $OutDir
if ([string]::IsNullOrWhiteSpace($outFull)) {
    throw "OutDir is empty"
}

New-Item -ItemType Directory -Force -Path $outFull | Out-Null
$dest = Join-Path $outFull "wn9s_nihaoxiaozhi"
if (Test-Path -LiteralPath $dest) {
    Remove-Item -LiteralPath $dest -Recurse -Force
}
Copy-Item -LiteralPath $modelSrc -Destination $dest -Recurse

Write-Host "[wake-model] copied wn9s_nihaoxiaozhi"
Write-Host "[wake-model] source: $modelSrc"
Write-Host "[wake-model] output: $dest"
Write-Host "[wake-model] copy files under wn9s_nihaoxiaozhi to /sd/apps/xiaozhi/wake on the device"
