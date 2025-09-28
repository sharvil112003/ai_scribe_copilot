import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';

// core/upload_queue.dart (or next to it)
enum UploadState { queued, uploading, success, failed }

class UploadEvent {
  final String path;           // local file path
  final UploadState state;
  final String? error;
  UploadEvent(this.path, this.state, {this.error});
}


class UploadQueue {
  final ApiClient api;
  final _uuid = const Uuid();
  late final Directory _queueDir;

  UploadQueue(this.api);

  Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    _queueDir = Directory('${base.path}/upload_queue');
    if (!await _queueDir.exists()) await _queueDir.create(recursive: true);
    Connectivity().onConnectivityChanged.listen((_) => drain());
  }

  /// Enqueue a local chunk file to upload (AAC/ADTS)
  Future<void> enqueue({
    required String sessionId,
    required int chunkNumber,
    required String mimeType,
    required File file,
  }) async {
    // Persist a small JSON descriptor for idempotency/retry
    final meta = {
      'id': _uuid.v4(),
      'sessionId': sessionId,
      'chunkNumber': chunkNumber,
      'mimeType': mimeType,
      'path': file.path,
    };
    final metaFile = File('${_queueDir.path}/${meta['id']}.json');
    await metaFile.writeAsString(jsonEncode(meta), flush: true);

    // Try immediately
    await _tryUpload(metaFile);
  }

  Future<void> _tryUpload(File metaFile) async {
    Map<String, dynamic> meta;
    try {
      meta = jsonDecode(await metaFile.readAsString());
    } catch (_) {
      return;
    }
    final f = File(meta['path'] as String);
    if (!await f.exists()) {
      await metaFile.delete().catchError((_) {});
      return;
    }

    try {
      final presigned = await api.getPresignedUrl(
        sessionId: meta['sessionId'],
        chunkNumber: meta['chunkNumber'],
        mimeType: meta['mimeType'],
      );
      final bytes = await f.readAsBytes();
      await api.putChunkBinary(
        presignedUrl: presigned,
        bytes: bytes,
        mimeType: meta['mimeType'],
      );
      // Notify uploaded (not final here; finalization is done externally)
      await api.notifyChunkUploaded(
        sessionId: meta['sessionId'],
        chunkNumber: meta['chunkNumber'],
        isLast: false,
      );
      await f.delete().catchError((_) {});
      await metaFile.delete().catchError((_) {});
    } on DioError {
      // keep for retry
    } catch (_) {
      // keep
    }
  }

  Future<void> drain() async {
    final items = _queueDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final meta in items) {
      await _tryUpload(meta);
    }
  }

  /// Mark stream finished: tell backend `isLast: true`
  Future<void> finalizeSession({
    required String sessionId,
    required int lastChunkNumber,
  }) async {
    await api.notifyChunkUploaded(
      sessionId: sessionId,
      chunkNumber: lastChunkNumber,
      isLast: true,
    );
  }
}
