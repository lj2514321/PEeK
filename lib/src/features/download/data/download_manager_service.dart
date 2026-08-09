import 'dart:io';
import 'package:dio/dio.dart';

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.title,
    required this.url,
    required this.savePath,
    this.progress = 0.0,
    this.completed = false,
  });

  final String id;
  final String title;
  final String url;
  final String savePath;
  final double progress;
  final bool completed;

  DownloadTask copyWith({double? progress, bool? completed}) {
    return DownloadTask(
      id: id,
      title: title,
      url: url,
      savePath: savePath,
      progress: progress ?? this.progress,
      completed: completed ?? this.completed,
    );
  }
}

class DownloadManagerService {
  DownloadManagerService([Dio? dio, Directory? downloadDir])
      : _dio = dio ?? Dio(),
        _downloadDir = downloadDir ?? _defaultDirectory();

  final Dio _dio;
  final Directory _downloadDir;

  static Directory _defaultDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? Directory.systemTemp.path
        : localAppData;
    return Directory(
      '$root${Platform.pathSeparator}PEeK${Platform.pathSeparator}Downloads',
    );
  }

  Future<DownloadTask> downloadFile({
    required String id,
    required String title,
    required String url,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
  }) async {
    if (!await _downloadDir.exists()) {
      await _downloadDir.create(recursive: true);
    }
    final savePath = '${_downloadDir.path}${Platform.pathSeparator}$id.mp4';
    try {
      await _dio.download(
        url,
        savePath,
        options: Options(headers: headers),
        onReceiveProgress: (count, total) {
          if (total > 0 && onProgress != null) {
            onProgress(count / total);
          }
        },
      );
      return DownloadTask(
        id: id,
        title: title,
        url: url,
        savePath: savePath,
        progress: 1.0,
        completed: true,
      );
    } catch (_) {
      return DownloadTask(
        id: id,
        title: title,
        url: url,
        savePath: savePath,
        progress: 0.0,
        completed: false,
      );
    }
  }
}
