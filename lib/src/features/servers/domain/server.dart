enum ServerKind { jellyfin, emby }

extension ServerKindLabel on ServerKind {
  String get label => switch (this) {
    ServerKind.jellyfin => 'Jellyfin',
    ServerKind.emby => 'Emby',
  };
}

class DiscoveredServer {
  const DiscoveredServer({
    required this.kind,
    required this.name,
    required this.version,
    required this.serverId,
    required this.apiBaseUri,
  });

  final ServerKind kind;
  final String name;
  final String version;
  final String serverId;
  final Uri apiBaseUri;
}

class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.kind,
    required this.name,
    required this.apiBaseUri,
    required this.serverId,
    required this.userId,
    required this.deviceId,
  });

  final String id;
  final ServerKind kind;
  final String name;
  final Uri apiBaseUri;
  final String serverId;
  final String userId;
  final String deviceId;
}

class AuthenticatedServer {
  const AuthenticatedServer({
    required this.server,
    required this.userId,
    required this.userName,
    required this.deviceId,
    required this.accessToken,
  });

  final DiscoveredServer server;
  final String userId;
  final String userName;
  final String deviceId;
  final String accessToken;
}
