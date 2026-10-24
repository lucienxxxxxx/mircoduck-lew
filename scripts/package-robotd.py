#!/usr/bin/env python3
"""Build an upgrade ZIP from a pinned upstream runtime bundle and your compiled robotd."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE_SHA = 'bcfd5c183c697b9c4e0fdbd563d995eda6a48331a7c49b9e76d20bd156c65cce'
BASE_URL = ('https://raw.githubusercontent.com/kissqy/Microduck-kissqy/'
            'f02e875e73b88bf8ec7d5bbb34d0b461ac83b010/microduck-hd1910/firmware/'
            'console/updates/Microduck-Robotd-FT6-R17.tar.gz')
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--robotd', type=Path, default=ROOT/'dist/robotd')
    parser.add_argument('--base-archive', type=Path)
    args = parser.parse_args()
    binary = args.robotd.resolve()
    header = binary.read_bytes()[:20]
    if header[:6] != b'\x7fELF\x02\x01' or int.from_bytes(header[18:20], 'little') != 183:
        raise ValueError('robotd must be ELF64 little-endian AArch64')
    dist = ROOT/'dist'; dist.mkdir(exist_ok=True)
    archive = args.base_archive or dist/'upstream-control43.tar.gz'
    if not archive.is_file():
        urllib.request.urlretrieve(BASE_URL, archive)
    if sha(archive) != BASE_SHA:
        raise ValueError('Upstream bundle SHA256 does not match pinned control.43')
    metadata = json.loads((ROOT/'PROJECT.json').read_text(encoding='utf-8'))
    with tempfile.TemporaryDirectory(prefix='mircoduck-lew-', dir=dist) as temp:
        stage = Path(temp)
        with tarfile.open(archive) as source:
            for member in source.getmembers():
                name = PurePosixPath(member.name)
                if name.is_absolute() or '..' in name.parts or not (member.isfile() or member.isdir()):
                    raise ValueError('Unsupported archive member: ' + member.name)
            source.extractall(stage, filter='data')
        payload = stage/'Microduck-Robotd-FT6-R17'
        shutil.copy2(binary, payload/'robotd')
        shutil.copy2(ROOT/'scripts/install-robotd.sh', payload/'upgrade-lew.sh')
        identity = payload/'release_identity.py'
        text = identity.read_text(encoding='utf-8')
        text = re.sub(r'^BUILD = .*$', 'BUILD = '+repr(metadata['service_build']), text, flags=re.M)
        identity.write_text(text, encoding='utf-8')
        service = payload/'service.sh'; text = service.read_text(encoding='utf-8')
        start = text.index('    if [[ -f $temporary_dir/hd1910-calibration.toml ]]; then\n        if python3 -c')
        end = text.index('    install_log 成功', start)
        service.write_text(text[:start]+'    # mircoduck-lew: preserve calibration; always start commissioning.\n'+text[end:], encoding='utf-8')
        # Never distribute another assembled robot's measured calibration as a default.
        example = ROOT/'config/hd1910-calibration.example.toml'
        for name in ['hd1910-calibration.robot.toml','hd1910-calibration.training.toml','hd1910-calibration.template.toml']:
            shutil.copy2(example, payload/name)
        (payload/'robot-calibration-source.json').unlink(missing_ok=True)
        build = json.loads((payload/'BUILD.json').read_text(encoding='utf-8'))
        build.update(build=metadata['service_build'], project='mircoduck-lew', hardware_verified=False)
        build['built_binaries']['robotd'] = {'sha256':sha(payload/'robotd'),'bytes':(payload/'robotd').stat().st_size,'machine':'AArch64'}
        (payload/'BUILD.json').write_text(json.dumps(build,ensure_ascii=False,indent=2), encoding='utf-8')
        # Validate every executable and replace the upstream robotd's stale report.
        spec = importlib.util.spec_from_file_location('bundle_elf', payload/'elf_integrity.py')
        elf = importlib.util.module_from_spec(spec)
        previous_bytecode_setting = sys.dont_write_bytecode
        try:
            sys.dont_write_bytecode = True
            spec.loader.exec_module(elf)
        finally:
            sys.dont_write_bytecode = previous_bytecode_setting
        elf.validate_bundle(payload)
        report_path = payload/'ELF-CHECK.json'
        report = json.loads(report_path.read_text(encoding='utf-8'))
        versions = set(re.findall(rb'GLIBC_([0-9]+\.[0-9]+)', binary.read_bytes()))
        report['robotd'] = dict(elf.validate_elf(payload/'robotd'), sha256=sha(payload/'robotd'),
                               glibc_versions=[v.decode() for v in sorted(versions, key=lambda v: tuple(map(int,v.split(b'.'))))])
        report_path.write_text(json.dumps(report,indent=2), encoding='utf-8')
        shutil.copy2(ROOT/'NOTICE.md', payload/'MIRCODUCK-LEW-NOTICE.md')
        shutil.copy2(ROOT/'docs/INSTALL.md', payload/'MIRCODUCK-LEW-INSTALL.md')
        shutil.copytree(ROOT/'LICENSES', payload/'LICENSES')
        files = sorted(p for p in payload.rglob('*') if p.is_file() and p.name != 'SHA256SUMS')
        (payload/'SHA256SUMS').write_text(''.join(f'{sha(p)}  {p.relative_to(payload).as_posix()}\n' for p in files), encoding='utf-8')
        output = dist/f'mircoduck-lew-{metadata["version"]}-robotd.zip'
        with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
            for path in sorted(payload.rglob('*')):
                if path.is_file():
                    z.write(path, 'mircoduck-lew-upgrade/'+path.relative_to(payload).as_posix())
        with zipfile.ZipFile(output) as z:
            if z.testzip() is not None: raise ValueError('ZIP integrity failure')
        output.with_suffix(output.suffix+'.sha256').write_text(sha(output)+'  '+output.name+'\n')
        print(output)

if __name__ == '__main__':
    main()
