import 'dart:async';
import 'dart:io';

import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/player/data/playback_diagnostic_log.dart';
import 'package:embyplayer/src/features/player/data/playback_diagnostics_service.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_diagnostics.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_queue.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/player/domain/playback_source_transition.dart';
import 'package:embyplayer/src/features/player/presentation/playback_controls.dart';
import 'package:embyplayer/src/features/player/presentation/playback_diagnostics_panel.dart';
import 'package:embyplayer/src/features/player/presentation/playback_quality_sheet.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

class PlaybackPage extends ConsumerStatefulWidget {
  const PlaybackPage({
    super.key,
    required this.account,
    required this.item,
    required this.plan,
    this.queue,
    this.hardwareDecodingMode = HardwareDecodingMode.automatic,
    this.maxStreamingBitrate = PlaybackBitrate.original,
    this.subtitlePreferences = const SubtitlePreferences(),
  });

  final AuthenticatedServer account;
  final MediaItem item;
  final PlaybackPlan plan;
  final PlaybackQueue? queue;
  final HardwareDecodingMode hardwareDecodingMode;
  final PlaybackBitrate maxStreamingBitrate;
  final SubtitlePreferences subtitlePreferences;

  @override
  ConsumerState<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<PlaybackPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      hwdec: widget.hardwareDecodingMode.mpvValue,
      enableHardwareAcceleration: true,
    ),
  );
  late PlaybackPlan _plan = widget.plan;
  late MediaItem _item = widget.item;
  late PlaybackQueue? _queue = widget.queue;

  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _progressTimer;
  Timer? _controlsTimer;
  Timer? _nextEpisodeTimer;
  Timer? _diagnosticsTimer;
  Timer? _subtitleSettingsTimer;
  late final PlaybackDiagnosticLog _diagnosticLog;
  final PlaybackDiagnosticsService _diagnosticsService =
      const PlaybackDiagnosticsService();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  Duration? _previewPosition;
  Tracks _tracks = const Tracks();
  Track _track = const Track();
  double _volume = 100;
  double _lastAudibleVolume = 100;
  double _rate = 1;
  int? _selectedAudioStreamIndex;
  int? _selectedSubtitleStreamIndex;
  bool _subtitlesDisabled = false;
  bool _playing = false;
  bool _buffering = false;
  bool _controlsVisible = true;
  bool _reportedStarted = false;
  bool _reportedStopped = false;
  bool _playerDisposed = false;
  bool _closing = false;
  bool _changingSource = false;
  String _sourceChangeLabel = '正在切换媒体';
  bool _fullScreen = false;
  bool _diagnosticsVisible = false;
  bool _diagnosticsLoading = false;
  bool _diagnosticsReading = false;
  String? _error;
  PlaybackDiagnosticsSnapshot? _diagnostics;
  int? _nextEpisodeCountdown;
  late PlaybackBitrate _maxStreamingBitrate = widget.maxStreamingBitrate;
  late SubtitlePreferences _subtitlePreferences = widget.subtitlePreferences;

  static const _autoNextSeconds = 8;

  Duration get _effectiveDuration {
    if (_duration > Duration.zero) return _duration;
    return _plan.duration ?? Duration.zero;
  }

  @override
  void initState() {
    super.initState();
    _diagnosticLog = ref.read(playbackDiagnosticLogProvider);
    AppChrome.enterImmersive();
    _duration = widget.plan.duration ?? Duration.zero;
    _position = widget.plan.startPosition;
    _selectedAudioStreamIndex = widget.plan.audioStreamIndex;
    _selectedSubtitleStreamIndex = widget.plan.subtitleStreamIndex;
    _subtitlesDisabled = widget.plan.subtitleStreamIndex == null;
    _listenToPlayer();
    Future<void>.microtask(_openInitialMedia);
  }

  void _listenToPlayer() {
    _subscriptions.addAll([
      _player.stream.playing.listen(_playingChanged),
      _player.stream.position.listen((value) {
        if (mounted && _previewPosition == null) {
          setState(() => _position = value);
        }
      }),
      _player.stream.duration.listen((value) {
        if (mounted && value > Duration.zero) {
          setState(() => _duration = value);
        }
      }),
      _player.stream.buffer.listen((value) {
        if (mounted) setState(() => _buffer = value);
      }),
      _player.stream.buffering.listen((value) {
        if (mounted) setState(() => _buffering = value);
      }),
      _player.stream.volume.listen((value) {
        if (!mounted) return;
        if (value > 0) _lastAudibleVolume = value;
        setState(() => _volume = value);
      }),
      _player.stream.rate.listen((value) {
        if (mounted) setState(() => _rate = value);
      }),
      _player.stream.tracks.listen((value) {
        if (mounted) setState(() => _tracks = value);
      }),
      _player.stream.track.listen((value) {
        if (mounted) setState(() => _track = value);
      }),
      _player.stream.completed.listen((completed) {
        if (completed) _finishCompletedPlayback();
      }),
      _player.stream.error.listen((message) {
        if (mounted && message.isNotEmpty) {
          _writeDiagnosticLog('player_error', fields: {'message': message});
          setState(() => _error = '播放器无法继续播放：$message');
          _showControls();
        }
      }),
    ]);
  }

  Future<void> _openInitialMedia() async {
    try {
      await _openMedia(_plan, play: true);
      _writeDiagnosticLog('playback_opened');
      await _safeReportStarted();
      _startProgressTimer();
    } catch (error) {
      _writeDiagnosticLog(
        'playback_open_failed',
        fields: {'message': error.toString()},
      );
      if (mounted) setState(() => _error = '无法打开媒体：$error');
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _safeReportProgress('TimeUpdate'),
    );
  }

  Future<void> _openMedia(
    PlaybackPlan plan, {
    required bool play,
    Duration? startPosition,
  }) async {
    await _player.open(
      Media(
        plan.streamUri.toString(),
        httpHeaders: plan.httpHeaders,
        start: startPosition ?? plan.startPosition,
      ),
      play: play,
    );
    await _applySubtitleDelay();
  }

  void _playingChanged(bool playing) {
    if (!mounted) return;
    setState(() => _playing = playing);
    if (playing) {
      _scheduleControlsHide();
    } else {
      _controlsTimer?.cancel();
      if (!_controlsVisible) setState(() => _controlsVisible = true);
    }
    if (_reportedStarted && !_closing && !_changingSource) {
      _safeReportProgress(playing ? 'Unpause' : 'Pause');
    }
  }

  void _showControls() {
    if (!mounted) return;
    if (_diagnosticsVisible) return;
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (!_playing || _changingSource || _error != null || _diagnosticsVisible) {
      return;
    }
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_changingSource && _error == null) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _togglePlayPause() async {
    _showControls();
    await _player.playOrPause();
  }

  void _previewSeek(Duration position) {
    _showControls();
    setState(() => _previewPosition = _clampPosition(position));
  }

  Future<void> _seek(Duration position) async {
    final target = _clampPosition(position);
    setState(() {
      _position = target;
      _previewPosition = null;
    });
    await _player.seek(target);
    await _safeReportProgress('TimeUpdate');
    _showControls();
  }

  Future<void> _seekRelative(Duration offset) {
    return _seek(_position + offset);
  }

  Duration _clampPosition(Duration value) {
    final duration = _effectiveDuration;
    if (value < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && value > duration) return duration;
    return value;
  }

  Future<void> _setVolume(double value) async {
    _showControls();
    final normalized = value.clamp(0, 100).toDouble();
    if (normalized > 0) _lastAudibleVolume = normalized;
    setState(() => _volume = normalized);
    await _player.setVolume(normalized);
  }

  Future<void> _adjustVolume(double delta) {
    return _setVolume(_volume + delta);
  }

  Future<void> _toggleMute() {
    return _setVolume(_volume <= 0 ? _lastAudibleVolume.clamp(1, 100) : 0);
  }

  Future<void> _setRate(double value) async {
    _showControls();
    setState(() => _rate = value);
    await _player.setRate(value);
    await _safeReportProgress('PlaybackRateChange');
  }

  Future<void> _toggleFullScreen() async {
    _showControls();
    if (!Platform.isWindows) return;
    final next = !_fullScreen;
    try {
      await windowManager.setFullScreen(next);
      if (mounted) setState(() => _fullScreen = next);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '无法切换全屏：$error');
    }
  }

  Future<void> _handleEscape() async {
    if (_diagnosticsVisible) {
      _closeDiagnostics();
      return;
    }
    if (_fullScreen) {
      await _toggleFullScreen();
    } else {
      await _close();
    }
  }

  void _toggleDiagnostics() {
    if (_diagnosticsVisible) {
      _closeDiagnostics();
      return;
    }
    _controlsTimer?.cancel();
    setState(() {
      _diagnosticsVisible = true;
      _controlsVisible = false;
    });
    _writeDiagnosticLog('diagnostics_opened');
    unawaited(_refreshDiagnostics());
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refreshDiagnostics()),
    );
  }

  void _closeDiagnostics() {
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;
    if (!mounted) return;
    setState(() {
      _diagnosticsVisible = false;
      _diagnosticsLoading = false;
    });
    _showControls();
  }

  Future<void> _refreshDiagnostics() async {
    if (!_diagnosticsVisible ||
        _diagnosticsReading ||
        _playerDisposed ||
        _closing) {
      return;
    }
    _diagnosticsReading = true;
    if (mounted) setState(() => _diagnosticsLoading = true);
    final video = _track.video;
    final audio = _track.audio;
    try {
      final snapshot = await _diagnosticsService.collect(
        readProperty: _readMpvProperty,
        plan: _plan,
        requestedDecodingMode: widget.hardwareDecodingMode,
        serverKind: widget.account.server.kind.name,
        serverVersion: widget.account.server.version,
        position: _position,
        bufferedUntil: _buffer,
        buffering: _buffering,
        videoCodec: video.codec,
        audioCodec: audio.codec,
        fallbackWidth: video.w,
        fallbackHeight: video.h,
        fallbackFrameRate: video.fps,
        fallbackVideoBitrate: video.bitrate,
        fallbackAudioBitrate: audio.bitrate,
      );
      if (mounted && _diagnosticsVisible) {
        setState(() => _diagnostics = snapshot);
      }
    } finally {
      _diagnosticsReading = false;
      if (mounted) setState(() => _diagnosticsLoading = false);
    }
  }

  Future<String?> _readMpvProperty(String property) async {
    final platform = _player.platform;
    if (platform is! NativePlayer || _playerDisposed) return null;
    try {
      return await platform.getProperty(property);
    } on Object {
      return null;
    }
  }

  Future<void> _applySubtitleDelay() async {
    final platform = _player.platform;
    if (platform is! NativePlayer || _playerDisposed) return;
    try {
      final seconds = _subtitlePreferences.delayMilliseconds / 1000;
      await platform.setProperty('sub-delay', seconds.toStringAsFixed(3));
    } on Object {
      // Subtitle styling remains available if the native delay is unsupported.
    }
  }

  void _updateSubtitlePreferences(SubtitlePreferences preferences) {
    if (_subtitlePreferences == preferences) return;
    setState(() => _subtitlePreferences = preferences);
    unawaited(_applySubtitleDelay());
    _subtitleSettingsTimer?.cancel();
    _subtitleSettingsTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_persistPlaybackPreferences()),
    );
  }

  Future<void> _persistPlaybackPreferences() async {
    try {
      final store = ref.read(playbackSettingsStoreProvider);
      final settings = await store.read();
      await store.write(
        settings.copyWith(
          maxStreamingBitrate: _maxStreamingBitrate,
          subtitlePreferences: _subtitlePreferences,
        ),
      );
    } on Object {
      // Playback must not be interrupted by an optional preference write.
    }
  }

  Future<void> _copyDiagnostics() async {
    final snapshot = _diagnostics;
    if (snapshot == null) return;
    await Clipboard.setData(
      ClipboardData(
        text: snapshot.toClipboardText(platform: Platform.operatingSystem),
      ),
    );
    _writeDiagnosticLog('diagnostics_copied');
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制脱敏播放诊断信息。')));
  }

  void _writeDiagnosticLog(
    String event, {
    Map<String, Object?> fields = const {},
  }) {
    unawaited(
      _diagnosticLog.write(
        event,
        fields: {
          'serverKind': widget.account.server.kind.name,
          'serverVersion': widget.account.server.version,
          'playbackMethod': _plan.method.name,
          'sourceProtocol': _plan.streamUri.scheme,
          'hardwarePreference': widget.hardwareDecodingMode.name,
          ...fields,
        },
        secrets: [widget.account.accessToken, ..._plan.httpHeaders.values],
      ),
    );
  }

  Future<void> _showAudioTracks() {
    return _showTrackSheet(
      title: '选择音轨',
      icon: Icons.graphic_eq_rounded,
      options: _audioOptions(),
      emptyMessage: '当前媒体没有可切换的音轨。',
    );
  }

  Future<void> _showQualityOptions() async {
    if (_changingSource || _closing) return;
    _controlsTimer?.cancel();
    _showControls();
    final selected = await showModalBottomSheet<PlaybackBitrate>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      isScrollControlled: true,
      builder: (context) =>
          PlaybackQualitySheet(selected: _maxStreamingBitrate),
    );
    if (selected != null && selected != _maxStreamingBitrate && mounted) {
      await _switchQuality(selected);
    }
    if (mounted) _scheduleControlsHide();
  }

  Future<void> _switchQuality(PlaybackBitrate bitrate) async {
    final switched = await _replaceCurrentPlan(
      statusLabel: '正在切换至${bitrate.label}',
      actionLabel: '切换画质',
      successEvent: 'playback_quality_changed',
      committedBitrate: bitrate,
      createPlan: (position) => ref
          .read(playbackServiceProvider)
          .createPlan(
            widget.account,
            _item,
            startPosition: position,
            audioStreamIndex: _selectedAudioStreamIndex,
            subtitleStreamIndex: _subtitlesDisabled
                ? -1
                : _selectedSubtitleStreamIndex,
            mediaSourceId: _plan.mediaSourceId,
            maxStreamingBitrate: bitrate,
          ),
    );
    if (!switched || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('画质上限已切换为${bitrate.label}')));
  }

  Future<void> _showSubtitleTracks() {
    _controlsTimer?.cancel();
    _showControls();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      isScrollControlled: true,
      builder: (context) => _SubtitleSheet(
        preferences: _subtitlePreferences,
        options: _subtitleOptions(),
        onPreferencesChanged: _updateSubtitlePreferences,
      ),
    ).whenComplete(() {
      if (mounted) _scheduleControlsHide();
    });
  }

  Future<void> _showTrackSheet({
    required String title,
    required IconData icon,
    required List<_TrackMenuOption> options,
    required String emptyMessage,
  }) async {
    _controlsTimer?.cancel();
    _showControls();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      isScrollControlled: true,
      builder: (context) => _TrackSheet(
        title: title,
        icon: icon,
        options: options,
        emptyMessage: emptyMessage,
      ),
    );
    if (mounted) _scheduleControlsHide();
  }

  List<_TrackMenuOption> _audioOptions() {
    final engineTracks = _usableAudioTracks;
    if (_plan.audioTracks.isNotEmpty) {
      return [
        for (var index = 0; index < _plan.audioTracks.length; index++)
          _TrackMenuOption(
            title: _plan.audioTracks[index].label,
            detail: _trackDetail(_plan.audioTracks[index]),
            selected:
                _selectedAudioStreamIndex == _plan.audioTracks[index].index,
            onSelected: () => _selectServerAudio(
              _plan.audioTracks[index],
              index < engineTracks.length ? engineTracks[index] : null,
            ),
          ),
      ];
    }
    return [
      for (final track in engineTracks)
        _TrackMenuOption(
          title: _engineTrackLabel(track),
          detail: _engineTrackDetail(track),
          selected: _track.audio.id == track.id,
          onSelected: () => _selectEngineAudio(track),
        ),
    ];
  }

  List<_TrackMenuOption> _subtitleOptions() {
    final options = <_TrackMenuOption>[
      _TrackMenuOption(
        title: '关闭字幕',
        detail: '不显示任何字幕',
        selected: _subtitlesDisabled,
        onSelected: _disableSubtitles,
      ),
    ];
    final engineTracks = _usableSubtitleTracks;
    if (_plan.subtitleTracks.isNotEmpty) {
      final embeddedTracks = _plan.subtitleTracks
          .where((track) => !track.isExternal)
          .toList(growable: false);
      for (final info in _plan.subtitleTracks) {
        final embeddedIndex = embeddedTracks.indexOf(info);
        options.add(
          _TrackMenuOption(
            title: info.label,
            detail: _trackDetail(info),
            selected:
                !_subtitlesDisabled &&
                _selectedSubtitleStreamIndex == info.index,
            onSelected: () => _selectServerSubtitle(
              info,
              embeddedIndex >= 0 && embeddedIndex < engineTracks.length
                  ? engineTracks[embeddedIndex]
                  : null,
            ),
          ),
        );
      }
      return options;
    }
    options.addAll([
      for (final track in engineTracks)
        _TrackMenuOption(
          title: _engineTrackLabel(track),
          detail: _engineTrackDetail(track),
          selected: !_subtitlesDisabled && _track.subtitle.id == track.id,
          onSelected: () => _selectEngineSubtitle(track),
        ),
    ]);
    return options;
  }

  List<AudioTrack> get _usableAudioTracks => _tracks.audio
      .where((track) => track.id != 'auto' && track.id != 'no')
      .toList(growable: false);

  List<SubtitleTrack> get _usableSubtitleTracks => _tracks.subtitle
      .where((track) => track.id != 'auto' && track.id != 'no')
      .toList(growable: false);

  Future<void> _selectServerAudio(
    PlaybackTrackInfo info,
    AudioTrack? engineTrack,
  ) async {
    if (_plan.method != PlaybackMethod.transcode && engineTrack != null) {
      await _player.setAudioTrack(engineTrack);
      if (mounted) setState(() => _selectedAudioStreamIndex = info.index);
      await _safeReportProgress('AudioTrackChange');
      return;
    }
    await _rebuildPlan(
      audioStreamIndex: info.index,
      subtitleStreamIndex: _subtitlesDisabled
          ? -1
          : _selectedSubtitleStreamIndex,
    );
  }

  Future<void> _selectEngineAudio(AudioTrack track) async {
    await _player.setAudioTrack(track);
    if (mounted) setState(() => _selectedAudioStreamIndex = null);
    await _safeReportProgress('AudioTrackChange');
  }

  Future<void> _selectServerSubtitle(
    PlaybackTrackInfo info,
    SubtitleTrack? engineTrack,
  ) async {
    if (_plan.method != PlaybackMethod.transcode &&
        info.isExternal &&
        info.deliveryUri != null) {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          info.deliveryUri.toString(),
          title: info.label,
          language: info.language,
        ),
      );
      if (mounted) {
        setState(() {
          _selectedSubtitleStreamIndex = info.index;
          _subtitlesDisabled = false;
        });
      }
      await _safeReportProgress('SubtitleTrackChange');
      return;
    }
    if (_plan.method != PlaybackMethod.transcode && engineTrack != null) {
      await _player.setSubtitleTrack(engineTrack);
      if (mounted) {
        setState(() {
          _selectedSubtitleStreamIndex = info.index;
          _subtitlesDisabled = false;
        });
      }
      await _safeReportProgress('SubtitleTrackChange');
      return;
    }
    await _rebuildPlan(
      audioStreamIndex: _selectedAudioStreamIndex,
      subtitleStreamIndex: info.index,
    );
  }

  Future<void> _selectEngineSubtitle(SubtitleTrack track) async {
    await _player.setSubtitleTrack(track);
    if (mounted) {
      setState(() {
        _selectedSubtitleStreamIndex = null;
        _subtitlesDisabled = false;
      });
    }
    await _safeReportProgress('SubtitleTrackChange');
  }

  Future<void> _disableSubtitles() async {
    if (_plan.method == PlaybackMethod.transcode &&
        _selectedSubtitleStreamIndex != null) {
      await _rebuildPlan(
        audioStreamIndex: _selectedAudioStreamIndex,
        subtitleStreamIndex: -1,
      );
      return;
    }
    await _player.setSubtitleTrack(SubtitleTrack.no());
    if (mounted) {
      setState(() {
        _selectedSubtitleStreamIndex = null;
        _subtitlesDisabled = true;
      });
    }
    await _safeReportProgress('SubtitleTrackChange');
  }

  Future<void> _rebuildPlan({
    required int? audioStreamIndex,
    required int? subtitleStreamIndex,
  }) async {
    await _replaceCurrentPlan(
      statusLabel: '正在切换媒体轨道',
      actionLabel: '切换轨道',
      successEvent: 'playback_tracks_rebuilt',
      subtitlesDisabledAfterSwitch: subtitleStreamIndex == -1,
      createPlan: (position) => ref
          .read(playbackServiceProvider)
          .createPlan(
            widget.account,
            _item,
            startPosition: position,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            mediaSourceId: _plan.mediaSourceId,
            maxStreamingBitrate: _maxStreamingBitrate,
          ),
    );
  }

  Future<bool> _replaceCurrentPlan({
    required String statusLabel,
    required String actionLabel,
    required String successEvent,
    required Future<PlaybackPlan> Function(Duration position) createPlan,
    PlaybackBitrate? committedBitrate,
    bool? subtitlesDisabledAfterSwitch,
  }) async {
    if (_changingSource || _closing) return false;
    _controlsTimer?.cancel();
    _progressTimer?.cancel();
    final oldPlan = _plan;
    final oldTrack = _track;
    final oldSubtitlesDisabled = _subtitlesDisabled;
    final wasPlaying = _playing;
    final position = _position;
    final preservedVolume = _volume;
    final preservedRate = _rate;
    final shouldReportOldStopped = _reportedStarted && !_reportedStopped;
    final oldSnapshot = PlaybackSessionSnapshot(
      plan: oldPlan,
      position: position,
      isPaused: !wasPlaying,
      volume: preservedVolume,
      audioStreamIndex: _selectedAudioStreamIndex,
      subtitleStreamIndex: _selectedSubtitleStreamIndex,
      subtitlesDisabled: oldSubtitlesDisabled,
      playbackRate: preservedRate,
      subtitleOffset: _subtitlePreferences.delay,
    );
    setState(() {
      _changingSource = true;
      _sourceChangeLabel = statusLabel;
      _controlsVisible = true;
      _error = null;
    });

    try {
      try {
        await _player.pause();
      } on Object catch (error) {
        _reportRecoveredSourceChangeFailure(actionLabel, error);
        return false;
      }
      final transition = await const PlaybackSourceTransition()
          .execute<PlaybackPlan>(
            prepare: () => createPlan(position),
            open: (plan) => _openMedia(plan, play: wasPlaying),
            restore: () async {
              final restored = await _restorePreviousSource(
                oldPlan,
                oldTrack,
                position: position,
                play: wasPlaying,
                volume: preservedVolume,
                rate: preservedRate,
                subtitlesDisabled: oldSubtitlesDisabled,
              );
              if (!restored) {
                throw StateError('原播放源无法重新打开');
              }
            },
          );
      if (transition.status ==
          PlaybackSourceTransitionStatus.preparationFailed) {
        if (wasPlaying) await _resumeQuietly();
        _reportRecoveredSourceChangeFailure(actionLabel, transition.error!);
        return false;
      }
      if (transition.status == PlaybackSourceTransitionStatus.restored) {
        _reportRecoveredSourceChangeFailure(actionLabel, transition.error!);
        return false;
      }
      if (transition.status == PlaybackSourceTransitionStatus.restoreFailed) {
        if (mounted) {
          setState(
            () => _error = '$actionLabel失败，且原播放源无法恢复：${transition.error}',
          );
        }
        return false;
      }
      final nextPlan = transition.value!;

      if (shouldReportOldStopped) {
        try {
          await ref
              .read(playbackServiceProvider)
              .reportStopped(widget.account, oldSnapshot);
        } on Object {
          // The newly opened source remains usable if the old check-in fails.
        }
      }

      _plan = nextPlan;
      _selectedAudioStreamIndex = nextPlan.audioStreamIndex;
      _selectedSubtitleStreamIndex = nextPlan.subtitleStreamIndex;
      _subtitlesDisabled = subtitlesDisabledAfterSwitch ?? oldSubtitlesDisabled;
      _reportedStarted = false;
      _reportedStopped = false;
      if (committedBitrate != null) {
        _maxStreamingBitrate = committedBitrate;
      }
      if (_diagnosticsVisible) _diagnostics = null;
      if (mounted) {
        setState(() {
          _duration = nextPlan.duration ?? _duration;
          _position = nextPlan.startPosition;
          _previewPosition = null;
          _buffer = Duration.zero;
          _error = null;
        });
      }
      await _restorePlanTracks(
        nextPlan,
        previousTrack: oldTrack,
        subtitlesDisabled: _subtitlesDisabled,
      );
      await _restoreRuntimeState(volume: preservedVolume, rate: preservedRate);
      _writeDiagnosticLog(
        successEvent,
        fields: {
          if (committedBitrate != null)
            'maxStreamingBitrate': committedBitrate.name,
        },
      );
      if (_diagnosticsVisible) unawaited(_refreshDiagnostics());
      await _safeReportStarted();
      if (committedBitrate != null) {
        await _persistPlaybackPreferences();
      }
      return true;
    } finally {
      if (mounted) {
        setState(() => _changingSource = false);
        if (!_closing) {
          _startProgressTimer();
          _scheduleControlsHide();
        }
      }
    }
  }

  Future<void> _resumeQuietly() async {
    try {
      await _player.play();
    } on Object {
      // The player error stream will surface a failure to resume.
    }
  }

  Future<bool> _restorePreviousSource(
    PlaybackPlan plan,
    Track previousTrack, {
    required Duration position,
    required bool play,
    required double volume,
    required double rate,
    required bool subtitlesDisabled,
  }) async {
    try {
      await _openMedia(plan, play: play, startPosition: position);
      await _restorePlanTracks(
        plan,
        previousTrack: previousTrack,
        subtitlesDisabled: subtitlesDisabled,
      );
      await _restoreRuntimeState(volume: volume, rate: rate);
      return true;
    } on Object catch (error) {
      _writeDiagnosticLog(
        'playback_source_restore_failed',
        fields: {'message': error.toString()},
      );
      return false;
    }
  }

  Future<void> _restoreRuntimeState({
    required double volume,
    required double rate,
  }) async {
    try {
      await _player.setVolume(volume);
    } on Object {
      // A media source switch should still succeed if volume restore fails.
    }
    try {
      await _player.setRate(rate);
    } on Object {
      // A media source switch should still succeed if rate restore fails.
    }
  }

  Future<void> _restorePlanTracks(
    PlaybackPlan plan, {
    required Track previousTrack,
    required bool subtitlesDisabled,
  }) async {
    if (plan.method == PlaybackMethod.transcode) return;
    final tracks = _player.state.tracks;
    final audioTracks = tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
    final subtitleTracks = tracks.subtitle
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
    try {
      final selectedAudioIndex = plan.audioTracks.indexWhere(
        (track) => track.index == plan.audioStreamIndex,
      );
      if (selectedAudioIndex >= 0 && selectedAudioIndex < audioTracks.length) {
        await _player.setAudioTrack(audioTracks[selectedAudioIndex]);
      } else {
        final previousAudioIndex = audioTracks.indexWhere(
          (track) => track.id == previousTrack.audio.id,
        );
        if (previousAudioIndex >= 0) {
          await _player.setAudioTrack(audioTracks[previousAudioIndex]);
        }
      }
    } on Object {
      // The server-selected audio track remains the safe fallback.
    }

    try {
      if (subtitlesDisabled) {
        await _player.setSubtitleTrack(SubtitleTrack.no());
        return;
      }
      PlaybackTrackInfo? selectedSubtitle;
      for (final track in plan.subtitleTracks) {
        if (track.index == plan.subtitleStreamIndex) {
          selectedSubtitle = track;
          break;
        }
      }
      if (selectedSubtitle?.isExternal == true &&
          selectedSubtitle?.deliveryUri != null) {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(
            selectedSubtitle!.deliveryUri.toString(),
            title: selectedSubtitle.label,
            language: selectedSubtitle.language,
          ),
        );
        return;
      }
      final embeddedTracks = plan.subtitleTracks
          .where((track) => !track.isExternal)
          .toList(growable: false);
      final embeddedIndex = embeddedTracks.indexWhere(
        (track) => track.index == plan.subtitleStreamIndex,
      );
      if (embeddedIndex >= 0 && embeddedIndex < subtitleTracks.length) {
        await _player.setSubtitleTrack(subtitleTracks[embeddedIndex]);
        return;
      }
      final previousSubtitleIndex = subtitleTracks.indexWhere(
        (track) => track.id == previousTrack.subtitle.id,
      );
      if (previousSubtitleIndex >= 0) {
        await _player.setSubtitleTrack(subtitleTracks[previousSubtitleIndex]);
      }
    } on Object {
      // The server-selected subtitle remains the safe fallback.
    }
  }

  void _reportRecoveredSourceChangeFailure(String actionLabel, Object error) {
    final message = error is PlaybackServiceException
        ? error.message
        : error.toString();
    _writeDiagnosticLog(
      'playback_source_change_failed',
      fields: {'action': actionLabel, 'message': message},
    );
    if (!mounted) return;
    setState(() => _error = null);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$actionLabel失败，已继续原播放：$message')));
  }

  String get _currentAudioLabel {
    for (final track in _plan.audioTracks) {
      if (track.index == _selectedAudioStreamIndex) return track.label;
    }
    return _engineTrackLabel(_track.audio, fallback: '自动');
  }

  String get _currentSubtitleLabel {
    if (_subtitlesDisabled) return '关闭';
    for (final track in _plan.subtitleTracks) {
      if (track.index == _selectedSubtitleStreamIndex) return track.label;
    }
    return _engineTrackLabel(_track.subtitle, fallback: '自动');
  }

  String _trackDetail(PlaybackTrackInfo track) {
    final parts = <String>[
      if (track.language != null) track.language!.toUpperCase(),
      if (track.codec != null) track.codec!.toUpperCase(),
      if (track.channels != null) track.channels!,
      if (track.isDefault) '默认',
      if (track.isForced) '强制',
      if (track.isExternal) '外挂',
    ];
    return parts.isEmpty ? '媒体轨道 ${track.index}' : parts.join(' · ');
  }

  String _engineTrackLabel(dynamic track, {String fallback = '轨道'}) {
    final title = track.title as String?;
    final language = track.language as String?;
    if (title != null && title.isNotEmpty) return title;
    if (language != null && language.isNotEmpty) return language.toUpperCase();
    final id = track.id as String;
    return id == 'auto' ? fallback : '$fallback $id';
  }

  String _engineTrackDetail(dynamic track) {
    final parts = <String>[
      if (track.language != null && (track.language as String).isNotEmpty)
        (track.language as String).toUpperCase(),
      if (track.codec != null && (track.codec as String).isNotEmpty)
        (track.codec as String).toUpperCase(),
      if (track.channels != null && (track.channels as String).isNotEmpty)
        track.channels as String,
    ];
    return parts.isEmpty ? '播放器识别的媒体轨道' : parts.join(' · ');
  }

  Future<void> _safeReportStarted() async {
    try {
      await ref
          .read(playbackServiceProvider)
          .reportStarted(widget.account, _snapshot());
      _reportedStarted = true;
    } catch (_) {
      // Playback remains available if presence reporting is unavailable.
    }
  }

  Future<void> _safeReportProgress(String eventName) async {
    if (!_reportedStarted || _reportedStopped) return;
    try {
      await ref
          .read(playbackServiceProvider)
          .reportProgress(widget.account, _snapshot(), eventName: eventName);
    } catch (_) {
      // A later periodic update can recover from a transient failure.
    }
  }

  Future<void> _safeReportStopped() async {
    if (_reportedStopped || !_reportedStarted) return;
    _reportedStopped = true;
    try {
      await ref
          .read(playbackServiceProvider)
          .reportStopped(widget.account, _snapshot());
    } catch (_) {
      // Closing or rebuilding playback must not be blocked by reporting.
    }
  }

  Future<void> _safeMarkPlayed() async {
    try {
      await ref
          .read(playbackServiceProvider)
          .markPlayed(widget.account, _item.id);
    } catch (_) {
      // The completed check-in can still mark the item on the server.
    }
  }

  Future<void> _showEpisodes() async {
    final queue = _queue;
    if (queue == null || queue.items.isEmpty) return;
    _controlsTimer?.cancel();
    _showControls();
    final index = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      isScrollControlled: true,
      builder: (context) => _EpisodeSheet(queue: queue),
    );
    if (index != null && mounted) {
      await _playQueueIndex(index);
    }
    if (mounted) _scheduleControlsHide();
  }

  Future<void> _showChapters() async {
    if (_plan.chapters.isEmpty) return;
    _controlsTimer?.cancel();
    _showControls();
    final target = await showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      isScrollControlled: true,
      builder: (context) =>
          _ChapterSheet(chapters: _plan.chapters, position: _position),
    );
    if (target != null && mounted) await _seek(target);
    if (mounted) _scheduleControlsHide();
  }

  void _startNextEpisodeCountdown() {
    final queue = _queue;
    if (queue == null || !queue.hasNext || _closing || _changingSource) return;
    _nextEpisodeTimer?.cancel();
    setState(() {
      _nextEpisodeCountdown = _autoNextSeconds;
      _controlsVisible = true;
    });
    _nextEpisodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _closing) {
        timer.cancel();
        return;
      }
      final remaining = (_nextEpisodeCountdown ?? 1) - 1;
      if (remaining <= 0) {
        timer.cancel();
        setState(() => _nextEpisodeCountdown = null);
        final queue = _queue;
        if (queue != null) {
          unawaited(_playQueueIndex(queue.currentIndex + 1, automatic: true));
        }
      } else {
        setState(() => _nextEpisodeCountdown = remaining);
      }
    });
  }

  void _cancelNextEpisodeCountdown({bool showControls = true}) {
    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = null;
    if (mounted && _nextEpisodeCountdown != null) {
      setState(() => _nextEpisodeCountdown = null);
    }
    if (showControls) _showControls();
  }

  Future<void> _playQueueIndex(int index, {bool automatic = false}) async {
    final queue = _queue;
    if (queue == null ||
        index < 0 ||
        index >= queue.items.length ||
        index == queue.currentIndex ||
        _changingSource ||
        _closing) {
      return;
    }
    final target = queue.items[index];
    final wasPlaying = _playing;
    final preservedVolume = _volume;
    final preservedRate = _rate;
    _cancelNextEpisodeCountdown(showControls: false);
    _progressTimer?.cancel();
    _controlsTimer?.cancel();
    setState(() {
      _changingSource = true;
      _sourceChangeLabel = automatic ? '正在播放下一集' : '正在切换剧集';
      _controlsVisible = true;
      _error = null;
    });
    await _player.pause();
    try {
      final nextPlan = await ref
          .read(playbackServiceProvider)
          .createPlan(
            widget.account,
            target,
            startPosition: automatic ? Duration.zero : null,
            maxStreamingBitrate: _maxStreamingBitrate,
          );
      await _safeReportStopped();
      _plan = nextPlan;
      if (_diagnosticsVisible) _diagnostics = null;
      _item = target;
      _queue = queue.select(index);
      _selectedAudioStreamIndex = nextPlan.audioStreamIndex;
      _selectedSubtitleStreamIndex = nextPlan.subtitleStreamIndex;
      _subtitlesDisabled = nextPlan.subtitleStreamIndex == null;
      _reportedStarted = false;
      _reportedStopped = false;
      _duration = nextPlan.duration ?? target.runTime ?? Duration.zero;
      _position = nextPlan.startPosition;
      _previewPosition = null;
      _buffer = Duration.zero;
      await _openMedia(nextPlan, play: true);
      _writeDiagnosticLog('queue_item_opened');
      if (_diagnosticsVisible) unawaited(_refreshDiagnostics());
      await _player.setVolume(preservedVolume);
      await _player.setRate(preservedRate);
      await _safeReportStarted();
      _startProgressTimer();
    } on PlaybackServiceException catch (error) {
      _writeDiagnosticLog(
        'queue_item_open_failed',
        fields: {'message': error.message},
      );
      if (mounted) setState(() => _error = '无法播放所选剧集：${error.message}');
      if (wasPlaying) await _player.play();
      _startProgressTimer();
    } on Object catch (error) {
      _writeDiagnosticLog(
        'queue_item_open_failed',
        fields: {'message': error.toString()},
      );
      if (mounted) setState(() => _error = '无法播放所选剧集：$error');
      if (wasPlaying) await _player.play();
      _startProgressTimer();
    } finally {
      if (mounted) {
        setState(() => _changingSource = false);
        _scheduleControlsHide();
      }
    }
  }

  Future<void> _finishCompletedPlayback() async {
    if (_closing || _changingSource || _nextEpisodeCountdown != null) return;
    _progressTimer?.cancel();
    await _safeReportStopped();
    unawaited(_safeMarkPlayed());
    if (!mounted || _closing) return;
    if (_queue?.hasNext ?? false) {
      _startNextEpisodeCountdown();
    } else {
      _showControls();
    }
  }

  PlaybackSessionSnapshot _snapshot() {
    return PlaybackSessionSnapshot(
      plan: _plan,
      position: _player.state.position,
      isPaused: !_player.state.playing,
      volume: _player.state.volume,
      audioStreamIndex: _selectedAudioStreamIndex,
      subtitleStreamIndex: _selectedSubtitleStreamIndex,
      subtitlesDisabled: _subtitlesDisabled,
      playbackRate: _player.state.rate,
      subtitleOffset: _subtitlePreferences.delay,
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    _progressTimer?.cancel();
    _controlsTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _diagnosticsTimer?.cancel();
    _subtitleSettingsTimer?.cancel();
    await _persistPlaybackPreferences();
    _writeDiagnosticLog('playback_closed');
    await _safeReportStopped();
    if (_fullScreen && Platform.isWindows) {
      try {
        await windowManager.setFullScreen(false);
      } on Object {
        // The page still needs to close if the native window is unavailable.
      }
      _fullScreen = false;
    }
    await _disposePlayer();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disposePlayer() async {
    if (_playerDisposed) return;
    _playerDisposed = true;
    await _player.dispose();
  }

  @override
  void dispose() {
    AppChrome.leaveImmersive();
    _progressTimer?.cancel();
    _controlsTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _diagnosticsTimer?.cancel();
    _subtitleSettingsTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_fullScreen && Platform.isWindows) {
      unawaited(windowManager.setFullScreen(false));
    }
    if (!_reportedStopped) unawaited(_safeReportStopped());
    if (!_playerDisposed) unawaited(_disposePlayer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shownPosition = _previewPosition ?? _position;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleEscape());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space): () {
              unawaited(_togglePlayPause());
            },
            const SingleActivator(LogicalKeyboardKey.keyK): () {
              unawaited(_togglePlayPause());
            },
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
              unawaited(_seekRelative(const Duration(seconds: -10)));
            },
            const SingleActivator(LogicalKeyboardKey.keyJ): () {
              unawaited(_seekRelative(const Duration(seconds: -10)));
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              unawaited(_seekRelative(const Duration(seconds: 10)));
            },
            const SingleActivator(LogicalKeyboardKey.keyL): () {
              unawaited(_seekRelative(const Duration(seconds: 10)));
            },
            const SingleActivator(LogicalKeyboardKey.arrowUp): () {
              unawaited(_adjustVolume(5));
            },
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              unawaited(_adjustVolume(-5));
            },
            const SingleActivator(LogicalKeyboardKey.keyM): () {
              unawaited(_toggleMute());
            },
            const SingleActivator(LogicalKeyboardKey.keyF): () {
              unawaited(_toggleFullScreen());
            },
            const SingleActivator(LogicalKeyboardKey.keyD, control: true):
                _toggleDiagnostics,
            const SingleActivator(LogicalKeyboardKey.keyP): () {
              final queue = _queue;
              if (queue != null && queue.hasPrevious) {
                unawaited(_playQueueIndex(queue.currentIndex - 1));
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyN): () {
              final queue = _queue;
              if (queue != null && queue.hasNext) {
                unawaited(_playQueueIndex(queue.currentIndex + 1));
              }
            },
            const SingleActivator(LogicalKeyboardKey.escape): () {
              unawaited(_handleEscape());
            },
          },
          child: Focus(
            autofocus: true,
            child: MouseRegion(
              cursor: _controlsVisible || _diagnosticsVisible
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.none,
              onEnter: (_) {
                if (!_diagnosticsVisible) _showControls();
              },
              onHover: (_) {
                if (!_diagnosticsVisible) _showControls();
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showControls,
                onDoubleTap: () => unawaited(_toggleFullScreen()),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(
                      controller: _controller,
                      controls: NoVideoControls,
                      subtitleViewConfiguration: SubtitleViewConfiguration(
                        style: TextStyle(
                          height: 1.35,
                          fontSize: _subtitlePreferences.fontSize,
                          color: _subtitleForeground(
                            _subtitlePreferences.appearance,
                          ),
                          backgroundColor: _subtitleBackground(
                            _subtitlePreferences.appearance,
                          ),
                          fontWeight: FontWeight.w600,
                          shadows: _subtitleShadows(
                            _subtitlePreferences.appearance,
                          ),
                        ),
                        padding: EdgeInsets.fromLTRB(
                          32,
                          24,
                          32,
                          _subtitlePreferences.bottomPadding,
                        ),
                      ),
                    ),
                    PlaybackControls(
                      title: _item.name,
                      method: _plan.method,
                      quality: _maxStreamingBitrate,
                      visible:
                          (_controlsVisible || !_playing) &&
                          !_diagnosticsVisible,
                      playing: _playing,
                      buffering: _buffering,
                      changingSource: _changingSource,
                      sourceChangeLabel: _sourceChangeLabel,
                      position: shownPosition,
                      duration: _effectiveDuration,
                      buffer: _buffer,
                      volume: _volume,
                      rate: _rate,
                      fullScreen: _fullScreen,
                      audioLabel: _currentAudioLabel,
                      subtitleLabel: _currentSubtitleLabel,
                      chapters: _plan.chapters,
                      queueAvailable: (_queue?.items.length ?? 0) > 1,
                      canPrevious: _queue?.hasPrevious ?? false,
                      canNext: _queue?.hasNext ?? false,
                      onBack: () => unawaited(_close()),
                      onPlayPause: () => unawaited(_togglePlayPause()),
                      onSeekPreview: _previewSeek,
                      onSeek: (value) => unawaited(_seek(value)),
                      onSeekBack: () => unawaited(
                        _seekRelative(const Duration(seconds: -10)),
                      ),
                      onSeekForward: () =>
                          unawaited(_seekRelative(const Duration(seconds: 10))),
                      onVolumeChanged: (value) => unawaited(_setVolume(value)),
                      onMute: () => unawaited(_toggleMute()),
                      onRateChanged: (value) => unawaited(_setRate(value)),
                      onAudio: () => unawaited(_showAudioTracks()),
                      onSubtitle: () => unawaited(_showSubtitleTracks()),
                      onChapters: () => unawaited(_showChapters()),
                      onPrevious: () {
                        final queue = _queue;
                        if (queue != null && queue.hasPrevious) {
                          unawaited(_playQueueIndex(queue.currentIndex - 1));
                        }
                      },
                      onNext: () {
                        final queue = _queue;
                        if (queue != null && queue.hasNext) {
                          unawaited(_playQueueIndex(queue.currentIndex + 1));
                        }
                      },
                      onEpisodes: () => unawaited(_showEpisodes()),
                      onDiagnostics: _toggleDiagnostics,
                      onQuality: () => unawaited(_showQualityOptions()),
                      onFullScreen: () => unawaited(_toggleFullScreen()),
                    ),
                    if (_diagnosticsVisible)
                      Positioned.fill(
                        child: SafeArea(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 720;
                              final maxHeight = (constraints.maxHeight - 24)
                                  .clamp(220.0, 680.0)
                                  .toDouble();
                              return Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    compact ? 12 : 24,
                                    12,
                                    compact ? 12 : 24,
                                    12,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: compact ? 520 : 470,
                                      maxHeight: maxHeight,
                                    ),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {},
                                      onDoubleTap: () {},
                                      child: PlaybackDiagnosticsPanel(
                                        snapshot: _diagnostics,
                                        loading: _diagnosticsLoading,
                                        onCopy: () =>
                                            unawaited(_copyDiagnostics()),
                                        onRefresh: () =>
                                            unawaited(_refreshDiagnostics()),
                                        onClose: _closeDiagnostics,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    if (_nextEpisodeCountdown != null && _queue?.next != null)
                      NextEpisodeCountdown(
                        item: _queue!.next!,
                        secondsRemaining: _nextEpisodeCountdown!,
                        totalSeconds: _autoNextSeconds,
                        onPlayNow: () {
                          final queue = _queue;
                          if (queue == null || !queue.hasNext) return;
                          _cancelNextEpisodeCountdown(showControls: false);
                          unawaited(
                            _playQueueIndex(
                              queue.currentIndex + 1,
                              automatic: true,
                            ),
                          );
                        },
                        onCancel: _cancelNextEpisodeCountdown,
                      ),
                    if (_error != null)
                      Center(
                        child: _PlaybackError(
                          message: _error!,
                          onBack: () => unawaited(_close()),
                          onDismiss: () {
                            setState(() => _error = null);
                            _scheduleControlsHide();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.queue});

  final PlaybackQueue queue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassSurface(
            radius: 24,
            blur: 28,
            tint: AppColors.glassStrong,
            elevated: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 14, 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.video_collection_rounded,
                          color: AppColors.spotlight,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '选集',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${queue.items.length} 集 · 当前第 ${queue.currentIndex + 1} 集',
                                style: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                      itemCount: queue.items.length,
                      itemBuilder: (context, index) {
                        final item = queue.items[index];
                        final selected = index == queue.currentIndex;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: selected
                                ? AppColors.glassSelected
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              key: ValueKey('episode-$index'),
                              borderRadius: BorderRadius.circular(14),
                              onTap: selected
                                  ? null
                                  : () => Navigator.of(context).pop(index),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 30,
                                      child: selected
                                          ? const Icon(
                                              Icons.play_arrow_rounded,
                                              color: AppColors.spotlight,
                                            )
                                          : Text(
                                              '${index + 1}',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: AppColors.textTertiary,
                                                fontFamily: 'Cascadia Mono',
                                                fontSize: 11,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _queueItemTitle(item),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _queueItemStatus(item, selected),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.textTertiary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _queueItemTitle(MediaItem item) {
  final season = item.parentIndexNumber;
  final episode = item.indexNumber;
  final prefix = season == 0
      ? '特别篇${episode == null ? '' : ' ${episode.toString().padLeft(2, '0')}'}'
      : season == null && episode == null
      ? ''
      : 'S${(season ?? 0).toString().padLeft(2, '0')}'
            'E${(episode ?? 0).toString().padLeft(2, '0')}';
  return prefix.isEmpty ? item.name : '$prefix · ${item.name}';
}

String _queueItemStatus(MediaItem item, bool selected) {
  if (selected) return '正在播放';
  if (item.resumePosition > Duration.zero) {
    return '上次看到 ${_queueTime(item.resumePosition)}';
  }
  if (item.played) return '已播放';
  return item.runTime == null ? '未播放' : '时长 ${_queueTime(item.runTime!)}';
}

String _queueTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

Color _subtitleForeground(SubtitleAppearance appearance) {
  return switch (appearance) {
    SubtitleAppearance.cinema => Colors.white,
    SubtitleAppearance.warm => const Color(0xFFFFE79A),
    SubtitleAppearance.highContrast => Colors.white,
  };
}

Color _subtitleBackground(SubtitleAppearance appearance) {
  return appearance == SubtitleAppearance.highContrast
      ? const Color(0xC4000000)
      : Colors.transparent;
}

List<Shadow> _subtitleShadows(SubtitleAppearance appearance) {
  if (appearance == SubtitleAppearance.highContrast) return const [];
  return const [
    Shadow(color: Colors.black, blurRadius: 5, offset: Offset(0, 2)),
    Shadow(color: Colors.black, blurRadius: 10),
  ];
}

String _subtitleDelayLabel(int milliseconds) {
  if (milliseconds == 0) return '0.0 秒';
  final seconds = milliseconds / 1000;
  return '${seconds > 0 ? '+' : ''}${seconds.toStringAsFixed(1)} 秒';
}

class _SubtitleSheet extends StatefulWidget {
  const _SubtitleSheet({
    required this.preferences,
    required this.options,
    required this.onPreferencesChanged,
  });

  final SubtitlePreferences preferences;
  final List<_TrackMenuOption> options;
  final ValueChanged<SubtitlePreferences> onPreferencesChanged;

  @override
  State<_SubtitleSheet> createState() => _SubtitleSheetState();
}

class _SubtitleSheetState extends State<_SubtitleSheet> {
  late SubtitlePreferences _preferences = widget.preferences;

  void _update(SubtitlePreferences preferences) {
    setState(() => _preferences = preferences);
    widget.onPreferencesChanged(preferences);
  }

  void _adjustDelay(int delta) {
    _update(
      _preferences.copyWith(
        delayMilliseconds: (_preferences.delayMilliseconds + delta).clamp(
          -10000,
          10000,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassSurface(
            radius: 24,
            blur: 28,
            tint: AppColors.glassStrong,
            elevated: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: height * 0.88,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 14, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.subtitles_rounded,
                          color: AppColors.spotlight,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '字幕与显示',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                '调整会即时应用，并自动用于下次播放',
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                      children: [
                        Container(
                          key: const ValueKey('subtitle-preview'),
                          height: 92,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1D2230), Color(0xFF090B10)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '在光影之间，故事正在发生。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              height: 1.35,
                              fontSize: _preferences.fontSize.clamp(18, 32),
                              color: _subtitleForeground(
                                _preferences.appearance,
                              ),
                              backgroundColor: _subtitleBackground(
                                _preferences.appearance,
                              ),
                              fontWeight: FontWeight.w600,
                              shadows: _subtitleShadows(
                                _preferences.appearance,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const _SheetLabel('字幕风格'),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final appearance in SubtitleAppearance.values)
                              ChoiceChip(
                                key: ValueKey(
                                  'subtitle-style-${appearance.name}',
                                ),
                                label: Text(appearance.label),
                                selected: _preferences.appearance == appearance,
                                onSelected: (_) => _update(
                                  _preferences.copyWith(appearance: appearance),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _PreferenceSlider(
                          label: '字号',
                          valueLabel: '${_preferences.fontSize.round()} px',
                          value: _preferences.fontSize,
                          min: 18,
                          max: 42,
                          divisions: 12,
                          onChanged: (value) =>
                              _update(_preferences.copyWith(fontSize: value)),
                        ),
                        _PreferenceSlider(
                          label: '垂直位置',
                          valueLabel:
                              '距底部 ${_preferences.bottomPadding.round()} px',
                          value: _preferences.bottomPadding,
                          min: 48,
                          max: 180,
                          divisions: 11,
                          onChanged: (value) => _update(
                            _preferences.copyWith(bottomPadding: value),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '字幕延迟',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    '正值延后，负值提前',
                                    style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton.outlined(
                              key: const ValueKey('subtitle-delay-minus'),
                              tooltip: '字幕提前 0.1 秒',
                              onPressed: () => _adjustDelay(-100),
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            SizedBox(
                              width: 82,
                              child: TextButton(
                                key: const ValueKey('subtitle-delay-reset'),
                                onPressed: () => _update(
                                  _preferences.copyWith(delayMilliseconds: 0),
                                ),
                                child: Text(
                                  _subtitleDelayLabel(
                                    _preferences.delayMilliseconds,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Cascadia Mono',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                            IconButton.outlined(
                              key: const ValueKey('subtitle-delay-plus'),
                              tooltip: '字幕延后 0.1 秒',
                              onPressed: () => _adjustDelay(100),
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Divider(height: 1),
                        ),
                        const _SheetLabel('字幕轨道'),
                        const SizedBox(height: 8),
                        for (final option in widget.options)
                          Material(
                            color: option.selected
                                ? AppColors.glassSelected
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                Navigator.of(context).pop();
                                unawaited(option.onSelected());
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: option.selected
                                          ? const Icon(
                                              Icons.check_rounded,
                                              color: AppColors.spotlight,
                                              size: 20,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            option.detail,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.textTertiary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textTertiary,
        fontFamily: 'Cascadia Mono',
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _PreferenceSlider extends StatelessWidget {
  const _PreferenceSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              valueLabel,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontFamily: 'Cascadia Mono',
                fontSize: 10,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ChapterSheet extends StatelessWidget {
  const _ChapterSheet({required this.chapters, required this.position});

  final List<MediaChapter> chapters;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    var currentIndex = 0;
    for (var index = 0; index < chapters.length; index++) {
      if (chapters[index].startPosition <= position) currentIndex = index;
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassSurface(
            radius: 24,
            blur: 28,
            tint: AppColors.glassStrong,
            elevated: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: MediaQuery.sizeOf(context).height * 0.78,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 14, 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bookmarks_rounded,
                          color: AppColors.spotlight,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '章节导航',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '共 ${chapters.length} 个章节',
                                style: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                      itemCount: chapters.length,
                      itemBuilder: (context, index) {
                        final chapter = chapters[index];
                        final selected = index == currentIndex;
                        return Material(
                          color: selected
                              ? AppColors.glassSelected
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            key: ValueKey('chapter-option-$index'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.of(
                              context,
                            ).pop(chapter.startPosition),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 48,
                                    child: Text(
                                      'CH ${(index + 1).toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                        color: selected
                                            ? AppColors.spotlight
                                            : AppColors.textTertiary,
                                        fontFamily: 'Cascadia Mono',
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      chapter.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _queueTime(chapter.startPosition),
                                    style: const TextStyle(
                                      color: AppColors.textTertiary,
                                      fontFamily: 'Cascadia Mono',
                                      fontSize: 10,
                                    ),
                                  ),
                                  if (selected) ...[
                                    const SizedBox(width: 10),
                                    const Icon(
                                      Icons.graphic_eq_rounded,
                                      color: AppColors.spotlight,
                                      size: 18,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackSheet extends StatelessWidget {
  const _TrackSheet({
    required this.title,
    required this.icon,
    required this.options,
    required this.emptyMessage,
  });

  final String title;
  final IconData icon;
  final List<_TrackMenuOption> options;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassSurface(
            radius: 24,
            blur: 28,
            tint: AppColors.glassStrong,
            elevated: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 14, 12),
                    child: Row(
                      children: [
                        Icon(icon, color: AppColors.spotlight),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: options.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              emptyMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options[index];
                              return Material(
                                color: option.selected
                                    ? AppColors.glassSelected
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    unawaited(option.onSelected());
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 13,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 28,
                                          child: option.selected
                                              ? const Icon(
                                                  Icons.check_rounded,
                                                  color: AppColors.spotlight,
                                                  size: 20,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                option.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                option.detail,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppColors.textTertiary,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackMenuOption {
  const _TrackMenuOption({
    required this.title,
    required this.detail,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final String detail;
  final bool selected;
  final Future<void> Function() onSelected;
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({
    required this.message,
    required this.onBack,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onBack;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 20,
      blur: 26,
      tint: AppColors.glassStrong,
      elevated: true,
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton(onPressed: onDismiss, child: const Text('关闭提示')),
                FilledButton(onPressed: onBack, child: const Text('返回详情')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
