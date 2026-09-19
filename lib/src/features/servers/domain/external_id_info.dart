class ExternalIdInfo {
  const ExternalIdInfo({
    required this.name,
    required this.key,
    this.type,
    this.urlFormatString,
  });

  factory ExternalIdInfo.fromJson(Map<String, dynamic> json) {
    return ExternalIdInfo(
      name: json['Name']?.toString() ?? '',
      key: json['Key']?.toString() ?? '',
      type: json['Type']?.toString(),
      urlFormatString: json['UrlFormatString']?.toString(),
    );
  }

  final String name;
  final String key;
  final String? type;
  final String? urlFormatString;
}
