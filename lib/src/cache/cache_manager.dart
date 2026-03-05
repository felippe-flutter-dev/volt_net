import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../volt_net.dart';

/// Internal entry for the L1 (Memory) cache to track TTL.
class _MemoryCacheEntry {
  final ResultApi data;
  final int createdAt;

  _MemoryCacheEntry(this.data, this.createdAt);
}

/// [CacheManager] is the core engine for the Hybrid Cache architecture (L1/L2).
///
/// It manages an in-memory [Map] for lightning-fast access (L1) and a SQLite
/// database for persistent storage (L2).
class CacheManager {
  /// Maximum number of items allowed in the RAM cache ([L1]).
  static int maxMemoryItems = 100;

  /// Internal L1 cache storage with TTL tracking.
  /// Uses Map insertion order to implement LRU (Least Recently Used).
  static final Map<String, _MemoryCacheEntry> _memoryCache = {};

  /// Instance of [SqlDatabaseHelper] used for L2 (Disk) operations.
  late final SqlDatabaseHelper _dbHelper;

  /// Creates a [CacheManager] instance.
  CacheManager({SqlDatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? SqlDatabaseHelper();

  /// Initializes the caching system.
  static Future<void> init({SqlDatabaseHelper? dbHelper}) async {
    final helper = dbHelper ?? SqlDatabaseHelper();
    await helper.clearVolatileCache();
  }

  /// Generates a secure SHA-256 hash to be used as a cache key.
  /// Includes the [token] to ensure user isolation and privacy.
  String _generateKey(String token, String endpoint, {String? cacheGroup}) {
    final base = cacheGroup ?? endpoint;
    final rawKey = '$token:$base';

    final bytes = utf8.encode(rawKey);
    final digest = sha256.convert(bytes);

    return digest.toString();
  }

  /// Retrieves a [ResultApi] from the cache.
  Future<ResultApi?> get({
    required CacheType? type,
    required String token,
    required String endpoint,
    String? cacheGroup,
    Duration? ttl,
  }) async {
    if (type == null) return null;

    final key = _generateKey(token, endpoint, cacheGroup: cacheGroup);
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Try RAM first (L1) with TTL validation
    if (type == CacheType.memory || type == CacheType.both) {
      final entry = _memoryCache[key];
      if (entry != null) {
        if (ttl == null || (now - entry.createdAt <= ttl.inMilliseconds)) {
          // Promote to "Recently Used" by re-inserting
          _memoryCache.remove(key);
          _memoryCache[key] = entry;
          return entry.data;
        } else {
          _memoryCache.remove(key); // Expired in L1
        }
      }
    }

    // 2. Try Disk (L2)
    final map = await _dbHelper.getCache(key);

    if (map != null) {
      final createdAt = map['created_at'] as int;
      if (ttl != null && (now - createdAt > ttl.inMilliseconds)) {
        await _dbHelper.deleteCache(key);
        return null;
      }

      final result = ResultApi(
        response: Response(map['body'], map['status_code']),
      );

      // Promote to L1
      if (type != CacheType.disk) {
        _saveToMemory(key, result, createdAt);
      }
      return result;
    }

    return null;
  }

  void _saveToMemory(String key, ResultApi data, int createdAt) {
    // LRU: If key exists, remove to re-insert at the end
    if (_memoryCache.containsKey(key)) {
      _memoryCache.remove(key);
    } else if (_memoryCache.length >= maxMemoryItems) {
      // Remove the oldest (first) item
      final firstKey = _memoryCache.keys.first;
      _memoryCache.remove(firstKey);
    }
    _memoryCache[key] = _MemoryCacheEntry(data, createdAt);
  }

  /// Saves a [ResultApi] into the specified cache levels.
  Future<void> save({
    required CacheType type,
    required String token,
    required String endpoint,
    required ResultApi data,
    String? cacheGroup,
  }) async {
    final key = _generateKey(token, endpoint, cacheGroup: cacheGroup);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (type == CacheType.memory || type == CacheType.both) {
      _saveToMemory(key, data, now);
    }

    if (type == CacheType.disk || type == CacheType.both) {
      await _dbHelper.saveCache(
        key: key,
        body: data.bodyAsString ?? '',
        statusCode: data.statusCode,
        isVolatile: type == CacheType.memory,
      );
    }
  }

  /// Persists a custom [SqlModel] into its corresponding dynamic table.
  Future<void> saveModel(SqlModel model) async {
    await _dbHelper.saveModel(model);
  }

  /// Fetches raw data from a specific [tableName].
  Future<List<Map<String, dynamic>>> getModels(String tableName) async {
    return await _dbHelper.getModels(tableName);
  }

  /// Wipes only the memory cache.
  static void clearMemory() {
    _memoryCache.clear();
  }

  /// Wipes all data from both [L1] and [L2] caches.
  static Future<void> clearAll({SqlDatabaseHelper? dbHelper}) async {
    _memoryCache.clear();
    final helper = dbHelper ?? SqlDatabaseHelper();
    await helper.clearAll();
  }
}
