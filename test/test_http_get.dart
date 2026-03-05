import 'dart:convert';
import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';

class MockHttpClient extends Mock implements Client {}

class FakeUri extends Fake implements Uri {}

class _TestApiConfig extends BaseApiUrlConfig {
  @override
  Future<String> getToken() async => 'teste';

  @override
  Future<Map<String, String>> getHeader() async => Future.value({
        'Authorization': 'Bearer ${await getToken()}',
        'Content-Type': 'application/json',
      });

  @override
  String resolveBaseUrl() => 'https://www.testeurl.com';
}

class _TesteRepo {
  final GetRequest _getRequest;

  _TesteRepo(this._getRequest);

  Future<TestModel?> getTestModel() async {
    final config = _TestApiConfig();
    final result = await _getRequest.getModel<TestModel>(
      config,
      '/test',
      TestModel.fromJson,
      cacheEnabled: true,
      type: CacheType.both,
    );
    return result;
  }

  Future<List<TestModel>> getTestModelList() async {
    final config = _TestApiConfig();
    final result = await _getRequest.getModel<TestModel>(
      config,
      '/test-list',
      TestModel.fromJson,
      cacheEnabled: true,
      asList: true,
      type: CacheType.both,
    );
    return (result as List).cast<TestModel>();
  }
}

void main() {
  late _TesteRepo testeRepo;
  late MockHttpClient mockClient;
  late GetRequest getRequest;
  late CacheManager cacheManager;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerFallbackValue(FakeUri());
    await CacheManager.init();
    cacheManager = CacheManager();
    mockClient = MockHttpClient();
    getRequest = GetRequest(client: mockClient, cache: cacheManager);
    testeRepo = _TesteRepo(getRequest);
  });

  group('Testando GET', () {
    test('Deve retornar o objeto Teste', () async {
      final jsonResponse = jsonEncode(TestModel.mock().toJson());
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => Response(jsonResponse, 200));

      final result = await testeRepo.getTestModel();

      expect(result?.nome, 'Flutter Test',
          reason: 'Retornado: ${result?.nome}');

      verify(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).called(1);
    });

    test(
      'Deve retornar uma lista do objeto Teste',
      () async {
        final jsonResponse =
            jsonEncode(TestModel.mockList().map((e) => e.toJson()).toList());
        when(
          () => mockClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => Response(jsonResponse, 200),
        );

        final result = await testeRepo.getTestModelList();

        expect(result[0].nome, contains('Flutter Test 1'));
        expect(result[1].nome, contains('Flutter Test 2'));

        verify(() => mockClient.get(any(), headers: any(named: 'headers')))
            .called(1);
      },
    );
  });
}
