import 'dart:convert';
import 'dart:io';

class PlaybackDiagnosticLog {
  PlaybackDiagnosticLog({
    Directory? directory,
    this.maxBytes = 1024 * 1024,
    DateTime Function()? now,
  }) : _directory = directory ?? _defaultDirectory(),
       _now = now ?? DateTime.now;

  final Directory _directory;
  final int maxBytes;
  final DateTime Function() _now;
  Future<void> _writeQueue = Future.value();

  File get currentFile => File(
    '${_directory.path}${Platform.pathSeparator}playback_diagnostics.log',
  );

  File get previousFile => File(
    '${_directory.path}${Platform.pathSeparator}playback_diagnostics.previous.log',
  );

  static Directory _defaultDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? Directory.systemTemp.path
        : localAppData;
    return Directory(
      '$root${Platform.pathSeparator}PEeK${Platform.pathSeparator}logs',
    );
  }

  Future<void> write(
    String event, {
    Map<String, Object?> fields = const {},
    Iterable<String> secrets = const [],
  }) {
    final safeSecrets = secrets.where((value) => value.isNotEmpty).toList();
    final record = <String, Object?>{
      'timestamp': _now().toUtc().toIso8601String(),
      'event': PlaybackDiagnosticRedactor.sanitizeText(
        event,
        secrets: safeSecrets,
      ),
      'fields': PlaybackDiagnosticRedactor.sanitizeFields(
        fields,
        secrets: safeSecrets,
      ),
    };
    final line = '${jsonEncode(record)}\n';
    _writeQueue = _writeQueue.catchError((_) {}).then((_) => _append(line));
    return _writeQueue;
  }

  Future<void> _append(String line) async {
    try {
      await _directory.create(recursive: true);
      final file = currentFile;
      final incomingBytes = utf8.encode(line).length;
      if (await file.exists() &&
          await file.length() + incomingBytes > maxBytes) {
        final previous = previousFile;
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      await currentFile.writeAsString(line, mode: FileMode.append, flush: true);
    } on FileSystemException {
      // Diagnostics must never interrupt playback.
    }
  }
}

abstract final class PlaybackDiagnosticRedactor {
  static final _sensitiveKey = RegExp(
    r'(token|password|authorization|cookie|headers?|api.?key|url|uri|path|user.?id|user.?name|item.?id|media.?source.?id|play.?session.?id|device.?id)',
    caseSensitive: false,
  );
  static final _url = RegExp(
    r'(?:https?|file|rtsp|rtmp)://\S+',
    caseSensitive: false,
  );
  static final _credential = RegExp(
    r'\b(api[_-]?key|access[_-]?token|token|authorization|password)\b\s*[:=]\s*[^,\s;]+',
    caseSensitive: false,
  );

  static Map<String, Object?> sanitizeFields(
    Map<String, Object?> fields, {
    Iterable<String> secrets = const [],
  }) {
    return fields.map(
      (key, value) => MapEntry(
        key,
        _sensitiveKey.hasMatch(key)
            ? '<redacted>'
            : _sanitizeValue(value, secrets: secrets),
      ),
    );
  }

  static String sanitizeText(
    String value, {
    Iterable<String> secrets = const [],
  }) {
    var result = value.replaceAll(_url, '<redacted-url>');
    result = result.replaceAllMapped(
      _credential,
      (match) => '${match.group(1)}=<redacted>',
    );
    for (final secret in secrets) {
      if (secret.isNotEmpty) result = result.replaceAll(secret, '<redacted>');
    }
    return result;
  }

  static Object? _sanitizeValue(
    Object? value, {
    required Iterable<String> secrets,
  }) {
    if (value is String) return sanitizeText(value, secrets: secrets);
    if (value is Map) {
      return sanitizeFields(
        value.map((key, value) => MapEntry(key.toString(), value)),
        secrets: secrets,
      );
    }
    if (value is Iterable) {
      return value
          .map((item) => _sanitizeValue(item, secrets: secrets))
          .toList(growable: false);
    }
    return value;
  }
}
