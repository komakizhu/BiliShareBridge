#!/usr/bin/env python3
# Copyright (C) 2026 Komaki Zhu
# SPDX-License-Identifier: GPL-3.0-only
"""Build standalone TrollFools and jailbreak packages for BiliShareBridge."""
import hashlib
import json
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / 'work/sharebridge-packages'
SOURCES = [ROOT / 'src/BiliShareBridge.m', ROOT / 'src/SharePayload.m']
BUNDLE_IDS = ['tv.danmaku.bilianime', 'tv.danmaku.bilianime.blue']
PACKAGE_ID = 'com.github.komakizhu.bilisharebridge'
VERSION = '1.1.1'
MAINTAINER = 'Komaki Zhu <145947842+komakizhu@users.noreply.github.com>'
OUT = ROOT / f'outputs/plugins/BiliShareBridge/{VERSION}'
LIBRARY = 'BiliShareBridge.dylib'
FILTER_NAME = 'BiliShareBridge.plist'
FILTER = plistlib.dumps(
    {'Filter': {'Bundles': BUNDLE_IDS}},
    fmt=plistlib.FMT_XML,
    sort_keys=False,
)
INSTALL_PATH = Path('Library/MobileSubstrate/DynamicLibraries')
SCHEMES = [
    {
        'name': 'rootful',
        'arch': 'iphoneos-arm',
        'prefix': Path(),
        'minimum_ios': '13.0',
    },
    {
        'name': 'rootless',
        'arch': 'iphoneos-arm64',
        'prefix': Path('var/jb'),
        'minimum_ios': '15.0',
    },
    {
        'name': 'roothide',
        'arch': 'iphoneos-arm64e',
        'prefix': Path(),
        'minimum_ios': '15.0',
    },
]


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def compile_library(directory):
    thin = []
    for arch, minimum_ios in [('arm64', '13.0'), ('arm64e', '15.0')]:
        target = directory / f'{arch}/{LIBRARY}'
        target.parent.mkdir(parents=True)
        run([
            'xcrun', '--sdk', 'iphoneos', 'clang', '-arch', arch,
            f'-miphoneos-version-min={minimum_ios}', '-fobjc-arc', '-O2',
            '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
            '-Wno-deprecated-declarations', '-dynamiclib',
            '-framework', 'Foundation', '-framework', 'UIKit',
            '-framework', 'CoreGraphics', '-install_name',
            '@rpath/BiliShareBridge.dylib', *SOURCES, '-o', target,
        ])
        thin.append(target)

    universal = directory / LIBRARY
    run(['lipo', '-create', *thin, '-output', universal])
    run(['codesign', '--force', '--sign', '-', '--timestamp=none', universal])
    run(['codesign', '--verify', '--strict', universal])
    run(['lipo', universal, '-verify_arch', 'arm64', 'arm64e'])
    linked = subprocess.check_output(['otool', '-L', universal], text=True)
    for forbidden in ('CydiaSubstrate', 'Substitute', 'BiliNetworkCompat', 'BiliBiliTweak'):
        if forbidden in linked:
            raise ValueError(f'Unexpected external dependency in bridge: {forbidden}')
    return universal


def control_file(scheme):
    return (
        f'Package: {PACKAGE_ID}\n'
        f'Name: BiliShareBridge ({scheme["name"]})\n'
        f'Version: {VERSION}\n'
        f'Architecture: {scheme["arch"]}\n'
        f'Maintainer: {MAINTAINER}\n'
        'Section: Tweaks\n'
        f'Depends: firmware (>= {scheme["minimum_ios"]}), mobilesubstrate\n'
        'Description: Bilibili system share sheet and dual-app URL routing\n'
    )


def build_deb(library, scheme, output, directory):
    stage = directory / f'stage-{scheme["name"]}'
    install_dir = stage / scheme['prefix'] / INSTALL_PATH
    debian_dir = stage / 'DEBIAN'
    install_dir.mkdir(parents=True)
    debian_dir.mkdir()
    shutil.copy2(library, install_dir / LIBRARY)
    (install_dir / FILTER_NAME).write_bytes(FILTER)
    (debian_dir / 'control').write_text(control_file(scheme))
    run(['dpkg-deb', '--build', '--root-owner-group', stage, output])

    fields = {
        name: subprocess.check_output(['dpkg-deb', '-f', output, name], text=True).strip()
        for name in ('Package', 'Version', 'Architecture', 'Depends')
    }
    expected = [PACKAGE_ID, VERSION, scheme['arch']]
    actual = [fields['Package'], fields['Version'], fields['Architecture']]
    if actual != expected or f'firmware (>= {scheme["minimum_ios"]})' not in fields['Depends']:
        raise ValueError(f'Unexpected Debian control fields in {output.name}: {fields}')

    extracted = directory / f'extracted-{scheme["name"]}'
    run(['dpkg-deb', '-x', output, extracted])
    installed = extracted / scheme['prefix'] / INSTALL_PATH
    actual_library = installed / LIBRARY
    actual_filter = installed / FILTER_NAME
    if sha256(actual_library) != sha256(library):
        raise ValueError(f'Packaged dylib differs in {output.name}')
    if plistlib.loads(actual_filter.read_bytes()) != {'Filter': {'Bundles': BUNDLE_IDS}}:
        raise ValueError(f'Unexpected app filter in {output.name}')

    package_list = subprocess.check_output(['dpkg-deb', '--contents', output], text=True)
    expected_path = str(Path(scheme['prefix']) / INSTALL_PATH / LIBRARY)
    if expected_path not in package_list or str(Path(scheme['prefix']) / INSTALL_PATH / FILTER_NAME) not in package_list:
        raise ValueError(f'Package paths do not match {scheme["name"]} layout')
    return {
        'scheme': scheme['name'],
        'file': str(output.relative_to(ROOT)),
        'architecture': scheme['arch'],
        'minimum_ios': scheme['minimum_ios'],
        'bundle_ids': BUNDLE_IDS,
        'sha256': sha256(output),
        'bytes': output.stat().st_size,
        'archive_check': 'passed',
        'filter_check': 'passed',
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    artifacts = [
        OUT / LIBRARY,
        OUT / 'BiliShareBridge-TrollFools.zip',
        *(OUT / f'BiliShareBridge_{VERSION}_{scheme["arch"]}.deb' for scheme in SCHEMES),
        OUT / 'packages-manifest.json',
    ]
    existing = [str(path) for path in artifacts if path.exists()]
    if existing:
        raise FileExistsError('Refusing to overwrite existing package artifacts: ' + ', '.join(existing))

    with tempfile.TemporaryDirectory(prefix='build-', dir=WORK) as temporary:
        directory = Path(temporary)
        built = compile_library(directory)
        shutil.copy2(built, OUT / LIBRARY)

        trollfools_zip = OUT / 'BiliShareBridge-TrollFools.zip'
        with zipfile.ZipFile(trollfools_zip, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            archive.write(OUT / LIBRARY, LIBRARY)
        with zipfile.ZipFile(trollfools_zip) as archive:
            if archive.testzip() is not None or archive.namelist() != [LIBRARY]:
                raise ValueError('TrollFools ZIP failed archive or contents validation')
            if hashlib.sha256(archive.read(LIBRARY)).hexdigest() != sha256(OUT / LIBRARY):
                raise ValueError('TrollFools ZIP contains a different dylib')

        packages = []
        for scheme in SCHEMES:
            output = OUT / f'BiliShareBridge_{VERSION}_{scheme["arch"]}.deb'
            packages.append(build_deb(built, scheme, output, directory))

        manifest = {
            'name': 'BiliShareBridge',
            'version': VERSION,
            'source_files': [str(path.relative_to(ROOT)) for path in SOURCES],
            'source_sha256': {str(path.relative_to(ROOT)): sha256(path) for path in SOURCES},
            'architectures': ['arm64', 'arm64e'],
            'dylib_sha256': sha256(OUT / LIBRARY),
            'trollfools': {
                'file': str(trollfools_zip.relative_to(ROOT)),
                'sha256': sha256(trollfools_zip),
                'archive_check': 'passed',
            },
            'jailbreak_packages': packages,
            'BiliNetworkCompat_included': False,
            'embedded_ipa_duplicate_warning': (
                "Do not inject into this repository's 8.76 IPA builds; those already embed BiliShareBridge."
            ),
            'device_injection_tested': False,
            'device_share_tested': False,
        }
        manifest_path = OUT / 'packages-manifest.json'
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')

    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
