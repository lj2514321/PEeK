# PEeK

面向 Jellyfin 和 Emby 的 Windows 优先桌面播放器。项目使用 Flutter 构建界面，以 `media_kit/libmpv` 作为播放内核，并通过独立适配器隔离两类服务器的 API 差异。

## 当前状态

项目当前已经具备：

- Windows Flutter 工程与深色桌面 UI 壳层
- Jellyfin/Emby 公共信息接口探测
- Jellyfin/Emby 用户名密码登录与 Windows Token 安全存储
- 多服务器账户持久化、快速切换、退出登录与 401/403 失效恢复
- 服务器与登录持久化、媒体库分页浏览和本地缓存
- 海报、背景图和人物头像的统一磁盘缓存与安静占位图
- 登录后每日自动更新的推荐轮播、继续观看、最近电影和最新剧集
- 电影、剧集、演员详情、相似推荐和全局搜索
- STRM、原码、直传与转码播放计划及播放进度上报
- 可持久化的最大串流码率与解码方式设置，支持播放中切换画质上限并失败回滚
- `media_kit/libmpv` 影院控制层、快捷键、全屏、倍速、音字幕轨道与章节导航
- 可即时预览并持久化的字幕风格、字号、位置和音画延迟设置
- 按需播放诊断面板、实际硬解/编码/码率/缓存/丢帧统计和可轮转的脱敏日志
- 剧集队列、选集、上一集/下一集和可取消的片尾自动连播
- 统一服务器、媒体条目和播放计划模型
- Riverpod、Dio、Drift、安全凭据存储及 media_kit 依赖
- 基础组件测试

下一阶段将继续完善编解码器、字幕、HDR 与弱网兼容性验证。详细边界见 [架构说明](docs/ARCHITECTURE.md)、[开发路线](docs/ROADMAP.md) 和 [播放验证矩阵](docs/PLAYBACK_TEST_MATRIX.md)。

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
