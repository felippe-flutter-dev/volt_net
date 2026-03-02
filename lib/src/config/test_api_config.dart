import '../../volt_net.dart';

class TestApiConfig extends BaseApiUrlConfig {
  @override
  String get baseUrl => 'www.testeurl.com';

  @override
  Future<String> getToken() async => 'teste';
}
