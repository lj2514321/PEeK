import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('declares a stable x64 MSIX identity and safe development signing', () {
    expect(pubspec, contains('msix: ^3.18.0'));
    expect(pubspec, contains('identity_name: PEeK.Player'));
    expect(pubspec, contains('publisher: CN=PEeK Development'));
    expect(pubspec, contains('architecture: x64'));
    expect(pubspec, contains('os_min_version: 10.0.19041.0'));
    expect(pubspec, contains('install_certificate: false'));
    expect(pubspec, isNot(contains('certificate_password:')));
    expect(pubspec, isNot(contains('certificate_path:')));
  });

  test(
    'keeps the package version representable as a four-part MSIX version',
    () {
      final appVersion = RegExp(
        r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);
      final packageVersion = RegExp(
        r'^\s*msix_version:\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(appVersion, isNotNull);
      expect(packageVersion, isNotNull);
      for (var index = 1; index <= 4; index++) {
        final appPart = int.parse(appVersion!.group(index)!);
        final packagePart = int.parse(packageVersion!.group(index)!);
        expect(appPart, inInclusiveRange(0, 65535));
        expect(packagePart, appPart, reason: 'MSIX 版本必须与应用版本一致');
      }
    },
  );

  test('includes repeatable package and App Installer scripts', () {
    expect(File('scripts/build_windows_package.ps1').existsSync(), isTrue);
    expect(File('scripts/new_windows_appinstaller.ps1').existsSync(), isTrue);
    expect(File('docs/WINDOWS_RELEASE.md').existsSync(), isTrue);
  });

  test('automates Windows builds and tagged GitHub releases', () {
    final workflow = File(
      '.github/workflows/windows-release.yml',
    ).readAsStringSync();
    final packageScript = File(
      'scripts/build_windows_package.ps1',
    ).readAsStringSync();

    expect(workflow, contains('branches:'));
    expect(workflow, contains('- master'));
    expect(workflow, contains("- 'v*'"));
    expect(workflow, contains('flutter analyze'));
    expect(workflow, contains('flutter test'));
    expect(workflow, contains('build_windows_package.ps1'));
    expect(workflow, contains('actions/upload-artifact@v7'));
    expect(workflow, contains('actions/download-artifact@v8'));
    expect(workflow, contains("startsWith(github.ref, 'refs/tags/v')"));
    expect(workflow, contains('gh release create'));
    expect(workflow, contains('gh release upload'));
    expect(workflow, contains('--clobber'));
    expect(workflow, contains('contents: write'));
    expect(workflow, contains(r'${{ secrets.WINDOWS_CERTIFICATE_BASE64 }}'));
    expect(workflow, isNot(contains('pull_request_target:')));

    expect(packageScript, contains(r'$MsixVersion'));
    expect(packageScript, contains(r'$CertificatePath'));
    expect(packageScript, contains("'--build-name'"));
    expect(packageScript, contains("'--build-number'"));
    expect(packageScript, contains("'--certificate-password'"));
    expect(packageScript, contains("'--publisher'"));
  });
}
