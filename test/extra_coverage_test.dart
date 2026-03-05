import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

  late _TestApiConfig apiConfig;

  setUpAll(() async {
    registerFallbackValue(FakeBaseRequest());
    SqlDatabaseHelper.databaseName = ':memory:';
    apiConfig = _TestApiConfig();
    await SqlDatabaseHelper.reset();
  });

  group('SyncQueueManager Coverage', () {
    test('syncPendingRequests handles 4xx errors by removing from queue',
        () async {
      final mockHttpClient = MockHttpClient();
      final syncManager = SyncQueueManager();

      await syncManager.enqueue(
        endpoint: 'https://test.com/404',
        method: 'POST',
        body: {'data': 1},
        headers: {},
      );

      when(() => mockHttpClient.send(any()))
          .thenAnswer((_) async => http.StreamedResponse(
                Stream.fromIterable([utf8.encode('Not Found')]),
                404,
              ));

      await syncManager.syncPendingRequests(httpClient: mockHttpClient);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending.isEmpty, true);
    });

    test('syncPendingRequests handles 5xx errors by keeping in queue',
        () async {
      final mockHttpClient = MockHttpClient();
      final syncManager = SyncQueueManager();

      await syncManager.enqueue(
        endpoint: 'https://test.com/500',
        method: 'POST',
        body: {'data': 1},
        headers: {},
      );

      when(() => mockHttpClient.send(any()))
          .thenAnswer((_) async => http.StreamedResponse(
                Stream.fromIterable([utf8.encode('Server Error')]),
                500,
              ));

      await syncManager.syncPendingRequests(httpClient: mockHttpClient);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending.isNotEmpty, true);
    });
  });

  group('ResultApi Coverage', () {
    test('isServerError should return true for 5xx', () {
      final res = ResultApi(response: http.Response('Error', 500));
      expect(res.isServerError, true);
    });
  });

  group('GetRequest Extra Coverage', () {
    test('getModel with asList true from cache', () async {
      final mockClient = MockHttpClient();
      final cacheManager = CacheManager();
      final getRequest = GetRequest(client: mockClient, cache: cacheManager);
      final listData = [
        {'nome': 'Cached 1'}
      ];

      await cacheManager.save(
        type: CacheType.memory,
        token: 'teste',
        endpoint: 'https://www.testeurl.com/cached-list',
        data: ResultApi(response: http.Response(jsonEncode(listData), 200)),
      );

      final result = await getRequest.getModel<TestModel>(
        apiConfig,
        '/cached-list',
        TestModel.fromJson,
        cacheEnabled: true,
        type: CacheType.memory,
        asList: true,
      );

      expect(result.length, 1);
      expect(result[0].nome, 'Cached 1');
    });
  });
}
