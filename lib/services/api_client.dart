import 'package:dio/dio.dart';
import '../app_config.dart';

class ApiClient {
  final Dio dio;
  ApiClient._(this.dio);

  factory ApiClient() {
    final d = Dio(BaseOptions(
      baseUrl: AppConfig.backendBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Authorization': 'Bearer ${AppConfig.authToken}'},
    ));
    // Basic retry
    d.interceptors.add(InterceptorsWrapper(
      onError: (e, handler) async {
        if (_shouldRetry(e)) {
          await Future.delayed(const Duration(seconds: 2));
          try { final clone = await d.request(
            e.requestOptions.path,
            data: e.requestOptions.data,
            queryParameters: e.requestOptions.queryParameters,
            options: Options(
              method: e.requestOptions.method,
              headers: e.requestOptions.headers,
              contentType: e.requestOptions.contentType,
              responseType: e.requestOptions.responseType,
            ),
          ); return handler.resolve(clone);
          } catch (_) {}
        }
        handler.next(e);
      },
    ));
    return ApiClient._(d);
  }

  static bool _shouldRetry(DioException e) {
    if (e.type == DioExceptionType.connectionError) return true;
    if (e.response == null) return true;
    final s = e.response!.statusCode ?? 0;
    return s >= 500;
  }
}
