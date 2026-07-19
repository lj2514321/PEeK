# 第三方许可证

PEeK 的 Windows 发布包同时包含 Dart/Flutter 依赖、Flutter 引擎及原生媒体与数据库组件。发布流程会生成 `THIRD_PARTY_NOTICES.txt` 并放入 MSIX 安装目录。

## 生成方式

先生成 Windows Release 构建，再运行：

```powershell
F:\flutter\bin\dart.bat run tool\generate_third_party_notices.dart `
  --flutter-notices build\windows\x64\runner\Release\data\flutter_assets\NOTICES.Z `
  --output THIRD_PARTY_NOTICES.txt
```

正式打包无需单独执行该命令；`scripts/build_windows_package.ps1` 会自动生成并复制 notices，然后再创建 MSIX。生成器读取以下来源：

- `.dart_tool/package_graph.json` 与 `package_config.json` 中的锁定运行时依赖。
- 每个 Dart/Flutter 包随包发布的 `LICENSE`、`COPYING` 或 `NOTICE` 文件。
- `third_party/native_components.json` 中维护的原生组件、版本、文件、许可证与源码地址。
- Flutter Release 构建生成的 `NOTICES.Z`，解压后覆盖 Flutter 引擎、Skia、ICU 等组件声明。

## 原生组件审计

| 组件 | Release 文件 | 许可结论 |
| --- | --- | --- |
| mpv / FFmpeg bundle | `libmpv-2.dll` | mpv 使用 `-Dgpl=false`，FFmpeg 使用 `--disable-gpl --disable-nonfree --enable-version3`；分别适用 LGPL 2.1+、LGPL 3.0+ 及依赖自身条款 |
| ANGLE runtime | `libEGL.dll`、`libGLESv2.dll`、SwiftShader、Vulkan、zlib 等 | ANGLE BSD-3-Clause 风格许可，并合并 Flutter 生成的组件 notices |
| SQLite 3.53.3 | `sqlite3.dll` | SQLite 核心为 Public Domain；Dart wrapper 为 MIT |
| Flutter engine | `flutter_windows.dll`、ICU 与 Flutter assets | Flutter BSD-3-Clause 及引擎依赖各自条款，由 Flutter notices 覆盖 |

libmpv 的二进制来自 media-kit 固定的 2023-09-24 构建，版本为 `v0.36.0-403-g652a1dd907`。FFmpeg 固定提交为 `ea3d24bbe3c58b171e55fe2151fc7ffaca3ab3d2`。精确链接、构建配方和完整许可证文本由 `native_components.json` 与 `third_party/licenses` 保存。

## 发布要求

- 公开分发前保存或镜像 libmpv/FFmpeg 的对应源码、补丁和构建配方，并按 LGPL 要求持续提供获取方式。
- 保持 `libmpv-2.dll` 可替换，不将其静态合并进 PEeK 主程序。
- 不删除安装目录中的 `THIRD_PARTY_NOTICES.txt`。
- 依赖版本、Flutter SDK 或原生 DLL 变化后必须重新生成 notices，并重新审计 `native_components.json`。
- 当前清单用于工程合规准备，不替代针对目标发行地区的专业法律意见。
