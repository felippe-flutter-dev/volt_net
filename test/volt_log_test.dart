import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:volt_net/volt_net.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

class _TestApiConfig extends BaseApiUrlConfig {
  @override
  Future<String> getToken() async => 'test_token';
  @override
  Future<Map<String, String>> getHeader() async => {
        'Authorization': 'Bearer test_token',
      };
  @override
  String resolveBaseUrl() => 'https://api.test.com';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late _TestApiConfig apiConfig;
  final List<String> capturedLogs = [];

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
    // Override debugPrint to capture logs
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) capturedLogs.add(message);
    };
  });

  setUp(() async {
    mockClient = MockHttpClient();
    apiConfig = _TestApiConfig();
    capturedLogs.clear();

    // Reset Volt state to default (logging false)
    await Volt.initialize(logging: false, enableSync: false);
  });

  group('VoltLog & Logging Flag Tests', () {
    test('Should NOT capture logs when logging is false', () async {
      VoltLog.d('Secret message');
      VoltLog.i('Info message');

      expect(
          capturedLogs.any((log) => log.contains('Secret message')), isFalse);
      expect(capturedLogs.any((log) => log.contains('Info message')), isFalse);
    });

    test('Should capture ERROR logs even if logging is false', () async {
      VoltLog.e('Critical error');
      expect(capturedLogs.any((log) => log.contains('Critical error')), isTrue);
    });

    test('Should capture all logs when logging is true', () async {
      await Volt.initialize(logging: true, enableSync: false);

      VoltLog.d('Debug message');
      VoltLog.i('Info message');

      expect(capturedLogs.any((log) => log.contains('Debug message')), isTrue);
      expect(capturedLogs.any((log) => log.contains('Info message')), isTrue);
    });

    test('GET request should produce detailed logs when enabled', () async {
      await Volt.initialize(logging: true, enableSync: false);
      final getRequest = GetRequest(client: mockClient);

      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable(['{"status": "ok"}'.codeUnits]), 200));

      await getRequest.get(apiConfig, 'test-endpoint');

      // Verify DebugUtils usage
      expect(capturedLogs.any((log) => log.contains('REQUEST: GET')), isTrue);
      expect(capturedLogs.any((log) => log.contains('CURL')), isTrue);
      expect(capturedLogs.any((log) => log.contains('RESPONSE')), isTrue);
      expect(
          capturedLogs.any((log) => log.contains('Status Code: 200')), isTrue);
      expect(
          capturedLogs.any((log) => log.contains('{"status": "ok"}')), isTrue);
    });

    test('POST request should produce detailed logs when enabled', () async {
      await Volt.initialize(logging: true, enableSync: false);
      final postRequest = PostRequest(client: mockClient);

      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable(['{"created": true}'.codeUnits]), 201));

      await postRequest
          .post(apiConfig, endpoint: 'create', data: {'name': 'Volt'});

      expect(capturedLogs.any((log) => log.contains('REQUEST: POST')), isTrue);
      expect(capturedLogs.any((log) => log.contains('CURL')), isTrue);
      expect(capturedLogs.any((log) => log.contains('curl -X POST')), isTrue);
      expect(
          capturedLogs.any((log) => log.contains('{"name":"Volt"}')), isTrue);
      expect(
          capturedLogs.any((log) => log.contains('Status Code: 201')), isTrue);
    });

    test('PUT request should produce detailed logs when enabled', () async {
      await Volt.initialize(logging: true, enableSync: false);
      final putRequest = PutRequest(client: mockClient);

      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable(['{"updated": true}'.codeUnits]), 200));

      await putRequest.put(apiConfig, endpoint: 'update', data: {'id': 1});

      expect(capturedLogs.any((log) => log.contains('REQUEST: PUT')), isTrue);
      expect(capturedLogs.any((log) => log.contains('update')), isTrue);
      expect(
          capturedLogs.any((log) => log.contains('Status Code: 200')), isTrue);
    });

    test('DELETE request should produce detailed logs when enabled', () async {
      await Volt.initialize(logging: true, enableSync: false);
      final deleteRequest = DeleteRequest(client: mockClient);

      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(Stream.fromIterable([''.codeUnits]), 204));

      await deleteRequest.delete(apiConfig, endpoint: 'delete/1');

      expect(
          capturedLogs.any((log) => log.contains('REQUEST: DELETE')), isTrue);
      expect(capturedLogs.any((log) => log.contains('delete/1')), isTrue);
      expect(
          capturedLogs.any((log) => log.contains('Status Code: 204')), isTrue);
    });
  });
}
