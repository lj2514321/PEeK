import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/storage/app_storage_path.dart';
import 'package:embyplayer/src/features/download/domain/download_task_item.dart';
import 'package:flutter/foundation.dart';

export 'package:embyplayer/src/features/download/domain/download_task_item.dart';

class DownloadManagerService {
  DownloadManagerService({Dio? dio, Directory? downloadDir})
      : _dio = dio ?? Dio(),
        _downloadDir = downloadDir ?? AppStoragePath.downloadsDirectory;

  static DownloadManagerService? _instance;
  static DownloadManagerService get instance =>
      _instance ??= DownloadManagerService();

  final Dio _dio;
  final Directory _downloadDir;
  final ValueNotifier<List<DownloadTaskItem>> tasksNotifier =
      ValueNotifier<List<DownloadTaskItem>>([]);

  final Map<String, CancelToken> _cancelTokens = {};
  int maxConcurrentDownloads = 2;
  bool _initialized = false;

  File get _registryFile => File(
        '${_downloadDir.path}${Platform.pathSeparator}download_tasks_v1.json',
      );

  List<DownloadTaskItem> get tasks => tasksNotifier.value;

  int get activeDownloadingCount =>
      tasks.where((t) => t.status == DownloadTaskStatus.downloading).length;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (!await _downloadDir.exists()) {
      await _downloadDir.create(recursive: true);
    }

    await _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      if (await _registryFile.exists()) {
        final content = await _registryFile.readAsString();
        final raw = jsonDecode(content);
        if (raw is List) {
          final loaded = raw
              .whereType<Map<String, dynamic>>()
              .map(DownloadTaskItem.fromJson)
              .map((t) {
                // If it was downloading when app closed, set back to paused
                if (t.status == DownloadTaskStatus.downloading) {
                  return t.copyWith(status: DownloadTaskStatus.paused);
                }
                return t;
              })
              .toList(growable: true);
          tasksNotifier.value = loaded;
        }
      }
    } catch (_) {}
  }

  Future<void> _saveTasks() async {
    try {
      if (!await _downloadDir.exists()) {
        await _downloadDir.create(recursive: true);
      }
      final jsonList = tasks.map((t) => t.toJson()).toList();
      await _registryFile.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  DownloadTaskItem? getCompletedTask(String itemId, {String? mediaSourceId}) {
    for (final task in tasks) {
      if (task.itemId == itemId &&
          task.isCompleted &&
          (mediaSourceId == null || task.mediaSourceId == mediaSourceId)) {
        final file = File(task.savePath);
        if (file.existsSync()) {
          return task;
        }
      }
    }
    return null;
  }

  Future<DownloadTaskItem> enqueueTask({
    required String itemId,
    required String title,
    String? seriesName,
    int? seasonNumber,
    int? episodeNumber,
    required String url,
    String? mediaSourceId,
    int estimatedBytes = 0,
    Map<String, String>? headers,
  }) async {
    await init();

    // Check if task already exists
    final existingIndex = tasks.indexWhere(
      (t) => t.itemId == itemId && (mediaSourceId == null || t.mediaSourceId == mediaSourceId),
    );
    if (existingIndex != -1) {
      final existing = tasks[existingIndex];
      if (existing.status == DownloadTaskStatus.paused ||
          existing.status == DownloadTaskStatus.failed) {
        await resumeTask(existing.id, headers: headers);
      }
      return tasks[existingIndex];
    }

    final sanitizedId = itemId.replaceAll(RegExp(r'[^\w\-]'), '_');
    final filename = mediaSourceId != null
        ? '${sanitizedId}_$mediaSourceId.mp4'
        : '$sanitizedId.mp4';
    final savePath = '${_downloadDir.path}${Platform.pathSeparator}$filename';

    final newTask = DownloadTaskItem(
      id: '${itemId}_${DateTime.now().millisecondsSinceEpoch}',
      itemId: itemId,
      title: title,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      url: url,
      savePath: savePath,
      totalBytes: estimatedBytes,
      downloadedBytes: 0,
      status: DownloadTaskStatus.queued,
      mediaSourceId: mediaSourceId,
      createdAt: DateTime.now(),
    );

    final updated = List<DownloadTaskItem>.from(tasks)..add(newTask);
    tasksNotifier.value = updated;
    await _saveTasks();

    _scheduleNext(headers: headers);
    return newTask;
  }

  Future<void> pauseTask(String taskId) async {
    final token = _cancelTokens.remove(taskId);
    token?.cancel('User paused download');

    _updateTaskStatus(taskId, DownloadTaskStatus.paused);
    await _saveTasks();
    _scheduleNext();
  }

  Future<void> resumeTask(String taskId, {Map<String, String>? headers}) async {
    _updateTaskStatus(taskId, DownloadTaskStatus.queued);
    await _saveTasks();
    _scheduleNext(headers: headers);
  }

  Future<void> pauseAll() async {
    for (final task in tasks) {
      if (task.status == DownloadTaskStatus.downloading ||
          task.status == DownloadTaskStatus.queued) {
        final token = _cancelTokens.remove(task.id);
        token?.cancel('User paused all');
        _updateTaskStatus(task.id, DownloadTaskStatus.paused);
      }
    }
    await _saveTasks();
  }

  Future<void> resumeAll({Map<String, String>? headers}) async {
    for (final task in tasks) {
      if (task.status == DownloadTaskStatus.paused ||
          task.status == DownloadTaskStatus.failed) {
        _updateTaskStatus(task.id, DownloadTaskStatus.queued);
      }
    }
    await _saveTasks();
    _scheduleNext(headers: headers);
  }

  Future<void> deleteTask(String taskId, {bool deleteFile = true}) async {
    final token = _cancelTokens.remove(taskId);
    token?.cancel('Task deleted');

    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = tasks[index];
      if (deleteFile) {
        try {
          final file = File(task.savePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }

      final updated = List<DownloadTaskItem>.from(tasks)..removeAt(index);
      tasksNotifier.value = updated;
      await _saveTasks();
    }
    _scheduleNext();
  }

  void _updateTaskStatus(String taskId, DownloadTaskStatus status) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final updated = List<DownloadTaskItem>.from(tasks);
      updated[index] = updated[index].copyWith(
        status: status,
        speedBytesPerSec: status == DownloadTaskStatus.downloading ? null : 0.0,
      );
      tasksNotifier.value = updated;
    }
  }

  void _scheduleNext({Map<String, String>? headers}) {
    final downloadingCount = activeDownloadingCount;
    if (downloadingCount >= maxConcurrentDownloads) return;

    final availableSlots = maxConcurrentDownloads - downloadingCount;
    final queuedTasks = tasks
        .where((t) => t.status == DownloadTaskStatus.queued)
        .take(availableSlots)
        .toList(growable: false);

    for (final task in queuedTasks) {
      _startDownload(task, headers: headers);
    }
  }

  Future<void> _startDownload(
    DownloadTaskItem task, {
    Map<String, String>? headers,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;
    _updateTaskStatus(task.id, DownloadTaskStatus.downloading);

    final file = File(task.savePath);
    var existingBytes = 0;
    if (await file.exists()) {
      existingBytes = await file.length();
    }

    final reqHeaders = <String, String>{...?headers};
    if (existingBytes > 0) {
      reqHeaders['Range'] = 'bytes=$existingBytes-';
    }

    var lastBytes = existingBytes;
    var lastTime = DateTime.now();

    try {
      final response = await _dio.get<ResponseBody>(
        task.url,
        options: Options(
          headers: reqHeaders,
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );

      final totalHeader = response.headers.value('content-length');
      var totalBytes = int.tryParse(totalHeader ?? '') ?? task.totalBytes;
      if (existingBytes > 0) {
        totalBytes += existingBytes;
      }

      final raf = await file.open(
        mode: existingBytes > 0 ? FileMode.append : FileMode.write,
      );

      var downloadedBytes = existingBytes;
      final stream = response.data?.stream;
      if (stream == null) throw Exception('No response stream');

      await for (final chunk in stream) {
        if (cancelToken.isCancelled) break;
        await raf.writeFrom(chunk);
        downloadedBytes += chunk.length;

        final now = DateTime.now();
        final elapsedMs = now.difference(lastTime).inMilliseconds;
        if (elapsedMs >= 500) {
          final bytesDelta = downloadedBytes - lastBytes;
          final speed = (bytesDelta / (elapsedMs / 1000.0)).clamp(0.0, 1e9);

          _updateTaskProgress(
            task.id,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes > 0 ? totalBytes : downloadedBytes,
            speed: speed,
          );

          lastBytes = downloadedBytes;
          lastTime = now;
        }
      }

      await raf.close();

      if (!cancelToken.isCancelled) {
        _completeTask(task.id, totalBytes: downloadedBytes);
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // Cancelled by user pause/delete
      } else {
        _failTask(task.id, e.message ?? '网络异常下载失败');
      }
    } catch (e) {
      _failTask(task.id, e.toString());
    } finally {
      _cancelTokens.remove(task.id);
      _scheduleNext(headers: headers);
    }
  }

  void _updateTaskProgress(
    String taskId, {
    required int downloadedBytes,
    required int totalBytes,
    required double speed,
  }) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final updated = List<DownloadTaskItem>.from(tasks);
      updated[index] = updated[index].copyWith(
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        speedBytesPerSec: speed,
      );
      tasksNotifier.value = updated;
    }
  }

  void _completeTask(String taskId, {required int totalBytes}) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final updated = List<DownloadTaskItem>.from(tasks);
      updated[index] = updated[index].copyWith(
        status: DownloadTaskStatus.completed,
        downloadedBytes: totalBytes,
        totalBytes: totalBytes,
        speedBytesPerSec: 0.0,
      );
      tasksNotifier.value = updated;
      _saveTasks();
    }
  }

  void _failTask(String taskId, String error) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final updated = List<DownloadTaskItem>.from(tasks);
      updated[index] = updated[index].copyWith(
        status: DownloadTaskStatus.failed,
        errorMessage: error,
        speedBytesPerSec: 0.0,
      );
      tasksNotifier.value = updated;
      _saveTasks();
    }
  }
}
