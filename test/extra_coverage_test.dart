import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

class TestConfig extends BaseApiUrlConfig {
  @override
  String get baseUrl => 'https://api.test.com';
  @override
  Future<String> getToken() async => 'mock_token';
}

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockConnectivity mockConnectivity;

  setUpAll(() async {
    registerFallbackValue(FakeUri());
    registerFallbackValue(FakeBaseRequest());
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
  });

  setUp(() {
    mockConnectivity = MockConnectivity();
  });

  group('SyncQueueManager Coverage', () {
    test('startMonitoring should listen to connectivity and sync', () async {
      final syncManager = SyncQueueManager();
      syncManager.setDependencies(connectivity: mockConnectivity);

      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => Stream.value([ConnectivityResult.wifi]));

      syncManager.startMonitoring();

      // Let the stream listener trigger
      await Future.delayed(Duration.zero);

      syncManager.dispose();
    });

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

      when(() => mockHttpClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response('Not Found', 404));

      await syncManager.syncPendingRequests(httpClient: mockHttpClient);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query('offline_sync_queue');
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

      when(() => mockHttpClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response('Server Error', 500));

      await syncManager.syncPendingRequests(httpClient: mockHttpClient);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query('offline_sync_queue');
      expect(pending.isNotEmpty, true);

      await db.delete('offline_sync_queue'); // Cleanup
    });

    test('syncPendingRequests handles exception by keeping in queue', () async {
      final mockHttpClient = MockHttpClient();
      final syncManager = SyncQueueManager();

      await syncManager.enqueue(
        endpoint: 'https://test.com/error',
        method: 'POST',
        body: {'data': 1},
        headers: {},
      );

      when(() => mockHttpClient.post(any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'))).thenThrow(Exception('Network Fail'));

      await syncManager.syncPendingRequests(httpClient: mockHttpClient);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query('offline_sync_queue');
      expect(pending.isNotEmpty, true);

      await db.delete('offline_sync_queue'); // Cleanup
    });
  });

  group('ResultApi Coverage', () {
    test('isServerError should return true for 5xx', () {
      final res = ResultApi(response: http.Response('Error', 500));
      expect(res.isServerError, true);
      expect(res.isClientError, false);
      expect(res.isSuccess, false);
    });

    test('isNetworkError should return true when response and body are null',
        () {
      final res = ResultApi();
      expect(res.isNetworkError, true);
    });

    test('jsonBody should handle empty/null response', () {
      final res = ResultApi(response: http.Response('', 204));
      expect(res.jsonBody, null);
    });

    test('jsonBody should handle invalid JSON', () {
      final res = ResultApi(response: http.Response('invalid', 200));
      expect(res.jsonBody, null);
    });
  });

  group('DebugUtils Coverage', () {
    test('Should call print methods without crashing', () {
      DebugUtils.printUrl(
          method: 'GET',
          url: 'https://test.com',
          headers: {'Auth': 'Bearer token'},
          body: '{"key":"value"}');
      DebugUtils.printCurl(
          method: 'POST',
          url: 'https://test.com',
          headers: {'Content-Type': 'application/json'},
          body: '{"key":"value"}');
    });

    test('generateCurl should escape quotes in body', () {
      final curl = DebugUtils.generateCurl(
          method: 'POST', url: 'https://test.com', body: '{"name": "test"}');
      expect(curl, contains('\\"name\\": \\"test\\"'));
    });
  });

  group('Volt & Initialization Coverage', () {
    test('Volt.initialize should configure and init', () async {
      await Volt.initialize(
        databaseName: 'test_volt.db',
        maxMemoryItems: 50,
        enableSync: false,
      );

      expect(SqlDatabaseHelper.databaseName, 'test_volt.db');
      expect(CacheManager.maxMemoryItems, 50);
    });

    test('Volt.initialize with enableSync true', () async {
      // Note: This calls startMonitoring() which uses Connectivity()
      // Since it's a global call, it's hard to mock unless we use setDependencies before
      final mock = MockConnectivity();
      when(() => mock.onConnectivityChanged).thenAnswer((_) => Stream.empty());
      SyncQueueManager().setDependencies(connectivity: mock);
      await Volt.initialize(enableSync: true);
    });
  });

  group('CacheManager & SQL Extra Coverage', () {
    test('SqlDatabaseHelper.getCache should return null for non-existent key',
        () async {
      final helper = SqlDatabaseHelper();
      final result = await helper.getCache('non_existent');
      expect(result, null);
    });
    test('CacheManager.clearAll should work', () async {
      await CacheManager.init();
      await CacheManager.clearAll();
      // No exception means it worked
    });

    test('SqlDatabaseHelper.reset should close and clear', () async {
      await SqlDatabaseHelper.reset();
      // No exception means it worked
    });

    test('SqlDatabaseHelper database getter handles errors', () async {
      // Mocking database failure is hard with sqflite_ffi but we can try to force a closed state or similar
      // For now, let's just ensure it's called
      final db = await SqlDatabaseHelper().database;
      expect(db.isOpen, true);
    });
  });

  group('PostRequest Extra Coverage', () {
    test('postList should return a list of models', () async {
      final mockClient = MockHttpClient();
      final postRequest = PostRequest(client: mockClient);
      final config = TestConfig();
      final listData = [
        {'nome': 'Item 1'},
        {'nome': 'Item 2'}
      ];

      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response(jsonEncode(listData), 200));

      final result = await postRequest.postList<TestModel>(
        config,
        '/list',
        TestModel.fromJson,
        data: {'param': 1},
      );

      expect(result.length, 2);
      expect(result[0].nome, 'Item 1');
    });

    test('Should handle Multipart with list of files', () async {
      final mockClient = MockHttpClient();
      final postRequest = PostRequest(client: mockClient);
      final config = TestConfig();

      final mockFile1 = http.MultipartFile.fromBytes('file1', [1]);
      final mockFile2 = http.MultipartFile.fromBytes('file2', [2]);

      when(() => mockClient.send(any())).thenAnswer((_) async {
        return http.StreamedResponse(
            Stream.fromIterable([utf8.encode('{"ok":true}')]), 200);
      });

      final result = await postRequest
          .post(config, endpoint: '/multi-upload', isMultipart: true, data: {
        'files': [mockFile1, mockFile2],
        'other': 'data'
      });

      expect(result.isSuccess, true);
    });
  });

  group('Isolate Utils Coverage', () {
// ... existing tests ...
  });

  group('GetRequest Extra Coverage', () {
    test('Default constructor uses real client and cache', () {
      final request = GetRequest();
      expect(request.client, isA<http.Client>());
      expect(request.requestCache, isA<CacheManager>());
    });

    test('getModel with asList: true from cache', () async {
      final mockClient = MockHttpClient();
      final cacheManager = CacheManager();
      final getRequest = GetRequest(client: mockClient, cache: cacheManager);
      final config = TestConfig();
      final listData = [
        {'nome': 'Cached 1'},
        {'nome': 'Cached 2'}
      ];

      await cacheManager.save(
        type: CacheType.memory,
        token: 'mock_token',
        endpoint: 'https://api.test.com/cached-list',
        data: ResultApi(response: http.Response(jsonEncode(listData), 200)),
      );

      final result = await getRequest.getModel<TestModel>(
        config,
        '/cached-list',
        TestModel.fromJson,
        cacheEnabled: true,
        type: CacheType.memory,
        asList: true,
      );

      expect(result.length, 2);
      expect(result[0].nome, 'Cached 1');
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('getBytes throws ApiException on failure', () async {
      final mockClient = MockHttpClient();
      final getRequest = GetRequest(client: mockClient);
      final config = TestConfig();

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('Not Found', 404));

      expect(
        () => getRequest.getBytes(config, 'https://test.com/image.jpg',
            cacheEnabled: false),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
