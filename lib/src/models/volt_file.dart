import 'package:http/http.dart' as http;

/// [VoltFile] is a simple wrapper for file uploads that supports Offline Sync.
///
/// Instead of using [http.MultipartFile] directly, use [VoltFile] to allow
/// VoltNet to persist the file path if the user is offline.
class VoltFile {
  final String path;
  final String? field;

  VoltFile({required this.path, this.field});

  /// Converts the [VoltFile] to a native [http.MultipartFile] for immediate upload.
  Future<http.MultipartFile> toMultipartFile() async {
    return await http.MultipartFile.fromPath(field ?? 'file', path);
  }
}
