#!/usr/bin/env python3
"""CRC check v2: kernel exports + vendor-module exports vs vendor-module references."""
import collections
import glob
import os
import subprocess
import sys

VENDOR = os.environ.get("MODS_DIR",
                        "/mnt/d/Program/Codex/2026-10-14/w/work/vendor_mods")
DEFAULT_SYMVERS = "/root/kb/ack/Module.symvers"


def load_symvers(path):
    table = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 2 and parts[0].startswith("0x"):
                table[parts[1]] = parts[0][2:].lower()
    return table


def referenced(path):
    res = subprocess.run(["modprobe", "--dump-modversions", path],
                         capture_output=True, text=True)
    out = []
    for line in res.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            crc = parts[0]
            crc = crc[2:].lower() if crc.startswith("0x") else crc.lower()
            out.append((parts[1], crc))
    return out


def exported_names(path):
    """Symbols a module exports: __ksymtab_<name> entries in the symbol table."""
    res = subprocess.run(["readelf", "-sW", path], capture_output=True, text=True)
    names = set()
    for line in res.stdout.splitlines():
        if "__ksymtab_" in line:
            for tok in line.split():
                if tok.startswith("__ksymtab_"):
                    names.add(tok[len("__ksymtab_"):])
    return names


def main():
    symvers = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SYMVERS
    kernel = load_symvers(symvers)
    print("kernel exports : %d" % len(kernel))

    mods = sorted(glob.glob(os.path.join(VENDOR, "**", "*.ko"), recursive=True))
    print("vendor modules : %d" % len(mods))

    vendor_exports = set()
    refs = {}
    for path in mods:
        base = os.path.basename(path)
        vendor_exports |= exported_names(path)
        refs[base] = referenced(path)
    print("vendor exports : %d symbols (provided by the modules themselves)" % len(vendor_exports))

    available = set(kernel) | vendor_exports

    missing = collections.Counter()
    missing_ex = {}
    mismatch = collections.Counter()
    mismatch_ex = {}
    bad = set()

    for base, pairs in refs.items():
        for name, crc in pairs:
            if name in vendor_exports:
                continue          # resolved by another vendor module
            if name not in kernel:
                missing[name] += 1
                missing_ex.setdefault(name, base)
                bad.add(base)
            elif kernel[name] != crc:
                mismatch[name] += 1
                mismatch_ex.setdefault(name, (base, crc, kernel[name]))
                bad.add(base)

    print()
    print("modules with real problems : %d" % len(bad))
    print("truly missing symbols      : %d" % len(missing))
    for name, cnt in missing.most_common(20):
        print("   MISSING  %-42s used by %3d modules (e.g. %s)" % (name, cnt, missing_ex[name]))
    print("crc mismatches             : %d" % len(mismatch))
    for name, cnt in mismatch.most_common(20):
        ex = mismatch_ex[name]
        print("   MISMATCH %-42s module=%s kernel=%s (e.g. %s)" % (name, ex[1], ex[2], ex[0]))

    if not missing and not mismatch:
        print()
        print("RESULT: ALL GOOD - every vendor module reference resolves, CRCs identical")
    else:
        print()
        print("RESULT: PROBLEMS FOUND")


main()
