"""Fail CI if packaging loses the thumbnail extension or changes the supported UTI."""
import plistlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    base='Payload/IPAUtility.app/'
    ext=base+'PlugIns/IPAThumbnail.appex/'
    app=plistlib.loads(z.read(base+'Info.plist'))
    plugin=plistlib.loads(z.read(ext+'Info.plist'))
    config=plugin['NSExtension']
    assert config['NSExtensionPointIdentifier']=='com.apple.quicklook.thumbnail'
    assert {'com.apple.itunes.ipa', 'sign.wnqapp.com.ipa', 'com.lxyvee.ipautility.ipa'} <= set(config['NSExtensionAttributes']['QLSupportedContentTypes'])
    assert config['NSExtensionAttributes']['QLThumbnailMinimumDimension']==0
    assert plugin['CFBundleIdentifier'].startswith(app['CFBundleIdentifier']+'.')
    assert float(app['MinimumOSVersion'])<=16.7
    assert float(plugin['MinimumOSVersion'])<=16.7
    for path in (base+app['CFBundleExecutable'],ext+plugin['CFBundleExecutable']):
        assert len(z.read(path))>4096, 'Missing Mach-O executable: '+path
    for key in ('CFBundleIcons', 'CFBundleIcons~ipad'):
        icon = app[key]['CFBundlePrimaryIcon']
        assert not icon.get('CFBundleIconName'), 'Icon should use standalone PNGs'
        assert {'Icon20', 'Icon29', 'Icon40'} <= set(icon['CFBundleIconFiles'])
        for name in icon['CFBundleIconFiles']:
            assert base + name + '@2x.png' in z.namelist(), 'Missing 2x icon: '+name
    assert 'com.lxyvee.ipautility.ipa' in {x['UTTypeIdentifier'] for x in app['UTExportedTypeDeclarations']}
    assert app['CFBundleShortVersionString'] == '1.2'
    print('IPA checked: standalone system icons, both IPA UTIs, thumbnail extension and iPadOS 16.7 compatibility.')
