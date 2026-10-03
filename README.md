# IPA 图标 · IPAUtility

为 iPadOS 16.0+ 制作的 IPA 图标和文件名整理工具。Bundle ID 沿用测试版的 `com.lxyvee.ipautility`。

## 功能

- 内置 Quick Look Thumbnail Extension，为系统“文件”中的 IPA 提供包内应用图标。
- 选择“下载”里的文件夹后，直接在原位置读取 IPA，可包含子文件夹。
- 中文名称识别、版本号、构建号、Bundle ID、最低系统版本、图标来源。
- 默认开启点击应用卡片自动重命名：`App 名称 版本号.ipa`。
- 批量整理当前筛选结果、同名文件自动编号、撤销最近一次重命名。
- 系统缩略图检测；同内容 `.ipa` / `.ipacheck` 样本辅助定位文件类型关联。
- 全部文件处理在本机进行。

## 签名安装后

1. 签名工具中保留并签名 `PlugIns/IPAThumbnail.appex`，关闭“移除插件 / 扩展”。
2. 打开“IPA 图标”一次，选择存放 IPA 的子文件夹。
3. 回到系统“文件”，切换为“图标”视图；若提供“显示图标预览”选项，请开启。
4. iCloud 中的 IPA 先下载到本机。已有缩略图缓存可能需要退出“文件”重新打开。
5. 点开本 App 的应用卡片即可自动重命名；详情也可手动操作或检测系统缩略图。

“文件”中点按 IPA 的打开方式由系统和已有应用关联决定。通过本 App 打开的文件，在已授权文件夹内执行自动重命名。单个文件访问权限不能代替父文件夹的重命名权限，因此初次需选择文件夹。

## 图标读取

优先读取主应用 `Info.plist` 中声明的独立图标，支持普通 PNG、Apple CgBI PNG、JPEG 和旧式 `iTunesArtwork`。`Assets.car` 使用公开 UIKit 资源查询尝试读取；部分资源目录无法通过公开接口取得 AppIcon，此时显示具体原因。

解析仅提取名称与图标资源，限制解压大小并校验 CRC，不展开整个 IPA，不执行其中的应用代码。重命名不改变 IPA 字节内容。

缩略图扩展使用精确 UTI `com.apple.itunes.ipa`，与 Apple 的 Quick Look 扩展规则一致。其他签名/文件管理 App 若为 IPA 注册了不同 UTI，需要根据设备返回的实际类型继续适配。`.ipacheck` 样本用于区分扩展调用问题和 IPA 类型冲突。

## GitHub 构建

沿用此前已验证的 `macos-15-intel` 运行器。Actions 中运行 **Build IPAUtility**：

1. XcodeGen 生成 App、缩略图扩展和测试 target。
2. 编译 iPhone/iPad 真机 Release 二进制。
3. 在模拟器运行 8 项解析、CgBI、ZIP64、文件名和扩展打包配置测试。
4. 检查 IPA 确实包含扩展与正确 UTI，再上传 `IPAUtility-Unsigned` artifact。

解压 artifact 得到 `IPAUtility-Unsigned.ipa`，按此前方式签名安装。

## 当前验证状态

截至源代码准备阶段：已检查 Swift 语法树、plist / YAML、图标尺寸和样本 ZIP 完整性。**尚未进行 Xcode 编译、模拟器测试或 iPadOS 16.7 实机缩略图验证。** GitHub 接口可用后应首先运行 CI 并修复编译/测试结果，再交付正式 IPA。

## 开发

```sh
brew install xcodegen
python3 scripts/make_fixtures.py
xcodegen generate
```

打开生成的 `IPAUtility.xcodeproj`，选择 `IPAUtility` scheme。Xcode 工程由 `project.yml` 生成，不提交生成物。

ZIPFoundation 0.9.20 已随工程附带，MIT 许可证位于 `Vendor/ZIPFoundation/LICENSE`。固定上游提交：`22787ffb59de99e5dc1fbfe80b19c97a904ad48d`。

参考：[Apple 缩略图扩展文档](https://developer.apple.com/documentation/quicklookthumbnailing/providing-thumbnails-of-your-custom-file-types)。
