"""Deterministic local IPA fixtures. All fixture applications are synthetic."""
from pathlib import Path
import plistlib, struct, zlib, zipfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'Tests/Fixtures'
FIXTURES.mkdir(parents=True, exist_ok=True)

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

def png(crushed=False):
    w, h = 8, 5
    pixels = [(20+x*8, 100+y*12, 180, 255) for y in range(h) for x in range(w)]
    rows = []
    previous = bytes(w*4)
    for y in range(h):
        row = bytes(v for r,g,b,a in pixels[y*w:(y+1)*w] for v in ((b,g,r,a) if crushed else (r,g,b,a)))
        filt = y
        out = bytearray([filt])
        for x, v in enumerate(row):
            a = row[x-4] if x >= 4 else 0
            b = previous[x]
            c = previous[x-4] if x >= 4 else 0
            q = a+b-c
            distances = (abs(q-a), abs(q-b), abs(q-c))
            predictor = (0, a, b, (a+b)//2, (a,b,c)[distances.index(min(distances))])[filt]
            out.append((v-predictor) % 256)
        rows.append(out)
        previous = row
    compress = zlib.compressobj(wbits=-15 if crushed else 15)
    payload = compress.compress(b''.join(rows))+compress.flush()
    return b'\x89PNG\r\n\x1a\n' + (chunk(b'CgBI', b'\x40\xa0\x60\x82') if crushed else b'') + chunk(b'IHDR', struct.pack('>IIBBBBB',w,h,8,6,0,0,0)) + chunk(b'IDAT',payload) + chunk(b'IEND',b'')

def ipa(path, *, icon=None, localized=False, malformed=False, zip64=False, artwork=False):
    info = {'CFBundleName':'Fixture', 'CFBundleDisplayName':'Test App', 'CFBundleShortVersionString':'2.3.4',
            'CFBundleVersion':'57', 'CFBundleIdentifier':'example.fixture', 'MinimumOSVersion':'16.0',
            'CFBundleIcons':{'CFBundlePrimaryIcon':{'CFBundleIconFiles':['AppIcon60x60']}}}
    files = {'Payload/Fixture.app/Info.plist':plistlib.dumps(info,fmt=plistlib.FMT_BINARY)}
    if localized:
        files['Payload/Fixture.app/zh-Hans.lproj/InfoPlist.strings'] = plistlib.dumps({'CFBundleDisplayName':'示例应用'})
        files['Payload/Fixture.app/en.lproj/InfoPlist.strings'] = plistlib.dumps({'CFBundleDisplayName':'English App'})
        files['Payload/Fixture.app/PlugIns/Wrong.appex/Info.plist'] = plistlib.dumps({'CFBundleDisplayName':'Wrong'})
    if icon: files['iTunesArtwork' if artwork else 'Payload/Fixture.app/AppIcon60x60@3x.png'] = icon
    if malformed: files = {'README.txt':b'not an IPA'}
    with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            info = zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0)); info.compress_type = zipfile.ZIP_DEFLATED
            with z.open(info,'w',force_zip64=zip64) as f: f.write(data)

(FIXTURES/'ordinary.png').write_bytes(png())
(FIXTURES/'crushed.png').write_bytes(png(True))
ipa(FIXTURES/'localized.ipa',icon=png(),localized=True)
ipa(FIXTURES/'crushed.ipa',icon=png(True))
ipa(FIXTURES/'zip64.ipa',icon=png(),zip64=True)
ipa(FIXTURES/'artwork.ipa',icon=png(),artwork=True)
ipa(FIXTURES/'no-icon.ipa')
ipa(FIXTURES/'invalid.ipa',malformed=True)
icon = (ROOT/'App/Assets.xcassets/AppIcon.appiconset/Icon-180.png').read_bytes()
ipa(ROOT/'App/ThumbnailSample.ipa',icon=icon,localized=True)
print('Created 8 parser fixtures and one Files thumbnail sample.')
