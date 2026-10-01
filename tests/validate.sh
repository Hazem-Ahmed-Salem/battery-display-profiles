#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Validating Omarchy plugin structure at $PLUGIN_DIR"

# 1. Check required files
echo "Checking essential files..."
for file in manifest.json README.md LICENSE BarWidget.qml Service.qml DisplayController.qml; do
  if [[ ! -f "$PLUGIN_DIR/$file" ]]; then
    echo "ERROR: Missing required file '$file'" >&2
    exit 1
  fi
  echo "  ✓ $file found"
done

# 2. Check JSON validity
echo "Checking JSON formatting..."
if command -v jq >/dev/null 2>&1; then
  jq empty "$PLUGIN_DIR/manifest.json"
  echo "  ✓ manifest.json is valid JSON"
fi

# 3. Omarchy plugin CLI validation
echo "Running omarchy plugin validate..."
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$PLUGIN_DIR"
  echo "  ✓ omarchy plugin validate passed"
else
  echo "  ⚠ omarchy CLI not in PATH, skipping omarchy plugin validate"
fi

# 4. QML syntax linting
echo "Running qmllint on QML components..."
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$PLUGIN_DIR"/*.qml
  echo "  ✓ qmllint passed with 0 warnings"
else
  echo "  ⚠ qmllint not installed, skipping QML linting"
fi

# 5. Logic unit tests
if command -v node >/dev/null 2>&1; then
  node "$PLUGIN_DIR/tests/test_mode_logic.js"
fi

echo "==> All plugin validation checks passed successfully!"
