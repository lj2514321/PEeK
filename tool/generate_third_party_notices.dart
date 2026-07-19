import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  final root = Directory.current;
  final outputPath =
      _argumentValue(arguments, '--output') ??
      '${root.path}${Platform.pathSeparator}THIRD_PARTY_NOTICES.txt';
  final flutterNoticesPath =
      _argumentValue(arguments, '--flutter-notices') ??
      '${root.path}${Platform.pathSeparator}build${Platform.pathSeparator}'
          'windows${Platform.pathSeparator}x64${Platform.pathSeparator}'
          'runner${Platform.pathSeparator}Release${Platform.pathSeparator}'
          'data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}'
          'NOTICES.Z';

  final graph = _readJson('.dart_tool/package_graph.json');
  final packageConfig = _readJson('.dart_tool/package_config.json');
  final packageNotices = _collectPackageNotices(graph, packageConfig);
  final nativeManifest = _readJson('third_party/native_components.json');
  final flutterNotices = _readFlutterNotices(flutterNoticesPath);

  final output = StringBuffer()
    ..writeln('PEeK THIRD-PARTY NOTICES')
    ..writeln()
    ..writeln(
      'This file is generated from the locked Dart/Flutter dependency graph, '
      'the native component manifest, and Flutter\'s generated notices.',
    )
    ..writeln(
      'Do not edit it manually. Run: dart run '
      'tool/generate_third_party_notices.dart',
    )
    ..writeln();

  _writeNativeComponents(output, nativeManifest);
  _writePackageNotices(output, packageNotices);
  output
    ..writeln(_separator)
    ..writeln('FLUTTER ENGINE AND GENERATED THIRD-PARTY NOTICES')
    ..writeln(_separator)
    ..writeln()
    ..writeln(flutterNotices.trim())
    ..writeln();

  File(
    outputPath,
  ).writeAsStringSync(output.toString().replaceAll('\r\n', '\n'), flush: true);
  stdout.writeln(
    'Generated ${File(outputPath).lengthSync()} bytes at $outputPath '
    'from ${packageNotices.packageCount} packages.',
  );
}

const _separator =
    '===============================================================================';

String? _argumentValue(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 >= arguments.length) {
    throw FormatException('Missing value for $name.');
  }
  return arguments[index + 1];
}

Map<String, dynamic> _readJson(String path) {
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

_PackageNoticeCollection _collectPackageNotices(
  Map<String, dynamic> graph,
  Map<String, dynamic> packageConfig,
) {
  final graphPackages = <String, Map<String, dynamic>>{
    for (final item in graph['packages'] as List)
      (item as Map)['name'] as String: Map<String, dynamic>.from(item),
  };
  final configPackages = <String, Map<String, dynamic>>{
    for (final item in packageConfig['packages'] as List)
      (item as Map)['name'] as String: Map<String, dynamic>.from(item),
  };
  final rootNames = (graph['roots'] as List).cast<String>();
  if (rootNames.length != 1) {
    throw StateError('Expected one package graph root, found $rootNames.');
  }
  final rootPackage = graphPackages[rootNames.single];
  if (rootPackage == null) {
    throw StateError('Package graph root is missing.');
  }

  final pending = <String>[
    ...(rootPackage['dependencies'] as List).cast<String>(),
  ];
  final visited = <String>{};
  final packages = <_PackageLicense>[];
  while (pending.isNotEmpty) {
    final name = pending.removeLast();
    if (!visited.add(name)) continue;
    final package = graphPackages[name];
    final config = configPackages[name];
    if (package == null || config == null) {
      throw StateError('Missing graph or package configuration for $name.');
    }
    pending.addAll((package['dependencies'] as List).cast<String>());

    final rootUri = Uri.parse(config['rootUri'] as String);
    if (rootUri.scheme != 'file') {
      throw StateError('Unsupported package URI for $name: $rootUri');
    }
    final licenseFiles = _findLicenseFiles(Directory.fromUri(rootUri));
    if (licenseFiles.isEmpty) {
      throw StateError('No license file found for $name at $rootUri.');
    }
    final licenseText = licenseFiles
        .map((file) => file.readAsStringSync().trim())
        .join('\n\n');
    packages.add(
      _PackageLicense(
        name: name,
        version: package['version'] as String,
        fileNames: licenseFiles
            .map((file) => file.uri.pathSegments.last)
            .toSet(),
        licenseText: licenseText,
      ),
    );
  }

  packages.sort((a, b) => a.name.compareTo(b.name));
  return _PackageNoticeCollection(packages);
}

List<File> _findLicenseFiles(Directory packageRoot) {
  var directory = packageRoot;
  for (var level = 0; level < 4; level++) {
    final files =
        directory
            .listSync(followLinks: false)
            .whereType<File>()
            .where(
              (file) => RegExp(
                r'^(LICENSE|COPYING|NOTICE)(\..*)?$',
                caseSensitive: false,
              ).hasMatch(file.uri.pathSegments.last),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isNotEmpty) return files;
    directory = directory.parent;
  }
  return const [];
}

String _readFlutterNotices(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'Flutter notices not found at $path. Build Windows Release first or pass '
      '--flutter-notices.',
    );
  }
  return utf8.decode(zlib.decode(file.readAsBytesSync()));
}

void _writeNativeComponents(
  StringBuffer output,
  Map<String, dynamic> manifest,
) {
  if (manifest['schemaVersion'] != 1) {
    throw StateError('Unsupported native component manifest schema.');
  }
  final components = (manifest['components'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  output
    ..writeln(_separator)
    ..writeln('NATIVE COMPONENTS DISTRIBUTED WITH PEeK')
    ..writeln(_separator)
    ..writeln();

  for (final component in components) {
    output
      ..writeln('${component['name']} — ${component['version']}')
      ..writeln('License: ${component['license']}')
      ..writeln(
        'Distributed files: '
        '${(component['distributedFiles'] as List).join(', ')}',
      )
      ..writeln('Source and build information:');
    for (final url in component['sourceUrls'] as List) {
      output.writeln('  $url');
    }
    output
      ..writeln('Notes: ${component['notes']}')
      ..writeln();
    for (final licensePath
        in (component['licenseFiles'] as List).cast<String>()) {
      final file = File(licensePath);
      if (!file.existsSync()) {
        throw StateError('Native license file is missing: $licensePath');
      }
      output
        ..writeln('--- ${file.uri.pathSegments.last} ---')
        ..writeln(file.readAsStringSync().trim())
        ..writeln();
    }
    output
      ..writeln(_separator)
      ..writeln();
  }
}

void _writePackageNotices(
  StringBuffer output,
  _PackageNoticeCollection collection,
) {
  output
    ..writeln(_separator)
    ..writeln('DART AND FLUTTER PACKAGE LICENSES')
    ..writeln(_separator)
    ..writeln();

  for (final group in collection.groups) {
    output
      ..writeln(
        'Packages: ${group.packages.map((item) => '${item.name}@${item.version}').join(', ')}',
      )
      ..writeln('License files: ${group.fileNames.join(', ')}')
      ..writeln()
      ..writeln(group.licenseText)
      ..writeln()
      ..writeln(_separator)
      ..writeln();
  }
}

final class _PackageLicense {
  const _PackageLicense({
    required this.name,
    required this.version,
    required this.fileNames,
    required this.licenseText,
  });

  final String name;
  final String version;
  final Set<String> fileNames;
  final String licenseText;
}

final class _PackageLicenseGroup {
  _PackageLicenseGroup(this.licenseText);

  final String licenseText;
  final List<_PackageLicense> packages = [];
  final Set<String> fileNames = {};
}

final class _PackageNoticeCollection {
  _PackageNoticeCollection(List<_PackageLicense> packages)
    : packageCount = packages.length,
      groups = _group(packages);

  final int packageCount;
  final List<_PackageLicenseGroup> groups;

  static List<_PackageLicenseGroup> _group(List<_PackageLicense> packages) {
    final byText = <String, _PackageLicenseGroup>{};
    for (final package in packages) {
      final group = byText.putIfAbsent(
        package.licenseText,
        () => _PackageLicenseGroup(package.licenseText),
      );
      group.packages.add(package);
      group.fileNames.addAll(package.fileNames);
    }
    final groups = byText.values.toList()
      ..sort((a, b) => a.packages.first.name.compareTo(b.packages.first.name));
    return groups;
  }
}
