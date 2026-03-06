import 'package:meta/meta.dart';
import 'cache/cache_manager.dart';
import 'cache/sql_database_helper.dart';
import 'offline/sync_queue_manager.dart';
import 'connection/volt_interceptor.dart';
import 'utils/volt_log.dart';

/// [Volt] is the main configuration entry point for the VoltNet framework.
///
/// It manages global settings such as interceptors, timeouts, and logging.
class Volt {
  static final List<VoltInterceptor> _interceptors = [];

  /// Global timeout applied to all requests. Defaults to 15 seconds.
  static Duration timeout = const Duration(seconds: 15);

  /// Global flag to enable or disable internal logging.
  /// When true, it uses [DebugUtils] to print requests, responses, and CURLs.
  static bool logging = false;

  /// Returns an unmodifiable list of all registered interceptors.
  static List<VoltInterceptor> get interceptors =>
      List.unmodifiable(_interceptors);

  /// Adds a [VoltInterceptor] to the global pipeline.
  ///
  /// Example:
  /// ```dart
  /// Volt.addInterceptor(MyAuthInterceptor());
  /// ```
  static void addInterceptor(VoltInterceptor interceptor) {
    _interceptors.add(interceptor);
  }

  /// Removes a specific [VoltInterceptor] from the global pipeline.
  static void removeInterceptor(VoltInterceptor interceptor) {
    _interceptors.remove(interceptor);
  }

  /// Clears all registered interceptors.
  @visibleForTesting
  static void clearInterceptors() {
    _interceptors.clear();
  }

  /// Initializes the VoltNet Framework with custom configurations.
  ///
  /// [databaseName] The filename for the SQLite database (e.g., 'app_cache.db').
  /// [maxMemoryItems] Maximum number of items kept in the L1 (memory) cache.
  /// [enableSync] Whether to activate the background offline synchronization engine.
  /// [defaultTimeout] Sets the global timeout for all network requests.
  /// [logging] Enables the built-in logging system for debugging.
  ///
  /// Example:
  /// ```dart
  /// await Volt.initialize(
  ///   logging: true,
  ///   enableSync: true,
  ///   defaultTimeout: Duration(seconds: 30),
  /// );
  /// ```
  static Future<void> initialize({
    String? databaseName,
    int? maxMemoryItems,
    bool enableSync = true,
    Duration? defaultTimeout,
    bool logging = false,
  }) async {
    Volt.logging = logging;
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
