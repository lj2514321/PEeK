import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/analytics/data/viewing_history_store.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class AnalyticsDashboardPage extends StatefulWidget {
  const AnalyticsDashboardPage({super.key});

  @override
  State<AnalyticsDashboardPage> createState() => _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState extends State<AnalyticsDashboardPage> {
  final _store = ViewingHistoryStore();
  final _scrollController = SmoothScrollController();
  List<ViewingRecord> _records = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _store.readRecords();
    if (mounted) {
      setState(() {
        _records = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final totalMinutes = _records.fold<int>(0, (sum, item) => sum + item.minutes);
    final totalHours = (totalMinutes / 60.0).toStringAsFixed(1);
    final movieCount = _records.where((r) => r.kind == 'movie').length;
    final seriesCount = _records.where((r) => r.kind == 'series').length;
    final avgDaily = _records.isNotEmpty
        ? (totalMinutes / _records.length).round()
        : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: PeekSmoothScroll(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '观影数据分析与统计',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                '基于本地播放行为自动生成的私有视听健康仪表盘',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              // Summary Cards
              Row(
                children: [
                  _StatCard(
                    title: '累计观影时长',
                    value: '$totalHours 小时',
                    icon: Icons.timer_rounded,
                    color: AppColors.spotlight,
                  ),
                  const SizedBox(width: 16),
                  _StatCard(
                    title: '观影总场次',
                    value: '${_records.length} 部/集',
                    icon: Icons.movie_rounded,
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(width: 16),
                  _StatCard(
                    title: '日均观影',
                    value: '$avgDaily 分钟',
                    icon: Icons.auto_graph_rounded,
                    color: Colors.purpleAccent,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Bar Chart Section
              Container(
                padding: const EdgeInsets.all(24),
                decoration: AppGlass.decoration(radius: 20, elevated: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '近 7 日每日观影时长 (分钟)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          borderData: FlBorderData(show: false),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (val) => FlLine(
                              color: Colors.white.withValues(alpha: 0.08),
                              strokeWidth: 1,
                            ),
                          ),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx >= 0 && idx < _records.length) {
                                    final date = _records[idx].dateString;
                                    final parts = date.split('-');
                                    final label = parts.length > 2
                                        ? '${parts[1]}/${parts[2]}'
                                        : date;
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          color: AppColors.textTertiary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                          ),
                          barGroups: [
                            for (var i = 0; i < _records.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: _records[i].minutes.toDouble(),
                                    color: AppColors.spotlight,
                                    width: 18,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              // Pie Chart Section
              Container(
                padding: const EdgeInsets.all(24),
                decoration: AppGlass.decoration(radius: 20, elevated: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '媒体类型分布占比',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        SizedBox(
                          height: 180,
                          width: 180,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 4,
                              centerSpaceRadius: 42,
                              sections: [
                                PieChartSectionData(
                                  value: movieCount.toDouble(),
                                  title: '电影',
                                  color: AppColors.spotlight,
                                  radius: 40,
                                  titleStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    fontSize: 13,
                                  ),
                                ),
                                PieChartSectionData(
                                  value: seriesCount.toDouble(),
                                  title: '剧集',
                                  color: Colors.cyanAccent,
                                  radius: 40,
                                  titleStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 32),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LegendItem(
                              color: AppColors.spotlight,
                              label: '电影 ($movieCount 部)',
                            ),
                            const SizedBox(height: 12),
                            _LegendItem(
                              color: Colors.cyanAccent,
                              label: '剧集 ($seriesCount 集)',
                            ),
                          ],
                        ),
                      ],
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
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: AppGlass.decoration(radius: 20, elevated: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
