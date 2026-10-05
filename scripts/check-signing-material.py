#!/usr/bin/env python3
"""Reject tracked private signing files without displaying their contents.

Checks the Git index (the checked-out commit in CI), not untracked operator
credentials. This prevents new exposure; it cannot revoke historical keys.
"""
import pathlib
import subprocess
import sys


def violations():
    files = subprocess.check_output(["git", "ls-files", "-z"]).split(b"\0")
    blocked = {p for p in files if p and pathlib.PurePosixPath(
        p.decode("utf-8", "surrogateescape")).suffix.lower() in {".p8", ".p12", ".pfx"}}
    # Names only, never matched lines. Split construction keeps the scanner's
    # source from containing an actual PEM boundary of its own.
    pattern = r"^[[:space:]]*-----BEGIN ([A-Z0-9]+ )?" + r"PRIVATE KEY-----[[:space:]]*$"
    result = subprocess.run(
        ["git", "grep", "--cached", "-Ilz", "-E", "--", pattern, "--", "."],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError("Git signing-material scan could not complete")
    blocked.update(p for p in result.stdout.split(b"\0") if p)
    return sorted(blocked)


def main():
    try:
        blocked = violations()
    except (OSError, subprocess.SubprocessError, RuntimeError):
        print("Signing-material scan failed; refusing a partial result.", file=sys.stderr)
        return 2
    if blocked:
        print("Private signing material is tracked; remove it and assess revocation:", file=sys.stderr)
        for path in blocked:
            # repr escapes hostile filenames and control characters in CI logs.
            print(repr(path.decode("utf-8", "surrogateescape")), file=sys.stderr)
        return 1
    print("No tracked signing files or standalone private-key PEM boundaries found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
