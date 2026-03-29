#!/bin/bash

# =================================================================
# Rhome AI Lab: Radxa Nio 12L Provisioning Script (v1.0)
# Purpose: From Fresh Flash to MLPerf-Ready AI Station
# =================================================================

set -e # Exit on any error

echo "🚀 Starting Rhome AI Lab Provisioning..."

# --- Phase 1: System Baseline ---
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    build-essential cmake git \
    python3-dev python3-venv python3-pip \
    pybind11-dev libpython3.12-dev \
    htop wget curl

# --- Phase 2: Python Sandbox ---
echo "🐍 Setting up Python Virtual Environment..."
mkdir -p ~/repos
cd ~/repos
python3 -m venv .mlperf_venv
source .mlperf_venv/bin/activate

echo "🛠️  Upgrading VENV build tools (Python 3.12 Fixes)..."
pip install --upgrade pip setuptools wheel pybind11

# --- Phase 3: AI Infrastructure (MLPerf LoadGen) ---
echo "🏗️  Installing MLPerf LoadGen..."
# We use the pip-hosted version for reliability, 
# but keep the source clone for classroom demos.
pip install mlcommons-loadgen

if [ ! -d "mlperf_inference" ]; then
    echo "📂 Cloning MLPerf Inference repo for documentation/demos..."
    git clone --depth 1 --recurse-submodules https://github.com/mlcommons/inference.git mlperf_inference
fi

# --- Phase 4: Classroom Utilities ---
echo "📋 Creating 'Thermal Pulse' command..."
cat << 'EOF' > ~/thermal_pulse.sh
#!/bin/bash
while true; do
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
    echo -ne "SoC Temperature: $((TEMP/1000))°C\r"
    sleep 1
done
EOF
chmod +x ~/thermal_pulse.sh

# --- Phase 5: Performance Benchmarking ---
echo "🏎️  Downloading Geekbench 6.4 (ARM Preview)..."
mkdir -p ~/benchmarks
cd ~/benchmarks
wget -q https://cdn.geekbench.com/Geekbench-6.4.0-LinuxARMPreview.tar.gz
tar -xzf Geekbench-6.4.0-LinuxARMPreview.tar.gz
rm Geekbench-6.4.0-LinuxARMPreview.tar.gz

# --- Wrap Up ---
echo "✅ Provisioning Complete!"
echo "-------------------------------------------------------"
echo "To enter the AI environment: source ~/repos/.mlperf_venv/bin/activate"
echo "To check thermals:           ./thermal_pulse.sh"
echo "To run benchmarks:           cd ~/benchmarks/Geekbench-6.4.0-LinuxARMPreview/ && ./geekbench6"
echo "-------------------------------------------------------"