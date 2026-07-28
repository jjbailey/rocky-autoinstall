# Rocky Linux Autoinstall ISO and Kickstart Seed Image Builder

This project simplifies the creation of:

- A custom Rocky Linux Autoinstall ISO for fully automated installations
- A VFAT-formatted `OEMDRV` image holding a Kickstart file, which Anaconda
  picks up automatically with no kernel arguments

All processes are managed through a single `Makefile`.

The two are alternatives, not steps. See
[USAGE-OPTIONS.md](USAGE-OPTIONS.md) for which to pick, and for what actually
boots versus what merely gets read.

## Features

- Automatic dependency checks for ISO builds and required-file checks
- Customizable GRUB menu, applied to both the BIOS and the UEFI GRUB config
- Non-interactive scripts: controlled entirely via `make`
- VFAT `OEMDRV` image production using a temporary mount point

## Typical Use Cases

- Provisioning multiple Rocky servers quickly and consistently in a
  datacenter or virtualized environment
- Automated lab or testbed setup
- Infrastructure as Code (IaC) deployments

## Requirements

### Rocky Host Packages

Install the following packages on your Rocky host:

```bash
sudo dnf install curl xorriso dosfstools util-linux pykickstart
```

`pykickstart` is optional but strongly recommended: it provides `ksvalidator`,
which `make` uses to catch Kickstart syntax errors before they cost you an ISO
build and a boot. Without it that check is skipped with a warning.

`xorriso` handles both extraction and mastering, so no p7zip (and therefore no
EPEL) is needed.

**Note**: `sudo` is required for `make oemdrv` to create and mount the
image as a loop device.

You also need roughly **25 GB free**: about 10 GB for the downloaded DVD, the
same again for the extracted tree, and the rebuilt ISO on top.

## Preparation

Provide the following files in your project directory:

| File                    | Purpose                                      |
| ----------------------- | -------------------------------------------- |
| `ks.cfg`                | Kickstart file (used by both the ISO and the |
|                         | `OEMDRV` targets)                            |
| `grub-autoinstall.menu` | GRUB menu entries for the autoinstall ISO    |

The repo includes three Kickstart variants to choose from:

- `ks-bios.ks` — BIOS-only installs
- `ks-efi.ks` — UEFI-only installs
- `ks-bios+efi.ks` — detects firmware at install time and does the right thing

Copy the appropriate one to `ks.cfg` before building:

```bash
cp ks-bios+efi.ks ks.cfg
```

The `rocky` user's password is `rocky`. This is deliberately a **bootstrap
credential**: these hosts are handed to Ansible immediately after install, and
the first configuration pass rotates it. Treat the window between first boot
and that pass as the exposure, and keep provisioning on a trusted segment.

If you are not following that workflow, change the hash in the `user` line
before deploying — generate a replacement with `openssl passwd -6`.

The supplied Kickstarts wipe the install disk (`clearpart --all`). A `%pre`
script picks the first fixed disk that is not the `OEMDRV` seed; set
`ignoredisk --only-use=` explicitly if you want to pin the target. If no
suitable disk is found the install halts with an error rather than continuing
with no `ignoredisk` line — which would have let `clearpart --all` wipe every
attached disk, seed image included.

### Minimum Target Disk Size

The fixed logical volumes total 27 GiB before `pv.01 --grow` claims anything,
so the **install disk** must be at least:

| Kickstart        | Minimum target disk |
| ---------------- | ------------------- |
| `ks-bios.ks`     | 28 GiB              |
| `ks-efi.ks`      | 29 GiB              |
| `ks-bios+efi.ks` | 29 GiB (under UEFI) |

A 20 GB VM disk — a natural default — fails during partitioning. This is
separate from the ~25 GB of scratch space the _build host_ needs for the DVD
and the extracted tree. Shrink the `logvol` lines if you want a smaller target.

### Example `grub-autoinstall.menu`

```text
menuentry "Rocky Server Autoinstall" {
    set gfxpayload=keep
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=@VOLID@ inst.ks=cdrom:/ks.cfg inst.text quiet
    initrd /images/pxeboot/initrd.img
}
```

`@VOLID@` is substituted with the ISO volume label at patch time. Anaconda
locates its stage2 (`/images/install.img`) by that label, so the two must
agree — see [Customization](#customization).

## Usage

### 1. Create the Custom Rocky Autoinstall ISO

Run:

```bash
make
```

This command:

- Downloads the Rocky DVD ISO
- Extracts it with `xorriso -osirrox`
- Adds `ks.cfg` to the ISO root
- Patches both `/boot/grub2/grub.cfg` (BIOS) and `/EFI/BOOT/grub.cfg` (UEFI)
- Creates `rocky-10.2-autoinstall.iso` by default

You can boot this ISO in a virtual machine or on physical hardware for
an unattended installation.

### 2. Create the `OEMDRV` Kickstart Seed Image

Run (requires root privileges):

```bash
sudo make oemdrv
```

**Output**: `oemdrv.img` (8 MB VFAT image, volume label `OEMDRV`)

**Contents**:

- `ks.cfg`

Anaconda scans for a filesystem labelled `OEMDRV` containing `ks.cfg` and uses
it automatically — no `inst.ks=` kernel argument required. Attach it as a
secondary disk alongside a stock Rocky ISO:

- **Proxmox**: Add as a second SCSI/SATA disk to the VM
- **QEMU**: `-drive file=oemdrv.img,if=virtio,format=raw`

Attach it as a **disk**, not a floppy: modern Anaconda does not scan `/dev/fd0`
for `OEMDRV`.

### 3. Clean Up Build Artifacts

Run:

```bash
make clean
```

`clean` deliberately keeps the downloaded DVD so you do not have to re-fetch
10 GB. Use `make distclean` to remove that as well.

### 4. Extract Kernel/Initrd for Netboot (`kernel-extractor.sh`)

`kernel-extractor.sh` mounts a Rocky ISO (loopback) and copies out the
kernel, initrd, and the installer root filesystem (`install.img`) — useful for
iPXE or other netboot setups where the kernel and initrd are served directly
rather than booted from an ISO. This script is standalone and not wired into
the `Makefile`.

```bash
sudo ./kernel-extractor.sh <path-to.iso> <output-dir>
```

Requires root (or equivalent loopback-mount privileges) to mount the ISO.

## Customization

- **Rocky Release**: Edit `MAJOR` and `VERSION` in the `Makefile`. The current
  default is `10` / `10.2`.
- **Volume Label**: `VOLID` defaults to `Rocky-10-2-x86_64-dvd`, matching the
  stock ISO. Anaconda finds its stage2 by this label, so if you change it the
  `patch` rule rewrites every `inst.stage2=hd:LABEL=` in both GRUB configs to
  match. Labels are capped at 32 characters.
- **GRUB Menu**: Modify `grub-autoinstall.menu` to add or edit GRUB menu
  entries, including different kernel arguments for multiple install modes.
  Rename the entries freely — the patch rule brackets whatever it inserts
  between `ROCKY-AUTOINSTALL-MENU-BEGIN` / `-END` comment markers and rewrites
  that block on every build, so menu edits are picked up and the entries never
  accumulate. Do not hand-edit between those markers; the next build discards
  it. The patch rule also sets `set default="0"` so the autoinstall entry is
  the one that boots unattended; edit `set timeout=` in the extracted
  `grub.cfg` if 60 seconds is too long a wait.
- **Kickstart Configuration**: Use valid Kickstart syntax in `ks.cfg`. `make`
  validates it automatically; run `make validate` on its own to check without
  building.

  **Kickstart has no line-continuation.** A trailing `\` does not join lines
  the way it does in shell — each command must sit on a single line, however
  long. Splitting one is the most common way to get an installer that dies at
  "unrecognized arguments". (This does not apply inside `%pre`/`%post`, which
  are ordinary shell scripts.)

### Loading the Kickstart from Somewhere Else

The ISO menu entry uses `inst.ks=cdrom:/ks.cfg`. Other useful forms:

```text
inst.ks=hd:LABEL=OEMDRV:/ks.cfg          # explicit seed image
inst.ks=http://10.0.0.6/uai/ks.cfg       # served over HTTP
```

An `OEMDRV`-labelled device is found with no `inst.ks=` argument at all.

### Example iPXE Menu Entry

The Rocky Autoinstall ISO can be used in an iPXE setup. Use
`kernel-extractor.sh` to pull `vmlinuz` and `initrd.img` out of the ISO built
above. Anaconda needs both a stage2 and a package repo over the network:

Everything below is fetched over HTTP, including the kernel and initrd, so this
is a web root rather than a TFTP one. Note that `install.img` goes under an
`images/` subdirectory: given a directory URL, Anaconda appends
`images/install.img` to find its stage2 — the same layout as the `inst.repo`
tree in the next block. Placing it flat alongside `vmlinuz` will fail to mount
stage2.

```text
/var/www/html/uai
├── images/
│   └── install.img
├── initrd.img
├── ks.cfg
└── vmlinuz
```

```text
:uai
kernel http://10.0.0.6/uai/vmlinuz
initrd http://10.0.0.6/uai/initrd.img
imgargs vmlinuz initrd=initrd.img ip=dhcp \
    inst.stage2=http://10.0.0.6/uai/ \
    inst.repo=https://download.rockylinux.org/pub/rocky/10/BaseOS/x86_64/os/ \
    inst.ks=http://10.0.0.6/uai/ks.cfg inst.text
boot
```

Note that `cdrom` in `ks.cfg` must be swapped for a matching `url --url=...`
line when installing over the network.

## Notes

- **`/boot` is a separate partition.** Anaconda requires `/boot` to be a plain
  partition when root is a logical volume, so the Kickstarts create a separate
  1 GiB `/boot` outside the volume group.
- **The BIOS and UEFI boot paths are independent.** GRUB is configured twice,
  through `/boot/grub2/grub.cfg` and `/EFI/BOOT/grub.cfg`, and the ISO carries
  `/images/eltorito.img` as its El Torito BIOS image with
  `/images/efiboot.img` as an embedded alt-boot entry for UEFI.
- **Open vSwitch is not on the DVD.** It is absent from Rocky BaseOS and
  AppStream, living instead in the CentOS NFV SIG repo, so it has to be
  installed after the fact:

  ```bash
  dnf install centos-release-nfv-openvswitch
  dnf install openvswitch3.5
  ```

## Troubleshooting

- **Missing Dependencies**: The default `make` target checks for required
  commands before building the ISO. The `oemdrv` target checks its own.
- **Root Privileges**: If you see "must be run as root" when building
  `oemdrv`, use `sudo make oemdrv`.
- **Dropped to a rescue shell / "Failed to mount stage2"**: The ISO volume
  label and `inst.stage2=hd:LABEL=` disagree. Check `VOLID` in the `Makefile`.
- **Installer starts interactively**: Kickstart was not found. Confirm
  `ks.cfg` is at the ISO root, or that the seed image really is labelled
  `OEMDRV` (`blkid oemdrv.img`).
- **"An error occurred during reading the kickstart file: unrecognized
  arguments"**, usually followed by `Unknown command: --something`. A Kickstart
  command was split across lines with a trailing `\`. Kickstart does not honour
  line continuation, so the tail of the command is parsed as a command of its
  own. Join it back onto one line.
- **Kickstart syntax errors** halt the install at a prompt. `make` runs
  `ksvalidator` for you; run `make validate` to check without building.

### References

<https://docs.rockylinux.org/guides/automation/>

<https://anaconda-installer.readthedocs.io/en/latest/boot-options.html>

<https://pykickstart.readthedocs.io/en/latest/kickstart-docs.html>

<https://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_type_GUIDs>

## Author, License, and Disclaimer

- **Author**: Copyright (c) 2023-2026 Jack Bailey
- **License**: MIT
- **Disclaimer**: [Use at your own risk!](MAINTENANCE-TERMS.md)
