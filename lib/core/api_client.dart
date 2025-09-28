import 'package:dio/dio.dart';

class ApiClient {
  final Dio _dio;
  final String baseUrl;
  final String authToken;

  ApiClient({
    required this.baseUrl,
    required this.authToken,
  }) : _dio = Dio(BaseOptions(baseUrl: baseUrl));

  Map<String, String> get _auth => {'Authorization': 'Bearer $authToken'};

  Future<String> createUploadSession({
    required String patientId,
    required String userId,
    required String patientName,
  }) async {
    final r = await _dio.post(
      '/api/v1/upload-session',
      data: {'patientId': patientId, 'userId': userId, 'patientName': patientName},
      options: Options(headers: _auth),
    );
    return r.data['id'] as String;
  }

  Future<String> getPresignedUrl({
    required String sessionId,
    required int chunkNumber,
    required String mimeType,
  }) async {
    final r = await _dio.post(
      '/api/v1/get-presigned-url',
      data: {'sessionId': sessionId, 'chunkNumber': chunkNumber, 'mimeType': mimeType},
      options: Options(headers: _auth),
    );
    return r.data['url'] as String;
  }

  Future<void> putChunkBinary({
    required String presignedUrl,
    required List<int> bytes,
    required String mimeType,
  }) async {
    await _dio.put(
      presignedUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(headers: {'Content-Type': mimeType}, responseType: ResponseType.plain),
    );
  }

  Future<void> notifyChunkUploaded({
    required String sessionId,
    required int chunkNumber,
    required bool isLast,
  }) async {
    await _dio.post(
      '/api/v1/notify-chunk-uploaded',
      data: {'sessionId': sessionId, 'chunkNumber': chunkNumber, 'isLast': isLast},
      options: Options(headers: _auth),
    );
  }
}
