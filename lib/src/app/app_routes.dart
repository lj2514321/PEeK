import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/domain/playback_plan.dart';
import 'package:embyplayer/src/core/domain/playback_settings.dart';
import 'package:embyplayer/src/core/domain/server.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/dedupe/presentation/media_dedupe_page.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/people/presentation/person_works_page.dart';
import 'package:embyplayer/src/features/player/domain/playback_queue.dart';
import 'package:embyplayer/src/features/player/domain/player_window_payload.dart';
import 'package:embyplayer/src/features/player/presentation/playback_page.dart';
import 'package:embyplayer/src/features/player/presentation/playback_runtime.dart';
import 'package:embyplayer/src/features/player/presentation/player_window_coordinator.dart';

/// Centralized, type-safe navigation facade to decouple inter-feature presentation dependencies.
abstract final class AppRoutes {
  /// Opens the media detail view for a given item.
  /// If the item is a person/actor, automatically redirects to [openPersonWorks].
  /// Returns the updated [MediaItem] if any changes were made (e.g. favorite/played status).
  static Future<MediaItem?> openMediaDetail(
    BuildContext context, {
    required MediaItem item,
    AuthenticatedServer? account,
  }) {
    if (item.kind == MediaItemKind.person && account != null) {
      openPersonWorks(
        context,
        account: account,
        person: MediaPerson(
          id: item.id,
          name: item.name,
          type: 'Actor',
          imageUri: item.imageUri,
          imageHeaders: item.imageHeaders,
        ),
        onOpen: (work) =>
            openMediaDetail(context, item: work, account: account),
      );
      return Future.value(null);
    }
    return Navigator.of(context).push<MediaItem>(
      Peek3DPageRoute(
        builder: (_) => MediaDetailPage(initialItem: item, account: account),
      ),
    );
  }

  /// Opens the full-screen media playback page.
  static Future<void> openPlayback(
    BuildContext context, {
    required AuthenticatedServer? account,
    required MediaItem item,
    required PlaybackPlan plan,
    PlaybackQueue? queue,
    HardwareDecodingMode hardwareDecodingMode = HardwareDecodingMode.automatic,
    PlaybackBitrate maxStreamingBitrate = PlaybackBitrate.original,
    SubtitlePreferences subtitlePreferences = const SubtitlePreferences(),
    SkipIntroPreferences skipIntroPreferences = const SkipIntroPreferences(),
    DanmakuPreferences danmakuPreferences = const DanmakuPreferences(),
    PlaybackRuntime? runtime,
    bool isResumingFromMini = false,
    bool enableMiniPlayer = true,
    double longPressSpeed = 2.0,
    WidgetRef? ref,
  }) async {
    // On Windows desktop, when starting fresh playback (not resuming from floating mini player),
    // launch or switch to the dedicated independent Player Window.
    if (!kIsWeb && Platform.isWindows && runtime == null && !AppMotion.isTest) {
      try {
        final coordinator = ref != null
            ? ref.read(playerWindowCoordinatorProvider)
            : ProviderScope.containerOf(
                context,
                listen: false,
              ).read(playerWindowCoordinatorProvider);
        final payload = PlayerWindowPayload(
          account: account,
          item: item,
          plan: plan,
          queue: queue,
          hardwareDecodingMode: hardwareDecodingMode,
          maxStreamingBitrate: maxStreamingBitrate,
          subtitlePreferences: subtitlePreferences,
          skipIntroPreferences: skipIntroPreferences,
          danmakuPreferences: danmakuPreferences,
        );
        await coordinator.openOrSwitch(payload);
        return;
      } catch (e) {
        debugPrint(
          '[AppRoutes] Failed to open playback in dedicated window, falling back: $e',
        );
      }
    }

    if (!context.mounted) return;
    return Navigator.of(context).push<void>(
      TheatricalIrisPageRoute(
        builder: (_) => PlaybackPage(
          account: account,
          item: item,
          plan: plan,
          queue: queue,
          hardwareDecodingMode: hardwareDecodingMode,
          maxStreamingBitrate: maxStreamingBitrate,
          subtitlePreferences: subtitlePreferences,
          skipIntroPreferences: skipIntroPreferences,
          danmakuPreferences: danmakuPreferences,
          runtime: runtime,
          isResumingFromMini: isResumingFromMini,
          enableMiniPlayer: enableMiniPlayer,
          longPressSpeed: longPressSpeed,
        ),
      ),
    );
  }

  /// Opens the works listing page for an actor/person.
  static Future<void> openPersonWorks(
    BuildContext context, {
    required AuthenticatedServer account,
    required MediaPerson person,
    required ValueChanged<MediaItem> onOpen,
  }) {
    return Navigator.of(context).push<void>(
      Peek3DPageRoute(
        builder: (_) =>
            PersonWorksPage(account: account, person: person, onOpen: onOpen),
      ),
    );
  }

  /// Opens the duplicate media detection & cleaning page.
  static Future<void> openDedupe(
    BuildContext context, {
    required AuthenticatedServer? account,
    List<MediaItem> initialItems = const [],
    String? libraryId,
    String? libraryName,
  }) {
    return Navigator.of(context).push<void>(
      Peek3DPageRoute(
        builder: (_) => MediaDedupePage(
          account: account,
          initialItems: initialItems,
          libraryId: libraryId,
          libraryName: libraryName,
        ),
      ),
    );
  }
}
