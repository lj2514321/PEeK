# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

PEeK (`embyplayer`) — a Windows-first Flutter desktop client for Jellyfin/Emby media servers, plus local folder/STRM browsing, presented as a "VisionOS spatial cinema" desktop shell. Playback runs on `media_kit` / libmpv. Danmaku comes from the DandanPlay API and anime scrobbling from Bangumi. UI copy, `README.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md` and `design-system/default/MASTER.md` are Chinese — match that language when editing user-facing text; code comments and this file are English.

- Version `0.1.1+2`. Flutter **3.44.6** stable / Dart **3.12.2**, pinned in CI and matching the local SDK; `pubspec.yaml` requires `sdk: ^3.12.2`.
- Windows x64 is the only shipped target (Windows 10 2004+ / `10.0.19041.0`, Visual Studio 2022 with "Desktop development with C++"). `android/` and the non-Windows branches are scaffolding: `lib/main.dart` only configures `window_manager` under `Platform.isWindows`, and Windows-only features degrade rather than branch everywhere.
- Playback normally runs in its **own OS window** (`desktop_multi_window` + `PlayerWindowApp`), not inside the main window. The main window can host a mini/PiP player instead.

## Commands

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool   # CI format gate
flutter analyze
flutter test                                      # full suite
flutter test test/playback_page_test.dart         # single test file
flutter run -d windows
flutter build windows --profile                   # dev profile build
```

- CI (`.github/workflows/windows-release.yml`) runs format check → analyze → test on every push/PR to `master`, then builds the MSIX. A tag `vMAJOR.MINOR.PATCH[.REVISION]` publishes a GitHub Release (`release` job).
- Packaging is scripted, not manual: `scripts/build_windows_package.ps1` (release build → regenerate `THIRD_PARTY_NOTICES.txt` via `tool/generate_third_party_notices.dart` → `dart run msix:create`, optional signing parameters) and `scripts/new_windows_appinstaller.ps1` (emits `PEeK.appinstaller`). `scripts/upload_github_release_assets.sh` publishes the assets. Details in `docs/WINDOWS_RELEASE.md`.
- `test/` and `tool/` are inside the format gate, so format them along with `lib/`.

## Architecture

Layered Presentation → Application → Domain → Infrastructure, feature-first under `lib/src/features/`, each feature split into `presentation/`, `domain/`, `data/`.

- `lib/main.dart` — two entry paths. Always: Skia warm-up (`_warmupGraphicsPipeline`), `AppStoragePath.ensureInitialized()`, `MediaKit.ensureInitialized()`. On Windows it then either boots a **player window** (`args[0] == 'multi_window'`, or `WindowController.fromCurrentEngine().arguments` carrying a `PlayerWindowPayload`) into `PlayerWindowApp`, or opens the frameless 1280×800 main window and runs `ProviderScope(child: EmbyPlayerApp())`.
- `lib/src/app/` — `app.dart` (`MaterialApp`, frameless chrome, mini-player overlay), `app_chrome.dart`, `app_providers.dart` (composition root: all cross-feature service wiring), `app_routes.dart` (the `AppRoutes` navigation facade), `theme.dart` (`AppColors`/`AppMotion`; `AppMotion.isTest` is true whenever `FLUTTER_TEST` is set, and every motion component short-circuits on it), `glass.dart`, `peek_warmup_gate.dart` (`PeekWarmupGate`: ~520 ms startup shader/typography warm-up that also prewarms session, local libraries, playback settings and Bangumi state).
- `lib/src/core/domain/` — the **single source of truth** for shared models: `MediaItem`, `ServerAccount`/`ServerType`, `PlaybackPlan`, `PlaybackSettings`, `ExternalIdInfo`, `RemoteSearchResult`.
- `lib/src/core/network/` — `network_providers.dart` (Dio, auth headers, secure-token providers) and `session_expiry_coordinator.dart`. Must never import upward into `features/`.
- `lib/src/core/storage/` — `app_storage_path.dart` (cross-platform root: `%LOCALAPPDATA%\PEeK` on Windows, `path_provider` support dir + `PEeK` elsewhere; exposes `logs/`, `Downloads/`, `ActorFavorites/`, `Shaders/`), `secure_token_store.dart`, `media_cache_store.dart`, `search_history_store.dart`.
- `lib/src/core/presentation/` — the motion and rendering toolkit: `peek_motion.dart` (`PeekIndexedTransitionStack`, `PeekStaggeredGridItem`, `PeekSpatialPageRoute` + `Peek3DPageRoute` typedef, `PeekPageRoute`, `TheatricalIrisPageRoute`, `PeekMotionOrigin`, `PeekTabTransitionScope`; re-exports `peek_spring`, `peek_magnetic_button`, `peek_cascading_sheet`), plus `peek_3d_card.dart`, `peek_smooth_scroll.dart`, `peek_horizontal_rail.dart`, `peek_media_image.dart`, `peek_context_menu.dart`, `peek_border_beam.dart`, `cinematic_scroll_behavior.dart`.
- `lib/src/core/utils/pinyin_matcher.dart` — hand-maintained Hanzi → Pinyin-initial table backing full-spelling and initials search (`zxc` → 周星驰); applied by `MediaLibraryService` when it filters search results locally.
- `lib/src/features/servers/` — discovery probes `{base}/System/Info/Public` then `{base}/emby/System/Info/Public` and persists the real API root; auth posts `Users/AuthenticateByName` with the `MediaBrowser` scheme for Jellyfin and `Emby` for Emby. `data/media_library_service.dart` is the actual Jellyfin/Emby HTTP adapter (items, resume, favorites, played, people, search, collections) and, with `emby_media_item_parser.dart`, owns all server JSON. Note: `domain/media_server_gateway.dart` declares a `MediaServerGateway` interface that currently has **no implementations** — `JellyfinGateway`/`EmbyGateway` do not exist. Treat it as an unused seam; add adapters rather than assuming one.
- `lib/src/features/player/` — the largest feature. `presentation/playback_runtime.dart` is the media_kit boundary: abstract `PlaybackRuntime` (position/duration/buffer/volume/rate/tracks streams + open/seek/volume/tracks) with `MediaKitPlaybackRuntime` as the only real implementation; tests inject a fake runtime. `domain/` holds `PlaybackPlan`, `PlaybackQueue`, `PlaybackSettings`, `PlayerWindowPayload`, `PlaybackSourceTransition`, `SmartIntroSkipper`, shader/equalizer settings. `data/` holds `PlaybackPreparationService` (builds the plan), `PlaybackService` (server reporting), `PlaybackDiagnosticsService`, `PlaybackDiagnosticLog`, `ExternalPlayerService`, `ShaderManagerService`, `WindowsMediaSession`. Presentation also covers `playback_page.dart`, `playback_controls.dart`, `playback_interaction_coordinator.dart`, `playback_gesture_overlay.dart`, `playback_shortcut_controller.dart`, `playback_quality_sheet.dart`, `playback_diagnostics_panel.dart`, `floating_mini_player.dart`, `playback_pip_controller.dart`, `player_window_coordinator.dart`, `player_window_chrome.dart`, and the danmaku overlay.
- Other features, one line each: `home/` (hero carousel, daily recommendations, continue watching, latest movies grouped per library, latest episodes, `HomeShell` navigation), `library/` (remote browsing, server-side filters, paging, three poster densities, bulk actions), `local_library/` (folders + STRM, persisted to `local_libraries_v1.json`, never touches the server), `favorites/` (cross-library favorites with undo), `people/` (actor catalog + `person_works_page.dart`; `features/details/presentation/person_works_page.dart` is only an `export` shim), `details/` (`media_detail_page.dart`: seasons/episodes, cast, similar, collections, identify/remote-search dialog), `search/` (top search bar + history), `auth/` (Jellyfin Quick Connect), `danmaku/` (DandanPlay matching + overlay + settings), `download/` (batch episode downloads, 2 concurrent, resumable registry `download_tasks_v1.json`), `analytics/` (local viewing history + `fl_chart` dashboard), `dedupe/` (duplicate grouping with an ignored-pairs store), `scrobble/` (Bangumi API v0 binding/summary), `settings/` (hardware decoding mode, max streaming bitrate, long-press speed, external-player command).
- `windows/runner/windows_media_session.cpp` — native bridge exposing SMTC (system media transport controls) and per-app WASAPI volume over a method channel; `flutter_window.cpp` creates one `WindowsMediaSessionBridge` per top-level window and opens sub-window sessions for the player window. Frameless chrome itself comes from `window_manager` on the Dart side.
- `design-system/default/` + `UI-Prompts.md` — the visual contract; read `MASTER.md` before restyling anything.

## Non-obvious rules

**Layering and navigation**

- Cross-feature navigation MUST go through `AppRoutes` (`openMediaDetail`, `openPlayback`, `openPersonWorks`, `openDedupe`), never by importing a foreign feature's Page class. `AppRoutes.openMediaDetail` also redirects person items to the works page.
- Circular dependencies between feature packages are prohibited; shared models live in `core/domain/`. Several feature-local files are deliberate `export` shims kept for import compatibility (`features/servers/domain/media_item.dart`, `features/player/domain/playback_plan.dart`, `features/details/presentation/person_works_page.dart`) — edit the `core/`/`people/` original, not the shim.
- `core/` (especially `core/network`) must not import `features/`; cross-feature composition belongs in `app_providers.dart`.

**Playback**

- Playback is usually a separate window: `AppRoutes.openPlayback` hands the payload to `PlayerWindowCoordinator.openOrSwitch` on Windows and only falls back to an in-window `PlaybackPage` when a `runtime` is injected (tests) or `AppMotion.isTest`. Keep both paths working.
- Quality switching prepares the new `PlaybackPlan` first and falls back to the current source if the open fails (`PlaybackSourceTransition`).
- Server reporting is remote-only: `Sessions/Playing`, `Sessions/Playing/Progress`, `Sessions/Playing/Stopped`. A progress timer fires every **3.5 s** while playing plus on state changes; local playback must never produce server requests. Marking played goes to `Users/{UserId}/PlayedItems/{ItemId}`.
- `GlobalPlaybackCoordinator` keeps an optimistic in-memory mirror (`recentPositions`) and broadcasts local progress to home continue-watching, detail and library views; resume queries must keep `excludeActiveSessions: true` (the `getResumeItems` default) so a lagging server resume item cannot overwrite fresher local state. `HomeFeedService.refreshContinueWatching` deliberately passes `false` to include the live session — that is the only sanctioned exception.
- Diagnostics sample libmpv properties only while the panel is open (every 3 s) and stop on close. The log lives at `%LOCALAPPDATA%\PEeK\logs\playback_diagnostics.log`, rotates at 1 MiB, and redacts URLs, paths, headers and user/media/session IDs before writing.
- SMTC/WASAPI failures must never block playback; volume sync only touches PEeK's own audio session, never system master volume, and native events must be unregistered and the media card cleared on exit.

**Data, state and security**

- Favorites/played read `UserData.IsFavorite`/`UserData.Played` and write `Users/{UserId}/FavoriteItems/{ItemId}` / `PlayedItems/{ItemId}`. Batch writes run in groups of ≤4 concurrent requests, then clear the media JSON cache — and a cache-clear failure must not surface as a write failure.
- A 401/403 on a token-carrying request triggers exactly one session-expiry event: `SessionExpiryCoordinator` holds a pending token until `acknowledge()`, so concurrent failures collapse into one logout. A login-endpoint 401 does not participate.
- Never log or persist tokens/passwords; no token in cache keys, filenames or URLs (`PeekMediaImageCache.keyFor` strips secret query params). HTTPS certificate errors block by default — no global bypass. The password exists only for the login request; only the AccessToken is saved. DeviceId is generated once and kept stable.
- Library sorting/type/played/year filters MUST be sent to the server as `Items` query parameters; paging merges only under an identical filter set (never re-sort loaded partial data locally). View density is a purely local grid change. Favorites use a `ParentId`-less recursive `Users/{UserId}/Items?Filters=IsFavorite` query; actors use `IncludeItemTypes=Person&PersonTypes=Actor`.
- Local library browsing enumerates only the current directory level (never a full scan on the UI thread); every browse/play path re-validates the target stays under an added root; removing a library only deletes the record, never files. Covers: same-name image first, then `poster`/`folder`/`cover` in the folder.
- Multi-server support exists in the data model from day one, but the UI activates exactly one server at a time.

**UI, motion and performance**

- Grid/rail cards are wrapped in `PeekStaggeredGridItem`: its 2D diagonal wave (`row * 78ms + col * 52ms`, clamped ≤620 ms per card, ≤480 ms for rail batches) starts from `addPostFrameCallback` with a 45 ms lead-in on first build (`fromInit ? 45 : 0`) and 55 ms on tab replay, uses `RepaintBoundary` + hardware-composited 3D spring transforms, and unwraps every transform layer once settled. Do not reintroduce per-frame `setState` or drop the `RepaintBoundary`.
- Glass panels (`GlassSurface`, `VisionGlassCapsuleIsland`, `_VisionLiquidGlassPanel`) keep their `BackdropFilter` in a static `Positioned.fill` layer of a `Stack` so child animation cannot invalidate the blur every frame. Child tabs under `HomeShell` must stay on a transparent canvas (`Colors.transparent`) and must not nest another `AmbientBackdrop` or an opaque header.
- `PeekMediaImage` enforces adaptive `memCacheWidth` (poster 440, episode 600, backdrop 960, person 280, library 400, or `width * 2.2` clamped 120–1920) to bound Skia raster memory; the image cache is 30 days / 600 objects, and the Flutter image cache is warmed to 512 MB / 1500 entries at boot.
- `HomeShell` keeps pages alive on an on-demand `PeekIndexedTransitionStack` (created on first visit, never prefetched, scroll/state preserved) and drives the sidebar from a single `_sidebarController` with `_LiquidRailIndicator`.
- UI affordances must match behavior: downward arrows (`keyboard_arrow_down`, `expand_more`) only on widgets that really expand inline or open a menu. The top command bar user pill (`_AccountStatus`) navigates straight to server settings and must stay a plain status badge with no false dropdown arrow.
- Animate with `AppMotion` durations and `AppMotion.responsive`; anything that must not run under `flutter test` should check `AppMotion.isTest` (that is how the warm-up gate and route transitions stay fast in tests).
- Wheel scrolling is spring-driven (`peek_smooth_scroll.dart`): a packet only extends the spring target while the running activity keeps its velocity. Do **not** go back to calling `animateTo` per packet — that restarts the tween at t=0 and drops the frame each packet lands on (50% dead frames at one packet per two frames, a total freeze at one packet per frame). `test/peek_smooth_scroll_test.dart` guards the continuity; `tool/motion_bench.dart` (profile mode) measures glass raster cost.

## Tests

71 files in `test/`, **336 tests, all passing**, and `flutter analyze` is clean (verified on Flutter 3.44.6 / Dart 3.12.2). Coverage spans domain models, the `AppRoutes` facade, discovery/auth/secure storage, caches, playback plan and lifecycle, controls and gestures, the global progress coordinator, multi-window/PiP, diagnostics, danmaku, downloads, dedupe, scrobble, search, smooth scrolling, spatial motion, window chrome and the SMTC bridge.

- Playback tests follow the fake-runtime pattern (`test/playback_page_test.dart`, `test/playback_interaction_coordinator_test.dart`): inject a `PlaybackRuntime` fake — never construct a media_kit `Player`.
- Widget tests rely on `AppMotion.isTest` and `AppStoragePath.overrideDirectory` to stay hermetic; reset the override in `tearDown`.
- `docs/PLAYBACK_TEST_MATRIX.md` and `docs/playback-matrix/*.json` record the codec/subtitle/HDR compatibility matrix; keep new media coverage consistent with it.
