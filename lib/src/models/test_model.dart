/// A simple model used for testing purposes within the framework.
class TestModel {
  /// The name of the test item.
  final String nome;

  /// Creates a [TestModel].
  TestModel({required this.nome});

  /// Factory constructor to create a [TestModel] from a JSON map.
  factory TestModel.fromJson(Map<String, dynamic> json) =>
      TestModel(nome: json['nome'] as String? ?? 'Unknown');

  /// Converts the [TestModel] to a JSON map.
  Map<String, dynamic> toJson() => {'nome': nome};

  /// Returns a mocked instance of [TestModel].
  factory TestModel.mock() => TestModel(nome: 'Flutter Test');

  /// Returns a mocked list of [TestModel].
  static List<TestModel> mockList() => [
        TestModel(nome: 'Flutter Test 1'),
        TestModel(nome: 'Flutter Test 2'),
      ];

  @override
  String toString() => 'TestModel(nome: $nome)';
}
