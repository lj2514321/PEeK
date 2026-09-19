import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/scrobble/domain/bangumi_profile.dart';
import 'package:embyplayer/src/features/scrobble/domain/bangumi_subject.dart';

class BangumiScrobbleService {
  BangumiScrobbleService([Dio? dio]) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _baseUrl = 'https://api.bgm.tv/v0';
  static const _userAgent =
      'PEeK-Player/1.0 (https://github.com/lj2514321/PEeK)';

  Options _authOptions(String accessToken) {
    return Options(
      headers: {
        'Authorization': 'Bearer $accessToken',
        'User-Agent': _userAgent,
        'Content-Type': 'application/json',
      },
    );
  }

  Options _publicOptions() {
    return Options(
      headers: {
        'User-Agent': _userAgent,
        'Content-Type': 'application/json',
      },
    );
  }

  Future<BangumiProfile?> verifyToken(String accessToken) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/me',
        options: _authOptions(accessToken),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final userId = data['id'] as int? ?? 0;
        final username = data['username']?.toString() ?? '';
        final nickname = data['nickname']?.toString() ?? username;
        final avatar = data['avatar'] as Map<String, dynamic>?;
        final avatarUrl = avatar?['large']?.toString() ??
            avatar?['medium']?.toString() ??
            avatar?['small']?.toString() ??
            '';

        return BangumiProfile(
          userId: userId,
          username: username,
          nickname: nickname,
          avatarUrl: avatarUrl,
          accessToken: accessToken,
          autoScrobble: true,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> searchSubjectId(String keyword) async {
    try {
      final cleanKeyword = keyword
          .replaceAll(RegExp(r'(第[0-9一二三四五六七八九十]+季|Season\s*\d+|S\d+)', caseSensitive: false), '')
          .trim();
      final response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/search/subjects',
        queryParameters: {'keyword': cleanKeyword.isNotEmpty ? cleanKeyword : keyword, 'type': 2},
        options: _publicOptions(),
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

  Future<BangumiSubject?> getSubject(
    int subjectId, {
    String? accessToken,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/subjects/$subjectId',
        options: accessToken != null ? _authOptions(accessToken) : _publicOptions(),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;

      var subject = BangumiSubject.fromJson(data);

      if (accessToken != null) {
        try {
          final collResponse = await _dio.get<Map<String, dynamic>>(
            '$_baseUrl/users/-/collections/$subjectId',
            options: _authOptions(accessToken),
          );
          final collData = collResponse.data;
          if (collData is Map<String, dynamic>) {
            final typeVal = collData['type'] as int?;
            subject = subject.copyWith(
              userCollectionType: BangumiCollectionType.fromValue(typeVal),
            );
          }
        } catch (_) {}
      }

      return subject;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateCollectionStatus({
    required int subjectId,
    required int collectionType,
    required String accessToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/users/-/collections/$subjectId',
        data: {'type': collectionType},
        options: _authOptions(accessToken),
      );
      return response.statusCode == 200 || response.statusCode == 202;
    } catch (_) {
      return false;
    }
  }

  Future<bool> scrobbleEpisode({
    required int subjectId,
    required int episodeNumber,
    required String accessToken,
  }) async {
    try {
      // 1. Fetch episodes for subject
      final epResponse = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/episodes',
        queryParameters: {'subject_id': subjectId, 'type': 0, 'limit': 100},
        options: _authOptions(accessToken),
      );
      final epData = epResponse.data;
      int? episodeId;
      if (epData is Map<String, dynamic>) {
        final epList = epData['data'];
        if (epList is List) {
          for (final ep in epList) {
            if (ep is Map<String, dynamic>) {
              final sort = ep['sort'] as num?;
              if (sort?.toInt() == episodeNumber) {
                episodeId = ep['id'] as int?;
                break;
              }
            }
          }
        }
      }

      if (episodeId != null) {
        final markResponse = await _dio.put<Map<String, dynamic>>(
          '$_baseUrl/users/-/collections/$subjectId/episodes/$episodeId',
          data: {'type': 2}, // 2 = watched (已看)
          options: _authOptions(accessToken),
        );
        return markResponse.statusCode == 200 || markResponse.statusCode == 204;
      }

      // Fallback: If episode not individually indexed, mark collection as "3" (在看 doing)
      return updateCollectionStatus(
        subjectId: subjectId,
        collectionType: BangumiCollectionType.doing.value,
        accessToken: accessToken,
      );
    } catch (_) {
      return false;
    }
  }
}
