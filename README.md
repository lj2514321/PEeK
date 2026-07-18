# PEeK

面向 Jellyfin 和 Emby 的 Windows 优先桌面播放器。项目使用 Flutter 构建界面，以 `media_kit/libmpv` 作为播放内核，并通过独立适配器隔离两类服务器的 API 差异。

## 当前状态

项目处于第一个开发里程碑，已经具备：

- Windows Flutter 工程与深色桌面 UI 壳层
- Jellyfin/Emby 公共信息接口探测
- Jellyfin/Emby 用户名密码登录与 Windows Token 安全存储
- 统一服务器、媒体条目和播放计划模型
- Riverpod、Dio、Drift、安全凭据存储及 media_kit 依赖
- 基础组件测试

服务器资料持久化、媒体库浏览和实际播放将在后续里程碑接入。详细边界见 [架构说明](docs/ARCHITECTURE.md) 和 [开发路线](docs/ROADMAP.md)。

视觉与交互实现遵循 [PEeK 设计系统](design-system/default/MASTER.md)，首页状态与响应式规则见 [首页规范](design-system/default/pages/home.md)。

## 本地运行

要求：

- Flutter stable，当前开发环境位于 `F:\flutter`
- Visual Studio 2022，安装“使用 C++ 的桌面开发”和 Windows SDK
- Windows 开发者模式，用于 Flutter 插件的符号链接

```powershell
F:\flutter\bin\flutter.bat pub get
F:\flutter\bin\flutter.bat run -d windows
```

检查代码：

```powershell
F:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
F:\flutter\bin\flutter.bat analyze
F:\flutter\bin\flutter.bat test
```
