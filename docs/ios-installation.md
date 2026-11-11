# iOS 实验性版本：自行签名安装

GitHub Release 提供 `fknotes-<版本>-ios-unsigned.ipa`，适用于 **iOS 15.5 及以上的 ARM64 iPhone**。这是需要用户自行签名的实验性包，不能在 Safari 或“文件”中点击后直接安装；不是 App Store / TestFlight 版本，也不是已通过真机验收的正式 iOS 版本。

本项目发布未签名包无需购买 Apple 开发者会员。用户可以使用自己的免费 Apple 账号，通过第三方工具签名安装；这仍会使用 Apple 的开发签名服务，不能完全免账号安装。免费签名通常 **7 天到期**，到期前需刷新；免费账号每台设备最多安装 3 个此类应用，扩展还会占用 App ID 配额。以 [Apple 账号限制](https://developer.apple.com/help/account/basics/about-your-developer-account)与工具当前规则为准。

## 下载与校验

在[项目 Releases](https://github.com/wsshow/feikong-notes/releases)的同一个版本中下载：

- `fknotes-<版本>-ios-unsigned.ipa`：待签名应用，包含分享扩展。
- `SHA256SUMS.txt`：包含 IPA 的 SHA-256 校验值。

安装教程统一维护在 `docs/ios-installation.md`，发布说明链接到对应构建的文档提交。[App Group 权限模板](ios-signing-entitlements.plist)也在 `docs/`，仅供高级签名参考，不是证书或描述文件；普通安装无需额外下载。构建来源与校验元数据保留在 CI 工作流产物中，不作为 Release 下载附件。

在 macOS 终端运行 `shasum -a 256 <IPA文件路径>`，或在 Windows PowerShell 运行 `Get-FileHash <IPA文件路径> -Algorithm SHA256`，与校验文件中同名文件对应的值比较。不一致时重新下载，不继续签名。

## 使用 Sideloadly 安装

以下是依据工具官方说明整理的操作流程，**本项目尚未完成该流程的真机实测**。具体菜单随工具版本可能变化；不能保证每个 iOS / 工具组合都能完成安装。

1. 从 [Sideloadly 官网](https://sideloadly.io/)安装 macOS 或 Windows 版本，按工具说明准备设备驱动等依赖。
2. 用数据线连接 iPhone，解锁手机并信任这台电脑，在工具中选择该设备。
3. 将下载的 IPA 拖入工具，选择使用 Apple ID 签名安装的模式，填写自己的 Apple 账号，按工具提示完成认证。账号密码和验证码只在你信任的工具或 Apple 界面输入，不发送给本项目维护者。
4. 首次尝试保留分享扩展；不降低应用最低系统版本，不启用插件注入或无关修改。启动签名与安装，等待工具报告完成。
5. 如系统提示，在“设置 → 通用 → VPN 与设备管理”中信任对应开发者；iOS 16 及以上按系统提示启用“设置 → 隐私与安全性 → 开发者模式”，重启并确认。开发者模式要求见 [Apple 文档](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。
6. 打开应用，先用临时测试笔记检查创建、编辑、退出后重开与备份导出，再决定是否用于日常记录。

也可使用 [AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore)，按其官方安装说明部署 AltServer / AltStore 后，在 My Apps 导入 IPA 并签名。AltStore 本身会占用应用名额；它提供刷新操作，但后台自动刷新不保证总能及时完成。这里指 Classic 自行签名方案，不是欧盟市场分发。

## 分享扩展与 App Group

主应用标识是 `com.fknotes.app`，扩展是 `com.fknotes.app.ShareExtension`，共享组是 `group.com.fknotes.app`。未签名包没有可供工具直接复用的开发者签名权限；第三方工具能否正确创建、映射并签入共享组，**尚未验证**。

- 完整签名需要主应用与扩展归属同一 Team，并在各自描述文件与签名权限中使用同一有效 App Group。若签名工具改写共享组，还须同步修改两个 `Info.plist` 的 `FKNotesAppGroup`；仅修改 Bundle ID 或附加权限模板不够。
- 文档中的[权限模板](ios-signing-entitlements.plist)只是原始配置参考，不能把不属于自己账号的组直接签进去。需要自定义组时，有开发环境的用户可按[源码构建文档](ios-development.md)配置自己的 Bundle ID、Team 与 App Group 后重新构建。
- 如果安装日志明确报扩展或共享组签名失败，可在工具支持时移除分享扩展后重新尝试。这样会失去从 Safari、照片、文件等应用通过系统分享导入笔记的能力；主应用其他能力仍须实际验证，不能据此承诺安装成功。

## 续签、更新与备份

- 免费签名到期后应用通常无法打开。定期连接签名工具刷新，在到期前通过应用内“备份”导出到应用之外；到期本身不代表笔记已被删除。
- 续签或升级时尽量沿用同一 Apple 账号、签名工具和最终 Bundle ID，覆盖安装。改变这些设置可能无法访问原有数据或凭据；本项目尚未验证重签升级的数据保留。
- **不要为了续签而先卸载应用。** 卸载可能删除笔记与附件；卸载、换账号或更换安装方式前应先完成并检查应用内备份。
- 应用受管数据已排除系统自动备份，不能依赖 iCloud 系统恢复。Android ↔ iOS 备份迁移尚未完成真机验收，保留原端数据与备份。
- iOS 更新仍需手动下载新版 IPA 并重新签名；Android 应用内安装包更新流程不适用于 iOS。

## 实验性与未验证范围

已验证无签名 iPhone ARM64 Release 构建、原生依赖及资源打包；ARM64 模拟器验证了中英文 OCR 与 MNN CPU 的加载、流式输出、取消和卸载重载。**这些结果不能替代真机验收。**

尚未验证：第三方工具签名安装、启动与升级；分享扩展 / App Group；麦克风、相机、Face ID / Touch ID、通知投递与点击；真实录音、语音识别与朗读；真机 MNN CPU / Metal、LiteRT-LM、多模态、性能和内存压力；后台切换、跨平台恢复与同步。更多已知差异见 [iOS 适配与验收](ios-development.md)。

反馈时附应用版本、iPhone 型号、iOS 与签名工具版本、是否保留扩展和脱敏后的错误信息，不上传账号、验证码、证书、描述文件或真实笔记。
