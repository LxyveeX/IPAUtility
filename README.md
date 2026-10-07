# IPA 图标 · IPAUtility

为 iPadOS 16.0+ 制作的 IPA 图标和文件名整理工具。Bundle ID 沿用测试版的 `com.lxyvee.ipautility`。

## 功能

- 1.1：兼容万能签的 `sign.wnqapp.com.ipa` 类型；系统图标改用完整的独立 PNG。
- 复制导入一个或多个 IPA 到本地库，原文件保留。
- 内置 Quick Look Thumbnail Extension，为系统“文件”中的 IPA 提供包内应用图标。
- 缩略图由系统自动请求，无需选择文件或文件夹；本地库用于整理副本。
- 中文名称识别、版本号、构建号、Bundle ID、最低系统版本、图标来源。
- 默认开启点击应用卡片自动重命名：`App 名称 版本号.ipa`。
- 批量整理当前筛选结果、同名文件自动编号、撤销最近一次重命名。
- 系统缩略图检测；同内容 `.ipa` / `.ipacheck` 样本辅助定位文件类型关联。
- 全部文件处理在本机进行。

## 签名安装后

1. 签名工具中保留并签名 `PlugIns/IPAThumbnail.appex`，关闭“移除插件 / 扩展”。
2. 打开“IPA 图标”一次；显示文件缩略图无需导入。需要整理名称时再导入本地库。
3. 回到系统“文件”，切换为“图标”视图；若提供“显示图标预览”选项，请开启。
4. iCloud 中的 IPA 先下载到本机。已有缩略图缓存可能需要退出“文件”重新打开。
5. 点开本 App 的应用卡片即可自动重命名；详情也可手动操作或检测系统缩略图。

“文件”中点按 IPA 的打开方式由系统和已有应用关联决定。通过本 App 打开的外部文件会立即显示详情，可复制导入本地库整理名称。单个文件访问权限不能代替父文件夹的重命名权限；1.3 移除原位置选择入口，保留已在用户设备验证可用的复制导入。

## 图标读取

优先读取主应用 `Info.plist` 中声明的独立图标，支持普通 PNG、Apple CgBI PNG、JPEG 和旧式 `iTunesArtwork`。`Assets.car` 先使用公开 UIKit 资源查询，再使用可选 CoreUI 图标查询读取专用 AppIcon rendition。后者属于未公开接口，运行时检查可用性并捕获异常；不同 iOS / 资源格式仍可能不兼容。仅查询主图标名称，不遍历任意界面素材。

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


## 1.2：按真机对照结果修正

2026-10-07 用户截图显示：同内容 `.ipacheck` 返回自定义图标，`.ipa` 仍是万能签的文档图标。因此当前重签名环境可以运行缩略图扩展；标识错配不能被当作“扩展完全不可用”的已证实原因。文件选择器的具体故障仍待真机确认。

- 去掉缩略图绘制中额外的圆角裁剪，避免 iOS 白色文档底板露出四角；保持原始图标满幅绘制。系统本身的装饰不属于应用可控制范围。
- 新增本 App 导出的 IPA 类型，并保持 Apple IPA / 万能签类型的精确支持。现有文件关联由系统决定，不能仅凭声明推断已经接管。
- 新增复制导入（`asCopy: true`）和无需选择器的本地 IPA 库；复制导入保留原文件、遇到同名文件另存，整理发生在副本上。原文件夹整理入口继续保留。
- 使用说明内增加无需选文件的一键检测，分别记录实际 UTI、自动判型和指定类型的系统请求结果。
- 新增原生选择器实际点击“打开”的 UI 测试，以及缩略图四角像素、复制导入不覆盖测试。模拟器测试不能替代 iPadOS 16.7 的重签名后测试。

源码中的 Debug UI 测试样本开关不进入 Release 包。用户签名包、证书和描述文件不会写入仓库。后台默认图标仍未在真机确认解决。

首轮 1.2 CI：17 项功能测试（含缩略图四角和复制导入）通过；本地库 UI 测试通过，两个原生选择器 UI 测试失败。失败时的界面树显示已回到空主页，选中文件未交给模型。因此删除通过 `onDismiss` 再读取临时 SwiftUI State 的中转，在原生 delegate 回调中直接处理选中结果，再复跑同一组 UI 测试。

第二轮 CI：17 项功能测试、本地库 UI、原生文件夹“打开”流程通过。复制选择器测试停在空“最近项目”页面，未进入选文件步骤；失败界面树显示远程选择器导航不完整。改为由 UIKit 原生模态呈现选择器，继续保留 delegate 直接处理结果。

### 1.2 最终验证与安装包

2026-10-07 已通过真机 Release 编译、17 项功能测试和 3 项 iPad 原生 UI 测试，全部零失败。UI 测试实际点击系统“打开”，验证文件夹返回列表、复制导入生成 `Picker Sample (2).ipa` 副本，以及无需选择器的本地库入口。系统缩略图测试检查四角像素已满幅绘制。最终包已检查 ARM64 主程序/扩展、最低 iOS 16.0、版本 1.2 (4)、独立图标及类型声明。

构建记录：[Build IPAUtility](https://github.com/LxyveeX/IPAUtility/actions/runs/37614864221)。构建源码提交：`0532b1be1ece5e9a157feb601c589e563c5a2f0b`。IPA SHA-256：`6ab4c50a3f92b99f22abc82a549f711f9a36c6f1e1f6e1a3b5502460d0037f4f`。

安装后使用“⋯ → 使用说明与图标检测 → 一键检测”生成带版本号和随机名称的新样本，减少旧缓存干扰。普通 `.ipa` 在用户 iPadOS 16.7 上的类型关联、选择器行为和后台图标仍需真机复测；这些不能从模拟器通过推断为全部解决。


## 1.3：按最新真机反馈收敛

用户卸载万能签后，大部分 IPA 已在系统“文件”正常显示图标；复制导入也确认可用。原位置文件/文件夹选择仍无响应，因此移除这些界面入口，保留复制导入、本地库及外部文件详情。显示缩略图无需导入或文件夹授权。

Lanerc 1.0.8 的主图标只有 `Assets.car` 内的 AppIcon，没有独立 PNG。已在本地解析并验证 1024×1024 图像；新增 CoreUI 专用图标查询用于 App 和扩展。仓库测试使用本项目自己的编译资源生成“仅 CAR”的 IPA，不包含用户上传的 IPA 或资源。

后台图标恢复由 Xcode 编译生成的主 AppIcon 声明，资源名称更新为 `IPAUtilityIcon`，保留独立 PNG 供签名预览读取。新增系统 App Switcher 截图供人工核对；截图及模拟器检查不能证明 iPadOS 16.7 重签名后的结果，真机后台图标仍待确认。
