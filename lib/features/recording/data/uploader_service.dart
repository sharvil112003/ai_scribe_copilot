import 'dart:io';
import 'package:dio/dio.dart';
import '../../../services/api_client.dart';
import '../domain/models.dart';
import 'chunk_queue_db.dart';

class UploaderService {
  final ApiClient api = ApiClient();

  Future<void> pumpQueueOnce(String sessionId) async {
    final batch = await ChunkQueueDb.nextBatch(limit: 4);
    for (final c in batch) {
      await _uploadChunk(sessionId, c);
    }
    // clean up uploaded after 2 days
    await ChunkQueueDb.clearUploadedOlderThan(const Duration(days: 2));
  }

  Future<void> _uploadChunk(String sessionId, ChunkItem c) async {
    try {
      await ChunkQueueDb.updateStatus(c.id!, 'uploading');

      // 1) presigned url
      final pres = await api.dio.post('/api/v1/get-presigned-url', data: {
        'sessionId': sessionId,
        'chunkNumber': c.chunkNumber,
        'mimeType': c.mimeType,
      });
      final url = pres.data['url'] as String;

      // 2) PUT binary
      final f = File(c.filePath);
      final bytes = await f.readAsBytes();
      await api.dio.put(
        url,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {'Content-Type': c.mimeType},
          responseType: ResponseType.plain,
        ),
      );

      // 3) notify
      await api.dio.post('/api/v1/notify-chunk-uploaded', data: {
        'sessionId': sessionId,
        'gcsPath': 'sessions/$sessionId/chunk_${c.chunkNumber}.wav',
        'chunkNumber': c.chunkNumber,
        'isLast': false,
        'totalChunksClient': 0,
        'publicUrl': '',
        'mimeType': c.mimeType,
        'selectedTemplate': null,
        'selectedTemplateId': null,
        'model': 'fast',
      });

      await ChunkQueueDb.updateStatus(c.id!, 'uploaded');
    } catch (e) {
      await ChunkQueueDb.incRetry(c.id!);
      await ChunkQueueDb.updateStatus(c.id!, 'failed');
    }
  }
}
