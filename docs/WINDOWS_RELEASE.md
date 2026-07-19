# Windows 发布

PEeK 使用 x64 MSIX 作为 Windows 安装格式，并使用 `.appinstaller` 描述文件提供自托管更新。最低系统版本为 Windows 10 2004（10.0.19041.0）。

## 生成开发安装包

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build_windows_package.ps1 `
  -FlutterExecutable F:\flutter\bin\flutter.bat
```

产物位于 `build\windows\x64\installer\PEeK-x64.msix`，同时生成 SHA-256 文件。开发包由打包工具生成的自签名测试证书签名，但脚本不会修改本机证书存储；该包仅用于受控测试，不作为正式公开发行包。

## 生成更新描述文件

正式签名后，为即将上传的 MSIX 生成 App Installer 文件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\new_windows_appinstaller.ps1 `
  -BaseUri https://downloads.example.com/peek `
  -PackagePath build\windows\x64\installer\PEeK-x64.msix
```

脚本直接读取 MSIX 内的 Identity、Publisher、Version 和架构，避免更新描述与安装包不一致。生成的 `PEeK.appinstaller` 在应用启动时最多每 24 小时检查一次更新，并允许后台检查；普通更新不会阻止应用启动。

将 `PEeK-x64.msix`、`PEeK-x64.msix.sha256` 和 `PEeK.appinstaller` 上传到同一个 HTTPS 目录。对外提供 `.appinstaller` 文件的直接下载链接。

## 版本规则

- 应用版本来自 `pubspec.yaml`，当前 `0.1.0+1` 对应 `msix_version: 0.1.0.1`。
- 每次发布同时更新 `version` 和 `msix_version`；自动化测试会阻止两者不一致。
- 每次发布必须提升版本；应用 Identity 和 Publisher 必须保持不变，否则 Windows 会把它识别为另一个应用。
- 不启用降级更新。需要回滚时发布一个版本号更高、内容回退的新包。
- 当前四段版本规则面向自托管发布；转向 Microsoft Store 时需使用 Partner Center 分配的 Identity/Publisher、启用 Store 打包，并将版本修订段设为 `0`。

## 正式签名

仓库中的 `CN=PEeK Development` 仅用于开发基线。公开发行前必须确定正式发布者，并让 `msix_config.publisher` 与签名证书 Subject 完全一致。

打包工具生成自签名证书时，会使用它自己的测试 Publisher；因此开发包不能直接覆盖升级为正式签名包，切换正式证书时应先卸载开发包。正式证书启用后，后续发布必须保持 Publisher 不变。

推荐顺序：

1. Microsoft Store：商店负责最终签名和更新分发。
2. Microsoft Artifact Signing：适合仓库或 CI 中的非商店发布，使用时间戳且不保存 PFX。
3. 受信任 CA 签发的代码签名证书：在受控发布环境中使用 SignTool 和 SHA-256 时间戳。

不得提交 PFX、证书密码、Azure 客户端密钥或签名元数据中的凭据。自托管 MSIX 必须由目标设备信任的证书签名。

## 发布检查

- `flutter analyze` 与 `flutter test` 通过。
- Release 构建可以启动、连接局域网 Jellyfin/Emby 并播放媒体。
- 安装、覆盖升级、卸载后用户数据行为符合预期。
- 安装包签名和 SHA-256 校验通过。
- `.appinstaller` 中的 Identity、Publisher、Version 和 URI 与已上传包一致。
