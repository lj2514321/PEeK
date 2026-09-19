class RemoteSearchResult {
  const RemoteSearchResult({
    required this.name,
    this.originalTitle,
    this.productionYear,
    this.imageUrl,
    this.overview,
    this.providerIds = const {},
    this.searchProviderName,
    this.artists = const [],
    this.rawPayload = const {},
  });

  final String name;
  final String? originalTitle;
  final int? productionYear;
  final String? imageUrl;
  final String? overview;
  final Map<String, String> providerIds;
  final String? searchProviderName;
  final List<String> artists;
  final Map<String, dynamic> rawPayload;

  factory RemoteSearchResult.fromJson(Map<String, dynamic> json) {
    final rawProviderIds = json['ProviderIds'];
    final providerIds = <String, String>{};
    if (rawProviderIds is Map) {
      for (final entry in rawProviderIds.entries) {
        if (entry.value != null && entry.value.toString().isNotEmpty) {
          providerIds[entry.key.toString()] = entry.value.toString();
        }
      }
    }

    final artistsList = <String>[];
    final rawArtists = json['Artists'];
    if (rawArtists is List) {
      for (final a in rawArtists) {
        if (a is String && a.trim().isNotEmpty) {
          artistsList.add(a.trim());
        } else if (a is Map && a['Name'] != null) {
          artistsList.add(a['Name'].toString().trim());
        }
      }
    }

    int? year;
    final rawYear = json['ProductionYear'];
    if (rawYear is int) {
      year = rawYear;
    } else if (rawYear is num) {
      year = rawYear.toInt();
    } else if (rawYear is String) {
      year = int.tryParse(rawYear.trim());
    }

    return RemoteSearchResult(
      name: json['Name']?.toString().trim() ?? '',
      originalTitle: json['OriginalTitle']?.toString().trim(),
      productionYear: year,
      imageUrl: json['ImageUrl']?.toString() ?? json['PrimaryImageTag']?.toString(),
      overview: json['Overview']?.toString().trim(),
      providerIds: providerIds,
      searchProviderName: json['SearchProviderName']?.toString(),
      artists: List.unmodifiable(artistsList),
      rawPayload: json,
    );
  }
}
