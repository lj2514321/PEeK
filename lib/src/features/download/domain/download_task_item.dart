enum DownloadTaskStatus {
  queued('排队中'),
  downloading('下载中'),
  paused('已暂停'),
  completed('已完成'),
  failed('下载失败');

  const DownloadTaskStatus(this.label);
  final String label;

  static DownloadTaskStatus fromString(String? val) {
    for (final s in DownloadTaskStatus.values) {
      if (s.name == val) return s;
    }
    return DownloadTaskStatus.queued;
  }
}

class DownloadTaskItem {
  const DownloadTaskItem({
    required this.id,
    required this.itemId,
    required this.title,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    required this.url,
    required this.savePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.status = DownloadTaskStatus.queued,
    this.mediaSourceId,
    required this.createdAt,
    this.errorMessage,
  });

  final String id;
  final String itemId;
  final String title;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final String url;
  final String savePath;
  final int totalBytes;
  final int downloadedBytes;
  final double speedBytesPerSec;
  final DownloadTaskStatus status;
  final String? mediaSourceId;
  final DateTime createdAt;
  final String? errorMessage;

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isCompleted => status == DownloadTaskStatus.completed;
  bool get isDownloading => status == DownloadTaskStatus.downloading;

  String get displayTitle {
    if (seriesName != null && seriesName!.isNotEmpty) {
      final s = seasonNumber != null ? 'S$seasonNumber' : '';
      final e = episodeNumber != null ? 'E$episodeNumber' : '';
      final se = [s, e].where((x) => x.isNotEmpty).join();
      return se.isNotEmpty
          ? '$seriesName $se · $title'
          : '$seriesName · $title';
    }
    return title;
  }

  String get formattedSpeed {
    if (speedBytesPerSec < 1024)
      return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
    if (speedBytesPerSec < 1024 * 1024) {
      return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  DownloadTaskItem copyWith({
    int? totalBytes,
    int? downloadedBytes,
    double? speedBytesPerSec,
    DownloadTaskStatus? status,
    String? errorMessage,
  }) {
    return DownloadTaskItem(
      id: id,
      itemId: itemId,
      title: title,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      url: url,
      savePath: savePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      status: status ?? this.status,
      mediaSourceId: mediaSourceId,
      createdAt: createdAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'itemId': itemId,
    'title': title,
    'seriesName': seriesName,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
    'url': url,
    'savePath': savePath,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'status': status.name,
    'mediaSourceId': mediaSourceId,
    'createdAt': createdAt.toIso8601String(),
    'errorMessage': errorMessage,
  };

  factory DownloadTaskItem.fromJson(Map<String, dynamic> json) {
    return DownloadTaskItem(
      id: json['id'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      seriesName: json['seriesName'] as String?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNumber: json['episodeNumber'] as int?,
      url: json['url'] as String? ?? '',
      savePath: json['savePath'] as String? ?? '',
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      speedBytesPerSec: 0.0,
      status: DownloadTaskStatus.fromString(json['status'] as String?),
      mediaSourceId: json['mediaSourceId'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
