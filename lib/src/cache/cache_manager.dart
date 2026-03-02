import 'package:http/http.dart' as http;
import '../../volt_net.dart';

class CacheManager {
  // Limite de itens na memória RAM (L1) para evitar Memory Leak - Agora configurável
  static int maxMemoryItems = 100;

  // Mantemos um Map estático para acesso instantâneo durante a sessão (L1)
  static final Map<String, ResultApi> _memoryCache = {};

  // Instância do SQL Helper (L2)
  static final SqlDatabaseHelper _dbHelper = SqlDatabaseHelper();

  /// MÉTODO CRÍTICO: Deve ser chamado no main() do seu app:
  /// await CacheManager.init();
  static Future<void> init() async {
    // Inicializa o banco e limpa caches voláteis (marcados como memory no disco)
    await _dbHelper.clearVolatileCache();
  }

  // Gera a chave única.
  String _generateKey(String token, String endpoint) {
    // O token e endpoint garantem que o dado retornado seja específico para esse usuário e essa rota
    return '${token.hashCode}_$endpoint';
  }

  Future<ResultApi?> get({
    required CacheType? type,
    required String token,
    required String endpoint,
    Duration? ttl,
  }) async {
    if (type == null) return null;

    final key = _generateKey(token, endpoint);

    // 1. Tenta RAM primeiro (L1) - Super rápido
    if (type == CacheType.memory || type == CacheType.both) {
      if (_memoryCache.containsKey(key)) {
        return _memoryCache[key];
      }
    }

    // 2. Tenta Disco (L2) - SQLite
    // A busca é automática pelo ID gerado via endpoint/token
    final map = await _dbHelper.getCache(key);

    if (map != null) {
      // Verifica TTL se fornecido (tempo de validade do dado)
      if (ttl != null) {
        final createdAt = map['created_at'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - createdAt > ttl.inMilliseconds) {
          // Cache expirado - O sistema vai buscar novo dado na API automaticamente via GetRequest
          return null;
        }
      }

      final result = ResultApi(
        response: http.Response(map['body'], map['status_code']),
      );

      // Se achou no disco e o tipo era memory/both, sobe para RAM para o próximo acesso
      if (type != CacheType.disk) {
        _manageMemoryGrowth();
        _memoryCache[key] = result;
      }
      return result;
    }

    return null;
  }

  /// Gerencia o crescimento da RAM para evitar leaks
  void _manageMemoryGrowth() {
    if (_memoryCache.length >= maxMemoryItems) {
      // Remove o item mais antigo (primeiro no Map)
      final firstKey = _memoryCache.keys.first;
      _memoryCache.remove(firstKey);
    }
  }

  Future<void> save({
    required CacheType type,
    required String token,
    required String endpoint,
    required ResultApi data,
  }) async {
    final key = _generateKey(token, endpoint);

    // Salva na RAM (L1)
    if (type == CacheType.memory || type == CacheType.both) {
      _manageMemoryGrowth();
      _memoryCache[key] = data;
    }

    // Salva no Disco (L2) - Persistência Real e Pesquisável automaticamente
    if (type == CacheType.disk || type == CacheType.both) {
      await _dbHelper.saveCache(
        key: key,
        body: data.bodyAsString ?? '',
        statusCode: data.statusCode,
        isVolatile: type == CacheType.memory,
      );
    }
  }

  /// Salva um modelo customizado em uma tabela dinâmica baseada no esquema do modelo
  Future<void> saveModel(SqlModel model) async {
    await _dbHelper.saveModel(model);
  }

  /// Recupera dados crus de uma tabela dinâmica
  Future<List<Map<String, dynamic>>> getModels(String tableName) async {
    return await _dbHelper.getModels(tableName);
  }

  static Future<void> clearAll() async {
    _memoryCache.clear();
    await _dbHelper.clearAll();
  }
}
