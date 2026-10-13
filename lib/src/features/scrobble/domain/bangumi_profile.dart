class BangumiProfile {
  const BangumiProfile({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.avatarUrl,
    required this.accessToken,
    this.autoScrobble = true,
  });

  final int userId;
  final String username;
  final String nickname;
  final String avatarUrl;
  final String accessToken;
  final bool autoScrobble;

  BangumiProfile copyWith({
    int? userId,
    String? username,
    String? nickname,
    String? avatarUrl,
    String? accessToken,
    bool? autoScrobble,
  }) {
    return BangumiProfile(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      accessToken: accessToken ?? this.accessToken,
      autoScrobble: autoScrobble ?? this.autoScrobble,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'username': username,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    'accessToken': accessToken,
    'autoScrobble': autoScrobble,
  };

  factory BangumiProfile.fromJson(Map<String, dynamic> json) {
    return BangumiProfile(
      userId: json['userId'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      autoScrobble: json['autoScrobble'] as bool? ?? true,
    );
  }
}
