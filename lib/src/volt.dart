import 'package:meta/meta.dart';
import 'cache/cache_manager.dart';
import 'cache/sql_database_helper.dart';
import 'offline/sync_queue_manager.dart';
import 'connection/volt_interceptor.dart';
import 'utils/volt_log.dart';

/// [Volt] is the main entry point for initializing the framework settings.
class Volt {
  static final List<VoltInterceptor> _interceptors = [];

  /// Global timeout for all requests.
  static Duration timeout = const Duration(seconds: 15);

  /// Returns the list of registered interceptors.
  static List<VoltInterceptor> get interceptors =>
      List.unmodifiable(_interceptors);

  /// Adds an interceptor to the framework.
  static void addInterceptor(VoltInterceptor interceptor) {
    _interceptors.add(interceptor);
  }

  /// Removes an interceptor from the framework.
  static void removeInterceptor(VoltInterceptor interceptor) {
    _interceptors.remove(interceptor);
  }

  /// Clears all interceptors.
  @visibleForTesting
  static void clearInterceptors() {
    _interceptors.clear();
  }

  /// Initializes the VoltNet Framework.
  ///
  /// [databaseName] allows changing the SQLite filename.
  /// [maxMemoryItems] sets the L1 cache limit.
  /// [enableSync] activates the offline synchronization engine.
  /// [defaultTimeout] sets the global timeout for requests.
  static Future<void> initialize({
    String? databaseName,
    int? maxMemoryItems,
    bool enableSync = true,
    Duration? defaultTimeout,
  }) async {
    VoltLog.i('Initializing VoltNet...');

    if (databaseName != null) {
      SqlDatabaseHelper.databaseName = databaseName;
    }

    if (maxMemoryItems != null) {
      CacheManager.maxMemoryItems = maxMemoryItems;
    }

    if (defaultTimeout != null) {
      timeout = defaultTimeout;
    }

    await CacheManager.init();

    if (enableSync) {
      SyncQueueManager().startMonitoring();
    }

    VoltLog.i('VoltNet initialized successfully.');
  }
}
