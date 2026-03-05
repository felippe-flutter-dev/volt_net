import '../../volt_net.dart';

/// [ResultModel] wraps the parsed model and the raw [ResultApi].
/// Now supports carrying exceptions for better error handling in the UI.
class ResultModel<M> {
  final M? model;
  final ResultApi? result;
  final dynamic error;

  ResultModel({this.model, this.result, this.error});

  bool get isCancelled => result?.isCancelled ?? false;
  bool get isSuccess => (result?.isSuccess ?? false) && error == null;
  bool get isPending => result?.isPending ?? false;
  bool get hasError => error != null || (result != null && !result!.isSuccess);

  /// Helper to get the error message
  String get errorMessage => error?.toString() ?? 'Unknown error';
}
