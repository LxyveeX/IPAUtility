"""Copy all existing icon sizes as standalone PNG resources before XcodeGen.

The primary icon uses the Xcode-compiled catalog. Keep these extra resources
for IPA readers and signing previews that look for standalone PNGs.
"""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
source = root / 'App/Assets.xcassets/IPAUtilityIcon.appiconset'
destination = root / 'App/IconFiles'
destination.mkdir(exist_ok=True)
for points, scales in [(20, [1, 2, 3]), (29, [1, 2, 3]), (40, [1, 2, 3]),
                       (60, [2, 3]), (76, [1, 2]), (83.5, [2])]:
    for scale in scales:
        suffix = '' if scale == 1 else f'@{scale}x'
        shutil.copyfile(source / f'Icon-{int(points * scale)}.png',
                        destination / f'Icon{points}{suffix}.png')
print('Prepared standalone iPhone and iPad icons, including 20/29/40 pt system sizes.')
