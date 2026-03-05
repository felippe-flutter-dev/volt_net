library;

export 'src/volt.dart';
export 'src/connection/get_request.dart';
export 'src/connection/post_request.dart';
export 'src/connection/put_request.dart';
export 'src/connection/delete_request.dart';
export 'src/cache/cache_manager.dart';
export 'src/cache/cache_type.dart';
export 'src/cache/sql_model.dart';
export 'src/cache/sql_database_helper.dart';
export 'src/offline/sync_queue_manager.dart';
export 'src/offline/volt_sync_listener.dart';
export 'src/config/base_api_url_config.dart';
export 'src/utils/debug_utils.dart';
export 'src/config/result_api.dart';
export 'src/connection/throw_http_exception.dart';
export 'src/connection/volt_interceptor.dart';
export 'src/models/result_model.dart';
export 'src/models/volt_file.dart';
export 'src/utils/volt_log.dart';

// Exporta classes essenciais do HTTP para suporte a Mocks, Multipart e extensões
export 'package:http/http.dart'
    show
        MultipartFile,
        Response,
        Client,
        BaseRequest,
        StreamedResponse,
        ByteStream;

// Exporta StreamSubscription para facilitar o gerenciamento de eventos sem precisar importar dart:async
export 'dart:async' show StreamSubscription, StreamController;
