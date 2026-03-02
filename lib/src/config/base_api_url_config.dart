abstract class BaseApiUrlConfig {
  String get baseUrl;

  String resolveBaseUrl() => baseUrl;

  Future<String> getToken();

  Future<Map<String, String>> getHeader() async => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await getToken()}',
      };
}
