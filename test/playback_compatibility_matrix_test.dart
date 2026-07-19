import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final casesDocument = _readJson('docs/playback-matrix/cases.json');
  final resultsDocument = _readJson('docs/playback-matrix/results.json');

  test(
    'compatibility matrix has stable ids and required category coverage',
    () {
      expect(casesDocument['schemaVersion'], 1);
      final cases = _records(casesDocument, 'cases');
      final ids = cases.map((item) => item['id'] as String).toSet();
      final categories = cases
          .map((item) => item['category'] as String)
          .toSet();

      expect(ids.length, cases.length, reason: '测试用例 id 不可重复');
      expect(
        categories,
        containsAll(<String>{
          'video',
          'audio',
          'subtitle',
          'hdr',
          'strm',
          'network',
        }),
      );
      expect(cases.length, greaterThanOrEqualTo(24));
    },
  );

  test('every case targets both servers and records reproducible evidence', () {
    const supportedMethods = <String>{
      'directPlay',
      'directStream',
      'transcode',
      'recovery',
      'failure',
    };

    for (final item in _records(casesDocument, 'cases')) {
      final servers = List<Object?>.from(
        item['servers'] as List,
      ).cast<String>().toSet();
      final methods = List<Object?>.from(
        item['allowedPlaybackMethods'] as List,
      ).cast<String>().toSet();
      final evidence = List<Object?>.from(
        item['evidence'] as List,
      ).cast<String>();

      expect(
        servers,
        equals(<String>{'jellyfin', 'emby'}),
        reason: '${item['id']} 必须覆盖 Jellyfin 与 Emby',
      );
      expect(
        methods.difference(supportedMethods),
        isEmpty,
        reason: '${item['id']} 包含未知播放方式',
      );
      expect(methods, isNotEmpty);
      expect(evidence, isNotEmpty);
      expect((item['expected'] as String).trim(), isNotEmpty);
      expect((item['fixture'] as String).trim(), isNotEmpty);
    }
  });

  test('results contain one Jellyfin and Emby slot for every case', () {
    expect(resultsDocument['schemaVersion'], casesDocument['schemaVersion']);
    final cases = _records(casesDocument, 'cases');
    final results = _records(resultsDocument, 'results');
    final caseIds = cases.map((item) => item['id'] as String).toSet();
    final resultIds = results.map((item) => item['caseId'] as String).toSet();

    expect(resultIds.length, results.length, reason: '结果 caseId 不可重复');
    expect(resultIds, equals(caseIds));

    for (final result in results) {
      for (final server in const ['jellyfin', 'emby']) {
        final serverResult = Map<String, dynamic>.from(result[server] as Map);
        _validateResult(
          caseId: result['caseId'] as String,
          server: server,
          result: serverResult,
        );
      }
    }
  });
}

Map<String, dynamic> _readJson(String path) {
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _records(Map<String, dynamic> document, String key) {
  return (document[key] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);
}

void _validateResult({
  required String caseId,
  required String server,
  required Map<String, dynamic> result,
}) {
  const allowedStatuses = <String>{'pending', 'pass', 'fail', 'blocked'};
  final status = result['status'];
  expect(allowedStatuses, contains(status), reason: '$caseId / $server 的状态无效');
  if (status == 'pending') return;

  expect(
    result.keys,
    containsAll(<String>['testedAt', 'appVersion', 'serverVersion', 'notes']),
    reason: '$caseId / $server 缺少实测环境信息',
  );
  if (status == 'pass' || status == 'fail') {
    expect(
      result.keys,
      containsAll(<String>['playbackMethod', 'diagnosticSummary']),
      reason: '$caseId / $server 缺少播放诊断证据',
    );
  }
}
