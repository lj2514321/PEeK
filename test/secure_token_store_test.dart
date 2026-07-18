import 'dart:convert';

import 'package:embyplayer/src/core/storage/secure_token_store.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'restores the active server session without storing a password',
    () async {
      final store = SecureTokenStore();
      final account = _account(
        serverId: 'server-id',
        userId: 'user-id',
        name: '客厅服务器',
        userName: 'Alex',
        token: 'secret-token',
      );

      await store.writeSession(account);
      final restored = await SecureTokenStore().readSession();

      expect(restored?.server.apiBaseUri, account.server.apiBaseUri);
      expect(restored?.server.kind, ServerKind.jellyfin);
      expect(restored?.userId, 'user-id');
      expect(restored?.userName, 'Alex');
      expect(restored?.accessToken, 'secret-token');
    },
  );

  test('persists multiple accounts and switches the active session', () async {
    final store = SecureTokenStore();
    final livingRoom = _account(
      serverId: 'living-room',
      userId: 'alex',
      name: '客厅',
      userName: 'Alex',
      token: 'living-token',
    );
    final study = _account(
      serverId: 'study',
      userId: 'sam',
      name: '书房',
      userName: 'Sam',
      token: 'study-token',
      kind: ServerKind.emby,
    );

    await store.writeSession(livingRoom);
    await store.writeSession(study);
    var state = await SecureTokenStore().readSessionState();

    expect(state.accounts, hasLength(2));
    expect(state.activeSession?.server.serverId, 'study');

    await store.activateSession(livingRoom);
    state = await SecureTokenStore().readSessionState();

    expect(state.activeSession?.server.serverId, 'living-room');
    expect(state.accounts.where((entry) => entry.signedIn), hasLength(2));
  });

  test('signs out but keeps the server profile for another login', () async {
    final store = SecureTokenStore();
    final account = _account(
      serverId: 'server-id',
      userId: 'user-id',
      name: '家庭影院',
      userName: 'Alex',
      token: 'secret-token',
    );
    await store.writeSession(account);

    await store.signOut(account);
    final state = await store.readSessionState();

    expect(state.activeSession, isNull);
    expect(state.accounts, hasLength(1));
    expect(state.accounts.single.signedIn, isFalse);
    expect(state.accounts.single.profile.name, '家庭影院');
    expect(await store.read(serverId: 'server-id', userId: 'user-id'), isNull);
  });

  test('removes both a saved profile and its token', () async {
    final store = SecureTokenStore();
    final account = _account(
      serverId: 'server-id',
      userId: 'user-id',
      name: '家庭影院',
      userName: 'Alex',
      token: 'secret-token',
    );
    await store.writeSession(account);

    await store.removeProfile(ServerProfile.fromSession(account));

    expect((await store.readSessionState()).accounts, isEmpty);
    expect(await store.read(serverId: 'server-id', userId: 'user-id'), isNull);
  });

  test(
    'migrates the legacy active session into the account directory',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'active_server_session_v1': jsonEncode({
          'kind': 'jellyfin',
          'name': '旧版服务器',
          'version': '10.10',
          'serverId': 'legacy-server',
          'apiBaseUri': 'http://192.168.1.20:8096/',
          'userId': 'legacy-user',
          'userName': 'Legacy',
          'deviceId': 'legacy-device',
        }),
        'server_token_legacy-server_legacy-user': 'legacy-token',
      });

      final state = await SecureTokenStore().readSessionState();

      expect(state.accounts, hasLength(1));
      expect(state.accounts.single.profile.name, '旧版服务器');
      expect(state.activeSession?.accessToken, 'legacy-token');
      expect((await SecureTokenStore().readSession())?.userName, 'Legacy');
    },
  );

  test('rebuilds a damaged account directory on the next login', () async {
    FlutterSecureStorage.setMockInitialValues({
      'server_account_directory_v2': '{damaged',
    });
    final store = SecureTokenStore();
    final account = _account(
      serverId: 'recovered-server',
      userId: 'alex',
      name: '恢复后的服务器',
      userName: 'Alex',
      token: 'fresh-token',
    );

    await store.writeSession(account);
    final state = await store.readSessionState();

    expect(state.accounts, hasLength(1));
    expect(state.activeSession?.server.serverId, 'recovered-server');
  });
}

AuthenticatedServer _account({
  required String serverId,
  required String userId,
  required String name,
  required String userName,
  required String token,
  ServerKind kind = ServerKind.jellyfin,
}) {
  return AuthenticatedServer(
    server: DiscoveredServer(
      kind: kind,
      name: name,
      version: kind == ServerKind.jellyfin ? '10.11.6' : '4.9',
      serverId: serverId,
      apiBaseUri: Uri.parse('http://$serverId.local:8096/'),
    ),
    userId: userId,
    userName: userName,
    deviceId: 'device-id',
    accessToken: token,
  );
}
