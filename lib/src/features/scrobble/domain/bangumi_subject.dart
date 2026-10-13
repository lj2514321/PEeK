enum BangumiCollectionType {
  wish(1, '想看'),
  collect(2, '看过'),
  doing(3, '在看'),
  onHold(4, '搁置'),
  dropped(5, '抛弃');

  const BangumiCollectionType(this.value, this.label);
  final int value;
  final String label;

  static BangumiCollectionType? fromValue(int? value) {
    if (value == null) return null;
    for (final type in BangumiCollectionType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

class BangumiSubject {
  const BangumiSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.score,
    required this.rank,
    required this.totalVotes,
    required this.tags,
    this.userCollectionType,
  });

  final int id;
  final String name;
  final String nameCn;
  final String summary;
  final double score;
  final int? rank;
  final int totalVotes;
  final List<String> tags;
  final BangumiCollectionType? userCollectionType;

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  BangumiSubject copyWith({BangumiCollectionType? userCollectionType}) {
    return BangumiSubject(
      id: id,
      name: name,
      nameCn: nameCn,
      summary: summary,
      score: score,
      rank: rank,
      totalVotes: totalVotes,
      tags: tags,
      userCollectionType: userCollectionType ?? this.userCollectionType,
    );
  }

  factory BangumiSubject.fromJson(Map<String, dynamic> json) {
    final rating = json['rating'] as Map<String, dynamic>?;
    final score =
        (rating?['score'] as num?)?.toDouble() ??
        (json['score'] as num?)?.toDouble() ??
        0.0;
    final rank =
        (rating?['rank'] as num?)?.toInt() ?? (json['rank'] as num?)?.toInt();
    final totalVotes = (rating?['total'] as num?)?.toInt() ?? 0;

    final tagsList = <String>[];
    final rawTags = json['tags'];
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t is Map<String, dynamic>) {
          final name = t['name']?.toString();
          if (name != null && name.isNotEmpty) {
            tagsList.add(name);
          }
        } else if (t is String && t.isNotEmpty) {
          tagsList.add(t);
        }
      }
    }

    BangumiCollectionType? collectionType;
    final rawCollection = json['collection'];
    if (rawCollection is Map<String, dynamic>) {
      final userType = rawCollection['type'] as int?;
      collectionType = BangumiCollectionType.fromValue(userType);
    }

    return BangumiSubject(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['name_cn'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      score: score,
      rank: rank,
      totalVotes: totalVotes,
      tags: tagsList,
      userCollectionType: collectionType,
    );
  }
}
