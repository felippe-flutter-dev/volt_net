import 'dart:convert';
import 'dart:io';
import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends Mock implements Client {}

class FakeBaseRequest extends Fake implements BaseRequest {}

class TestApiConfig extends BaseApiUrlConfig {
  @override
  Future<String> getToken() async => 'mock_token';
  @override
  Future<Map<String, String>> getHeader() async => {
        'Authorization': 'Bearer ${await getToken()}',
        'Content-Type': 'application/json',
      };
  @override
  String resolveBaseUrl() => 'https://api.voltnet.com';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late PostRequest postRequest;
  late TestApiConfig apiConfig;

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
    SqlDatabaseHelper.databaseName = ':memory:';
    // Cria um arquivo temporário para os testes de multipart
    File('test.png').writeAsBytesSync([0, 1, 2, 3]);
  });

  tearDownAll(() {
    if (File('test.png').existsSync()) {
      File('test.png').deleteSync();
    }
  });

  setUp(() async {
    mockClient = MockHttpClient();
    postRequest = PostRequest(client: mockClient);
    apiConfig = TestApiConfig();
    await SqlDatabaseHelper.reset();
  });

  group('PostRequest v2.0 - Core & Models', () {
    test('postModel should parse JSON into a Model', () async {
      final mockResponse = TestModel.mock().toJson();

      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode(jsonEncode(mockResponse))]),
                200,
              ));

      final result = await postRequest.postModel<TestModel>(
        apiConfig,
        '/manga',
        TestModel.fromJson,
        data: {'id': 1},
      );

      expect(result.model, isNotNull);
      expect(result.model!.nome, 'Flutter Test');
      expect(result.isSuccess, true);
    });

    test('post with Multipart should send correctly', () async {
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('{"ok":true}')]),
                201,
              ));

      final result = await postRequest.post(
        apiConfig,
        endpoint: '/upload',
        data: {'image': VoltFile(path: 'test.png')},
        isMultipart: true,
      );

      expect(result.isSuccess, true);
      verify(() => mockClient.send(any())).called(1);
    });
  });

  group('PostRequest v2.0 - Funcionalidades Avançadas', () {
    test('ResilientBatch: Deve interromper o fluxo no passo 2', () async {
      when(() => mockClient.send(any())).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as BaseRequest;
        if (request.url.toString().contains('/fail')) {
          return StreamedResponse(
              Stream.fromIterable([utf8.encode('{"error":"Bad"}')]), 400);
        }
        return StreamedResponse(
            Stream.fromIterable([utf8.encode('{"ok":true}')]), 200);
      });

      expect(
        () => postRequest.resilientBatch([
          ({extraHeaders}) => postRequest.post(apiConfig,
              endpoint: '/step1', extraHeaders: extraHeaders),
          ({extraHeaders}) => postRequest.post(apiConfig,
              endpoint: '/fail', extraHeaders: extraHeaders),
          ({extraHeaders}) => postRequest.post(apiConfig,
              endpoint: '/step3', extraHeaders: extraHeaders),
        ]),
        throwsA(isA<VoltNetException>()
            .having((e) => e.message, 'message', contains('step 2'))),
      );
    });
  });
}
