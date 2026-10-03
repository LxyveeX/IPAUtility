# IPA 图标 · IPAUtility

为 iPadOS 16.0+ 制作的 IPA 图标和文件名整理工具。Bundle ID 沿用测试版的 `com.lxyvee.ipautility`。

## 功能

- 1.1：兼容万能签的 `sign.wnqapp.com.ipa` 类型；系统图标改用完整的独立 PNG。
- 可直接选择一个或多个 IPA 读取信息，也可从所选文件定位父文件夹再授权。
- 内置 Quick Look Thumbnail Extension，为系统“文件”中的 IPA 提供包内应用图标。
- 选择“下载”里的文件夹后，直接在原位置读取 IPA，可包含子文件夹。
- 中文名称识别、版本号、构建号、Bundle ID、最低系统版本、图标来源。
- 默认开启点击应用卡片自动重命名：`App 名称 版本号.ipa`。
- 批量整理当前筛选结果、同名文件自动编号、撤销最近一次重命名。
- 系统缩略图检测；同内容 `.ipa` / `.ipacheck` 样本辅助定位文件类型关联。
- 全部文件处理在本机进行。

## 签名安装后

1. 签名工具中保留并签名 `PlugIns/IPAThumbnail.appex`，关闭“移除插件 / 扩展”。
2. 打开“IPA 图标”一次。可先选择一个 IPA；文件夹模式需在“浏览”中进入目标文件夹后点“打开”。
3. 回到系统“文件”，切换为“图标”视图；若提供“显示图标预览”选项，请开启。
4. iCloud 中的 IPA 先下载到本机。已有缩略图缓存可能需要退出“文件”重新打开。
5. 点开本 App 的应用卡片即可自动重命名；详情也可手动操作或检测系统缩略图。

“文件”中点按 IPA 的打开方式由系统和已有应用关联决定。通过本 App 打开的文件会立即显示详情，在已授权文件夹内执行自动重命名。单个文件访问权限不能代替父文件夹的重命名权限；单文件模式通过主页的“定位并授权所在文件夹”继续授权。选择器的起始目录是系统提示，部分云文件提供商可能忽略它。

## 图标读取

优先读取主应用 `Info.plist` 中声明的独立图标，支持普通 PNG、Apple CgBI PNG、JPEG 和旧式 `iTunesArtwork`。`Assets.car` 使用公开 UIKit 资源查询尝试读取；部分资源目录无法通过公开接口取得 AppIcon，此时显示具体原因。

解析仅提取名称与图标资源，限制解压大小并校验 CRC，不展开整个 IPA，不执行其中的应用代码。重命名不改变 IPA 字节内容。

缩略图扩展同时支持精确 UTI `com.apple.itunes.ipa` 与 `sign.wnqapp.com.ipa`。后者根据万能签官网公开的 27.1.0 安装包静态检查确认，它导出该类型并以 Owner 注册打开方式。来源为官网 `https://sign.wnqapp.com/dh/` 中链接的公开安装包，SHA-256 为 `243c254cbfa52a9e4d5bb480a7ff394d19a2a2b98050164da004e55fc9a99f6b`。仓库不包含万能签的代码或二进制。

其他工具若登记不同类型，可在详情“检测系统缩略图”中查看实际类型、匹配状态及系统返回结果，再分享检测文本。`.ipacheck` 样本用于区分扩展调用问题和 IPA 类型冲突。

## GitHub 构建

沿用此前已验证的 `macos-15-intel` 运行器。Actions 中运行 **Build IPAUtility**：

1. XcodeGen 生成 App、缩略图扩展和测试 target。
2. 编译 iPhone/iPad 真机 Release 二进制。
3. 在 iPad 模拟器运行解析、CgBI、ZIP64、文件名、单文件访问、选择器回调和系统缩略图调用测试；分别请求自动判型、Apple IPA 类型和万能签 IPA 类型。
4. 检查 IPA 确实包含扩展与正确 UTI，再上传 `IPAUtility-Unsigned` artifact。

解压 artifact 得到 `IPAUtility-Unsigned.ipa`，按此前方式签名安装。

## 1.0 验证记录与 1.1 修复

2026-10-03 已通过 Xcode 16.4 真机 Release 编译，9 项模拟器测试全部通过（0 失败），包括由系统 Quick Look 实际调用扩展生成 IPA 缩略图。最终 IPA 已检查 ARM64 真机二进制、iOS 16.0 最低版本、嵌入的缩略图扩展、UTI 和 SHA-256。

构建记录：[Build IPAUtility #4](https://github.com/LxyveeX/IPAUtility/actions/runs/37125202958)。构建代码提交：`82d6c3cf65d4778102cdfa90d5168a0adc9e3174`。IPA SHA-256：`0fbf5c5560f37e7de51b8afc492b867a852206f8611f495008fe5e3327c59f2e`。

用户在 iPadOS 16.7 上反馈：后台图标缺失、万能签接管 IPA、文件夹选择无响应。1.1 针对这些问题补齐精确类型支持，改用独立 PNG 图标，显式结束选择器并增加单文件备用入口。模拟器通过不能替代真实设备重新签名后的验证。

1.1 已通过真机 Release 编译和 15 项 iPad 模拟器测试（0 失败），包括自动判型、Apple IPA 类型、万能签 IPA 类型的真实系统缩略图生成，以及单文件读取、外部文件打开、选择/取消回调与小尺寸图标校验。最终包已检查 ARM64、iOS 16.0 最低版本、独立 PNG 和缩略图扩展。

构建记录：[Build IPAUtility #5](https://github.com/LxyveeX/IPAUtility/actions/runs/37128460304)。代码提交：`369215cae190714abbd5a84f510e975c16ad056a`。1.1 IPA SHA-256：`abfa340133b5a460bd5a30c5614b1c6718cf7b903fb77984d5bb250cf25ebf95`。

## 开发

```sh
brew install xcodegen
python3 scripts/make_fixtures.py
python3 scripts/prepare_icons.py
xcodegen generate
```

打开生成的 `IPAUtility.xcodeproj`，选择 `IPAUtility` scheme。Xcode 工程由 `project.yml` 生成，不提交生成物。

ZIPFoundation 0.9.20 已随工程附带，MIT 许可证位于 `Vendor/ZIPFoundation/LICENSE`。固定上游提交：`22787ffb59de99e5dc1fbfe80b19c97a904ad48d`。

参考：[Apple 缩略图扩展文档](https://developer.apple.com/documentation/quicklookthumbnailing/providing-thumbnails-of-your-custom-file-types)。

## 1.1 真机复测反馈（待排查）

用户在 iPadOS 16.7 安装 1.1 后反馈：后台仍为默认图标，IPA 文件缩略图未出现，文件和文件夹选择器的确认按钮都没有作用。现有 15 项测试覆盖模型、回调函数和系统缩略图请求；没有覆盖真实选择界面的点击流程，也没有验证万能签重新签名后的安装结果。当前不能把这些测试记作上述三个问题已解决。

已调整独立图标声明顺序，让大尺寸图片优先，避免按列表第一项取图的预览器使用 20 pt 小图。尚未发布新安装包；下一步需要对比用户实际安装的已签名 IPA 中的身份、签名权限、主程序与扩展配置，并查看卡住的选择界面。万能签原安装保持不动。
