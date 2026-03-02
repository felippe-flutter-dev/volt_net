import 'package:flutter/material.dart';
import 'package:volt_net/volt_net.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicializa o VoltNet
  await Volt.initialize(
    databaseName: 'example_volt.db',
    maxMemoryItems: 100,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoltNet Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PostListScreen(),
    );
  }
}

// 2. Define a configuração da API
class JsonPlaceholderConfig extends BaseApiUrlConfig {
  @override
  String get baseUrl => 'https://jsonplaceholder.typicode.com';

  @override
  Future<String> getToken() async => ''; // Sem token para API pública
}

// 3. Define o modelo de dados
class Post {
  final int id;
  final String title;
  final String body;

  Post({required this.id, required this.title, required this.body});

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'],
      title: json['title'],
      body: json['body'],
    );
  }
}

class PostListScreen extends StatefulWidget {
  const PostListScreen({super.key});

  @override
  State<PostListScreen> createState() => _PostListScreenState();
}

class _PostListScreenState extends State<PostListScreen> {
  final _getRequest = GetRequest();
  List<Post> _posts = [];
  bool _isLoading = false;
  String _status = 'Toque no botão para carregar';

  Future<void> _fetchPosts() async {
    setState(() {
      _isLoading = true;
      _status = 'Buscando dados...';
    });

    try {
      final startTime = DateTime.now();

      // 4. Faz a requisição com cache habilitado
      final List<Post> posts = await _getRequest.getModel<Post>(
        JsonPlaceholderConfig(),
        '/posts',
        Post.fromJson,
        cacheEnabled: true,
        asList: true,
        type: CacheType.both, // RAM + SQLite
        ttl: const Duration(minutes: 5),
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;

      setState(() {
        _posts = posts.take(10).toList(); // Mostra apenas os 10 primeiros
        _isLoading = false;
        _status =
            'Carregado em ${duration}ms (Verifique o log para saber se veio do cache)';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Erro: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VoltNet - Cache Híbrido')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(_status, textAlign: TextAlign.center),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _posts.length,
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text(post.id.toString())),
                        title: Text(post.title),
                        subtitle: Text(post.body,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchPosts,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
