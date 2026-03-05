/// Base configuration class for API URL management.
///
/// This class should be extended to provide specific API configurations,
/// such as base URLs, headers, and authentication tokens.
abstract class BaseApiUrlConfig {
  /// Returns the base URL for the API.
  String resolveBaseUrl();

  /// Returns the headers to be included in the requests.
  Future<Map<String, String>> getHeader();

  /// Returns the authentication token, if any.
  Future<String> getToken();
}
