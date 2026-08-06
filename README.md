<div align="center">

<img src="assets/branding/peek_app_icon.png" width="112" alt="PEeK application icon">

# PEeK

**连接本地媒体与 Jellyfin / Emby 的 Windows 桌面影院。**

浏览本地文件夹与远程媒体库、继续观看、搜索与收藏，并通过 `media_kit / libmpv` 完成本地直放、原码、直传、转码及 STRM 播放。

[![Windows](https://img.shields.io/badge/Windows-10%202004%2B-0078D4?logo=windows&logoColor=white)](https://github.com/lj2514321/PEeK)
[![Flutter](https://img.shields.io/badge/Flutter-3.44.6-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Version](https://img.shields.io/badge/version-0.1.0-F3C969)](https://github.com/lj2514321/PEeK/releases)
[![Windows Build](https://github.com/lj2514321/PEeK/actions/workflows/windows-release.yml/badge.svg?branch=master)](https://github.com/lj2514321/PEeK/actions/workflows/windows-release.yml)

[下载最新版本](https://github.com/lj2514321/PEeK/releases/latest) ·
[查看路线图](docs/ROADMAP.md) ·
[报告问题](https://github.com/lj2514321/PEeK/issues)

</div>

> [!IMPORTANT]
> PEeK 目前处于 `0.1.x` 开发预览阶段，优先支持 Windows x64。正式公开分发前仍需完成代码签名、HDR、弱网与更多编解码器的实机验证。

## 为什么是 PEeK

PEeK 希望提供一套真正适合桌面使用的 Jellyfin/Emby 体验：快速进入内容、清晰管理媒体库，并在播放时尽量保持安静和沉浸。

- **统一连接**：兼容 Jellyfin 与 Emby，支持局域网地址、端口和反向代理路径。
- **本地媒体库**：可添加电脑磁盘或局域网共享文件夹，分层浏览常见视频、音频和 STRM，并记住媒体库配置。
- **桌面优先**：无原生白色标题栏、可收纳侧栏、响应式布局及完整键盘快捷键。
- **媒体中心**：每日推荐、继续观看、按媒体库分组的最近添加、最新剧集和全局搜索。
- **完整详情**：电影、剧集、演员作品、演职员信息、相似推荐、收藏及已观看状态。
- **可靠播放**：STRM、原码直放、直传和服务端转码，支持播放失败回滚与进度同步。
- **影院控制**：音轨、字幕、章节、倍速、画质切换、剧集队列和片尾自动连播。
- **Windows 集成**：系统媒体面板、硬件媒体键、时间轴跳转和 PEeK 独立音频会话音量联动。
- **诊断友好**：按需显示硬解、编码、码率、缓存和丢帧信息，日志会自动轮转并清除敏感数据。

## 功能概览

| 分类 | 当前能力 |
| --- | --- |
| 服务器 | Jellyfin/Emby 探测、登录、多账户保存与切换、401/403 会话失效恢复 |
| 首页 | 每日推荐轮播、继续观看、最近添加电影、最新剧集 |
| 媒体库 | 本地/远程媒体库统一入口、分页、层级浏览、排序筛选、三档海报密度、远程批量操作 |
| 搜索与详情 | 全局搜索、人物结果、演员作品、相似内容、收藏与观看状态 |
| 演员 | 跨媒体库浏览演员，点击进入其全部作品与详情 |
| 播放 | 本地文件/STRM 直放、Direct Play、Direct Stream、Transcode、断点续播与远程进度上报 |
| 播放控制 | 音轨、字幕、章节、倍速、画质、全屏、上一集/下一集 |
| 本地体验 | 登录持久化、JSON 媒体缓存、图片磁盘缓存、搜索历史与播放偏好 |
| Windows | SMTC 系统媒体面板、媒体键、应用音频会话音量、MSIX/App Installer |

## 安装

### 从 GitHub Releases 安装

前往 [Releases](https://github.com/lj2514321/PEeK/releases/latest) 下载：

- `PEeK.appinstaller`：推荐，安装后可检查后续更新。
- `PEeK-x64.msix`：独立的 Windows x64 安装包。
- `PEeK-x64.msix.sha256`：用于校验安装包完整性。

最低系统版本为 **Windows 10 2004（10.0.19041.0）**。

开发预览包可能使用测试证书。Windows 无法验证签名时，请先阅读 [Windows 发布与签名说明](docs/WINDOWS_RELEASE.md)，不要关闭系统级安全检查或安装来源不明的包。

### 从源码运行

准备以下环境：

- Flutter stable，推荐与 CI 一致的 `3.44.6`
- Visual Studio 2022
- “使用 C++ 的桌面开发”工作负载与 Windows SDK
- 已启用 Windows 开发者模式

```powershell
git clone https://github.com/lj2514321/PEeK.git
cd PEeK
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
```

构建 Profile 版本：

```powershell
flutter build windows --profile
```

## 使用方式

1. 本地播放：打开“设置 → 本地媒体库 → 添加文件夹”，选择电脑磁盘或局域网共享目录。
2. 远程播放：输入 Jellyfin/Emby 服务器地址，例如 `http://192.168.1.10:8096`，并登录服务器账户。
3. 从媒体库选择本地或远程库；本地文件直接播放，远程内容按能力选择原码、直传或转码。

本地媒体库支持常见视频、音频和 `.strm` 文件。海报可使用与媒体同名的 `.jpg/.jpeg/.png/.webp`，或目录中的 `poster.jpg`、`folder.jpg`、`cover.jpg`；移除媒体库只删除 PEeK 的目录记录，不会删除原文件。

反向代理用户可以直接填写包含路径的完整地址。PEeK 会保存探测得到的实际 API 根路径，不会在后续请求中重复猜测。

## 快捷键

### 主界面

| 快捷键 | 操作 |
| --- | --- |
| `Ctrl + 1` ~ `Ctrl + 5` | 切换首页、媒体库、收藏、搜索和设置 |
| `Ctrl + 6` | 切换演员 |
| `Ctrl + B` | 收起或展开桌面侧栏 |
| `Ctrl + K` | 打开并聚焦全局搜索 |

### 播放器

| 快捷键 | 操作 |
| --- | --- |
| `Space` / `K` | 播放或暂停 |
| `←` / `J` | 后退 10 秒 |
| `→` / `L` | 前进 10 秒 |
| `↑` / `↓` | 调整音量 |
| `M` | 静音 |
| `F` | 切换全屏 |
| `P` / `N` | 上一集 / 下一集 |
| `Ctrl + D` | 打开播放诊断 |
| `Esc` | 关闭面板、退出全屏或返回 |

## 技术架构

```text
Flutter Presentation
  ├── Home / Library / Favorites / Search / Details
  └── PlaybackPage + PlaybackInteractionCoordinator
             │
             ▼
Application & Services
  ├── HomeFeedService / PlaybackPreparationService
  ├── MediaLibraryService / LocalMediaLibraryService / PlaybackService
  └── SessionExpiryCoordinator
             │
             ▼
Infrastructure
  ├── Dio + Jellyfin/Emby API + 本地文件系统
  ├── Windows Secure Storage + JSON Cache/Catalog
  ├── PlaybackRuntime → media_kit / libmpv
  └── Windows SMTC / WASAPI Session
```

播放器通过可替换的 `PlaybackRuntime` 隔离 media_kit，页面级测试可以使用假运行时验证打开、快进、上报和资源释放，而不需要启动 libmpv。

更完整的边界与约束请查看 [架构说明](docs/ARCHITECTURE.md)。

## 项目结构

```text
lib/src/
├── app/                  # 主题、玻璃拟态组件与窗口外壳
├── core/                 # 网络协调、本地存储与通用展示组件
└── features/
    ├── home/             # 首页与主导航
    ├── library/          # 媒体库浏览
    ├── local_library/    # 本地目录、扫描、持久化与播放计划
    ├── favorites/        # 收藏页
    ├── people/             # 演员浏览
    ├── search/           # 全局搜索
    ├── details/          # 媒体与演员详情
    ├── player/           # 播放计划、运行时、控制器与诊断
    ├── servers/          # 服务发现、认证及媒体 API
    └── settings/         # 播放偏好
```

视觉规范位于 [design-system](design-system/default/MASTER.md)，播放兼容性边界记录在 [播放验证矩阵](docs/PLAYBACK_TEST_MATRIX.md)。

## 开发与质量检查

```powershell
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build windows --profile
```

当前测试覆盖服务发现、认证与安全存储、媒体缓存、媒体库与搜索、播放计划、播放器控件、播放页面生命周期、Windows 窗口和系统媒体桥接等关键路径。

推送到 `master` 或提交 Pull Request 时，GitHub Actions 会自动执行格式检查、静态分析、全量测试与 Windows MSIX 打包。推送 `vMAJOR.MINOR.PATCH` 标签会自动创建 GitHub Release。

详细流程请查看 [Windows 发布文档](docs/WINDOWS_RELEASE.md)。

## 路线图

接下来重点推进：

- 网络中断、播放地址过期与错误分级恢复
- Jellyfin/Emby 实机编解码器、字幕、HDR 与弱网验证
- 正式 Windows 发布者、代码签名和端到端升级验证
- 媒体浏览分页状态复用与 Repository/Application 分层

完整进度见 [ROADMAP.md](docs/ROADMAP.md)。

## 隐私与安全

- 密码只存在于登录请求生命周期中，不写入本地文件。
- Access Token 使用 Windows 安全凭据存储，并按服务器与用户隔离。
- HTTPS 证书错误默认阻止连接，不提供全局忽略开关。
- 图片缓存键、文件名和诊断日志不会保存 Access Token。
- 播放诊断会清除 URL、路径、请求头、用户、媒体和会话标识。

## 参与贡献

欢迎提交 [Issue](https://github.com/lj2514321/PEeK/issues) 或 Pull Request。提交前请确保格式检查、静态分析和测试全部通过。

如果问题与播放有关，请尽量提供：

- Jellyfin 或 Emby 版本
- 媒体封装、视频/音频编码及字幕类型
- PEeK 诊断面板中的播放方式与硬件解码状态
- 已脱敏的错误信息

请勿公开服务器地址、用户名、Access Token、完整媒体路径或未经处理的诊断日志。

## 致谢

PEeK 建立在 [Flutter](https://flutter.dev)、[media_kit](https://github.com/media-kit/media-kit) 与 [libmpv](https://mpv.io) 之上，并面向 Jellyfin/Emby 媒体服务器生态构建。

第三方组件与许可信息见 [THIRD_PARTY_LICENSES.md](docs/THIRD_PARTY_LICENSES.md)。
