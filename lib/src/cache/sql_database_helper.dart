import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'sql_model.dart';

class SqlDatabaseHelper {
  static Database? _database;
  static Completer<Database>? _completer;
  static const String _cacheTable = 'api_cache';

  // Nome padrão do banco. Pode ser alterado para ':memory:' em testes.
  static String databaseName = 'volt_net_cache.db';

  /// Reseta a instância para testes
  static Future<void> reset() async {
    if (_database != null) {
      await _database!.close();
    }
    _database = null;
    _completer = null;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    // Se já estiver inicializando, aguarda o processo atual
    if (_completer != null) return _completer!.future;

    _completer = Completer<Database>();
    try {
      _database = await _initDatabase();
      _completer!.complete(_database);
      return _database!;
    } catch (e) {
      _completer!.completeError(e);
      _completer = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    String path;
    if (databaseName == ':memory:') {
      path = databaseName;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, databaseName);
    }

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Tabela de Cache Genérico
        await db.execute('''
          CREATE TABLE $_cacheTable (
            id_key TEXT PRIMARY KEY,
            body TEXT,
            status_code INTEGER,
            is_volatile INTEGER,
            created_at INTEGER
          )
        ''');

        // NOVA TABELA: Fila de Sincronização Offline
        await db.execute('''
          CREATE TABLE offline_sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            endpoint TEXT,
            method TEXT,
            body_payload TEXT,
            headers TEXT,
            created_at INTEGER
          )
        ''');
      },
    );
  }

  /// Garante que uma tabela exista baseado no esquema do SqlModel
  Future<void> _ensureTableExists(SqlModel model) async {
    final db = await database;
    final schema = model.tableSchema;
    final columns = schema.entries.map((e) => '${e.key} ${e.value}').join(', ');

    await db
        .execute('CREATE TABLE IF NOT EXISTS ${model.tableName} ($columns)');
  }

  /// Salva um modelo arbitrário em sua própria tabela dinâmica
  Future<void> saveModel(SqlModel model) async {
    await _ensureTableExists(model);
    final db = await database;
    await db.insert(
      model.tableName,
      model.toSqlMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Busca todos os registros de uma tabela específica
  Future<List<Map<String, dynamic>>> getModels(String tableName) async {
    final db = await database;
    try {
      return await db.query(tableName);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCache({
    required String key,
    required String body,
    required int statusCode,
    bool isVolatile = false,
  }) async {
    final db = await database;
    await db.insert(
      _cacheTable,
      {
        'id_key': key,
        'body': body,
        'status_code': statusCode,
        'is_volatile': isVolatile ? 1 : 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCache(String key) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _cacheTable,
      where: 'id_key = ?',
      whereArgs: [key],
    );

    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<void> clearVolatileCache() async {
    final db = await database;
    await db.delete(_cacheTable, where: 'is_volatile = ?', whereArgs: [1]);
  }

  Future<void> clearAll() async {
    final db = await database;
    // Limpa a tabela de cache principal
    await db.delete(_cacheTable);
  }
}
