# APU Quickstart

The fastest path to inference on the NIO 12L APU is to use the bundled MediaTek NeuroPilot tools in this repo. Do not start with LiteRT here.

## Fastest Demo Path

Preflight first:

```bash
chmod +x ./check-apu-env.sh
./check-apu-env.sh
```

If this reports missing `/etc/nhw` or `/vendor/etc/armnn_app.config`, fix BSP runtime packaging first.

On Ubuntu for Genio 1200, use the official package flow:

```bash
chmod +x ./install-genio-neuropilot.sh
sudo ./install-genio-neuropilot.sh
sudo reboot
./check-apu-env.sh
```

Run the bundled quantized MobileNet sample:

```bash
chmod +x ./run-apu-demo.sh
./run-apu-demo.sh
```

What this does:

- Adds the bundled NeuroPilot binaries to `PATH`
- Adds the bundled runtime libraries to `LD_LIBRARY_PATH`
- Uses `ncc-tflite` to compile the sample `.tflite` model to a `.dla`
- Runs inference on the first available `mdla` backend using `runtime_api_sample`

Host requirements on the target board:

```bash
sudo apt install python3 python3-numpy python3-pil libc++1 libc++abi1
```

If your distro still ships `libtinfo5`, install that too if the runtime complains about a missing library.

For reference, this installer follows the official Genio Ubuntu docs for adding `ppa:mediatek-genio/genio-public` and installing NeuroPilot packages.

## If You Already Have A `.dla`

If the model is already compiled for MediaTek, skip `ncc-tflite` and run `neuronrt` directly:

```bash
export PATH="$PWD/mtk-neuropilot-prebuilts/neuron/6/usr/sbin:$PWD/mtk-neuropilot-prebuilts/mdw/android13/usr/sbin:$PATH"
export LD_LIBRARY_PATH="$PWD/mtk-neuropilot-prebuilts/neuron/6/usr/lib64:$PWD/mtk-neuropilot-prebuilts/mdw/android13/usr/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

neuronrt -a /path/to/model.dla -d
neuronrt -m hw -a /path/to/model.dla -c 1 -i /path/to/input.bin -o output_0.bin
```

Use the first command to inspect tensor shapes and count how many `-o` output files you need.

## Why Not `benchmark.py`

The bundled benchmark script in this repo hardcodes a different repo path, so it is not the shortest reliable path here. Use [run-apu-demo.sh](/home/radxa/repos/radxa-nio-12l/run-apu-demo.sh) or direct `neuronrt` commands instead.