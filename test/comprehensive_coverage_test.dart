import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:volt_net/volt_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class MockHttpClient extends Mock implements Client {}

class FakeBaseRequest extends Fake implements BaseRequest {}

class MockConnectivity extends Mock implements Connectivity {}

class _CompApiConfig extends BaseApiUrlConfig {
  @override
  String resolveBaseUrl() => 'https://api.comp.com';
  @override
  Future<Map<String, String>> getHeader() async =>
      {'Content-Type': 'application/json'};
  @override
  Future<String> getToken() async => 'comp_token';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late _CompApiConfig apiConfig;
  late MockConnectivity mockConnectivity;

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
    registerFallbackValue(Uri.parse('https://api.comp.com'));
    File('test_sync.png').writeAsBytesSync([0, 1, 2]);
  });

  tearDownAll(() {
    if (File('test_sync.png').existsSync()) {
      File('test_sync.png').deleteSync();
    }
  });

  setUp(() async {
    mockClient = MockHttpClient();
    apiConfig = _CompApiConfig();
    mockConnectivity = MockConnectivity();
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
    SyncQueueManager().reset();
    SyncQueueManager().setDependencies(
      connectivity: mockConnectivity,
      dbHelper: SqlDatabaseHelper(),
      httpClient: mockClient,
    );
  });

  tearDown(() {
    SyncQueueManager().reset();
  });

  group('SyncQueueManager Advanced Coverage', () {
    test('startMonitoring and connectivity change', () async {
      final controller = StreamController<List<ConnectivityResult>>.broadcast();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => controller.stream);

      when(() => mockClient.send(any())).thenAnswer(
          (_) async => StreamedResponse(Stream.fromIterable([]), 200));

      final syncManager = SyncQueueManager();
      syncManager.startMonitoring();

      await syncManager.enqueue(
        endpoint: 'https://api.comp.com/offline',
        method: 'POST',
        body: {'id': 1},
        headers: {},
      );

      final done = syncManager.onQueueFinished.first;
      controller.add([ConnectivityResult.wifi]);
      await done;

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending.isEmpty, true);

      await controller.close();
    });

    test('syncPendingRequests handles 429 by retrying (incrementing retry)',
        () async {
      await SyncQueueManager().enqueue(
        endpoint: 'https://api.comp.com/retry',
        method: 'POST',
        body: {'id': 1},
        headers: {},
      );

      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('Rate Limit')]),
                429,
              ));

      await SyncQueueManager().syncPendingRequests(httpClient: mockClient);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending.first['retries'], 1);
    });

    test('syncPendingRequests handles multipart with files', () async {
      await SyncQueueManager().enqueue(
        endpoint: 'https://api.comp.com/upload',
        method: 'POST',
        body: {'name': 'test'},
        headers: {},
        isMultipart: true,
        filePaths: ['test_sync.png'],
      );

      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('{"ok":true}')]),
                200,
              ));

      await SyncQueueManager().syncPendingRequests(httpClient: mockClient);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending.isEmpty, true);
    });
  });

  group('GetRequest & PostRequest Debounce Coverage', () {
    test('getWithDebounce should only execute once', () async {
      final getRequest = GetRequest(client: mockClient);

      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('{"res":1}')]),
                200,
              ));

      final f1 = getRequest.getWithDebounce(apiConfig, '/debounce',
          delay: const Duration(milliseconds: 50));
      final f2 = getRequest.getWithDebounce(apiConfig, '/debounce',
          delay: const Duration(milliseconds: 50));

      final r1 = await f1;
      final r2 = await f2;

      expect(r1.isCancelled, true);
      expect(r2.isSuccess, true);
      verify(() => mockClient.send(any())).called(1);
    });

    test('postWithDebounce should only execute once', () async {
      final postRequest = PostRequest(client: mockClient);

      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('{"res":1}')]),
                200,
              ));

      final f1 = postRequest.postWithDebounce(apiConfig,
          endpoint: '/debounce', delay: const Duration(milliseconds: 50));
      final f2 = postRequest.postWithDebounce(apiConfig,
          endpoint: '/debounce', delay: const Duration(milliseconds: 50));

      final r1 = await f1;
      final r2 = await f2;

      expect(r1.isCancelled, true);
      expect(r2.isSuccess, true);
      verify(() => mockClient.send(any())).called(1);
    });
  });

  group('PostRequest resilientBatch Rollback Coverage', () {
    test('resilientBatch should call onRollback on failure', () async {
      final postRequest = PostRequest(client: mockClient);
      bool rollbackCalled = false;

      when(() => mockClient.send(any())).thenAnswer((invocation) async {
        final req = invocation.positionalArguments[0] as BaseRequest;
        if (req.url.path.contains('/fail')) {
          return StreamedResponse(Stream.fromIterable([]), 400);
        }
        return StreamedResponse(
            Stream.fromIterable([utf8.encode('{"ok":true}')]), 200);
      });

      try {
        await postRequest.resilientBatch(
          [
            ({extraHeaders}) => postRequest.post(apiConfig,
                endpoint: '/ok', extraHeaders: extraHeaders),
            ({extraHeaders}) => postRequest.post(apiConfig,
                endpoint: '/fail', extraHeaders: extraHeaders),
          ],
          onRollback: (results) async {
            rollbackCalled = true;
          },
        );
      } catch (_) {}

      expect(rollbackCalled, true);
    });
  });

  group('GetRequest Fallback Cache Coverage', () {
    test('get should fallback to expired cache on network error', () async {
      final getRequest = GetRequest(client: mockClient);
      final fullUrl = 'https://api.comp.com/fallback';

      await CacheManager().save(
        type: CacheType.disk,
        token: 'comp_token',
        endpoint: fullUrl,
        data: ResultApi(response: Response('{"expired":true}', 200)),
      );

      // Simulate network error
      when(() => mockClient.send(any()))
          .thenThrow(HttpNetworkException('No internet'));

      final res = await getRequest.get(
        apiConfig,
        '/fallback',
        cacheEnabled: true,
        type: CacheType.disk,
      );

      expect(res.jsonBody['expired'], true);
    });
  });
}
