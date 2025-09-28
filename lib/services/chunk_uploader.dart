import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ChunkUploader {
  final String token; // your bearer token (demo_* or JWT)
  ChunkUploader(this.token);

  /// Upload a single chunk file (AAC) for a session.
  /// Returns true when the server confirms the PUT and notify calls.
  Future<bool> uploadChunk({
    required String sessionId,
    required int chunkNumber,
    required String filePath,
    bool isLast = false,
    String contentType = 'audio/aac',
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      print('[ChunkUploader] file not found: $filePath');
      return false;
    }

    try {
      // 1) ask API for the presigned/put URL it wants us to use
      final presignedRes = await http.post(
        Uri.parse('${dotenv.env['BACKEND_URL']!}/api/v1/get-presigned-url'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sessionId': sessionId,
          'chunkNumber': chunkNumber,
          'mimeType': contentType,
        }),
      );

      if (presignedRes.statusCode != 200) {
        print('[ChunkUploader] get-presigned-url failed: '
            '${presignedRes.statusCode} ${presignedRes.body}');
        return false;
      }

      final p = jsonDecode(presignedRes.body) as Map<String, dynamic>;
      final putUrl = p['url'] as String; // e.g. http://<api>/api/upload-chunk/...

      // 2) PUT raw bytes
      final bytes = await file.readAsBytes();
      final putRes = await http.put(
        Uri.parse(putUrl),
        headers: {
          // Your server uses express.raw({ type: ["audio/*", "application/octet-stream"] })
          'Content-Type': contentType,
        },
        body: bytes,
      );

      if (putRes.statusCode != 200) {
        print('[ChunkUploader] PUT failed: ${putRes.statusCode} ${putRes.body}');
        return false;
      }

      // 3) notify server the chunk arrived
      final notifyRes = await http.post(
        Uri.parse('${dotenv.env['BACKEND_URL']!}/api/v1/notify-chunk-uploaded'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sessionId': sessionId,
          'chunkNumber': chunkNumber,
          'isLast': isLast,
        }),
      );

      if (notifyRes.statusCode != 200) {
        print('[ChunkUploader] notify failed: '
            '${notifyRes.statusCode} ${notifyRes.body}');
        return false;
      }

      print('[ChunkUploader] ✓ uploaded chunk $chunkNumber '
            '(isLast=$isLast) for session $sessionId');
      return true;
    } catch (e, st) {
      print('[ChunkUploader] exception: $e\n$st');
      return false;
    }
  }
}
