import 'dart:convert';
import 'package:volt_net/volt_net.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

class _TestApiConfig extends BaseApiUrlConfig {
  @override
  Future<String> getToken() async => 'teste';
  @override
  Future<Map<String, String>> getHeader() async => {
        'Authorization': 'Bearer teste',
        'Content-Type': 'application/json',
      };
  @override
  String resolveBaseUrl() => 'https://www.testeurl.com';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late PostRequest postRequest;
  late MockHttpClient mockClient;
  late _TestApiConfig apiConfig;

  setUpAll(() async {
    registerFallbackValue(FakeBaseRequest());
    SqlDatabaseHelper.databaseName = ':memory:';
    apiConfig = _TestApiConfig();
    await SqlDatabaseHelper.reset();
  });

  setUp(() async {
    mockClient = MockHttpClient();
    await CacheManager.init();
    await CacheManager.clearAll();
    postRequest = PostRequest(client: mockClient);
  });

  group('Offline-First (MesseZap Scenario)', () {
    test(
        'Deve enfileirar mensagem quando houver erro de rede (SocketException)',
        () async {
      final messageData = {'text': 'Olá amigo!', 'to': 'user_b'};

      when(() => mockClient.send(any())).thenThrow(
          http.ClientException('SocketException: Connection failed'));

      final result = await postRequest.post(
        apiConfig,
        endpoint: '/send_message',
        data: messageData,
      );

      expect(result.isPending, true);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);

      expect(pending.length, 1);
      final Map<String, dynamic> payload =
          jsonDecode(pending.first['body_payload'] as String);
      expect(payload['text'], 'Olá amigo!');
    });

    test('Deve sincronizar automaticamente a fila quando a internet voltar',
        () async {
      final syncManager = SyncQueueManager();
      final mockSyncClient = MockHttpClient();

      await syncManager.enqueue(
        endpoint: 'https://api.messezap.com/send_message',
        method: 'POST',
        body: {'text': 'Sync Test'},
        headers: {'Auth': 'token'},
      );

      when(() => mockSyncClient.send(any()))
          .thenAnswer((_) async => http.StreamedResponse(
                Stream.fromIterable([utf8.encode('{"ok":true}')]),
                200,
              ));

      await syncManager.syncPendingRequests(httpClient: mockSyncClient);

      final db = await SqlDatabaseHelper().database;
      final afterSync = await db.query(SqlDatabaseHelper.syncTable);
      expect(afterSync.isEmpty, true);
    });
  });
}
