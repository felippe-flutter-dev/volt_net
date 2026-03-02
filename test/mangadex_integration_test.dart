import 'dart:convert';
import 'package:volt_net/volt_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

class MangaDexConfig extends BaseApiUrlConfig {
  @override
  String get baseUrl => 'https://api.mangadex.org';
  @override
  Future<String> getToken() async => '';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late GetRequest getRequest;
  late CacheManager cacheManager;
  late MockHttpClient mockClient;

  setUpAll(() async {
    registerFallbackValue(FakeUri());
    // Configura o banco de dados para rodar na RAM (Zero Locks, Alta velocidade)
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
  });

  setUp(() async {
    mockClient = MockHttpClient();
    await CacheManager.init();
    await CacheManager.clearAll();
    cacheManager = CacheManager();
    getRequest = GetRequest(client: mockClient, cache: cacheManager);
  });

  group('MangaDex Mocked Integration (FINAL)', () {
    test('Deve processar busca complexa do MangaDex e salvar em cache',
        () async {
      final config = MangaDexConfig();
      final mockResponse = {
        'data': [
          {
            'id': 'manga-123',
            'attributes': {
              'title': {'en': 'Mock Manga'}
            },
            'relationships': [
              {
                'type': 'cover_art',
                'attributes': {'fileName': 'cover.jpg'}
              }
            ]
          }
        ]
      };

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
              (_) async => http.Response(jsonEncode(mockResponse), 200));

      final params = {
        'limit': 1,
        'translatedLanguage[]': ['pt-br'],
        'includes[]': ['cover_art'],
      };

      final result = await getRequest.get(
        config,
        '/manga',
        queryParameters: params,
        cacheEnabled: true,
        type: CacheType.disk,
      );

      expect(result.jsonBody!['data'][0]['id'], 'manga-123');

      final cachedResult = await getRequest.get(
        config,
        '/manga',
        queryParameters: params,
        cacheEnabled: true,
        type: CacheType.disk,
      );

      expect(cachedResult.bodyAsString, result.bodyAsString);
      verify(() => mockClient.get(any(), headers: any(named: 'headers')))
          .called(1);
    });

    test('Deve lidar com download de bytes via cache', () async {
      final config = MangaDexConfig();
      const imageUrl = 'https://uploads.mangadex.org/covers/123/cover.jpg';
      final mockBytes = List<int>.generate(100, (i) => i);

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response.bytes(mockBytes, 200));

      final bytes =
          await getRequest.getBytes(config, imageUrl, cacheEnabled: true);
      expect(bytes, mockBytes);

      final cachedBytes =
          await getRequest.getBytes(config, imageUrl, cacheEnabled: true);
      expect(cachedBytes, mockBytes);

      verify(() => mockClient.get(any(), headers: any(named: 'headers')))
          .called(1);
    });
  });
}
