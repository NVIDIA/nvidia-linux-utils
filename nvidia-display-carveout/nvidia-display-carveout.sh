#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

print_help() {
    cat <<'EOF'
Query or set the persistent Display firmware-reserved memory (FRM) carveout
(EXPOSED_DISP_FRM EFI variable).

  nvidia-display-carveout.sh --get-display-carveout
  nvidia-display-carveout.sh --set-display-carveout SIZE_MIB
  nvidia-display-carveout.sh --set-display-carveout=SIZE_MIB
  nvidia-display-carveout.sh --reset-display-carveout

--get-display-carveout
    Query the persistent display (FRM) memory carveout preference stored in
    the system firmware, and exit.  Print the stored preference, the
    firmware minimum/maximum/increment (when available), and the carveout
    applied on the current boot (when available); this only requires read
    access to efivarfs.

--set-display-carveout SIZE_MIB, --set-display-carveout=SIZE_MIB
    Set the persistent display (FRM) memory carveout preference stored in
    the system firmware to SIZE_MIB mebibytes, and exit.  The value must be
    within the minimum and maximum, and a multiple of the increment,
    reported by the firmware.  Setting requires write permission to
    efivarfs, existing EXPOSED_DISP_FRM and DISP_FRM_POLICY EFI variables.  The previous
    value is printed before it is changed.  The new carveout takes effect on the next boot.

--reset-display-carveout
    Set the persistent display (FRM) memory carveout preference stored in
    the system firmware to the default size reported by the firmware in
    DISP_FRM_POLICY and clear the explicit flag, and exit.  Requires write
    permission to efivarfs and the same existing EFI variables as
    --set-display-carveout.  The previous value is printed before it is
    changed.  The new carveout takes effect on the next boot.
EOF
}

GUID=4b086294-0740-4f71-a7b5-85a329c7ec5f
DIR=${EFIVARS_DIR:-/sys/firmware/efi/efivars}
PREF=$DIR/EXPOSED_DISP_FRM-$GUID
POLICY=$DIR/DISP_FRM_POLICY-$GUID
STATUS=$DIR/DISP_FRM_STATUS-$GUID
MIB=1048576
ABI_MAJOR=2

die() { echo "error: $*" >&2; exit 1; }

# Load a file into the global array B, one decimal byte per element.
load() { B=($(od -An -v -tu1 "$1")) && ((${#B[@]} > 0)); }

# le OFFSET LENGTH: little endian unsigned value from B.
le() {
    local v=0 i
    for ((i = $1 + $2 - 1; i >= $1; i--)); do v=$((v * 256 + B[i])); done
    echo "$v"
}

# Read an efivarfs file into B (attributes at 0..3, payload from 4).
# $2 is the minimum total size; for policy/status the ABI major and the
# declared length are checked as well.
read_var() {
    local file=$1 min=$2 version length
    if [[ ! -e $file ]]; then
        # An absent variable under a present efivarfs is normal for the
        # optional ones; a missing efivarfs directory is not.
        [[ -d $DIR ]] || echo "efivarfs directory $DIR not found; is efivarfs" \
            "mounted there (mount -t efivarfs efivarfs $DIR), or is it" \
            "mounted elsewhere (set EFIVARS_DIR)?" >&2
        return 2
    fi
    [[ -r $file ]] || { echo "no read permission for $file" >&2; return 1; }
    load "$file" && ((${#B[@]} >= min)) || { echo "bad size: $file" >&2; return 1; }
    if [[ $3 == versioned ]]; then
        version=$(le 4 4); length=$(le 8 4)
        ((version >> 16 == ABI_MAJOR && length >= min - 4 && length <= ${#B[@]} - 4)) ||
            { echo "unsupported layout: $file" >&2; return 1; }
    fi
}

read_pref() {   # sets SIZE_MIB PINC PMIN EXPLICIT
    [[ -e $PREF ]] || die "EXPOSED_DISP_FRM is absent"
    read_var "$PREF" 25 || die "cannot read EXPOSED_DISP_FRM"
    ((${#B[@]} == 25)) || die "unexpected EXPOSED_DISP_FRM size"
    SIZE_MIB=$(le 4 4); PINC=$(le 8 8); PMIN=$(le 16 8); EXPLICIT=${B[24]}
    ((PINC != 0 && PMIN != 0 && PINC % MIB == 0 && PMIN % MIB == 0 &&
      EXPLICIT <= 1)) || die "EXPOSED_DISP_FRM contains invalid values"
    local size_source="firmware default"
    if ((EXPLICIT)); then size_source="explicit"; fi
    echo "Stored display carveout: $SIZE_MIB MiB ($size_source)" >&2
}

read_policy() { # sets MIN MAX DEF INC; returns 2 when absent
    read_var "$POLICY" 44 versioned || return $?
    MIN=$(le 12 8); MAX=$(le 20 8); DEF=$(le 28 8); INC=$(le 36 8)
    ((MIN != 0 && INC != 0 && MIN <= MAX && DEF >= MIN && DEF <= MAX &&
      MIN % MIB == 0 && MAX % MIB == 0 && DEF % MIB == 0 &&
      INC % MIB == 0)) || { echo "invalid DISP_FRM_POLICY" >&2; return 1; }
}

STATUS_NAMES=(DEFAULT APPLIED ADJUSTED POLICY_UNAVAILABLE
              SECURE_RANGE_UNAVAILABLE HARDWARE_CONFIG_FAILED)

read_status() { # sets APPLIED_MIB STATUS_CODE; returns 2 when absent
    read_var "$STATUS" 28 versioned || return $?
    APPLIED_MIB=$(($(le 12 8) / MIB)); STATUS_CODE=$(le 20 8)
}

get() {
    read_pref
    # PMIN and PINC are in bytes, like MIN/MAX/DEF/INC; scale on assignment.
    local minimum="$((PMIN / MIB)) MiB"
    local maximum="unknown"
    local default_size="unknown"
    local increment="$((PINC / MIB)) MiB"
    if read_policy; then
        minimum="$((MIN / MIB)) MiB"
        maximum="$((MAX / MIB)) MiB"
        default_size="$((DEF / MIB)) MiB"
        increment="$((INC / MIB)) MiB"
    else
        echo "Failed to read policy values; falling back to preference values" >&2
    fi
    echo "Firmware policy: minimum=$minimum, maximum=$maximum," \
         "default=$default_size, increment=$increment" >&2

    if read_status; then
        echo "Applied this boot: $APPLIED_MIB MiB (status code $STATUS_CODE: ${STATUS_NAMES[STATUS_CODE]:-UNKNOWN})" >&2
    else
        echo "Applied this boot: unknown" >&2
    fi
}

is_immutable() { [[ $(lsattr -d "$1" 2>/dev/null) == *i*' '* ]]; }

# write_var FILE BYTE...: single write() of attributes + payload (BYTEs are
# decimal), then read back and compare.  Restores the immutable flag whatever
# happens.
write_var() {
    local file=$1 imm=0 ok=0 record
    shift
    is_immutable "$file" && imm=1
    ((imm)) && { chattr -i "$file" || die "cannot clear the immutable flag on" \
        "$file"; }
    # One printf, one write(), as efivarfs requires.  "1<>" opens the file
    # read/write without O_TRUNC, which efivarfs rejects.  dd cannot be used:
    # it tries to seek, which efivarfs does not support.
    printf -v record '\\%03o' "$@"
    if ! printf "$record" 1<>"$file"; then
        echo "cannot write $file; permission denied, or the update was" \
            "rejected by efivarfs or the firmware" >&2
    elif ! load "$file"; then
        echo "cannot read back $file to verify the update" >&2
    elif [[ "${B[*]}" != "$*" ]]; then
        echo "read-back of $file differs from the requested value" >&2
    else
        ok=1
    fi
    ((imm)) && { chattr +i "$file" || { echo "could not restore the immutable" \
        "flag; run 'chattr +i $file'" >&2; ok=0; }; }
    ((ok))
}

set_size() {
    local size_mib=$1 target orig i active want_explicit   # "default": policy default
    [[ $size_mib == 'default' ]] || {
        [[ $size_mib =~ ^[0-9]{1,10}$ ]] && ((size_mib <= 4294967295)) ||
            die "invalid size '$size_mib'; expected an integer number of MiB"
    }
    read_pref
    # efivarfs files are normally immutable, which makes -w fail even for
    # users who may clear the flag; chattr -i reports that case when we try.
    is_immutable "$PREF" || [[ -w $PREF ]] ||
        die "no write permission for $PREF"
    if read_status; then
        active="the current boot's carveout is $APPLIED_MIB MiB"
    else
        APPLIED_MIB=; active="the current boot's carveout is unknown"
    fi
    read_policy || die "DISP_FRM_POLICY is absent or invalid; cannot validate"
    # Reset stores the policy default as a non-explicit preference; an
    # explicit size always sets the explicit flag.
    want_explicit=1
    if [[ $size_mib == 'default' ]]; then
        size_mib=$((DEF / MIB)); want_explicit=0
    fi
    target=$((size_mib * MIB))
    ((target >= MIN)) || die "$size_mib MiB is below the minimum ($((MIN / MIB)) MiB)"
    ((target <= MAX)) || die "$size_mib MiB is above the maximum ($((MAX / MIB)) MiB)"
    ((target % INC == 0)) || die "$size_mib MiB is not a multiple of $((INC / MIB)) MiB"
    if ((SIZE_MIB * MIB == target && EXPLICIT == want_explicit)); then
        echo "Previously stored display carveout is already $size_mib MiB; no EFI write." >&2
        if [[ $APPLIED_MIB != "$size_mib" ]]; then
            echo "Note: $active and stays in effect until the next reboot." >&2
        fi
        return 0
    fi

    # New record = original with size_mib (bytes 4..7) and explicit (byte 24)
    # replaced.
    load "$PREF" || die "cannot read $PREF to save the original value"
    orig=("${B[@]}")
    for i in 0 1 2 3; do B[4 + i]=$((size_mib >> (8 * i) & 255)); done
    B[24]=$want_explicit

    if ! write_var "$PREF" "${B[@]}"; then
        echo "EFI write failed; restoring the original preference." >&2
        write_var "$PREF" "${orig[@]}" ||
            die "recovery failed; the stored value may differ from the original"
        exit 1
    fi
    echo "Stored display carveout is now $size_mib MiB.  Reboot for the" \
         "change to take effect; $active."
}

case $1 in
    --get-display-carveout) get ;;
    --set-display-carveout)
        (($# == 2)) || die "--set-display-carveout requires a SIZE_MIB argument"
        set_size "$2" ;;
    --set-display-carveout=*) set_size "${1#*=}" ;;   # also accepted
    --reset-display-carveout) set_size default ;;
    -h|--help) print_help ;;
    *) echo "usage: $0 --get-display-carveout" >&2
       echo "       $0 --set-display-carveout SIZE_MIB" >&2
       echo "       $0 --set-display-carveout=SIZE_MIB" >&2
       echo "       $0 --reset-display-carveout" >&2
       echo "       $0 --help" >&2
       exit 2 ;;
esac
