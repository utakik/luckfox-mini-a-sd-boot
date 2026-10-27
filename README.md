# Luckfox Pico Mini A SD image builder

Create a single, directly flashable SD-card image from the files in an official
Luckfox Pico Mini A MicroSD firmware bundle. The script runs on Windows
PowerShell 5.1 or PowerShell 7.

This repository intentionally contains **no firmware binaries**. Download the
appropriate MicroSD firmware for the **Luckfox Pico Mini A** from Luckfox, then
extract it locally.

## Safety

- The script creates an image file; it does not write to a physical disk.
- It checks `sd_update.txt` against the verified Mini A layout before writing.
- It refuses to overwrite an existing output file.
- Use firmware for the Mini A MicroSD model only. Do not use a NAND/Flash bundle.

The verified layout uses 512-byte sectors:

| File | Start sector | Byte offset | Reserved sectors |
| --- | ---: | ---: | ---: |
| `env.img` | `0x0` | `0x0` | `0x40` |
| `idblock.img` | `0x40` | `0x8000` | `0x400` |
| `uboot.img` | `0x440` | `0x88000` | `0x400` |
| `boot.img` | `0x840` | `0x108000` | `0x10000` |
| `oem.img` | `0x10840` | `0x2108000` | `0x100000` |
| `userdata.img` | `0x110840` | `0x22108000` | `0x80000` |
| `rootfs.img` | `0x190840` | `0x32108000` | `0xC00000` |

## Usage

Open PowerShell in this repository and run:

```powershell
.\New-LuckfoxMiniASdImage.ps1 `
  -FirmwareDirectory 'C:\path\to\Luckfox_Pico_Mini_A_MicroSD_250313' `
  -OutputImage '.\luckfox-mini-a.img'
```

To validate the input and preview the operation without creating a file:

```powershell
.\New-LuckfoxMiniASdImage.ps1 `
  -FirmwareDirectory 'C:\path\to\firmware' `
  -OutputImage '.\luckfox-mini-a.img' `
  -WhatIf
```

The firmware directory must contain:

```text
sd_update.txt
env.img
idblock.img
uboot.img
boot.img
oem.img
userdata.img
rootfs.img
```

After the script finishes, use a trusted imaging program such as Rufus or
balenaEtcher to write the resulting `.img` file to a MicroSD card. Double-check
the target drive: imaging erases the selected card.

## Why check `sd_update.txt`?

Luckfox firmware bundles describe the start offset and reserved size of each
component in `sd_update.txt`. The script parses that file and requires every
value to match the known Mini A MicroSD layout above. If a future bundle changes
the layout, the script stops instead of silently producing a misplaced image.

## LuckfoxをUSBカードリーダーなしでフォーマットし、Linuxをインストールする方法（Windowsのみ）


