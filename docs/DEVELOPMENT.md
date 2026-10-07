# 开发与编译

## 环境

- macOS、Xcode、XcodeGen；已验证构建使用 Xcode 16.4。
- 最低部署版本 iOS / iPadOS 16.0，支持 iPhone 与 iPad；实际使用验证以 iPadOS 16.7 为主。
- Swift 5，少量 Objective-C 用于图标资源查询。

```sh
brew install xcodegen
python3 scripts/make_fixtures.py
python3 scripts/prepare_icons.py
xcodegen generate
```

打开生成的 `IPAUtility.xcodeproj`，选择 `IPAUtility` scheme。工程由 `project.yml` 生成。

## GitHub Actions

在仓库 Actions 中选择 **Build IPAUtility → Run workflow → main**。工作流会编译未签名真机包、在 iPad 模拟器运行测试、检查扩展与图标资源，最后上传 `IPAUtility-Unsigned`。解压附件后使用自己的证书签名安装。

当前 CI 使用 `macos-15-intel`。应用和 `IPAThumbnail.appex` 均需签名并一同安装。

## 目录

| 路径 | 用途 |
| --- | --- |
| `App/` | SwiftUI 界面、本地库、文件整理和图标检测 |
| `Shared/` | IPA 解析、图标解码和文件名生成 |
| `ThumbnailExtension/` | 系统 Quick Look 缩略图扩展 |
| `Tests/` | 解析、文件操作和系统缩略图集成测试 |
| `UITests/` | 原生复制导入、本地库和后台截图 |
| `scripts/` | 样本生成、独立图标准备、安装包校验 |
| `Vendor/ZIPFoundation/` | 固定版本的 ZIPFoundation 源码与许可证 |

## 图标查询

优先读取主应用 Info.plist 声明的独立图标，再尝试 `iTunesArtwork` 和 `Assets.car`。资源目录先使用 UIKit 查询；专用 AppIcon rendition 使用运行时可选的 CoreUI 查询，检查接口是否存在并捕获异常。CoreUI 属于未公开接口，其可用性和格式兼容性取决于系统版本。

只提取资源，不提取或执行 IPA 中的应用二进制。解压设置大小上限，读取后校验 CRC。测试用 IPA 均由本项目生成；用户上传的 IPA、证书和描述文件不纳入仓库。

## 1.3 验证

- 真机 Release 编译通过，主程序与缩略图扩展均为 ARM64，最低系统 iOS 16.0。
- 18 项功能测试通过，包括普通 / CgBI PNG、ZIP64、仅 CAR 图标、系统 Quick Look、复制导入、文件名整理。
- 3 项界面测试通过，覆盖系统复制选择器、直接打开本地库和系统后台截图。
- 后台截图在模拟器显示蓝色图标；iPadOS 16.7 真机仍显示默认图标，详见 [当前状态](../README.md#当前状态)。

构建：[37630479429](https://github.com/LxyveeX/IPAUtility/actions/runs/37630479429)。构建源码：`3b392c2ec915b8eca51f995c2245aaa5aa4b58ec`。

已交付 IPA 的 SHA-256：

```text
1bef006e5773d60fa7472627999162b4b0c6f1590b5b7c1b5096dc93063bd8d1
```

## 第三方组件

ZIPFoundation 0.9.20，MIT 许可证，固定上游提交 `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`。许可证保留在 [Vendor/ZIPFoundation/LICENSE](../Vendor/ZIPFoundation/LICENSE)。

[应用图标设计记录](ICON_DESIGN.txt) · [历史开发记录](DEVELOPMENT_HISTORY.md)
