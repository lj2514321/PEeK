import 'package:dio/dio.dart';

class DanmakuItem {
  const DanmakuItem({
    required this.timeSeconds,
    required this.type,
    required this.color,
    required this.text,
  });

  factory DanmakuItem.fromDandanJson(Map<String, dynamic> json) {
    // DandanPlay comment format: "time,type,color,user"
    final p = (json['p'] as String? ?? '').split(',');
    final timeSeconds = p.isNotEmpty ? double.tryParse(p[0]) ?? 0.0 : 0.0;
    final type = p.length > 1 ? int.tryParse(p[1]) ?? 1 : 1;
    final color = p.length > 2 ? int.tryParse(p[2]) ?? 16777215 : 16777215;
    final text = json['m'] as String? ?? '';
    return DanmakuItem(
      timeSeconds: timeSeconds,
      type: type,
      color: color,
      text: text,
    );
  }

  final double timeSeconds;
  final int type; // 1: scroll, 4: bottom, 5: top
  final int color;
  final String text;
}

class DandanPlayService {
  DandanPlayService([Dio? dio]) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _baseUrl = 'https://api.dandanplay.net/api/v2';

  Future<int?> searchEpisodeId(String keyword) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/search/episodes',
        queryParameters: {'anime': keyword},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final animes = data['animes'];
        if (animes is List && animes.isNotEmpty) {
          final firstAnime = animes.first;
          if (firstAnime is Map<String, dynamic>) {
            final episodes = firstAnime['episodes'];
            if (episodes is List && episodes.isNotEmpty) {
              final ep = episodes.first;
              if (ep is Map<String, dynamic>) {
                return int.tryParse(ep['episodeId']?.toString() ?? '');
              }
            }
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<DanmakuItem>> fetchComments(int episodeId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/comment/$episodeId',
        queryParameters: {'withRelated': 'true'},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final comments = data['comments'];
        if (comments is List) {
          return comments
              .whereType<Map<String, dynamic>>()
              .map((json) => DanmakuItem.fromDandanJson(json))
              .where((item) => item.text.isNotEmpty)
              .toList(growable: false);
        }
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }
}
