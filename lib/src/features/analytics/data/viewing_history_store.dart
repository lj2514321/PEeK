import 'dart:convert';
import 'dart:io';

class ViewingRecord {
  const ViewingRecord({
    required this.dateString,
    required this.minutes,
    required this.kind, // 'movie' or 'series'
  });

  factory ViewingRecord.fromJson(Map<String, dynamic> json) {
    return ViewingRecord(
      dateString: json['dateString'] as String? ?? '',
      minutes: json['minutes'] as int? ?? 0,
      kind: json['kind'] as String? ?? 'movie',
    );
  }

  final String dateString;
  final int minutes;
  final String kind;

  Map<String, dynamic> toJson() => {
        'dateString': dateString,
        'minutes': minutes,
        'kind': kind,
      };
}

class ViewingHistoryStore {
  ViewingHistoryStore({Directory? directory})
      : _directory = directory ?? _defaultDirectory();

  final Directory _directory;

  File get _file => File(
        '${_directory.path}${Platform.pathSeparator}viewing_history_v1.json',
      );

  static Directory _defaultDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? Directory.systemTemp.path
        : localAppData;
    return Directory('$root${Platform.pathSeparator}PEeK');
  }

  Future<List<ViewingRecord>> readRecords() async {
    try {
      final file = _file;
      if (!await file.exists()) return _demoRecords();
      final content = await file.readAsString();
      final list = jsonDecode(content);
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map(ViewingRecord.fromJson)
            .toList(growable: false);
      }
    } catch (_) {}
    return _demoRecords();
  }

  Future<void> recordViewing({
    required int minutes,
    required String kind,
  }) async {
    try {
      final records = (await readRecords()).toList();
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      records.add(
        ViewingRecord(dateString: dateStr, minutes: minutes, kind: kind),
      );
      if (!await _directory.exists()) {
        await _directory.create(recursive: true);
      }
      await _file.writeAsString(
        jsonEncode(records.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  List<ViewingRecord> _demoRecords() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      final dateStr =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      return ViewingRecord(
        dateString: dateStr,
        minutes: (i + 1) * 35 + (i % 2 == 0 ? 40 : 15),
        kind: i % 2 == 0 ? 'movie' : 'series',
      );
    });
  }
}
