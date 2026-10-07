<p align="center">
  <img src="App/Assets.xcassets/IPAUtilityIcon.appiconset/Icon-180.png" width="112" height="112" alt="IPA 图标">
</p>

<h1 align="center">IPA 图标 · IPAUtility</h1>

<p align="center">在 iPad「文件」中显示 IPA 包内的应用图标，并在本地整理名称与版本。</p>

<p align="center"><strong>v1.3 (5)</strong> · iOS / iPadOS 16.0+ · Swift · 本机处理</p>

## 能做什么

- **文件缩略图**：通过 Quick Look 扩展，为系统「文件」中的 IPA 提供应用图标。
- **本地 IPA 库**：批量复制导入，保留原文件；也可直接从「文件」复制到本地库。
- **名称与版本整理**：按「App 名称 版本号.ipa」重命名副本，同名自动编号，支持撤销上次操作。
- **应用信息**：查看名称、版本、构建号、Bundle ID、最低系统版本和图标来源。

**显示文件缩略图无需导入，也无需选择文件夹。** 导入用于查看详情和整理副本。

## 开始使用

1. 前往 [v1.3 Release](https://github.com/LxyveeX/IPAUtility/releases/tag/v1.3)，下载 `IPAUtility-v1.3-Unsigned.ipa`（未签名）。
2. 使用自己的证书签名安装，保留并签名 `PlugIns/IPAThumbnail.appex` 缩略图扩展。
3. 打开「IPA 图标」一次，再回到系统「文件」查看 IPA。云端文件先下载到本机；若视图提供「显示图标预览」，请开启。
4. 需要整理文件名时，点击「导入 IPA」；本地库位于「文件 → 我的 iPad → IPA 图标 → IPA」。

已验证安装包已归档至 Release，附有 SHA-256 校验文件、安装说明和版本记录。日常下载使用上方 Release；需要自行编译时，可在 [Actions](https://github.com/LxyveeX/IPAUtility/actions/workflows/build.yml) 选择 `main`，手动运行 **Build IPAUtility**。Actions 构建附件保留 30 天。

### 与签名工具共存

2026-10-07，用户在 **iPadOS 16.7** 上验证了以下安装顺序：

**先安装 IPAUtility → 再安装签名工具 → IPA 缩略图继续由 IPAUtility 提供。**

此前先安装签名工具时，IPA 显示为签名工具的文档图标；卸载该工具后，大部分 IPA 恢复显示包内图标。这一安装顺序已在该设备验证，其他系统和工具的表现有待验证。

## 当前状态

当前保留 **1.3 (5)**，暂缓功能迭代。最新真机反馈如下：

| 项目 | 状态 |
| --- | --- |
| 系统「文件」中的 IPA 图标 | 正常，安装顺序经验见上文 |
| 复制导入与本地库 | 正常 |
| 桌面应用图标 | 正常 |
| 多任务后台小图标 | 仍显示系统默认空白图标 |
| 个别 IPA 的图标清晰度 | 仍有一例偏模糊 |

1.3 已通过真机目标编译、18 项功能测试和 3 项界面测试。模拟器后台图标正常，真机后台图标问题仍保留在上表。

原位置的「选择文件」「选择文件夹」入口已移除，使用复制导入统一整理副本。

## 图标读取与数据处理

支持独立 PNG / JPEG、Apple CgBI PNG、旧式 `iTunesArtwork`，以及部分仅存于 `Assets.car` 中的 AppIcon。读取过程只提取应用信息与图标资源，限制解压大小并校验 CRC；IPA 内容在本机处理，不上传。

图标效果取决于包内资源，个别资源格式可能无法读取或清晰度有限。详细实现与兼容性见 [开发说明](docs/DEVELOPMENT.md)。

## 项目文档

- [开发与编译说明](docs/DEVELOPMENT.md)
- [版本更新记录](CHANGELOG.md)
- [历史验证记录](docs/DEVELOPMENT_HISTORY.md)
- [ZIPFoundation 第三方许可证](Vendor/ZIPFoundation/LICENSE)

**构建源码**：[`3b392c2`](https://github.com/LxyveeX/IPAUtility/commit/3b392c2ec915b8eca51f995c2245aaa5aa4b58ec) · **主分支**：`main`
