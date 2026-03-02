import 'dart:convert';
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
  Future<String> getToken() async => 'token';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late PostRequest postRequest;

  setUpAll(() async {
    registerFallbackValue(FakeUri());
    registerFallbackValue(FakeBaseRequest());
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
  });

  setUp(() {
    mockClient = MockHttpClient();
    postRequest = PostRequest(client: mockClient);
  });

  group('PostRequest Tests', () {
    test('Should POST JSON and return Model', () async {
      final config = TestConfig();
      final mockData = {'name': 'New Manga'};
      final responseBody = jsonEncode(TestModel.mock().toJson());

      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response(responseBody, 201));

      final result = await postRequest.postModel<TestModel>(
        config,
        '/manga',
        TestModel.fromJson,
        data: mockData,
      );

      expect(result.model?.nome, 'Flutter Test');
      verify(() => mockClient.post(any(),
          headers: any(named: 'headers'),
          body: jsonEncode(mockData))).called(1);
    });

    test('Should handle Multipart POST with Fields and Files', () async {
      final config = TestConfig();

      // Criamos um MultipartFile mockado
      final mockFile = http.MultipartFile.fromBytes(
        'file',
        [1, 2, 3],
        filename: 'test.jpg',
      );

      final mockData = {
        'title': 'Manga Title',
        'image': mockFile,
      };

      // Mock para o send() do MultipartRequest
      when(() => mockClient.send(any())).thenAnswer((_) async {
        final response = http.StreamedResponse(
          Stream.fromIterable([utf8.encode('{"status": "ok"}')]),
          200,
        );
        return response;
      });

      final result = await postRequest.post(
        config,
        endpoint: '/upload',
        data: mockData,
        isMultipart: true,
      );

      expect(result.isSuccess, true);
      expect(result.jsonBody?['status'], 'ok');

      // Verifica se o send() foi chamado (Multipart usa send)
      verify(() => mockClient.send(any())).called(1);
    });

    test('Should throw ApiException on 500 Server Error', () async {
      final config = TestConfig();
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response('Server Error', 500));

      expect(
        () => postRequest.post(config, endpoint: '/fail'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });
}
