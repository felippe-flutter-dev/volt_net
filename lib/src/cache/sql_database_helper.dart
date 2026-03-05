import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'sql_model.dart';

class SqlDatabaseHelper {
  static Database? _database;
  static Completer<Database>? _completer;

  static const String cacheTable = 'api_cache';
  static const String syncTable = 'offline_sync_queue';

  static String databaseName = 'volt_net_cache.db';

  /// Permite injetar uma instância de Database para testes ou configurações avançadas.
  final Database? _injectedDatabase;
  SqlDatabaseHelper({Database? database}) : _injectedDatabase = database;

  Future<Database> get database async {
    if (_injectedDatabase != null) return _injectedDatabase!;
    if (_database != null) return _database!;
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
    final dbPath = databaseName == ':memory:'
        ? ':memory:'
        : join(await getDatabasesPath(), databaseName);

    return await openDatabase(
      dbPath,
      version: 6, // Incrementado para nova mecânica de arquivos
      onCreate: (db, version) async {
        await _executeV1(db);
        for (int i = 2; i <= version; i++) {
          await _runMigration(db, i);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        for (int i = oldVersion + 1; i <= newVersion; i++) {
          await _runMigration(db, i);
        }
      },
    );
  }

  Future<void> _executeV1(Database db) async {
    await db.execute('''
      CREATE TABLE $cacheTable (
        id_key TEXT PRIMARY KEY,
        body TEXT,
        status_code INTEGER,
        is_volatile INTEGER,
        created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint TEXT,
        method TEXT,
        body_payload TEXT,
        headers TEXT,
        created_at INTEGER
      )
    ''');
  }

  /// Centraliza todas as migrações de forma sequencial e segura.
  Future<void> _runMigration(Database db, int version) async {
    switch (version) {
      case 2:
        // Caso a tabela syncTable não tenha sido criada no onCreate original
        await db.execute(
            'CREATE TABLE IF NOT EXISTS $syncTable (id INTEGER PRIMARY KEY AUTOINCREMENT, endpoint TEXT, method TEXT, body_payload TEXT, headers TEXT, created_at INTEGER)');
        break;
      case 3:
        await db.execute(
            'ALTER TABLE $syncTable ADD COLUMN retries INTEGER DEFAULT 0');
        break;
      case 4:
        await db.execute(
            'ALTER TABLE $syncTable ADD COLUMN last_attempt INTEGER DEFAULT 0');
        break;
      case 5:
        await db.execute(
            'ALTER TABLE $syncTable ADD COLUMN is_multipart INTEGER DEFAULT 0');
        break;
      case 6:
        // Adiciona suporte para caminhos de arquivos em multipart
        await db.execute('ALTER TABLE $syncTable ADD COLUMN file_paths TEXT');
        break;
    }
  }

  // ... Métodos de CRUD (saveCache, getCache, etc) continuam os mesmos,
  // mas agora usam o getter `database` que suporta injeção.

  Future<void> saveCache(
      {required String key,
      required String body,
      required int statusCode,
      bool isVolatile = false}) async {
    final db = await database;
    await db.insert(
        cacheTable,
        {
          'id_key': key,
          'body': body,
          'status_code': statusCode,
          'is_volatile': isVolatile ? 1 : 0,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getCache(String key) async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query(cacheTable, where: 'id_key = ?', whereArgs: [key]);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<void> deleteCache(String key) async {
    final db = await database;
    await db.delete(cacheTable, where: 'id_key = ?', whereArgs: [key]);
  }

  Future<void> clearVolatileCache() async {
    final db = await database;
    await db.delete(cacheTable, where: 'is_volatile = ?', whereArgs: [1]);
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete(cacheTable);
  }

  Future<void> saveModel(SqlModel model) async {
    final db = await database;
    await db.execute(
        'CREATE TABLE IF NOT EXISTS ${model.tableName} (${model.tableSchema.entries.map((e) => "${e.key} ${e.value}").join(", ")})');
    await db.insert(model.tableName, model.toSqlMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getModels(String tableName) async {
    final db = await database;
    try {
      return await db.query(tableName);
    } catch (_) {
      return [];
    }
  }

  static Future<void> reset() async {
    if (_database != null) {
      await _database!.close();
    }
    _database = null;
    _completer = null;
  }
}
