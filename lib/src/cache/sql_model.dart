abstract class SqlModel {
  /// Nome da tabela no banco de dados
  String get tableName;

  /// Mapa de dados para salvar no SQL (chave: nome da coluna, valor: valor)
  Map<String, dynamic> toSqlMap();

  /// Esquema da tabela (chave: nome da coluna, valor: tipo SQL como 'TEXT', 'INTEGER PRIMARY KEY', etc)
  Map<String, String> get tableSchema;
}
