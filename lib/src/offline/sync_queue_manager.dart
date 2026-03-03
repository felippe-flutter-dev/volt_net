import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../volt_net.dart';

class SyncQueueManager {
  static final SyncQueueManager _instance = SyncQueueManager._internal();
  factory SyncQueueManager() => _instance;
  SyncQueueManager._internal();

  SqlDatabaseHelper _dbHelper = SqlDatabaseHelper();
  Connectivity _connectivity = Connectivity();
  StreamSubscription? _subscription;
  bool _isSyncing = false;

  /// Permite injetar dependências para testes
  @visibleForTesting
  void setDependencies(
      {Connectivity? connectivity, SqlDatabaseHelper? dbHelper}) {
    if (connectivity != null) _connectivity = connectivity;
    if (dbHelper != null) _dbHelper = dbHelper;
  }

  /// Inicia a observação da internet. Deve ser chamado no init do app.
  void startMonitoring() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      // Verifica se há alguma conexão ativa no array de resultados
      final hasConnection =
          results.any((result) => result != ConnectivityResult.none);
      if (hasConnection) {
        syncPendingRequests();
      }
    });
  }

  /// Adiciona uma requisição na fila offline
  Future<void> enqueue({
    required String endpoint,
    required String method,
    required dynamic body,
    required Map<String, String> headers,
  }) async {
    final db = await _dbHelper.database;
    await db.insert('offline_sync_queue', {
      'endpoint': endpoint,
      'method': method,
      'body_payload': jsonEncode(body),
      'headers': jsonEncode(headers),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    debugPrint('VoltNet: Request saved to offline queue ($endpoint)');
  }

  /// Processa a fila de pendências
  Future<void> syncPendingRequests({http.Client? httpClient}) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> pending =
          await db.query('offline_sync_queue', orderBy: 'created_at ASC');

      if (pending.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint(
          'VoltNet: Sincronizando ${pending.length} requisições pendentes...');

      final client = httpClient ?? http.Client();

      for (var row in pending) {
        final id = row['id'];
        final endpoint = row['endpoint'] as String;
        final method = row['method'] as String;
        final body = jsonDecode(row['body_payload']);
        final Map<String, String> headers =
            Map<String, String>.from(jsonDecode(row['headers']));

        try {
          http.Response response;
          final uri = Uri.parse(endpoint);

          if (method == 'POST') {
            response = await client.post(uri,
                headers: headers, body: jsonEncode(body));
          } else if (method == 'PUT') {
            response =
                await client.put(uri, headers: headers, body: jsonEncode(body));
          } else if (method == 'DELETE') {
            response = await client.delete(uri,
                headers: headers, body: jsonEncode(body));
          } else {
            continue;
          }

          if (response.statusCode >= 200 && response.statusCode < 300) {
            await db
                .delete('offline_sync_queue', where: 'id = ?', whereArgs: [id]);
            debugPrint('VoltNet: Sync success ($endpoint)');
          } else if (response.statusCode >= 400 && response.statusCode < 500) {
            // Erros do cliente (401, 404, etc) não devem ser retentados eternamente
            await db
                .delete('offline_sync_queue', where: 'id = ?', whereArgs: [id]);
            debugPrint(
                'VoltNet: Fatal error in sync ($endpoint). Removed from queue.');
          }
        } on http.ClientException catch (e) {
          debugPrint(
              'VoltNet: Network failure in sync for item $id: $e. Retrying later.');
          break;
        } catch (e) {
          // Erro genérico (ex: falha no parse ou banco), mantém na fila para segurança
          debugPrint(
              'VoltNet: Unexpected error syncing item $id: $e. Retrying later.');
          break;
        }
      }
      client.close();
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
