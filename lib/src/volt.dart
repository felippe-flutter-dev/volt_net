import '../volt_net.dart';

class Volt {
  /// Inicializa o Framework VoltNet com todas as suas funcionalidades.
  ///
  /// [databaseName] permite trocar o nome do arquivo SQLite.
  /// [maxMemoryItems] define o limite de itens na RAM (L1) para evitar memory leaks.
  /// [enableSync] ativa o monitoramento de rede e sincronização automática offline.
  static Future<void> initialize({
    String? databaseName,
    int? maxMemoryItems,
    bool enableSync = true,
  }) async {
    // 1. Aplica configurações globais
    if (databaseName != null) {
      SqlDatabaseHelper.databaseName = databaseName;
    }

    if (maxMemoryItems != null) {
      CacheManager.maxMemoryItems = maxMemoryItems;
    }

    // 2. Inicializa o banco de dados e o Cache Manager
    await CacheManager.init();

    // 3. Ativa o motor de sincronização offline se solicitado
    if (enableSync) {
      SyncQueueManager().startMonitoring();
    }
  }
}
