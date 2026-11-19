nvidia-display-carveout.sh
===================

A shell script to query and change the persistent Display firmware-reserved memory (FRM)
carveout size on some NVIDIA SoC systems which expose FRM allocation configuration via UEFI variables.
The carveout size is kept in the EXPOSED_DISP_FRM EFI variable.  Changing it
does not affect the running system; the new size is applied on the next boot.


Usage
-----

Unprivileged commands:

  nvidia-display-carveout.sh --get-display-carveout
  nvidia-display-carveout.sh --help

Privileged commands:

  nvidia-display-carveout.sh --set-display-carveout SIZE_MIB
  nvidia-display-carveout.sh --set-display-carveout=SIZE_MIB
  nvidia-display-carveout.sh --reset-display-carveout

--get-display-carveout
    Print the stored carveout preference, the firmware policy
    (minimum/maximum/default/increment) when available, and the carveout
    applied on the current boot when available.  Only requires read access to
    efivarfs.

      Stored display carveout: <N> MiB (<explicit|firmware default>)
      Firmware policy: minimum=.. MiB, maximum=.. MiB, default=.. MiB, increment=.. MiB
      Applied this boot: .. MiB (status code ..: NAME)

    "explicit" means a size was set by the user; "firmware default" means
    the default allocation size set in the firmware.

    The status code on the "Applied this boot" line comes from
    DISP_FRM_STATUS:

      Value  Meaning
      0      DEFAULT
      1      APPLIED
      2      ADJUSTED
      3      POLICY_UNAVAILABLE
      4      SECURE_RANGE_UNAVAILABLE
      5      HARDWARE_CONFIG_FAILED

--set-display-carveout SIZE_MIB, --set-display-carveout=SIZE_MIB
    Store SIZE_MIB mebibytes as the carveout preference.  The value must be
    an integer within the firmware minimum and maximum and a multiple of the
    firmware increment.  The previous value is printed before it is changed.
    Requires write permission to efivarfs (typically root).  Both forms are
    equivalent.

--reset-display-carveout
    Store the firmware default size (from DISP_FRM_POLICY) as the carveout
    preference and clear the explicit flag, so the preference is reported as
    "firmware default".  Same requirements as --set-display-carveout.

Examples:

  ./nvidia-display-carveout.sh --get-display-carveout
  sudo ./nvidia-display-carveout.sh --set-display-carveout 4096
  sudo ./nvidia-display-carveout.sh --set-display-carveout=4096
  sudo ./nvidia-display-carveout.sh --reset-display-carveout


EFI variables
-------------

The script reads and writes files in /sys/firmware/efi/efivars (efivarfs),
using vendor GUID 4b086294-0740-4f71-a7b5-85a329c7ec5f:

  EXPOSED_DISP_FRM   The stored preference (read/write).
  DISP_FRM_POLICY    Firmware minimum, maximum, default and increment
                     (read only; required for --set and --reset).
  DISP_FRM_STATUS    Carveout applied on this boot (read only; optional).

Each efivarfs file is a 4-byte attribute word followed by the variable's
payload.  All integers are little endian, and offsets below are from the start
of the file (so the payload starts at offset 4).  Sizes are in bytes unless
the field name says MiB.

Bytes 0-3 of every variable are the EFI variable attributes.  They are expected
to be 07 00 00 00 (little endian 0x7), that is NON_VOLATILE (0x1) |
BOOTSERVICE_ACCESS (0x2) | RUNTIME_ACCESS (0x4).  The script does not check
this value; when it writes EXPOSED_DISP_FRM it writes back the attribute bytes
it read.

EXPOSED_DISP_FRM (25 bytes in total: 4 attribute bytes + 21 payload bytes)

  Offset  Size  Field             Description
  0       4     attributes        EFI variable attributes; 07 00 00 00
                                  (NV|BS|RT)
  4       4     size_mib          Stored carveout size, in MiB
  8       8     increment_bytes   Size increment; a multiple of 1 MiB
  16      8     minimum_bytes     Minimum size; a multiple of 1 MiB
  24      1     explicit          1 = size was set explicitly, 0 = firmware
                                  default

DISP_FRM_POLICY (at least 44 bytes)

  Offset  Size  Field             Description
  0       4     attributes        EFI variable attributes; 07 00 00 00
                                  (NV|BS|RT)
  4       4     version           Layout version; the upper 16 bits are the
                                  major version (2 is supported)
  8       4     length            Payload length declared by the firmware: the
                                  bytes after the attribute word, including
                                  version and length (40 for this layout)
  12      8     minimum_bytes     Minimum carveout size
  20      8     maximum_bytes     Maximum carveout size
  28      8     default_bytes     Default carveout size
  36      8     increment_bytes   Size increment

DISP_FRM_STATUS (at least 28 bytes)

  Offset  Size  Field             Description
  0       4     attributes        EFI variable attributes; 07 00 00 00
                                  (NV|BS|RT)
  4       4     version           Layout version (major 2 is supported)
  8       4     length            Declared payload length (24 for this layout)
  12      8     applied_bytes     Carveout applied on this boot
  20      8     status_code       See the status code table above


Valid sizes
-----------

size_mib is a 32-bit value, but the sizes the firmware accepts are defined by
DISP_FRM_POLICY: a size must be between minimum_bytes and maximum_bytes
(inclusive) and a multiple of increment_bytes.  Use --get-display-carveout to
see the limits for a system.  For example, one N1x test system reports:

  Firmware policy: minimum=4096 MiB, maximum=49152 MiB, default=31232 MiB,
  increment=512 MiB

so sizes above 4 GiB, such as 8192, 16384 or 31232 MiB, are valid there, while
5000 MiB (not a multiple of 512) or 65536 MiB (above the maximum) are not.
The limits can differ between systems and firmware versions.  If
DISP_FRM_POLICY is not available, the script refuses to set a size, because it
cannot validate it.  The firmware may still adjust a stored size on the next
boot; the status code reported by --get-display-carveout shows whether it did
(ADJUSTED).


Requirements
------------

  - Compatible system with efivarfs mounted at /sys/firmware/efi/efivars (set the
    EFIVARS_DIR environment variable to use a different directory)
  - bash, od, lsattr/chattr
