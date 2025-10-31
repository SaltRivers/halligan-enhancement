#!/bin/bash

set -euo pipefail

# ---- Config ----
ZIP_URL="https://huggingface.co/code-philia/halligan-models/resolve/main/models.zip?download=true"  # 🔁 Replace this
ZIP_FILE="models.zip"
ZIP_SHA256=""
TARGET_DIR="halligan/models"
CACHE_DIR=".cache/models"

# ---- Go to script directory ----
cd "$(dirname "$0")"

# ---- Download .zip ----
mkdir -p "$CACHE_DIR"

echo "Downloading $ZIP_URL (resumable)..."
if [ -f "$CACHE_DIR/$ZIP_FILE" ]; then
  echo "Found cached archive at $CACHE_DIR/$ZIP_FILE"
else
  curl -L -C - "$ZIP_URL" -o "$CACHE_DIR/$ZIP_FILE"
fi

# Optional checksum
if [ -n "$ZIP_SHA256" ]; then
  echo "$ZIP_SHA256  $CACHE_DIR/$ZIP_FILE" | shasum -a 256 -c -
fi

cp "$CACHE_DIR/$ZIP_FILE" "$ZIP_FILE"

# ---- Unzip (creates /models) ----
echo "Unzipping $ZIP_FILE..."
unzip -q -o "$ZIP_FILE"

# ---- Replace target directory ----
echo "Replacing $TARGET_DIR..."
rm -rf "$TARGET_DIR"
mkdir -p "$(dirname "$TARGET_DIR")"
mv models "$TARGET_DIR"

# ---- Clean up ----
rm -f "$ZIP_FILE"

echo "✅ Update complete."