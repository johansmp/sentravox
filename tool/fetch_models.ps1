# Descarga los modelos grandes que no se versionan en Git.
#
# Uso (desde la raíz del repo):
#   powershell -ExecutionPolicy Bypass -File tool/fetch_models.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

New-Item -ItemType Directory -Force -Path 'assets/models' | Out-Null
New-Item -ItemType Directory -Force -Path 'assets/tts/es_female' | Out-Null
New-Item -ItemType Directory -Force -Path 'assets/tts/es_male' | Out-Null

# --- LLM local (Qwen3.5 0.8B Q4_K_M, Apache-2.0) -----------------------------
$llm = 'assets/models/Qwen3.5-0.8B-Q4_K_M.gguf'
if (Test-Path $llm) {
    Write-Host "LLM ya presente: $llm"
} else {
    Write-Host 'Descargando LLM (~508 MB)...'
    curl.exe -L --retry 3 -o $llm `
        'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf'
}

# --- Voces Piper (Apache-2.0) ------------------------------------------------
function Get-PiperVoice {
    param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    if ((Test-Path "$Destination/model.onnx") -and
        (Test-Path "$Destination/tokens.txt")) {
        Write-Host "Voz ya presente: $Destination"
        return
    }

    Write-Host "Descargando voz: $Url"
    $tmp = Join-Path $env:TEMP ("sentravox_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    try {
        $archive = Join-Path $tmp 'voice.tar.bz2'
        curl.exe -L --retry 3 -o $archive $Url
        tar -xjf $archive -C $tmp

        $onnx = Get-ChildItem $tmp -Recurse -Filter '*.onnx' |
            Select-Object -First 1
        $tokens = Get-ChildItem $tmp -Recurse -Filter 'tokens.txt' |
            Select-Object -First 1
        if (-not $onnx -or -not $tokens) {
            throw "El archivo descargado no contiene model.onnx/tokens.txt"
        }

        Copy-Item $onnx.FullName (Join-Path $Destination 'model.onnx') -Force
        Copy-Item $tokens.FullName (Join-Path $Destination 'tokens.txt') -Force
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Get-PiperVoice `
    -Url 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_MX-claude-high-int8.tar.bz2' `
    -Destination 'assets/tts/es_female'

Get-PiperVoice `
    -Url 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_ES-davefx-medium-int8.tar.bz2' `
    -Destination 'assets/tts/es_male'

Write-Host 'Listo. Ahora puedes ejecutar: flutter pub get; flutter run'
