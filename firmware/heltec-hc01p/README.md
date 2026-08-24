# Heltec HT-HC01P board configuration file (BCF)

## Why this directory exists

`bcf_HC01_V2_H.bin` is the board configuration file for the Heltec HT-HC01P HAT
(Morse Micro MM6108A2). **It is not distributed anywhere else that we have found**,
and the place you would most reasonably look serves a different file that does not
work — see "Do not use Heltec's download page" below.
`morse-firmware` at tag `mm6108-2.0.1` ships BCFs under
`bcf/{azurewave,morsemicro,netprisma,quectel}` and has no Heltec directory at all.
The only copy is the one inside Heltec's own OpenWrt image, where it sits at
`/lib/firmware/morse/bcf_HC01_V2_H.bin`, mode 0600.

Losing it costs the module its transmitter. That is not a guess: this board ran for
its first day on `bcf_mf08551.bin` — the BCF for Morse's EKH01-03 evaluation board,
which Heltec hardcoded into the shipped image — and in that state it received the AP
perfectly at −56 dBm while **not one** of the frames it transmitted ever reached the
AP. Full account in `NOTES.md`, 2026-08-24.

So it is kept here, hashed, before any porting work touches an SD card.

## Provenance

```
source host     Heltec HT-HC01P on Raspberry Pi 4B, board_name Heltec,Pi4-HT-HC01P-64bit
source path     /lib/firmware/morse/bcf_HC01_V2_H.bin
source image    openwrt-23.05.5-2.8.5-20251107-rpi4-HT-HC01P-sysupgrade.img.gz
                from https://resource.heltec.cn/download/HT-HC01P/Raspiberry%20firmware/raspiberry%204%20serias/
file date       Jun 23 2025 (as shipped)
copied          2026-08-24, by cat over ssh, read-only; the board was not modified
```

## Verify before you trust it

```
size     1170 bytes
sha256   5744fa288d79cd2a8ad8e146bec9aff8d06a6f87c160a0a44358ceb6cd53ba9f
crc32    0x389a48c4      (as printed by the driver: "Loaded BCF from morse/bcf_HC01_V2_H.bin,
                          size 1170, crc32 0x389a48c4")
```

The hash was checked three ways on the day of the copy: against the value recorded in
the inventory, against a fresh `sha256sum` run on the board itself, and against the
local copy. All three agree. Re-check it after every copy — this is the one file in
this project that cannot be fetched again if it is corrupted.

## What is inside it

An ELF32 little-endian RISC-V object, which is why `firmware.c` in morse_driver parses
it with `copy_bcf_section()` and ELF section headers rather than as a flat blob.

```
section          addr         size  content
.board_config    0x8011fa80    120  starts 0xDEADBEEF magic, then a checksum and a version word
.regdom_AU/CA/EU/IN/JP/KR/NZ/SG/US
                 0x8011faf8     12  each: 4-byte value, 4 zero bytes, 2-char country code
.board_desc      -               9  "HC01_V2_H"
.build_ver       -              25  "a49f6ff 17ee8d5 _Modified"
.chips           -               6  "mm610x"
```

Two things worth knowing from that:

- **`.chips` says `mm610x`** — the BCF is tagged to the *chip family*, not to a driver
  or firmware release. Nothing in the file mentions 1.15.3.
- **`.regdom_SG` is present**, so the SG regulatory domain this project uses is
  supported by this BCF and not only by the driver's `channels.csv`.
- `.build_ver` ends in `_Modified`, i.e. Heltec built it from a tree with local changes.

The residual compatibility risk for driver 2.0.1 is narrow and specific: `.board_config`
carries a fixed load address, and the driver copies BCF sections into a window whose
address and size come from **firmware** metadata TLVs (`MORSE_FW_INFO_TLV_BCF_ADDR`,
`MORSE_FW_INFO_TLV_BCF_SIZE`). If the 2.0 firmware advertises a different window than
the 1.15.3 firmware this BCF was built against, the load will land wrong. See
`heltec-hc01p-linux-port-analysis.md`, item U1, for how that gets tested.

## Do not use Heltec's download page for this file

Heltec publish a BCF for this product at
<https://resource.heltec.cn/download/HT-HC01P/BCF/driver_1_15_3/bcf_HC0P.bin>.
**It is the wrong file.** Checked 2026-08-24:

```
Heltec download   bcf_HC0P.bin        1150 B  57c50cb2c1d51187667677b392684285c616ddbf3fe262c3aeece342f446773e
                                      Last-Modified: Tue, 10 Jun 2025 23:41:15 GMT
this directory    bcf_HC01_V2_H.bin   1170 B  5744fa288d79cd2a8ad8e146bec9aff8d06a6f87c160a0a44358ceb6cd53ba9f
```

That download is **byte-identical to `bcf_mf08551.bin`**, the file already sitting
in Heltec's own image as the shipped default, and the files say so themselves:

```
bcf_HC0P.bin        .board_desc = "mf08551"     .build_ver = "a49f6ff 17ee8d5"
bcf_HC01_V2_H.bin   .board_desc = "HC01_V2_H"   .build_ver = "a49f6ff 17ee8d5 _Modified"
```

`mf08551` is Morse's **EKH01-03 evaluation board**. It is the BCF that left this
HAT receiving the AP at −56 dBm while transmitting nothing that ever arrived.
Renaming it `bcf_HC0P.bin` does not make it a HT-HC01P board config.

It is also not newer, which is the first thing you would check: its `Last-Modified`
is 2025-06-10, thirteen days *older* than the 2025-06-23 files in the shipped
image.

**So the vendor download cannot replace this directory, and this file cannot be
swapped for a link to it.** Anyone following Heltec's published route to a BCF for
the HT-HC01P gets a radio with no working transmitter.

## Licensing

This is a vendor binary redistributed from Heltec's published firmware image. It is not
covered by this repository's licence and no licence text accompanies it in the source
image. It is included because there is no other public source of a working HT-HC01P
board config: the vendor's own download page serves an evaluation-board file under a
HT-HC01P name, and the working file exists only inside already-shipped images. If
Heltec or Morse Micro publish the correct file, this copy should be replaced by a link
to it. If they object to it being here, it comes out.
