"""Fail CI if packaging loses the thumbnail extension or changes the supported UTI."""
import plistlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    base='Payload/IPAUtility.app/'
    ext=base+'PlugIns/IPAThumbnail.appex/'
    app=plistlib.loads(z.read(base+'Info.plist'))
    plugin=plistlib.loads(z.read(ext+'Info.plist'))
    config=plugin['NSExtension']
    assert config['NSExtensionPointIdentifier']=='com.apple.quicklook.thumbnail'
    assert 'com.apple.itunes.ipa' in config['NSExtensionAttributes']['QLSupportedContentTypes']
    assert config['NSExtensionAttributes']['QLThumbnailMinimumDimension']==0
    assert plugin['CFBundleIdentifier'].startswith(app['CFBundleIdentifier']+'.')
    assert float(app['MinimumOSVersion'])<=16.7
    assert float(plugin['MinimumOSVersion'])<=16.7
    for path in (base+app['CFBundleExecutable'],ext+plugin['CFBundleExecutable']):
        assert len(z.read(path))>4096, 'Missing Mach-O executable: '+path
    print('IPA checked: executable, bundled thumbnail extension, matching UTI, iPadOS 16.7 compatibility.')
