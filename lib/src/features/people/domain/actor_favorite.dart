import 'package:embyplayer/src/features/servers/domain/media_item.dart';

/// Data model representing a favorited/bookmarked actor.
class ActorFavorite {
  const ActorFavorite({
    required this.id,
    required this.name,
    this.role,
    this.imageUri,
    this.imageHeaders = const {},
    required this.savedAt,
  });

  final String id;
  final String name;
  final String? role;
  final Uri? imageUri;
  final Map<String, String> imageHeaders;
  final DateTime savedAt;

  factory ActorFavorite.fromMediaPerson(MediaPerson person) {
    return ActorFavorite(
      id: person.id,
      name: person.name,
      role: person.role,
      imageUri: person.imageUri,
      imageHeaders: person.imageHeaders,
      savedAt: DateTime.now(),
    );
  }

  factory ActorFavorite.fromJson(Map<String, dynamic> json) {
    return ActorFavorite(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未知演员',
      role: json['role'] as String?,
      imageUri: json['imageUri'] != null
          ? Uri.tryParse(json['imageUri'] as String)
          : null,
      imageHeaders: json['imageHeaders'] is Map
          ? Map<String, String>.from(json['imageHeaders'] as Map)
          : const {},
      savedAt: json['savedAt'] != null
          ? DateTime.tryParse(json['savedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'imageUri': imageUri?.toString(),
      'imageHeaders': imageHeaders,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  MediaPerson toMediaPerson() {
    return MediaPerson(
      id: id,
      name: name,
      type: 'Actor',
      role: role,
      imageUri: imageUri,
      imageHeaders: imageHeaders,
    );
  }

  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      name: name,
      kind: MediaItemKind.person,
      imageUri: imageUri,
      imageHeaders: imageHeaders,
    );
  }
}
