import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/scrobble/data/bangumi_scrobble_service.dart';
import 'package:embyplayer/src/features/scrobble/data/bangumi_store.dart';
import 'package:embyplayer/src/features/scrobble/domain/bangumi_profile.dart';
import 'package:embyplayer/src/features/scrobble/domain/bangumi_subject.dart';
import 'package:embyplayer/src/features/scrobble/presentation/bangumi_binding_sheet.dart';
import 'package:flutter/material.dart';

class BangumiSummaryCard extends StatefulWidget {
  const BangumiSummaryCard({
    super.key,
    required this.mediaName,
    this.bangumiService,
    this.bangumiStore,
  });

  final String mediaName;
  final BangumiScrobbleService? bangumiService;
  final BangumiStore? bangumiStore;

  @override
  State<BangumiSummaryCard> createState() => _BangumiSummaryCardState();
}

class _BangumiSummaryCardState extends State<BangumiSummaryCard> {
  late final BangumiScrobbleService _service =
      widget.bangumiService ?? BangumiScrobbleService();
  late final BangumiStore _store = widget.bangumiStore ?? BangumiStore();

  BangumiProfile? _profile;
  BangumiSubject? _subject;
  bool _loading = true;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final profile = await _store.readProfile();
    if (profile == null) {
      if (mounted) {
        setState(() {
          _profile = null;
          _subject = null;
          _loading = false;
        });
      }
      return;
    }

    final subjectId = await _service.searchSubjectId(widget.mediaName);
    BangumiSubject? subject;
    if (subjectId != null) {
      subject = await _service.getSubject(
        subjectId,
        accessToken: profile.accessToken,
      );
    }

    if (mounted) {
      setState(() {
        _profile = profile;
        _subject = subject;
        _loading = false;
      });
    }
  }

  Future<void> _changeCollection(BangumiCollectionType type) async {
    if (_profile == null || _subject == null) return;
    setState(() => _updating = true);
    final ok = await _service.updateCollectionStatus(
      subjectId: _subject!.id,
      collectionType: type.value,
      accessToken: _profile!.accessToken,
    );
    if (mounted) {
      if (ok) {
        setState(() {
          _subject = _subject!.copyWith(userCollectionType: type);
          _updating = false;
        });
      } else {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _openBindingDialog() async {
    await showDialog<bool>(
      context: context,
      builder: (context) => const Dialog(
        backgroundColor: Colors.transparent,
        child: BangumiBindingSheet(),
      ),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_subject == null) return const SizedBox.shrink();

    final subject = _subject!;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF09199).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFF09199).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF09199).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Color(0xFFF09199),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Bangumi 番组计划',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF09199),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (subject.rank != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Rank #${subject.rank}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.spotlight,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                subject.score.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '分 (${subject.totalVotes}人评分)',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (_profile == null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF09199),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.link_rounded, size: 16),
                  label: const Text('绑定打卡', style: TextStyle(fontSize: 12)),
                  onPressed: _openBindingDialog,
                )
              else
                _buildCollectionDropdown(),
            ],
          ),
          if (subject.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: subject.tags
                  .take(6)
                  .map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollectionDropdown() {
    if (_updating) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFFF09199),
        ),
      );
    }

    final currentType = _subject?.userCollectionType;
    return PopupMenuButton<BangumiCollectionType>(
      tooltip: '标记 Bangumi 追番状态',
      initialValue: currentType,
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: _changeCollection,
      itemBuilder: (context) {
        return BangumiCollectionType.values.map((type) {
          final isSelected = type == currentType;
          return PopupMenuItem<BangumiCollectionType>(
            value: type,
            child: Row(
              children: [
                Text(
                  type.label,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFF09199) : Colors.white,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  const Icon(
                    Icons.check_rounded,
                    color: Color(0xFFF09199),
                    size: 16,
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF09199).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFF09199).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentType?.label ?? '标记状态',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF09199),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: Color(0xFFF09199),
            ),
          ],
        ),
      ),
    );
  }
}
