import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/external_id_info.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/remote_search_result.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class IdentifyDialog extends ConsumerStatefulWidget {
  const IdentifyDialog({
    super.key,
    required this.account,
    required this.item,
  });

  final AuthenticatedServer account;
  final MediaItem item;

  @override
  ConsumerState<IdentifyDialog> createState() => _IdentifyDialogState();
}

class _IdentifyDialogState extends ConsumerState<IdentifyDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _yearController;
  final Map<String, TextEditingController> _providerControllers = {};

  List<ExternalIdInfo> _serverProviders = const [];
  bool _loadingProviders = false;
  bool _searching = false;
  bool _applying = false;
  bool _replaceAllImages = true;
  bool _showAdvancedIds = false;
  String? _errorMessage;
  List<RemoteSearchResult> _results = const [];
  RemoteSearchResult? _selected;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _yearController = TextEditingController(
      text: widget.item.productionYear != null
          ? '${widget.item.productionYear}'
          : '',
    );

    for (final entry in widget.item.providerIds.entries) {
      if (entry.value.isNotEmpty) {
        _providerControllers[entry.key] = TextEditingController(text: entry.value);
        _showAdvancedIds = true;
      }
    }
    _providerControllers.putIfAbsent('Tmdb', () => TextEditingController());
    _providerControllers.putIfAbsent('Imdb', () => TextEditingController());

    Future<void>.microtask(() {
      _loadServerProviders();
      _executeSearch();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
    for (final c in _providerControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadServerProviders() async {
    setState(() => _loadingProviders = true);
    try {
      final service = ref.read(mediaLibraryProvider);
      final list = await service.getExternalIdInfos(
        widget.account,
        itemId: widget.item.id,
      );
      if (!mounted) return;
      if (list.isNotEmpty) {
        setState(() {
          _serverProviders = list;
          for (final p in list) {
            _providerControllers.putIfAbsent(
              p.key,
              () => TextEditingController(
                text: widget.item.providerIds[p.key] ?? '',
              ),
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingProviders = false);
    }
  }

  Future<void> _executeSearch() async {
    final queryName = _nameController.text.trim();
    if (queryName.isEmpty) return;

    setState(() {
      _searching = true;
      _errorMessage = null;
    });

    final year = int.tryParse(_yearController.text.trim());
    final providerIds = <String, String>{};
    for (final entry in _providerControllers.entries) {
      final val = entry.value.text.trim();
      if (val.isNotEmpty) {
        providerIds[entry.key] = val;
      }
    }

    try {
      final service = ref.read(mediaLibraryProvider);
      final results = await service.searchRemoteMetadata(
        widget.account,
        itemId: widget.item.id,
        kind: widget.item.kind,
        name: queryName,
        year: year,
        providerIds: providerIds.isNotEmpty ? providerIds : null,
      );

      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        if (results.isNotEmpty) {
          _selected = results.first;
        } else {
          _selected = null;
        }
      });
    } on MediaLibraryException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '查询失败：$e';
        _searching = false;
      });
    }
  }

  Future<void> _applySelected() async {
    final selected = _selected;
    if (selected == null) return;

    setState(() {
      _applying = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(mediaLibraryProvider);
      await service.applyRemoteMetadata(
        widget.account,
        itemId: widget.item.id,
        result: selected,
        replaceAllImages: _replaceAllImages,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on MediaLibraryException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _applying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '应用失败：$e';
        _applying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Container(
          decoration: AppGlass.visionOSDecoration(
            radius: 24,
            elevated: true,
            borderOpacity: 0.28,
            glowColor: const Color(0x334A90E2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(context),

              // Search Inputs Form
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: _buildSearchForm(),
              ),

              const Divider(height: 1, color: Colors.white12),

              // Candidates List or Status
              Expanded(child: _buildCandidatesArea()),

              const Divider(height: 1, color: Colors.white12),

              // Footer Actions
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.spotlight.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_fix_high_rounded,
              color: AppColors.spotlight,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '修正匹配与刮削识别',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '当前条目: 《${widget.item.name}》',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  labelText: '影视标题 / 名称',
                  hintText: '输入准确的片名或剧名',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _nameController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () => setState(() => _nameController.clear()),
                        )
                      : null,
                ),
                onSubmitted: (_) => _executeSearch(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _yearController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '年份',
                  hintText: '如 2024',
                  isDense: true,
                ),
                onSubmitted: (_) => _executeSearch(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _searching || _applying ? null : _executeSearch,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _searching
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text('检索'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _showAdvancedIds = !_showAdvancedIds),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showAdvancedIds
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.spotlight,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showAdvancedIds ? '收起外部 ID 检索' : '高级：按外部 ID / 插件提供商精确检索',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.spotlight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_loadingProviders) ...[
                      const SizedBox(width: 6),
                      const SizedBox.square(
                        dimension: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.spotlight,
                        ),
                      ),
                    ] else if (_serverProviders.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.spotlight.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '已同步 ${_serverProviders.length} 个刮削插件源',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.spotlight,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_showAdvancedIds) ...[
          const SizedBox(height: 10),
          _buildAdvancedIdInputs(),
        ],
      ],
    );
  }

  Widget _buildAdvancedIdInputs() {
    final providersToRender = _serverProviders.isNotEmpty
        ? _serverProviders
        : const [
            ExternalIdInfo(name: 'TMDb', key: 'Tmdb'),
            ExternalIdInfo(name: 'IMDb', key: 'Imdb'),
          ];

    final rows = <Widget>[];
    for (var i = 0; i < providersToRender.length; i += 2) {
      final p1 = providersToRender[i];
      final p2 = (i + 1 < providersToRender.length) ? providersToRender[i + 1] : null;

      rows.add(
        Row(
          children: [
            Expanded(child: _buildProviderField(p1)),
            if (p2 != null) ...[
              const SizedBox(width: 12),
              Expanded(child: _buildProviderField(p2)),
            ] else
              const Spacer(),
          ],
        ),
      );
      if (i + 2 < providersToRender.length) {
        rows.add(const SizedBox(height: 8));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows,
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(
              Icons.sync_rounded,
              size: 12,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _serverProviders.isNotEmpty
                    ? '已动态同步服务端启用的刮削器（含豆瓣、Bangumi等插件），支持精准定向匹配'
                    : '正在同步服务端刮削器配置...',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProviderField(ExternalIdInfo info) {
    final controller = _providerControllers.putIfAbsent(
      info.key,
      () => TextEditingController(text: widget.item.providerIds[info.key] ?? ''),
    );

    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13, color: Colors.white),
      decoration: InputDecoration(
        labelText: '${info.name.isNotEmpty ? info.name : info.key} ID',
        hintText: '输入 ${info.name} 编号',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onSubmitted: (_) => _executeSearch(),
    );
  }

  Widget _buildCandidatesArea() {
    if (_searching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              '正在向远程刮削器检索匹配候选项...',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _executeSearch,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试检索'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, color: AppColors.textTertiary, size: 44),
              const SizedBox(height: 14),
              const Text(
                '未找到匹配条目',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '请尝试去除剧名后缀、修改关键词，或展开上方高级输入项直接填入 TMDb/IMDb ID 进行精准匹配。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    return PeekSmoothScroll(
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _results.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final candidate = _results[index];
          final isSelected = _selected == candidate;
          return _buildCandidateTile(candidate, isSelected);
        },
      ),
    );
  }

  Widget _buildCandidateTile(RemoteSearchResult candidate, bool isSelected) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selected = candidate),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.spotlight.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.spotlight
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 54,
                height: 80,
                color: Colors.white10,
                child: candidate.imageUrl != null && candidate.imageUrl!.isNotEmpty
                    ? Image.network(
                        candidate.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(Icons.movie_outlined, color: Colors.white30, size: 24),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.movie_outlined, color: Colors.white30, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Content details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          candidate.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (candidate.productionYear != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${candidate.productionYear})',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (candidate.originalTitle != null &&
                      candidate.originalTitle!.isNotEmpty &&
                      candidate.originalTitle != candidate.name) ...[
                    const SizedBox(height: 2),
                    Text(
                      candidate.originalTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),

                  // Provider badges
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (candidate.searchProviderName != null)
                        _buildBadge(candidate.searchProviderName!, Icons.source_rounded),
                      for (final entry in candidate.providerIds.entries)
                        _buildBadge('${entry.key}: ${entry.value}', Icons.tag_rounded),
                    ],
                  ),

                  if (candidate.overview != null && candidate.overview!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      candidate.overview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected ? AppColors.spotlight : Colors.white38,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _replaceAllImages = !_replaceAllImages),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _replaceAllImages,
                  activeColor: AppColors.spotlight,
                  checkColor: Colors.black,
                  onChanged: (val) =>
                      setState(() => _replaceAllImages = val ?? true),
                ),
                const Text(
                  '覆盖替换全部海报/背景图',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _applying ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _selected == null || _applying ? null : _applySelected,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.spotlight,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: _applying
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(
              _applying ? '正在应用匹配…' : '应用此匹配',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
