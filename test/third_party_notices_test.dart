import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest =
      jsonDecode(File('third_party/native_components.json').readAsStringSync())
          as Map<String, dynamic>;
  final components = (manifest['components'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);

  test('native component manifest has unique ids and complete sources', () {
    expect(manifest['schemaVersion'], 1);
    final ids = components.map((item) => item['id'] as String).toSet();

    expect(ids.length, components.length);
    for (final component in components) {
      expect((component['name'] as String).trim(), isNotEmpty);
      expect((component['version'] as String).trim(), isNotEmpty);
      expect(component['distributedFiles'] as List, isNotEmpty);
      expect(component['sourceUrls'] as List, isNotEmpty);
      for (final url in (component['sourceUrls'] as List).cast<String>()) {
        expect(Uri.parse(url).scheme, 'https');
      }
    }
  });

  test('all declared native license files are tracked in the repository', () {
    for (final component in components) {
      for (final path in (component['licenseFiles'] as List).cast<String>()) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '${component['id']} 缺少许可证文件 $path',
        );
      }
    }
  });

  test('release packaging generates and copies third-party notices', () {
    final script = File('scripts/build_windows_package.ps1').readAsStringSync();

    expect(script, contains('tool\\generate_third_party_notices.dart'));
    expect(script, contains('NOTICES.Z'));
    expect(script, contains('THIRD_PARTY_NOTICES.txt'));
    expect(script, contains('Copy-Item'));
  });

  test('manifest covers the native libraries with separate obligations', () {
    final files = components
        .expand((item) => (item['distributedFiles'] as List).cast<String>())
        .toSet();

    expect(files, contains('libmpv-2.dll'));
    expect(files, contains('libEGL.dll'));
    expect(files, contains('libGLESv2.dll'));
    expect(files, contains('sqlite3.dll'));
    expect(files, contains('flutter_windows.dll'));
  });
}
