import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/danmaku/data/dandanplay_service.dart';
import 'package:embyplayer/src/core/domain/playback_settings.dart';
import 'package:flutter/material.dart';

class DanmakuSettingsSheet extends StatefulWidget {
  const DanmakuSettingsSheet({
    super.key,
    required this.preferences,
    required this.onPreferencesChanged,
    this.initialSearchKeyword,
    this.onEpisodeSelected,
    this.onSendDanmaku,
  });

  final DanmakuPreferences preferences;
  final ValueChanged<DanmakuPreferences> onPreferencesChanged;
  final String? initialSearchKeyword;
  final ValueChanged<DandanEpisodeMatch>? onEpisodeSelected;
  final void Function(String text, {int color, int type})? onSendDanmaku;

  @override
  State<DanmakuSettingsSheet> createState() => _DanmakuSettingsSheetState();
}

class _DanmakuSettingsSheetState extends State<DanmakuSettingsSheet> {
  late DanmakuPreferences _preferences;
  final TextEditingController _blockController = TextEditingController();
  late final TextEditingController _searchController;
  final TextEditingController _danmakuInputController = TextEditingController();
  final DandanPlayService _dandanService = DandanPlayService();

  List<DandanEpisodeMatch> _searchResults = const [];
  bool _searching = false;
  String? _searchError;
  bool _showSearchSection = false;

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences;
    _searchController = TextEditingController(
      text: widget.initialSearchKeyword ?? '',
    );
  }

  @override
  void dispose() {
    _blockController.dispose();
    _searchController.dispose();
    _danmakuInputController.dispose();
    super.dispose();
  }

  void _update(DanmakuPreferences next) {
    setState(() => _preferences = next);
    widget.onPreferencesChanged(next);
  }

  Future<void> _doSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await _dandanService.searchEpisodes(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
          if (results.isEmpty) {
            _searchError = '未找到匹配的弹幕库条目';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _searchError = '搜索失败：$e';
        });
      }
    }
  }

  void _addBlockedKeyword() {
    final text = _blockController.text.trim();
    if (text.isEmpty) return;
    if (_preferences.blockedKeywords.contains(text)) {
      _blockController.clear();
      return;
    }
    final nextList = [..._preferences.blockedKeywords, text];
    _blockController.clear();
    _update(_preferences.copyWith(blockedKeywords: nextList));
  }

  void _removeBlockedKeyword(String keyword) {
    final nextList =
        _preferences.blockedKeywords.where((k) => k != keyword).toList();
    _update(_preferences.copyWith(blockedKeywords: nextList));
  }

  @override
  Widget build(BuildContext context) {
    final offsetSec = _preferences.offsetMilliseconds / 1000.0;

    return Container(
      width: 460,
      constraints: const BoxConstraints(maxHeight: 640),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: AppGlass.decoration(radius: 24, elevated: true),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.comment_rounded, color: AppColors.spotlight),
              const SizedBox(width: 10),
              const Text(
                '弹幕设置 (Danmaku 2.0)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Flexible(
            child: PeekSmoothScroll(
              child: SingleChildScrollView(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Master Switch
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '启用弹幕显示',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _preferences.enabled ? '弹幕已开启' : '弹幕已隐藏',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    value: _preferences.enabled,
                    activeThumbColor: AppColors.spotlight,
                    onChanged: (val) {
                      _update(_preferences.copyWith(enabled: val));
                    },
                  ),
                  const Divider(color: Colors.white12, height: 16),

                  // Timeline Calibration
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '时间轴校准',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${offsetSec >= 0 ? '+' : ''}${offsetSec.toStringAsFixed(1)}s',
                        style: const TextStyle(
                          color: AppColors.spotlight,
                          fontFamily: 'Cascadia Mono',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Slider(
                    value: offsetSec.clamp(-10.0, 10.0),
                    min: -10.0,
                    max: 10.0,
                    divisions: 40,
                    label: '${offsetSec.toStringAsFixed(1)}s',
                    activeColor: AppColors.spotlight,
                    onChanged: (val) {
                      final ms = (val * 1000).round();
                      _update(_preferences.copyWith(offsetMilliseconds: ms));
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _OffsetButton(
                        label: '-1.0s',
                        onTap: () {
                          _update(
                            _preferences.copyWith(
                              offsetMilliseconds:
                                  _preferences.offsetMilliseconds - 1000,
                            ),
                          );
                        },
                      ),
                      _OffsetButton(
                        label: '-0.5s',
                        onTap: () {
                          _update(
                            _preferences.copyWith(
                              offsetMilliseconds:
                                  _preferences.offsetMilliseconds - 500,
                            ),
                          );
                        },
                      ),
                      _OffsetButton(
                        label: '重置',
                        highlight: _preferences.offsetMilliseconds != 0,
                        onTap: () {
                          _update(_preferences.copyWith(offsetMilliseconds: 0));
                        },
                      ),
                      _OffsetButton(
                        label: '+0.5s',
                        onTap: () {
                          _update(
                            _preferences.copyWith(
                              offsetMilliseconds:
                                  _preferences.offsetMilliseconds + 500,
                            ),
                          );
                        },
                      ),
                      _OffsetButton(
                        label: '+1.0s',
                        onTap: () {
                          _update(
                            _preferences.copyWith(
                              offsetMilliseconds:
                                  _preferences.offsetMilliseconds + 1000,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),

                  // Display Area
                  const Text(
                    '屏幕显示区域',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _AreaChip(
                        label: '1/4 屏幕',
                        selected: (_preferences.displayArea - 0.25).abs() < 0.05,
                        onSelected: () =>
                            _update(_preferences.copyWith(displayArea: 0.25)),
                      ),
                      _AreaChip(
                        label: '半屏 (默认)',
                        selected: (_preferences.displayArea - 0.50).abs() < 0.05,
                        onSelected: () =>
                            _update(_preferences.copyWith(displayArea: 0.50)),
                      ),
                      _AreaChip(
                        label: '3/4 屏幕',
                        selected: (_preferences.displayArea - 0.75).abs() < 0.05,
                        onSelected: () =>
                            _update(_preferences.copyWith(displayArea: 0.75)),
                      ),
                      _AreaChip(
                        label: '全屏',
                        selected: (_preferences.displayArea - 1.0).abs() < 0.05,
                        onSelected: () =>
                            _update(_preferences.copyWith(displayArea: 1.0)),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),

                  // Subtitle Area Clearance & Types
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '避让底部字幕区',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '底部保留 22% 高度无弹幕重叠，保证字幕清晰',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _preferences.preventSubtitleOverlap,
                        activeThumbColor: AppColors.spotlight,
                        onChanged: (val) => _update(
                          _preferences.copyWith(preventSubtitleOverlap: val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('滚动弹幕'),
                        selected: _preferences.allowScroll,
                        selectedColor: AppColors.spotlight.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: _preferences.allowScroll
                              ? AppColors.spotlight
                              : AppColors.textSecondary,
                        ),
                        onSelected: (val) => _update(
                          _preferences.copyWith(allowScroll: val),
                        ),
                      ),
                      FilterChip(
                        label: const Text('顶部弹幕'),
                        selected: _preferences.allowTop,
                        selectedColor: AppColors.spotlight.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: _preferences.allowTop
                              ? AppColors.spotlight
                              : AppColors.textSecondary,
                        ),
                        onSelected: (val) => _update(
                          _preferences.copyWith(allowTop: val),
                        ),
                      ),
                      FilterChip(
                        label: const Text('底部弹幕'),
                        selected: _preferences.allowBottom,
                        selectedColor: AppColors.spotlight.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: _preferences.allowBottom
                              ? AppColors.spotlight
                              : AppColors.textSecondary,
                        ),
                        onSelected: (val) => _update(
                          _preferences.copyWith(allowBottom: val),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),

                  // Opacity & Font Size
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '不透明度 (${(_preferences.opacity * 100).toInt()}%)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            Slider(
                              value: _preferences.opacity.clamp(0.2, 1.0),
                              min: 0.2,
                              max: 1.0,
                              divisions: 8,
                              activeColor: AppColors.spotlight,
                              onChanged: (val) {
                                _update(_preferences.copyWith(opacity: val));
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '字体大小 (${_preferences.fontSize.toInt()}px)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            Slider(
                              value: _preferences.fontSize.clamp(12.0, 28.0),
                              min: 12.0,
                              max: 28.0,
                              divisions: 8,
                              activeColor: AppColors.spotlight,
                              onChanged: (val) {
                                _update(_preferences.copyWith(fontSize: val));
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),

                  // Blocked Keywords
                  const Text(
                    '关键词屏蔽过滤',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _blockController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '输入屏蔽词，回车或点击添加',
                            hintStyle: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _addBlockedKeyword(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.spotlight,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _addBlockedKeyword,
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                  if (_preferences.blockedKeywords.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final kw in _preferences.blockedKeywords)
                          Chip(
                            label: Text(
                              kw,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                            deleteIcon: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.white70,
                            ),
                            onDeleted: () => _removeBlockedKeyword(kw),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const Divider(color: Colors.white12, height: 24),

                  if (widget.onSendDanmaku != null) ...[
                    const Text(
                      '实时发射弹幕',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _danmakuInputController,
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: '发一条友善的弹幕...',
                              hintStyle: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Colors.white12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.spotlight),
                              ),
                            ),
                            onSubmitted: (val) {
                              if (val.trim().isNotEmpty) {
                                widget.onSendDanmaku!(val);
                                _danmakuInputController.clear();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.spotlight,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () {
                            final val = _danmakuInputController.text;
                            if (val.trim().isNotEmpty) {
                              widget.onSendDanmaku!(val);
                              _danmakuInputController.clear();
                            }
                          },
                          child: const Text('发射', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 24),
                  ],

                  // Manual Rebind / Search Section
                  InkWell(
                    onTap: () {
                      setState(() {
                        _showSearchSection = !_showSearchSection;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            _showSearchSection
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_right_rounded,
                            color: AppColors.spotlight,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '手动搜索与换源 (DandanPlay)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showSearchSection) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '输入动漫或剧集名称搜索',
                              hintStyle: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.06),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => _doSearch(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surfaceHigh,
                            foregroundColor: AppColors.spotlight,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _searching ? null : _doSearch,
                          child: _searching
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.spotlight,
                                  ),
                                )
                              : const Text('搜索'),
                        ),
                      ],
                    ),
                    if (_searchError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _searchError!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: PeekSmoothScroll(
                          child: ListView.separated(
                            shrinkWrap: true,
                          padding: const EdgeInsets.all(4),
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, index) =>
                              const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, i) {
                            final match = _searchResults[i];
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text(
                                match.animeTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                match.episodeTitle,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.spotlight,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                onPressed: () {
                                  widget.onEpisodeSelected?.call(match);
                                  Navigator.of(context).pop();
                                },
                                child: const Text(
                                  '绑定',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    ],
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    ),
  );
  }
}

class _OffsetButton extends StatelessWidget {
  const _OffsetButton({
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlight
          ? AppColors.spotlight.withValues(alpha: 0.15)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: highlight ? AppColors.spotlight : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaChip extends StatelessWidget {
  const _AreaChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.black : Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: selected,
      selectedColor: AppColors.spotlight,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (_) => onSelected(),
    );
  }
}
