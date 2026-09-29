#!/usr/bin/env python3
"""Check pinned dependency coverage and byte-for-byte distributable notices."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'Core/Licenses'


def verify(bundle=None):
    manifest = json.loads((SOURCE / 'manifest.json').read_text())
    for lockfile in [ROOT / 'Package.resolved', ROOT / 'Teleprompter.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']:
        pins = json.loads(lockfile.read_text())['pins']
        assert {p['identity']: p['state'] for p in pins} == manifest['packages'], f'Dependency pins changed: update license inventory for {lockfile}'
    required = {
        'Argmax/LICENSE.txt', 'Argmax/NOTICES.txt', 'FluidAudio/LICENSE.txt',
        'SwiftArgumentParser/LICENSE.txt', 'Moonshine/LICENSE.txt',
        'Moonshine/ONNXRuntime-ThirdPartyNotices.txt',
        'Moonshine/third-party/Eigen/COPYING.MPL2', 'Moonshine/Eigen-Source-Availability.txt',
        'NemoTextProcessing/LICENSE.txt', 'NemoTextProcessing/NOTICE.txt',
        'Models/Moonshine/LICENSE.txt', 'Models/Whisper/OpenAI-MIT.txt',
        'Models/Whisper/Argmax-MIT.txt', 'Models/Parakeet/NVIDIA-Open-Model-License.pdf',
        'Models/Parakeet/NVIDIA-Open-Model-License.txt', 'Models/Parakeet/Notice.txt',
        'Models/Parakeet/NVIDIA-Trustworthy-AI.txt',
    }
    paths = {entry['path'] for entry in manifest['files']}
    assert required <= paths, f'Missing component notices: {required - paths}'
    assert len(paths) == len(manifest['files']), 'Duplicate notice paths'
    folders = [SOURCE]
    if bundle:
        resources = Path(bundle) / 'Contents/Resources'
        folders.append(resources / 'Licenses')
        for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md']:
            assert (resources / name).read_bytes() == (ROOT / name).read_bytes(), f'Stale or missing app document: {name}'
    for folder in folders:
        assert json.loads((folder / 'manifest.json').read_text()) == manifest, f'Stale manifest in {folder}'
        actual = {str(p.relative_to(folder)) for p in folder.rglob('*') if p.is_file() and p.name != 'manifest.json'}
        assert actual == paths, f'Incomplete or extra license documents in {folder}: {actual ^ paths}'
        for entry in manifest['files']:
            file = folder / entry['path']
            assert file.stat().st_size > 0, f'Empty license document: {file}'
            assert hashlib.sha256(file.read_bytes()).hexdigest() == entry['sha256'], f'License checksum changed: {file}'
        assert (folder / 'Models/Parakeet/Notice.txt').read_text().strip() == 'Licensed by NVIDIA Corporation under the NVIDIA Open Model License'
    print(f'License verification passed: {len(paths)} documents, {len(manifest["packages"])} pinned packages' + ('; app resources match' if bundle else ''))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, help='Also verify a built Teleprompter.app')
    verify(parser.parse_args().bundle)
