# GPU Benchmarks — Radxa NIO 12L

## Environment

| | |
|---|---|
| Date | 2026-03-23 |
| OS | Armbian / Ubuntu 24.04 (Noble) |
| Kernel | 6.19.0-rc5-edge-genio |
| GPU driver | Panfrost 1.5.0 (open-source) |
| GL renderer | Mali-G57 (Panfrost) |
| Mesa version | 25.2.8-0ubuntu0.24.04.1 |
| OpenGL ES | 3.1 |
| Display | Wayland (GNOME Shell / GBM) |

---

## glmark2-es2-wayland

**Score: 2699**

| Scene | Parameters | FPS | Frame time (ms) |
|---|---|---:|---:|
| build | use-vbo=false | 3174 | 0.315 |
| build | use-vbo=true | 4861 | 0.206 |
| texture | texture-filter=nearest | 5727 | 0.175 |
| texture | texture-filter=linear | 4837 | 0.207 |
| texture | texture-filter=mipmap | 4789 | 0.209 |
| shading | shading=gouraud | 3772 | 0.265 |
| shading | shading=blinn-phong-inf | 3615 | 0.277 |
| shading | shading=phong | 2968 | 0.337 |
| shading | shading=cel | 2733 | 0.366 |
| bump | bump-render=high-poly | 1922 | 0.520 |
| bump | bump-render=normals | 4101 | 0.244 |
| bump | bump-render=height | 3575 | 0.280 |
| effect2d | kernel=0,1,0;1,-4,1;0,1,0 (Laplacian) | 2776 | 0.360 |
| effect2d | kernel=1,1,1,1,1;… (5×5 box) | 1510 | 0.663 |
| pulsar | light=false:quads=5:texture=false | 4329 | 0.231 |
| desktop | blur-radius=5:effect=blur:passes=1:separable=true:windows=4 | 749 | 1.335 |
| desktop | effect=shadow:windows=4 | 1677 | 0.597 |
| buffer | columns=200:update-method=map | 480 | 2.085 |
| buffer | columns=200:update-method=subdata | 471 | 2.126 |
| buffer | columns=200:interleave=true:update-method=map | 542 | 1.848 |
| ideas | speed=duration | 900 | 1.112 |
| jellyfish | default | 2039 | 0.491 |
| terrain | default | 125 | 8.043 |
| shadow | default | 1612 | 0.620 |
| refract | default | 304 | 3.298 |
| conditionals | fragment-steps=0:vertex-steps=0 | 3986 | 0.251 |
| conditionals | fragment-steps=5:vertex-steps=0 | 3017 | 0.332 |
| conditionals | fragment-steps=0:vertex-steps=5 | 3392 | 0.295 |
| function | fragment-complexity=low:fragment-steps=5 | 3267 | 0.306 |
| function | fragment-complexity=medium:fragment-steps=5 | 2654 | 0.377 |
| loop | fragment-loop=false:fragment-steps=5:vertex-steps=5 | 3268 | 0.306 |
| loop | fragment-steps=5:fragment-uniform=false:vertex-steps=5 | 3272 | 0.306 |
| loop | fragment-steps=5:fragment-uniform=true:vertex-steps=5 | 2679 | 0.373 |

---

## es2gears_wayland

| Interval | FPS |
|---|---:|
| 0–5 s | 54.2 |
| 5–10 s | 40.2 |

Note: es2gears is not a GPU stress test — it is largely CPU-bound by the gear rotation math and swap timing.

---

## Vulkan (vkmark)

Not available. No `panvk` ICD is shipped with Ubuntu 24.04's Mesa 25.2 for the Bifrost architecture (Mali-G57). Vulkan support for Panfrost/Bifrost is still in development upstream.

---

## DVFS (GPU frequency scaling)

500 frequency transitions were recorded during the benchmark run, spanning all 16 OPP levels from 390 MHz up to 880 MHz. The `simple_ondemand` governor scaled the GPU up and down correctly throughout.

This confirms the device-tree fix applied on 2026-03-23 (correcting `mali_sram-supply` to reference `mt6315_7_vbuck1`) is working. Prior to the fix, the GPU was stuck at 390 MHz with no frequency scaling.

Available OPP levels (MHz): 390, 410, 431, 473, 515, 556, 598, 640, 670, 700, 730, 760, 790, 820, 850, 880
