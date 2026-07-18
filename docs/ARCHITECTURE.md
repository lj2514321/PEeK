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

## 播放流程

1. 适配器向服务器请求 PlaybackInfo 与 MediaSources。
2. 播放策略根据客户端能力、用户码率、音轨和字幕生成 `PlaybackPlan`。
3. 播放准备阶段并行读取本地解码偏好；自动模式向 libmpv 传递 `auto-safe`，不支持的格式由底层回退到软件解码，兼容模式传递 `no`。
4. `PlaybackEngine` 将流地址、认证请求头和起始位置交给 libmpv。
5. 会话协调器发送 Started，并每约十秒及状态变化时发送 Progress。
6. 播放完成、切换条目或关闭窗口时发送 Stopped。
7. 诊断面板仅在打开时每三秒读取一次 libmpv 安全属性；关闭面板立即停止采样。

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
- libmpv 二进制发布前需要完成许可证与第三方声明审查。
