# Armbian Board Config Snapshots

This directory stores board config files tracked in this repo so they can be reapplied after pulling/updating the Armbian build tree.

Current workflow:

```bash
cp kernel/userpatches/config/boards/radxa-nio-12l.conf \
  /home/zach/Documents/build/config/boards/radxa-nio-12l.conf
```

Then rebuild as usual from `/home/zach/Documents/build`.
