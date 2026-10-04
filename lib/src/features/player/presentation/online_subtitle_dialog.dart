import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';

class OnlineSubtitleDialog extends StatefulWidget {
  const OnlineSubtitleDialog({
    super.key,
    required this.account,
    required this.itemId,
    required this.service,
  });

  final AuthenticatedServer account;
  final String itemId;
  final MediaLibraryService service;

  @override
  State<OnlineSubtitleDialog> createState() => _OnlineSubtitleDialogState();
}

class _OnlineSubtitleDialogState extends State<OnlineSubtitleDialog> {
  String _selectedLang = 'chi';
  bool _loading = true;
  String? _error;
  List<RemoteSubtitleInfo> _results = const [];
  String? _downloadingId;

  static const _languages = [
    ('chi', '中文 / 汉化'),
    ('eng', '英文 (English)'),
    ('zho', '繁体中文'),
  ];

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
    });
    try {
      final list = await widget.service.searchRemoteSubtitles(
        widget.account,
        itemId: widget.itemId,
        language: _selectedLang,
      );
      if (mounted) {
        setState(() {
          _results = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '检索字幕失败：$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _download(RemoteSubtitleInfo sub) async {
    setState(() => _downloadingId = sub.id);
    final ok = await widget.service.downloadRemoteSubtitle(
      widget.account,
      itemId: widget.itemId,
      subtitleId: sub.id,
    );
    if (!mounted) return;
    setState(() => _downloadingId = null);
    if (ok) {
      Navigator.of(context).pop(sub);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('字幕下载或挂载失败，请重试。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.subtitles_rounded, color: AppColors.spotlight),
          const SizedBox(width: 10),
          const Text('在线字幕检索与下载'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final lang in _languages)
                  ChoiceChip(
                    label: Text(lang.$2),
                    selected: _selectedLang == lang.$1,
                    onSelected: (val) {
                      if (val && _selectedLang != lang.$1) {
                        setState(() => _selectedLang = lang.$1);
                        _search();
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _results.isEmpty
                          ? const Center(
                              child: Text(
                                '未找到匹配的在线字幕',
                                style: TextStyle(color: AppColors.textTertiary),
                              ),
                            )
                          : PeekSmoothScroll(
                              child: ListView.separated(
                                itemCount: _results.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = _results[index];
                                  final isDownloading = _downloadingId == item.id;
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    title: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${item.providerName} · ${item.format.toUpperCase()}${item.comment != null ? ' · ${item.comment}' : ''}',
                                      style: const TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: isDownloading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : FilledButton.tonal(
                                            onPressed: () => _download(item),
                                            child: const Text('下载并挂载'),
                                          ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
