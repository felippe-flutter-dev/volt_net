import 'package:flutter/material.dart';
import 'package:volt_net/volt_net.dart';

void main() async {
  // Ensure Flutter is initialized before VoltNet
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize VoltNet with Enterprise-grade settings
  // This setup enables the Hybrid Cache (L1 RAM + L2 SQLite)
  // and the Background Sync Engine.
  await Volt.initialize(
    databaseName: 'volt_enterprise_v2.db',
    maxMemoryItems: 150, // L1 cache limit for performance
    enableSync: true, // Enable the resilient offline engine
    defaultTimeout: const Duration(seconds: 15),
  );

  runApp(const VoltEnterpriseApp());
}

class VoltEnterpriseApp extends StatelessWidget {
  const VoltEnterpriseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoltNet 2.0 Enterprise',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// --- Enterprise Models ---

class Post {
  final int? id;
  final int userId;
  final String title;
  final String body;

  Post(
      {this.id, required this.userId, required this.title, required this.body});

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'],
        userId: json['userId'] ?? 0,
        title: json['title'] ?? '',
        body: json['body'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'userId': userId,
        'title': title,
        'body': body,
      };
}

// --- API Configuration ---

class MyApiConfig extends BaseApiUrlConfig {
  @override
  String resolveBaseUrl() => 'https://jsonplaceholder.typicode.com';

  @override
  Future<Map<String, String>> getHeader() async => {
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Enterprise-Client': 'VoltNet-2.0',
      };

  @override
  Future<String> getToken() async => 'secure_session_token_example';
}

// --- UI Layer ---

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = MyApiConfig();
  final _getRequest = GetRequest<MyApiConfig>();
  final _postRequest = PostRequest<MyApiConfig>();

  List<Post> _posts = [];
  bool _isLoading = false;
  String _statusMessage = 'Ready for Resilient Operations';

  @override
  void initState() {
    super.initState();
    _fetchPosts();
  }

  /// Example 1: GET with Hybrid Cache (L1 RAM + L2 Disk)
  /// Uses getListResult for type-safe off-main-thread parsing.
  Future<void> _fetchPosts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final result = await _getRequest.getListResult(
      _api,
      '/posts',
      Post.fromJson,
      cacheEnabled: true,
      type: CacheType.both,
      ttl: const Duration(minutes: 10), // Cache valid for 10 minutes
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _posts = result.model?.take(10).toList() ?? [];
        _statusMessage =
            'Loaded from ${result.result?.response != null ? "Network" : "Cache"}';
      });
    } else {
      setState(() => _statusMessage = 'Error: ${result.errorMessage}');
    }

    setState(() => _isLoading = false);
  }

  /// Example 2: Resilient Batch with Idempotency & Local Rollback
  /// Ensures local consistency even if network fails midway.
  Future<void> _executeBatchOperation() async {
    setState(() => _isLoading = true);

    try {
      final results = await _postRequest.resilientBatch(
        [
          ({extraHeaders}) => _postRequest.post(
                _api,
                endpoint: '/posts',
                data: Post(userId: 1, title: 'Atomic Step 1', body: 'Payload A')
                    .toJson(),
                extraHeaders: extraHeaders,
              ),
          ({extraHeaders}) => _postRequest.post(
                _api,
                endpoint: '/posts',
                data: Post(userId: 1, title: 'Atomic Step 2', body: 'Payload B')
                    .toJson(),
                extraHeaders: extraHeaders,
              ),
        ],
        idempotencyKey:
            'batch_request_${DateTime.now().millisecondsSinceEpoch}',
        rollbackOnFailure: true,
        onRollback: (successfulSteps) async {
          // If Step 2 fails, you can revert local changes made during Step 1.
          VoltLog.w(
              'Rollback triggered! Steps completed before failure: ${successfulSteps.length}');
        },
      );

      if (results.every((r) => r.isSuccess)) {
        setState(
            () => _statusMessage = 'Batch Success! Idempotency protected.');
      }
    } on VoltNetException catch (e) {
      setState(() => _statusMessage = 'Batch Failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Example 3: POST with Automatic Offline Sync
  /// If offline, the request is queued in SQLite and retried automatically.
  Future<void> _createPostResiliently() async {
    final newPost = Post(
        userId: 1, title: 'Offline-Ready Post', body: 'Persisted by VoltNet');

    final result = await _postRequest.postModel(
      _api,
      '/posts',
      Post.fromJson,
      data: newPost.toJson(),
      offlineSync: true,
    );

    if (result.isPending) {
      _showSnackBar('Device Offline: Request queued for background sync 📦');
    } else if (result.isSuccess) {
      _showSnackBar('Post sent successfully! 🚀');
    } else {
      _showSnackBar('Operation failed: ${result.errorMessage}');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // VoltSyncListener automatically triggers a callback when the offline queue is flushed.
    return VoltSyncListener(
      onSync: _fetchPosts,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('VoltNet 2.0 Enterprise'),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _fetchPosts,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Force Refresh (Bypasses L1 Cache)',
            ),
          ],
        ),
        body: Column(
          children: [
            _buildActionPanel(),
            const Divider(height: 1),
            _buildStatusIndicator(),
            Expanded(
              child: _isLoading && _posts.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _buildPostList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPanel() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _executeBatchOperation,
              icon: const Icon(Icons.layers_rounded),
              label: const Text('Resilient Batch'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.withValues(alpha: 0.1),
                foregroundColor: Colors.indigo,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _createPostResiliently,
              icon: const Icon(Icons.cloud_off_rounded),
              label: const Text('Offline Sync'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.grey.shade100,
      child: Text(
        _statusMessage,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _statusMessage.contains('Error') ? Colors.red : Colors.indigo,
        ),
      ),
    );
  }

  Widget _buildPostList() {
    if (_posts.isEmpty) {
      return const Center(child: Text('No data loaded.'));
    }
    return ListView.separated(
      itemCount: _posts.length,
      separatorBuilder: (_, __) => const Divider(indent: 70),
      itemBuilder: (context, index) {
        final post = _posts[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.indigo.shade50,
            child:
                Text('${post.id ?? "?"}', style: const TextStyle(fontSize: 12)),
          ),
          title: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              Text(post.body, maxLines: 2, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}
