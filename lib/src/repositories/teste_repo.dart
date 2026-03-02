import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';

import '../config/test_api_config.dart';

class TesteRepo {
  final GetRequest _getRequest;

  TesteRepo(this._getRequest);

  Future<TestModel> getTestModel() async {
    return await _getRequest.getModel(
      TestApiConfig(),
      '/testando',
      TestModel.fromJson,
      cacheEnabled: true,
      type: CacheType.both,
    );
  }

  Future<List<TestModel>> getTestModelList() async {
    return await _getRequest.getModel(
        TestApiConfig(), '/testando', TestModel.fromJson,
        asList: true);
  }
}
