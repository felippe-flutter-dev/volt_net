import 'dart:convert';

/// Decodes a JSON string in a background Isolate.
M decodeJsonInIsolate<M>(List<dynamic> args) {
  final String source = args[0] as String;
  final dynamic parser = args[1];

  final decoded = jsonDecode(source);
  return _applyParser<M>(decoded, parser);
}

/// Decodes a JSON string representing a List in a background Isolate.
List<M> decodeJsonListInIsolate<M>(List<dynamic> args) {
  final String source = args[0] as String;
  final dynamic parser = args[1];

  final List<dynamic> decodedList = jsonDecode(source) as List<dynamic>;
  return decodedList.map<M>((e) => _applyParser<M>(e, parser)).toList();
}

/// Helper to apply parser with flexible type matching to avoid casting errors in Isolates.
M _applyParser<M>(dynamic data, dynamic parser) {
  if (parser is M Function(Map<String, dynamic>)) {
    return parser(data as Map<String, dynamic>);
  }
  if (parser is M Function(dynamic)) {
    return parser(data);
  }
  // Fallback for generic closures
  return (parser as Function)(data) as M;
}
