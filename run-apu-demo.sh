#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NP_DIR="$ROOT_DIR/mtk-neuropilot-prebuilts"
DEMO_DIR="$NP_DIR/sample/usr/share/demo_dla"

NEURON_BIN_DIR="$NP_DIR/neuron/6/usr/sbin"
MDW_BIN_DIR="$NP_DIR/mdw/android13/usr/sbin"
NEURON_LIB_DIR="$NP_DIR/neuron/6/usr/lib64"
MDW_LIB_DIR="$NP_DIR/mdw/android13/usr/lib64"
VENV_PYTHON="$ROOT_DIR/.venv/bin/python"

PYTHON_BIN="python3"
if [[ -x "$VENV_PYTHON" ]]; then
    PYTHON_BIN="$VENV_PYTHON"
fi

if [[ ! -x "$NEURON_BIN_DIR/ncc-tflite" ]]; then
    echo "Missing compiler: $NEURON_BIN_DIR/ncc-tflite" >&2
    exit 1
fi

if [[ ! -x "$NEURON_BIN_DIR/runtime_api_sample" ]]; then
    echo "Missing runtime sample: $NEURON_BIN_DIR/runtime_api_sample" >&2
    exit 1
fi

if [[ ! -f "$DEMO_DIR/label_image.py" ]]; then
    echo "Missing demo script: $DEMO_DIR/label_image.py" >&2
    exit 1
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "Python interpreter not found: $PYTHON_BIN" >&2
    exit 1
fi

if ! "$PYTHON_BIN" -c 'import numpy; from PIL import Image' >/dev/null 2>&1; then
    echo "Install Python dependencies into .venv: $ROOT_DIR/.venv/bin/pip install numpy Pillow" >&2
    exit 1
fi

export PATH="$NEURON_BIN_DIR:$MDW_BIN_DIR:$PATH"
export LD_LIBRARY_PATH="$NEURON_LIB_DIR:$MDW_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

BACKEND_OUTPUT="$($NEURON_BIN_DIR/ncc-tflite --arch=? 2>&1 || true)"
if ! echo "$BACKEND_OUTPUT" | grep -q "mdla"; then
    echo "NeuroPilot backend query failed." >&2
    echo "$BACKEND_OUTPUT" >&2
    echo "If you see 'Can't open config file', install the vendor Neuron config (commonly /vendor/etc/armnn_app.config) from the board BSP." >&2
    exit 1
fi

cd "$DEMO_DIR"
exec "$PYTHON_BIN" "$DEMO_DIR/label_image.py"