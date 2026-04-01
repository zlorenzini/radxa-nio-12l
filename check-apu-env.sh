#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NP_DIR="$ROOT_DIR/mtk-neuropilot-prebuilts"

NEURON_BIN_DIR="$NP_DIR/neuron/6/usr/sbin"
MDW_BIN_DIR="$NP_DIR/mdw/android13/usr/sbin"
NEURON_LIB_DIR="$NP_DIR/neuron/6/usr/lib64"
MDW_LIB_DIR="$NP_DIR/mdw/android13/usr/lib64"

TOTAL=0
FAIL=0
WARN=0

pass() {
    echo "[PASS] $1"
}

fail() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo "[WARN] $1"
    WARN=$((WARN + 1))
}

check_file() {
    local p="$1"
    local label="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -f "$p" ]]; then
        pass "$label: $p"
    else
        fail "$label missing: $p"
    fi
}

check_exec() {
    local p="$1"
    local label="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -x "$p" ]]; then
        pass "$label: $p"
    else
        fail "$label missing or not executable: $p"
    fi
}

check_dir_nonempty() {
    local p="$1"
    local label="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -d "$p" ]] && compgen -G "$p/*" >/dev/null; then
        pass "$label: $p"
    else
        fail "$label missing or empty: $p"
    fi
}

echo "== NIO 12L APU Environment Check =="
echo "Repo root: $ROOT_DIR"
echo

echo "-- Bundled NeuroPilot assets --"
check_exec "$NEURON_BIN_DIR/ncc-tflite" "Compiler"
check_exec "$NEURON_BIN_DIR/neuronrt" "Runtime CLI"
check_exec "$NEURON_BIN_DIR/runtime_api_sample" "Runtime sample tool"
check_dir_nonempty "$NEURON_LIB_DIR" "Neuron libs"
check_dir_nonempty "$MDW_LIB_DIR" "APUSYS middleware libs"
echo

echo "-- Board runtime config files --"
check_file "/etc/nhw" "Legacy nhw path"
check_file "/etc/apusys/mt8195/nhw" "Per-SoC nhw path"

TOTAL=$((TOTAL + 1))
if [[ -f "/vendor/etc/armnn_app.config" ]]; then
    pass "APUSYS config: /vendor/etc/armnn_app.config"
else
    fail "APUSYS config missing: /vendor/etc/armnn_app.config"
fi
echo

echo "-- Kernel firmware files --"
TOTAL=$((TOTAL + 1))
if [[ -f "/lib/firmware/mediatek/mt8395/apusys.sig.img" ]] || [[ -f "/lib/firmware/mediatek/mt8195/apusys.sig.img" ]]; then
    pass "APUSYS firmware present under /lib/firmware/mediatek/{mt8395|mt8195}/apusys.sig.img"
else
    warn "APUSYS firmware not found under /lib/firmware/mediatek/{mt8395|mt8195}/apusys.sig.img"
fi
echo

echo "-- Device nodes (informational) --"
TOTAL=$((TOTAL + 1))
if compgen -G "/dev/apusys*" >/dev/null || compgen -G "/dev/mdla*" >/dev/null || compgen -G "/dev/vpu*" >/dev/null; then
    pass "Found APUSYS-related device node(s)"
    ls -1 /dev/apusys* /dev/mdla* /dev/vpu* 2>/dev/null | sed 's/^/  - /'
else
    warn "No /dev/apusys*, /dev/mdla*, or /dev/vpu* nodes detected"
fi
echo

echo "-- Tool runtime probe --"
OLD_PATH="$PATH"
OLD_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export PATH="$NEURON_BIN_DIR:$MDW_BIN_DIR:$PATH"
export LD_LIBRARY_PATH="$NEURON_LIB_DIR:$MDW_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

TOTAL=$((TOTAL + 1))
BACKEND_OUTPUT="$(ncc-tflite --arch=? 2>&1 || true)"
if echo "$BACKEND_OUTPUT" | grep -q "mdla"; then
    pass "ncc-tflite backend query reports mdla"
else
    fail "ncc-tflite backend query did not report mdla"
    echo "$BACKEND_OUTPUT" | sed 's/^/  > /'
fi

PATH="$OLD_PATH"
LD_LIBRARY_PATH="$OLD_LD_LIBRARY_PATH"

echo
echo "== Summary =="
echo "Checks: $TOTAL"
echo "Failures: $FAIL"
echo "Warnings: $WARN"

if [[ $FAIL -ne 0 ]]; then
    echo
    echo "Result: NOT READY for APU inference."
    echo "Fix missing files above. On Genio Ubuntu you can run:"
    echo "  sudo ./install-genio-neuropilot.sh"
    echo "Then reboot, and re-run this script and ./run-apu-demo.sh"
    exit 1
fi

echo
echo "Result: READY (or close). Try ./run-apu-demo.sh"
exit 0