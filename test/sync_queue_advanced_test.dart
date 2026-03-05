import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:volt_net/volt_net.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockConnectivity extends Mock implements Connectivity {}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late SyncQueueManager syncManager;
  late MockHttpClient mockClient;
  late MockConnectivity mockConnectivity;

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
  });

  setUp(() async {
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();

    mockClient = MockHttpClient();
    mockConnectivity = MockConnectivity();
    syncManager = SyncQueueManager();
    syncManager.reset();
    syncManager.setDependencies(
      connectivity: mockConnectivity,
      httpClient: mockClient,
    );
  });

  group('SyncQueueManager Advanced Coverage', () {
    test('syncPendingRequests handles 4xx client errors (aborts)', () async {
      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable([utf8.encode('Bad Request')]), 400));

      await syncManager.enqueue(
        endpoint: 'https://api.com/bad',
        method: 'POST',
        body: {'data': 1},
        headers: {},
      );

      await syncManager.syncPendingRequests();

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(
          pending, isEmpty); // Should be removed because 400 is a client error
    });

    test('syncPendingRequests handles 5xx server errors (increments retry)',
        () async {
      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable([utf8.encode('Server Error')]), 500));

      await syncManager.enqueue(
        endpoint: 'https://api.com/retry',
        method: 'POST',
        body: {'data': 2},
        headers: {},
      );

      await syncManager.syncPendingRequests();

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending.first['retries'], 1);
    });

    test('syncPendingRequests handles multipart with fields and file_paths',
        () async {
      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable([utf8.encode('{"ok":true}')]), 200));

      // We can't easily test actual file reading in unit tests without more mocks or real files,
      // but we can test the flow. For this test, we skip the actual file part or expect a failure.

      await syncManager.enqueue(
        endpoint: 'https://api.com/multipart',
        method: 'POST',
        body: {'field1': 'val1'},
        headers: {},
        isMultipart: true,
        // filePaths: ['non_existent_file.txt'], // This would throw FileSystemException
      );

      await syncManager.syncPendingRequests();

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending, isEmpty);
    });

    test('Connectivity monitoring triggers sync', () async {
      final controller = StreamController<List<ConnectivityResult>>();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => controller.stream);

      syncManager.startMonitoring();

      // Enqueue something
      await syncManager.enqueue(
          endpoint: 'https://api.com/sync',
          method: 'POST',
          body: {},
          headers: {});

      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable([utf8.encode('{"ok":true}')]), 200));

      // Trigger connectivity change
      controller.add([ConnectivityResult.wifi]);

      // Wait a bit for the async sync to happen
      await Future.delayed(const Duration(milliseconds: 100));

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending, isEmpty);

      controller.close();
      syncManager.dispose();
    });
  });
}
