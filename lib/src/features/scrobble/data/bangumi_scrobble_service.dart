import 'package:dio/dio.dart';

class BangumiScrobbleService {
  BangumiScrobbleService([Dio? dio]) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _baseUrl = 'https://api.bgm.tv/v0';

  Future<int?> searchSubjectId(String keyword) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/search/subjects',
        queryParameters: {'keyword': keyword, 'type': 2},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final dataList = data['data'];
        if (dataList is List && dataList.isNotEmpty) {
          final first = dataList.first;
          if (first is Map<String, dynamic>) {
            return first['id'] as int?;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> scrobbleEpisode({
    required int subjectId,
    required String accessToken,
    int statusType = 3, // 3: watched (已看)
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/users/-/collections/$subjectId',
        data: {'type': statusType},
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.statusCode == 200 || response.statusCode == 202;
    } catch (_) {
      return false;
    }
  }
}
