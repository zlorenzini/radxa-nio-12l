# Gitignore Entries Required For Feature Migration

This inventory lists repository .gitignore entries that are required for the current
APU/USB/feature migration workflow. These items are needed operationally but should remain
ignored because they are large, generated, or vendor-delivered binaries.

Last updated: 2026-04-02

## Required ignored entries

| .gitignore entry | Required now | Why it is needed | Used in phase(s) | Keep ignored |
|---|---|---|---|---|
| genio-classic-desktop-noble-emmc-20250926-1185/ | Yes (optional reference) | Provides stock Genio Ubuntu desktop image artifacts for comparison and fallback checks. | Baseline/gap analysis | Yes |
| genio-g1200-evk-boot-assets-20250926-1185/ | Yes | Contains boot assets and environment references used to compare firmware/boot layout behavior. | Baseline/gap analysis, flashing validation | Yes |
| scarthgap_k6.6_v25.1.1_genio-1200-evk-ufs_private_260316022635/ | Yes (primary) | Source-of-truth Yocto bundle for extracting APU runtime components, firmware, DT/overlay references, and package manifests. | Phase 0 extraction, APU bring-up | Yes |
| .tmp-scarthgap-extract/ | Yes (working directory) | Local temporary workspace for loop-mounting and extracting files from the scarthgap image. | Phase 0 extraction and staging | Yes |
| *.wic.img | Yes | Yocto WIC rootfs image format used for mounting/extracting donor components. | Phase 0 extraction | Yes |
| *.ext4 | Maybe | Intermediate extracted rootfs artifacts can appear as ext4 images depending on extraction method. | Optional extraction workflows | Yes |
| *.raw.img | Maybe | Intermediate raw image artifacts generated during local image conversion/extraction workflows. | Optional extraction workflows | Yes |

## Not required for migration output

These entries are still reasonable to ignore but are not required deliverables:

- Local temporary conversion products that can be regenerated at any time.
- Any imported vendor image folders used only as reference once extraction is complete.

## Recommendation

Keep all entries above in .gitignore. They are operationally necessary for the migration process,
but should not be committed due to size, licensing/distribution concerns, and reproducibility.
