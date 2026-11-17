#!/usr/bin/env bash
# Descarga los modelos grandes que no se versionan en Git.
#
# Uso (desde la raíz del repo):
#   bash tool/fetch_models.sh
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p assets/models assets/tts/es_female assets/tts/es_male

# --- LLM local (Qwen3.5 0.8B Q4_K_M, Apache-2.0) -----------------------------
LLM="assets/models/Qwen3.5-0.8B-Q4_K_M.gguf"
if [ -f "$LLM" ]; then
  echo "LLM ya presente: $LLM"
else
  echo "Descargando LLM (~508 MB)..."
  curl -L --retry 3 -o "$LLM" \
    'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf'
fi

# --- Voces Piper (Apache-2.0) ------------------------------------------------
fetch_voice() {
  url="$1"
  dest="$2"

  if [ -f "$dest/model.onnx" ] && [ -f "$dest/tokens.txt" ]; then
    echo "Voz ya presente: $dest"
    return
  fi

  echo "Descargando voz: $url"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  curl -L --retry 3 -o "$tmp/voice.tar.bz2" "$url"
  tar -xjf "$tmp/voice.tar.bz2" -C "$tmp"

  onnx="$(find "$tmp" -name '*.onnx' | head -n 1)"
  tokens="$(find "$tmp" -name 'tokens.txt' | head -n 1)"
  if [ -z "$onnx" ] || [ -z "$tokens" ]; then
    echo "El archivo descargado no contiene model.onnx/tokens.txt" >&2
    return 1
  fi

  cp "$onnx" "$dest/model.onnx"
  cp "$tokens" "$dest/tokens.txt"
}

fetch_voice \
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_MX-claude-high-int8.tar.bz2' \
  'assets/tts/es_female'

fetch_voice \
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_ES-davefx-medium-int8.tar.bz2' \
  'assets/tts/es_male'

echo "Listo. Ahora puedes ejecutar: flutter pub get && flutter run"
