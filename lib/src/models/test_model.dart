/// Modelo para testes de objeto único
class TestModel {
  final String nome;
  final String message;

  TestModel({
    required this.nome,
    required this.message,
  });

  factory TestModel.fromJson(Map<String, dynamic> json) {
    return TestModel(
      nome: json['nome'] ?? '',
      message: json['message'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nome': nome,
      'message': message,
    };
  }

  /// Mock estático para teste de objeto único
  static TestModel mock() => TestModel(
        nome: 'Flutter Test',
        message: 'Sucesso no parse de objeto único',
      );

  static List<TestModel> mockList() => [
        TestModel(nome: 'Item 1', message: 'Mensagem 1'),
        TestModel(nome: 'Item 2', message: 'Mensagem 2'),
      ];
}
