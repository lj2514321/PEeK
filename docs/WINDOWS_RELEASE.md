# Windows 发布

PEeK 使用 x64 MSIX 作为 Windows 安装格式，并使用 `.appinstaller` 描述文件提供自托管更新。最低系统版本为 Windows 10 2004（10.0.19041.0）。

## 生成开发安装包

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build_windows_package.ps1 `
  -FlutterExecutable F:\flutter\bin\flutter.bat
```

产物位于 `build\windows\x64\installer\PEeK-x64.msix`，同时生成 SHA-256 文件。开发包由打包工具生成的自签名测试证书签名，但脚本不会修改本机证书存储；该包仅用于受控测试，不作为正式公开发行包。

打包脚本还会根据锁定依赖、原生组件清单和 Flutter 的 `NOTICES.Z` 重新生成 `THIRD_PARTY_NOTICES.txt`，并将其放入安装目录。具体规则见[第三方许可证说明](THIRD_PARTY_LICENSES.md)。

## GitHub 自动构建与发布

`.github/workflows/windows-release.yml` 使用 Windows 托管运行器执行依赖安装、静态分析、全量测试和 MSIX 打包：

- 推送到 `master`、提交针对 `master` 的 Pull Request，或手动运行工作流时，会构建并保留 14 天的 Actions Artifact。
- 推送 `vMAJOR.MINOR.PATCH` 或 `vMAJOR.MINOR.PATCH.REVISION` 标签时，会在构建通过后自动创建 GitHub Release，并附上 MSIX、SHA-256 与 `PEeK.appinstaller`。
- 三段标签会转换为四段 MSIX 版本，例如 `v0.2.0` 对应 `0.2.0.0`。每段取值必须在 0–65535 之间。
- `PEeK.appinstaller` 使用稳定的 `releases/latest/download` 地址。发布脚本通过 GitHub Release API 为 MSIX 和 App Installer 显式设置 Windows 要求的 MIME 类型。

发布示例：

```powershell
git tag v0.2.0
git push origin v0.2.0
```

默认情况下，CI 与本地开发构建一样使用测试证书。如果要让 GitHub Actions 使用正式 PFX，在仓库的 `Settings > Secrets and variables > Actions` 中同时添加以下 Repository Secrets：

- `WINDOWS_CERTIFICATE_BASE64`：PFX 文件的 Base64 内容。
- `WINDOWS_CERTIFICATE_PASSWORD`：PFX 密码。
- `WINDOWS_CERTIFICATE_PUBLISHER`：证书的完整 Subject，必须与 MSIX Publisher 完全一致。

可以在本地生成要粘贴到 Secret 中的 Base64 内容：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('PEeK-signing.pfx'))
```

三个签名 Secret 必须全部配置或全部留空。工作流不会把证书写入仓库，临时 PFX 只存在于 GitHub 托管运行器的临时目录中。

GitHub 自动更新要求仓库及 Release 资产无需登录即可访问。用户应直接下载并双击 `PEeK.appinstaller`；不要依赖默认已禁用的 `ms-appinstaller:` 网页协议。首次安装还必须信任用于签署 MSIX 的发布证书。

## 生成更新描述文件

正式签名后，为即将上传的 MSIX 生成 App Installer 文件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\new_windows_appinstaller.ps1 `
  -BaseUri https://downloads.example.com/peek `
  -PackagePath build\windows\x64\installer\PEeK-x64.msix
```

脚本直接读取 MSIX 内的 Identity、Publisher、Version 和架构，避免更新描述与安装包不一致。生成的 `PEeK.appinstaller` 在应用启动时最多每 24 小时检查一次更新，并允许后台检查；普通更新不会阻止应用启动。

将 `PEeK-x64.msix`、`PEeK-x64.msix.sha256` 和 `PEeK.appinstaller` 上传到同一个 HTTPS 目录。服务器必须为 `.msix` 返回 `application/msix`，为 `.appinstaller` 返回 `application/appinstaller`，并返回正确的 `Content-Length`。对外提供 `.appinstaller` 文件的直接下载链接。

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
- 安装目录包含最新的 `THIRD_PARTY_NOTICES.txt`，LGPL 对应源码与构建配方可访问。
