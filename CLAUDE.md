# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

PEeK (`embyplayer`) — a Windows-first Flutter desktop client for Jellyfin/Emby media servers, plus local media library browsing. Playback uses `media_kit` / libmpv. UI copy and most docs (README.md, docs/ARCHITECTURE.md, docs/ROADMAP.md, design-system/default/MASTER.md) are in Chinese. Requires Windows 10 2004+, Visual Studio 2022 with the "Desktop development with C++" workload.

## Commands

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool   # format check (CI enforces this)
flutter analyze
flutter test                                       # all tests
flutter test test/playback_page_test.dart          # single test file
flutter run -d windows
flutter build windows --profile                    # dev profile build
```

- CI (`.github/workflows/windows-release.yml`) pins Flutter **3.44.6** stable; format check, analyze, and tests run on every push/PR to `master`.
- MSIX packaging is scripted: `scripts/build_windows_package.ps1` (release build → regenerate `THIRD_PARTY_NOTICES.txt` via `tool/generate_third_party_notices.dart` → `dart run msix:create`). Pushing a `vMAJOR.MINOR.PATCH` tag builds, packages, and creates a GitHub Release; details in docs/WINDOWS_RELEASE.md.

## Architecture

Layered (Presentation → Application → Domain → Infrastructure), feature-first under `lib/src/features/`, each feature split into `data/`, `domain/`, `presentation/`.

- `lib/main.dart` — entry: initializes media_kit + window_manager (frameless window), runs `ProviderScope(child: EmbyPlayerApp())`.
- `lib/src/app/` — dark theme, glass-morphism components, frameless window chrome (`AppChrome`).
- `lib/src/core/network/network_providers.dart` — the composition root: every Riverpod provider (Dio, services, stores, coordinators) is registered here; Dio carries the `SessionExpiryInterceptor`.
- `lib/src/core/` — `session_expiry_coordinator.dart` (single-flight 401/403 handling), storage (`secure_token_store.dart` — Windows credential storage, one key per ServerId/UserId; `media_cache_store.dart`; `search_history_store.dart`), shared widgets (`peek_horizontal_rail.dart`, `peek_media_image.dart`, `peek_motion.dart`).
- `lib/src/features/servers/` — discovery (probes `{base}/System/Info/Public` then `{base}/emby/System/Info/Public`, saves the real API root), auth (`Users/AuthenticateByName`; Jellyfin uses the `MediaBrowser` scheme, Emby uses `Emby`), and the central domain interface `media_server_gateway.dart`: `JellyfinGateway`/`EmbyGateway` implement it, and UI depends only on the unified domain model (`MediaItem`, `ServerProfile`) — never server JSON DTOs.
- `lib/src/features/player/` — playback. `presentation/playback_runtime.dart` is the media_kit boundary: abstract `PlaybackRuntime` (streams + open/seek/volume/tracks) with `MediaKitPlaybackRuntime` as the real implementation; widget tests inject a fake runtime instead of constructing libmpv players. `PlaybackPlan` (domain) is built by `PlaybackPreparationService` and consumed by the runtime. `playback_service.dart` reports Started / Progress (~every 10 s + on state change) / Stopped — **remote playback only**; local playback never produces server requests.
- `lib/src/features/home/` — `home_shell.dart` hosts primary navigation as an on-demand `PageView`: pages are created on first visit and kept alive, so switching must preserve scroll/state and never prefetch hidden pages.
- `lib/src/features/local_library/` — local folders/STRM; roots persisted to `%LOCALAPPDATA%\PEeK\local_libraries_v1.json`; local playback bypasses the server entirely.
- `windows/runner/windows_media_session.cpp` — SMTC (system media transport controls) and WASAPI volume bridging; volume sync must only touch PEeK's own audio session, never system master volume.

## Non-obvious rules (docs/ARCHITECTURE.md)

- Security: never log or persist tokens/passwords; no token in cache keys, filenames, or URLs; HTTPS certificate errors block by default (no global bypass). The password exists only during the login request; only the AccessToken is saved.
- A 401/403 on a token-carrying request triggers exactly one session-expiry event (`SessionExpiryCoordinator` dedupes concurrent triggers); a 401 from the login endpoint does not participate in that flow.
- Library sorting/type/status/year filters must be sent to the server as `Items` query parameters; paging merges only under the same filter set (never sort already-loaded partial data locally). View density is purely a local grid change.
- Local library browsing enumerates only the current directory level (no full scans on the UI thread); every browse/play path re-validates it stays under an added root; removing a library never deletes files.
- Quality switching prepares the new playback plan first and falls back to the current source if the open fails.
- The diagnostics panel samples libmpv properties only while open (every 3 s); the diagnostics log redacts URLs, paths, headers, and user/media/session IDs, and rotates at 1 MiB.
- SMTC/audio-session failures must never block playback; on exit, unregister native events and clear the system media card.
- Favorites/played state reads `UserData.IsFavorite`/`UserData.Played`, writes via `Users/{UserId}/FavoriteItems/{ItemId}` and `PlayedItems`. Batch writes run ≤4 requests concurrently, then the media JSON cache is cleared — and a cache-clear failure must not surface as a server write failure.
- Multi-server support is in the data model from day one, but the UI activates exactly one server at a time.

## Tests

35 widget/unit test files in `test/` covering discovery/auth/secure storage, caches, services, playback plan/controls/lifecycle, window chrome, and the SMTC bridge. Follow the existing fake-runtime pattern for playback-page tests (`playback_page_test.dart`, `playback_interaction_coordinator_test.dart`) — do not construct `media_kit` `Player`s in tests.
