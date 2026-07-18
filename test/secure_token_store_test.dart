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
      final account = AuthenticatedServer(
        server: DiscoveredServer(
          kind: ServerKind.jellyfin,
          name: '客厅服务器',
          version: '10.11.6',
          serverId: 'server-id',
          apiBaseUri: Uri.parse('http://192.168.110.110:8096/'),
        ),
        userId: 'user-id',
        userName: 'Alex',
        deviceId: 'device-id',
        accessToken: 'secret-token',
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

  test('clears both active session metadata and its token', () async {
    final store = SecureTokenStore();
    final account = AuthenticatedServer(
      server: DiscoveredServer(
        kind: ServerKind.emby,
        name: 'Emby',
        version: '4.9',
        serverId: 'server-id',
        apiBaseUri: Uri.parse('http://localhost:8096/'),
      ),
      userId: 'user-id',
      userName: 'Alex',
      deviceId: 'device-id',
      accessToken: 'secret-token',
    );
    await store.writeSession(account);

    await store.clearSession(account: account);

    expect(await store.readSession(), isNull);
    expect(await store.read(serverId: 'server-id', userId: 'user-id'), isNull);
  });
}
