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
    required this.version,
    required this.apiBaseUri,
    required this.serverId,
    required this.userId,
    required this.userName,
    required this.deviceId,
  });

  final String id;
  final ServerKind kind;
  final String name;
  final String version;
  final Uri apiBaseUri;
  final String serverId;
  final String userId;
  final String userName;
  final String deviceId;

  DiscoveredServer get server => DiscoveredServer(
    kind: kind,
    name: name,
    version: version,
    serverId: serverId,
    apiBaseUri: apiBaseUri,
  );

  static ServerProfile fromSession(AuthenticatedServer account) {
    return ServerProfile(
      id: serverProfileId(account.server.serverId, account.userId),
      kind: account.server.kind,
      name: account.server.name,
      version: account.server.version,
      apiBaseUri: account.server.apiBaseUri,
      serverId: account.server.serverId,
      userId: account.userId,
      userName: account.userName,
      deviceId: account.deviceId,
    );
  }
}

class ServerAccountEntry {
  const ServerAccountEntry({required this.profile, this.session});

  final ServerProfile profile;
  final AuthenticatedServer? session;

  bool get signedIn => session != null;
}

class ServerAccountState {
  const ServerAccountState({this.accounts = const [], this.activeSession});

  final List<ServerAccountEntry> accounts;
  final AuthenticatedServer? activeSession;
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

  String get profileId => serverProfileId(server.serverId, userId);
}

String serverProfileId(String serverId, String userId) => '$serverId::$userId';
