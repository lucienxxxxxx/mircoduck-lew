#!/usr/bin/env python3
"""Download pinned optional console resources; never read or upload local credentials."""
import argparse
import hashlib
from pathlib import Path
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REV = 'f02e875e73b88bf8ec7d5bbb34d0b461ac83b010'
BASE = f'https://raw.githubusercontent.com/kissqy/Microduck-kissqy/{REV}/microduck-hd1910/firmware/console/'
RESOURCES = {
    'static/assets/duck-visual.bin': '2051b738abb89cc672923ee9ae4705354e0760ba90238398eb402ba453b06d98',
}

def obtain(relative, digest):
    output = ROOT / 'console' / relative
    if output.is_file() and hashlib.sha256(output.read_bytes()).hexdigest() == digest:
        print('Verified:', relative)
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + '.download')
    try:
        with urllib.request.urlopen(BASE + relative, timeout=60) as source, temporary.open('wb') as dest:
            while chunk := source.read(1024 * 1024):
                dest.write(chunk)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != digest:
            raise ValueError('Resource SHA256 mismatch: ' + relative)
        temporary.replace(output)
        print('Downloaded and verified:', relative)
    finally:
        temporary.unlink(missing_ok=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-geometry', action='store_true')
    args = parser.parse_args()
    if not args.no_geometry:
        for name, digest in RESOURCES.items():
            obtain(name, digest)
    if sys.platform == 'win32' and not (ROOT/'console/ssh-askpass.exe').exists():
        print('Windows password login requires console/ssh-askpass.exe; build it as documented in docs/BUILD.md.')
