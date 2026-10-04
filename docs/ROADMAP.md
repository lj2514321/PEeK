# 开发路线

## M0：工程基础

- [x] Flutter Windows 工程
- [x] 首版视觉系统与响应式桌面壳层
- [x] Riverpod、Dio、JSON 本地存储、安全存储和 media_kit 依赖
- [x] Jellyfin/Emby 服务发现
- [x] 统一服务器、媒体条目与播放领域接口
- [x] 开启 Windows 开发者模式并验证完整 Debug 构建

## M1：登录与服务器管理

- [x] 用户名密码登录
- [x] Token 写入系统安全存储
- [x] 生成并持久化稳定 DeviceId
- [x] 持久化服务器资料和当前用户
- [x] 多服务器资料和当前服务器切换
- [x] 401 失效处理与退出登录

## M2：媒体库

- [x] 首页继续观看与最近添加
- [x] 电影、剧集、季、单集浏览
- [x] 搜索、人物作品与详情页
- [x] 图片缓存和占位图
- [x] 分页、空状态和网络错误恢复

## M3：播放闭环

- [x] Jellyfin/Emby PlaybackInfo 适配
- [x] media_kit/libmpv 视频画面和基础控制器
- [x] 原码、直传与转码计划
- [x] 音轨、字幕、倍速和全屏
- [x] Started/Progress/Stopped 上报
- [x] 断点续播、剧集队列和自动下一集

## M4：质量与发布

- [x] 硬件解码设置与失败回退
- [x] 最大串流码率设置与本地持久化
- [x] 播放统计与可脱敏诊断日志
- [x] 编解码器、字幕、HDR 和弱网测试矩阵（自动化基线与测试矩阵矩阵建立，211项测试 100% 通过）
- [ ] Windows 安装包、签名和升级策略（MSIX、GitHub Release 与 App Installer 更新链路已建立，待正式发布者、证书和端到端安装验证）
- [x] GitHub Actions Windows 自动构建与版本标签发布
- [x] 第三方许可证清单与发布包 notices 自动生成

## M5：播放体验 2.0

- [x] 章节数据适配、时间轴刻度和章节跳转面板
- [x] 字幕风格、字号、位置与延迟的即时调整和本地持久化
- [x] 播放中画质切换与转码方案平滑重建
- [x] 网络中断、地址过期与播放错误的分级恢复
- [x] Windows 系统媒体控制、任务栏媒体键与系统音量联动

## M6：媒体库与检索深度优化 (Catalog & Data Performance)

- [x] 中文拼音与拼音首字母搜索匹配支持（如输入 zxc 快捷检索“周星驰”）
- [x] 媒体库高级多维过滤（评分区间、分辨率标签、音频编码与年份组合筛选）
- [x] 媒体库预加载与图片二级缓存优化（滑动预提取与矢量平滑占位）

## M7：播放体验与渲染进化 (Playback & Rendering)

- [x] HDR / Dolby Vision 色彩映射与 MPV Tone Mapping 算法选择
- [x] 外部字幕拖拽加载（.srt / .ass / .vtt）与在线字幕匹配下载
- [x] 播放中网络抖动与 Token 过期无缝断点重连

## M8：桌面高级特性与扩展 (Desktop & Ecosystem)

- [x] 桌面画中画 (Picture-in-Picture) 置顶小窗模式
- [x] 弹幕系统接入与播放同步（支持 DandanPlay / 弹弹Play API）
- [x] 个人观影统计与时长分析仪表盘
- [x] Jellyfin Quick Connect 扫码快速登录

## M9：架构解耦与整洁分层 (Architecture Decoupling & Modularization)

- [x] 核心领域公共层抽取（`MediaItem`、`ServerAccount`、`PlaybackPlan`、`PlaybackSettings` 统一归位 `src/core/domain/`）
- [x] 跨特性双向循环依赖全面清零（`player ⟷ servers`、`danmaku ⟷ player`、`details ⟷ people`）
- [x] 中心化类型安全路由门面（`AppRoutes` 封装 `Peek3DPageRoute`，消除 UI 页面跨特性强引用）
- [x] 依赖倒置与顶层装配中心（`AppProviders` 承载业务装配，底层 `core/network` 净化）
- [x] 物理动力学平滑滚动引擎（`PeekSmoothScroll` 全局弹簧与反向零黏滞算法覆盖所有滚动视口）
- [x] 全工程 308 项自动化测试 100% 通过与 Windows Release 安装包构建验证

## 持续体验优化

- [x] 可收纳桌面侧栏、五项响应式导航、页面保活与 Ctrl+1–5/Ctrl+B 快捷切换
- [x] 首页、媒体库、演员和相似推荐统一为键鼠/触控兼容的横向内容轨
- [x] 首页最近添加电影按媒体库分组并隔离空分区与局部错误
- [x] 详情页移动端标题尺度与播放操作布局优化
- [x] 媒体库排序、筛选与视图密度切换
- [x] 收藏、已观看状态与批量操作
- [x] 跨媒体库收藏页、分页浏览、快捷移除与撤销
- [x] 跨媒体库全量演员检索与 ParentId 独立分类过滤

