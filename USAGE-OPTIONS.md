# Usage Options: Custom ISO or OEMDRV Seed Image

There are two independent ways to deliver the same `ks.cfg` to an unattended
Rocky install. They are alternatives, not steps — pick one.

|                       | `make` (ISO)       | `make oemdrv` (seed) |
| --------------------- | ------------------ | -------------------- |
| Artifact              | ISO, ~10 GB        | `oemdrv.img`, 8 MB   |
| Stock ISO usable?     | No — remastered    | Yes, unmodified      |
| Kickstart found via   | `inst.ks=` in GRUB | Label scan, no args  |
| Rebuild after ks edit | Full remaster      | Seconds              |
| Devices to attach     | One                | Two (ISO + image)    |
| Needs root            | No                 | Yes (loop mount)     |

## What Boots, and What Merely Gets Read

This is the part that trips people up: **a machine never boots from
`oemdrv.img`.** It boots from the Rocky ISO. The seed image is pure data — it
has no bootloader, no El Torito record, and no EFI System Partition.

`mkfs.vfat` says so itself. The first sector of the image contains:

```console
$ dd if=oemdrv.img bs=512 count=1 status=none | strings -n 8
mkfs.fat
OEMDRV     FAT12
This is not a bootable disk.  Please insert a bootable floppy and
press any key to try again ...
```

The image _does_ carry the `0x55AA` signature at the end of that boot sector
(offset 510) — every FAT boot sector does — which is exactly why some firmware
will try it, land on the stub, and fall through to the next device. Nothing
installs.

The real sequence is two separate roles:

1. Firmware boots the **ISO** — `images/eltorito.img` under BIOS,
   `images/efiboot.img` under UEFI.
2. GRUB from the ISO loads `vmlinuz` and `initrd.img`.
3. Anaconda starts, mounting its stage2 (`images/install.img`) from the ISO by
   volume label.
4. _Then_ Anaconda scans every attached block device for a filesystem labelled
   `OEMDRV`.
5. It finds the seed image, reads `/ks.cfg` from it, and runs unattended.

In short: **boot medium = ISO, configuration = OEMDRV.** The seed image is
never booted, only read — and only once the installer is already running.

## Option 1: Custom Autoinstall ISO

```bash
cp ks-bios+efi.ks ks.cfg
make
```

Produces `rocky-10.2-autoinstall.iso` with `ks.cfg` at the ISO root and both
GRUB configs — `/boot/grub2/grub.cfg` (BIOS) and `/EFI/BOOT/grub.cfg` (UEFI) —
carrying an autoinstall entry that points at it with `inst.ks=cdrom:/ks.cfg`.

Boot it in a VM or write it to physical media. Nothing else to attach.

**Choose this when** you want one self-contained artifact to hand to someone
else, burn to a USB stick, or drop on a share — anywhere a second device would
be awkward.

## Option 2: OEMDRV Seed Image

```bash
cp ks-bios+efi.ks ks.cfg
sudo make oemdrv
```

Produces `oemdrv.img`: an 8 MB VFAT filesystem, volume label `OEMDRV`,
containing exactly one file — `ks.cfg`.

Attach it alongside a **stock, unmodified** Rocky DVD ISO:

- **Proxmox**: add as a second SCSI/SATA disk
- **QEMU**: `-drive file=oemdrv.img,if=virtio,format=raw`

The name `oemdrv.img` carries no meaning and can be anything. What Anaconda
matches on is the VFAT volume label set by `mkfs.vfat -n OEMDRV`. The label
itself is a leftover from OEM _driver_ disks — the lookup Anaconda originally
scanned for, which kickstart auto-discovery was later bolted onto.

**Choose this when** you are iterating. Editing the kickstart and rebuilding
the seed takes seconds instead of a 10 GB remaster, and you never touch the
vendor's ISO.

## Gotchas

- **Set boot order to the CD/ISO, not the seed disk.** Pointing firmware at
  `oemdrv.img` gets you the "not a bootable disk" stub and a fall-through.
- **Do not pass `inst.ks=` when using OEMDRV.** The label scan is automatic,
  and an explicit `inst.ks=` overrides it.
- **Attach the seed as a disk, not a floppy.** Modern Anaconda does not scan
  `/dev/fd0` for `OEMDRV`.
- **The seed is an ordinary disk, so the installer can see it as an install
  target.** That is why the `%pre` loop in the supplied Kickstarts skips any
  device labelled `OEMDRV` before `clearpart --all` runs. Removing that guard
  wipes your kickstart mid-install.
- **`oemdrv.img` ends up owned by root**, since `make oemdrv` needs sudo.
  `make clean` still removes it — removal depends on write permission of the
  directory, not ownership of the file.

## Verifying a Seed Image

`fsck.fat` — which `make oemdrv` runs for you — only proves the filesystem is
structurally sound. An empty VFAT filesystem passes it perfectly well, so it
cannot tell you the kickstart is actually present. To confirm that:

```console
$ blkid oemdrv.img
oemdrv.img: SEC_TYPE="msdos" LABEL_FATBOOT="OEMDRV" LABEL="OEMDRV" TYPE="vfat"

$ mdir -i oemdrv.img ::/          # needs mtools; no root, no mounting
 Volume in drive : is OEMDRV
Directory for ::/

KS       CFG      5449 2026-07-26  19:25  ks.cfg
        1 file                5 449 bytes
```

Two things to check: the label reads `OEMDRV`, and `ks.cfg` is present at the
filesystem root with a non-zero size. Without mtools, mount it read-only:

```bash
sudo mount -o loop,ro oemdrv.img /mnt && ls -l /mnt && sudo umount /mnt
```

## Loading the Kickstart from Somewhere Else

Neither option is mandatory — the kickstart can come from anywhere Anaconda can
reach:

```text
inst.ks=cdrom:/ks.cfg                    # baked into a custom ISO (Option 1)
inst.ks=hd:LABEL=OEMDRV:/ks.cfg          # seed image, named explicitly
inst.ks=http://10.0.0.6/uai/ks.cfg       # served over HTTP
```

An `OEMDRV`-labelled device needs no `inst.ks=` argument at all (Option 2). See
the iPXE section of [README.md](README.md) for the fully networked variant,
where the kernel, initrd, stage2, and kickstart are all fetched over HTTP.
