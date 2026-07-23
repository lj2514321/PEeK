# 架构说明

## 目标

构建一个 Windows 优先、可扩展到 macOS/Linux 的 Jellyfin 与 Emby 客户端。客户端应优先使用服务器提供的原始媒体流，在能力或网络条件不满足时由服务器直传或转码，并完整同步播放会话。

## 分层

```text
Presentation
  └── 页面、对话框、播放器控件
Application
  └── 登录、浏览、播放、进度上报等用例
Domain
  ├── ServerProfile / MediaItem
  ├── PlaybackPlan / PlaybackSessionSnapshot
  └── MediaServerGateway / PlaybackEngine
Infrastructure
  ├── JellyfinGateway / EmbyGateway
  ├── Dio 网络客户端
  ├── Drift 本地数据库
  ├── 系统安全凭据存储
  └── media_kit/libmpv
```

UI 只依赖统一领域模型，不直接读取 Jellyfin 或 Emby 的 JSON DTO。两个服务端适配器可以复用公共 HTTP 工具，但必须分别处理接口差异和版本兼容。

主导航使用按需创建、访问后保活的索引栈承载首页、媒体库、收藏、搜索和设置；切换一级页面不得销毁其滚动位置、媒体库路径或搜索上下文，也不得在首次访问前提前请求隐藏页面数据。宽屏侧栏允许用户主动收起，720–1039px 自动使用紧凑图标栏，小屏使用五项底部导航；收起态必须保留 Tooltip、语义标签和可见激活态。离屏页面停止非必要轮播并释放输入焦点，账户切换仍通过 `didUpdateWidget` 清理用户隔离状态。

首页最近添加的电影按媒体库分组：先读取用户可见媒体库的 `CollectionType`，只为 `movies`、`mixed` 及缺少类型的兼容库请求 `Items/Latest`，并通过 `ParentId` 保持归属。每库最多读取 12 项、最多四个请求并发；空分组隐藏，单库失败只在对应位置恢复，不得清空其他首页轨道。缺少 `CollectionType` 时允许发起兼容查询，由空结果自然淘汰非电影库。

媒体库的排序、类型/观看状态/年份筛选必须作为 Jellyfin/Emby `Items` 查询参数发送到服务器，分页只合并同一组查询条件下的结果，避免对已加载局部数据进行错误排序。视图密度只改变本地网格列数，不触发网络请求；筛选为空时必须保留一键清除入口。

收藏和已观看状态统一读取 `UserData.IsFavorite` 与 `UserData.Played`，写入使用 Jellyfin/Emby 共通的 `Users/{UserId}/FavoriteItems/{ItemId}` 和 `PlayedItems` 端点。收藏页通过不带 `ParentId` 的递归 `Users/{UserId}/Items?Filters=IsFavorite` 查询跨媒体库聚合当前用户收藏，并独立分页；进入详情返回后强制刷新，卡片取消收藏后立即从列表移除并提供撤销。批量写入以最多四个并发请求分组，完成后清理媒体 JSON 缓存；缓存清理失败不得反向报告服务器写入失败。详情页写入后做局部状态更新，媒体库批量写入提供可撤销反馈并在状态筛选生效时重新查询。

## 播放流程

1. 适配器向服务器请求 PlaybackInfo 与 MediaSources。
2. 播放策略根据客户端能力、用户码率、音轨和字幕生成 `PlaybackPlan`。
3. 播放准备阶段并行读取本地解码偏好；自动模式向 libmpv 传递 `auto-safe`，不支持的格式由底层回退到软件解码，兼容模式传递 `no`。
4. `PlaybackEngine` 将流地址、认证请求头和起始位置交给 libmpv；播放中切换画质时先准备新计划，打开失败则恢复原播放源。
5. 会话协调器发送 Started，并每约十秒及状态变化时发送 Progress。
6. 播放完成、切换条目或关闭窗口时发送 Stopped。
7. 诊断面板仅在打开时每三秒读取一次 libmpv 安全属性；关闭面板立即停止采样。
8. Windows Runner 通过 `ISystemMediaTransportControlsInterop` 为顶层窗口创建单一 SMTC 会话；Dart 侧同步标题、剧集、海报、播放状态、时间轴和队列能力，系统按钮事件再回到现有播放用例。

Windows 音量联动只操作当前 PEeK 进程的 WASAPI 音频会话：播放器滑块写入 `ISimpleAudioVolume`，系统音量混合器的外部修改通过 `IAudioSessionEvents` 回传。不得修改系统主音量或其他应用的音量；音频会话尚未创建时退回 media_kit 音量，并在媒体打开后有限次数重试绑定。

播放器不得在日志中记录 token 或完整认证 URL，也不应将密码写入本地数据库。诊断日志只记录服务器类型/版本、播放方式、传输协议、解码偏好和脱敏错误；所有 URL、请求头、路径、用户/媒体/会话标识及已知凭据在写入前清除。

## 服务器地址

用户可以输入主机、端口或带反向代理路径的完整 URL。探测流程依次尝试：

- `{base}/System/Info/Public`
- `{base}/emby/System/Info/Public`

探测结果保存实际 API 根路径；后续请求不得重新猜测路径。

登录统一调用 `{apiBase}/Users/AuthenticateByName`。Jellyfin 使用 `MediaBrowser` 认证方案，Emby 使用 `Emby` 认证方案；密码只存在于请求生命周期中，成功后只保存 AccessToken。

## 本地数据

- Drift：服务器资料、用户资料、媒体缓存、播放设置。
- 系统安全存储：服务器账户目录不包含密码或 token；每个 ServerId/UserId 的访问 token 使用独立键保存，当前账户只记录资料 ID。
- 文件缓存：海报、背景图与临时字幕；媒体图片按服务器完整 URL 和图片 Tag 隔离，保留 30 天且最多 600 个对象。
- 每日推荐缓存按服务器、用户和本地自然日隔离；当天直接复用，跨日只更新推荐分区，网络失败时保留上一批内容。
- 播放偏好：最大串流码率与解码方式保存在本机 PEeK 配置目录，不包含凭据；PlaybackInfo 的 POST 与兼容 GET 路径读取同一码率设置，视频控制器在创建时读取解码方式。
- 播放诊断：活动日志保存在 `%LOCALAPPDATA%\PEeK\logs\playback_diagnostics.log`，达到 1 MiB 后轮转为一个 previous 文件；日志不可用不影响播放。
- 持久 DeviceId：每次启动保持不变，以维持服务器会话识别。

## 关键约束

- 首版只支持 Windows x64。
- 数据模型从第一天支持多服务器，UI 首期只激活一个服务器。
- HTTPS 证书错误默认阻止连接，不提供全局忽略开关。
- 图片鉴权只通过请求头传递，缓存键、文件名和日志不得包含 AccessToken。
- 多服务器切换保留每个账户的安全 token，退出登录只删除目标 token 并保留服务器资料；移除服务器资料才删除完整本地条目。
- 带 `X-Emby-Token` 的请求收到 401/403 时，通过单次会话失效事件清理当前 token，避免并发请求重复触发退出流程；登录接口的 401 不参与该流程。
- 播放引擎通过接口隔离，避免业务层依赖 media_kit 的具体类型。
- SMTC 与音频会话桥接为 Windows 可选能力；初始化、海报读取或会话绑定失败不得阻断 libmpv 播放，退出播放时必须注销原生事件并清空系统媒体卡片。
- 横向内容轨统一使用惰性构建、触控/鼠标拖动和桌面方向按钮；按钮只在对应方向确实可滚动时启用。
- 媒体库批量模式必须明确显示选择数量、忙碌状态和退出入口；收藏与观看状态不能只依赖颜色，必须同时使用图标或文字。
- libmpv 二进制发布前需要完成许可证与第三方声明审查。
