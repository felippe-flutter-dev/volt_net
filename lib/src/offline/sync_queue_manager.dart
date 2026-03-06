import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../../volt_net.dart';

/// [SyncQueueManager] handles the offline synchronization logic.
///
/// It monitors connectivity and retries failed requests with exponential backoff.
class SyncQueueManager {
  static SyncQueueManager? _customInstance;
  static final SyncQueueManager _singleton = SyncQueueManager._internal();

  /// Returns the singleton instance or a custom mock instance if set via [setMock].
  factory SyncQueueManager() => _customInstance ?? _singleton;

  SyncQueueManager._internal();

  /// Allows injecting a mock instance for testing.
  static void setMock(SyncQueueManager? mock) {
    _customInstance = mock;
  }

  SqlDatabaseHelper _dbHelper = SqlDatabaseHelper();
  Connectivity _connectivity = Connectivity();
  http.Client? _httpClient;
  StreamSubscription? _subscription;
  Timer? _fallbackTimer;
  bool _isSyncing = false;

  static const int maxRetries = 5;
  static const int baseDelaySeconds = 10;

  final StreamController<String> _syncController =
      StreamController<String>.broadcast();

  /// Stream that emits the endpoint URL whenever a request is successfully synced.
  Stream<String> get syncStream => _syncController.stream;

  final StreamController<void> _queueFinishedController =
      StreamController<void>.broadcast();

  /// Stream that notifies when the entire synchronization queue has been processed.
  Stream<void> get onQueueFinished => _queueFinishedController.stream;

  /// Injects dependencies for testing or custom configurations.
  void setDependencies(
      {Connectivity? connectivity,
      SqlDatabaseHelper? dbHelper,
      http.Client? httpClient}) {
    if (connectivity != null) _connectivity = connectivity;
    if (dbHelper != null) _dbHelper = dbHelper;
    if (httpClient != null) _httpClient = httpClient;
  }

  /// Starts monitoring network changes and sets up a periodic fallback timer.
  void startMonitoring() {
    _subscription?.cancel();
    _fallbackTimer?.cancel();

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection =
          results.any((result) => result != ConnectivityResult.none);
      if (hasConnection) {
        syncPendingRequests();
      }
    });

    _fallbackTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncPendingRequests();
    });
  }

  /// Adds a request to the offline queue to be synced later.
  ///
  /// [endpoint] The full URL of the request.
  /// [method] The HTTP method (POST, PUT, DELETE).
  /// [body] The payload data.
  /// [headers] HTTP headers to be included.
  Future<void> enqueue({
    required String endpoint,
    required String method,
    required dynamic body,
    required Map<String, String> headers,
    bool isMultipart = false,
    List<String>? filePaths,
  }) async {
    final db = await _dbHelper.database;
    await db.insert(SqlDatabaseHelper.syncTable, {
      'endpoint': endpoint,
      'method': method,
      'body_payload': body != null ? jsonEncode(body) : null,
      'headers': jsonEncode(headers),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'retries': 0,
      'last_attempt': 0,
      'is_multipart': isMultipart ? 1 : 0,
      'file_paths': filePaths != null ? jsonEncode(filePaths) : null,
    });
    VoltLog.i('Request saved to offline queue ($endpoint)');
  }

  /// Attempts to sync all pending requests in the database.
  Future<void> syncPendingRequests({http.Client? httpClient}) async {
    if (_isSyncing) return;
    _isSyncing = true;

    final client = httpClient ?? _httpClient ?? http.Client();

    try {
      final db = await _dbHelper.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      final List<Map<String, dynamic>> pending = await db.query(
          SqlDatabaseHelper.syncTable,
          where: 'retries < ?',
          whereArgs: [maxRetries],
          orderBy: 'created_at ASC');

      if (pending.isEmpty) {
        return;
      }

      for (var row in pending) {
        final id = row['id'];
        final retries = row['retries'] as int;
        final lastAttempt = row['last_attempt'] as int;

        if (retries > 0) {
          final delay = pow(2, retries) * baseDelaySeconds * 1000;
          if (now - lastAttempt < delay) continue;
        }

        final endpoint = row['endpoint'] as String;
        final method = row['method'] as String;
        final isMultipart = (row['is_multipart'] as int?) == 1;
        final bodyPayload = row['body_payload'];
        final filePathsPayload = row['file_paths'];

        final Map<String, String> headers =
            Map<String, String>.from(jsonDecode(row['headers']));
        final uri = Uri.parse(endpoint);

        try {
          http.Response response;
          http.BaseRequest request;

          if (isMultipart) {
            final multipartRequest = http.MultipartRequest(method, uri);
            multipartRequest.headers.addAll(headers);

            if (bodyPayload != null) {
              final fields = jsonDecode(bodyPayload) as Map<String, dynamic>;
              fields
                  .forEach((k, v) => multipartRequest.fields[k] = v.toString());
            }

            if (filePathsPayload != null) {
              final paths = List<String>.from(jsonDecode(filePathsPayload));
              for (var path in paths) {
                multipartRequest.files
                    .add(await http.MultipartFile.fromPath('file', path));
              }
            }
            request = multipartRequest;
          } else {
            final standardRequest = http.Request(method, uri);
            standardRequest.headers.addAll(headers);
            if (bodyPayload != null) {
              standardRequest.body =
                  bodyPayload is String ? bodyPayload : jsonEncode(bodyPayload);
            }
            request = standardRequest;
          }

          final streamedResponse = await client.send(request);
          response = await http.Response.fromStream(streamedResponse);

          if (response.statusCode >= 200 && response.statusCode < 300) {
            await db.delete(SqlDatabaseHelper.syncTable,
                where: 'id = ?', whereArgs: [id]);
            VoltLog.i('Sync success ($endpoint)');
            _syncController.add(endpoint);
          } else if (response.statusCode >= 400 &&
              response.statusCode < 500 &&
              response.statusCode != 429) {
            await db.delete(SqlDatabaseHelper.syncTable,
                where: 'id = ?', whereArgs: [id]);
            VoltLog.w(
                'Sync aborted for $endpoint (Client Error: ${response.statusCode})');
          } else {
            await _incrementRetry(id, retries);
            VoltLog.w(
                'Sync failed for $endpoint (Status: ${response.statusCode}). Retrying later...');
          }
        } catch (e) {
          await _incrementRetry(id, retries);
          VoltLog.e('Unexpected error syncing item $id', e);
          break;
        }
      }
    } finally {
      if (httpClient == null && _httpClient == null) client.close();
      _isSyncing = false;
      _queueFinishedController.add(null);
    }
  }

  Future<void> _incrementRetry(int id, int currentRetries) async {
    final db = await _dbHelper.database;
    await db.update(
        SqlDatabaseHelper.syncTable,
        {
          'retries': currentRetries + 1,
          'last_attempt': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  /// Resets the manager state for testing purposes.
  void reset() {
    dispose();
    _isSyncing = false;
    _httpClient = null;
  }

  /// Disposes resources and cancels active subscriptions/timers.
  void dispose() {
    _subscription?.cancel();
    _fallbackTimer?.cancel();
  }
}
