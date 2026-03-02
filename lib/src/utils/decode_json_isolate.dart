import 'dart:convert';

M decodeJsonInIsolate<M>(List<dynamic> args) {
  final String source = args[0];
  final Function parser = args[1];
  return parser(jsonDecode(source));
}

List<M> decodeJsonListInIsolate<M>(List<dynamic> args) {
  final String source = args[0];
  final Function parser = args[1] as M Function(Map<String, dynamic>);
  final List<dynamic> decodedList = jsonDecode(source);
  return decodedList
      .map((e) => parser(e as Map<String, dynamic>))
      .toList()
      .cast<M>();
}
