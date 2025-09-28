import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;

// Keeping these imports so other parts of your app still compile.
// We no longer depend on UploadQueue; _queue is unused now.
import '../../core/api_client.dart';
import '../../core/upload_queue.dart';
import '../background/foreground_service.dart';

class RollingRecorder {
  final FlutterSoundRecorder _rec = FlutterSoundRecorder();

  // --- new: direct API config (no UploadQueue needed) ---
  final String apiBase;     // e.g. http://192.168.1.10:3001
  final String authToken;   // e.g. demo_abc123 or your JWT

  // kept for compatibility; not used anymore
  final UploadQueue _queue;
  final ApiClient _api;

  final int chunkSeconds; // e.g., 5–10
  final String userId;
  final String patientId;
  final String patientName;
  final String mimeType;

  Directory? _recDir;
  Timer? _ticker;
  bool _isRecording = false;
  int _chunkNo = 0;
  String? _sessionId;
  late final StreamSubscription _interruptSub;

  RollingRecorder({
    required UploadQueue queue, // kept for constructor compatibility
    required ApiClient api,     // kept for constructor compatibility
    required this.userId,
    required this.patientId,
    required this.patientName,
    required this.apiBase,      // NEW
    required this.authToken,    // NEW
    this.chunkSeconds = 5,
    this.mimeType = 'audio/aac',
  })  : _queue = queue,
        _api = api;

  bool get isRecording => _isRecording;
  String? get recordingDirPath => _recDir?.path;

  Future<void> init() async {
    // Directory (scoped, app-specific)
    final base = await getExternalStorageDirectory(); // Android; iOS returns app docs
    _recDir = Directory(p.join(base!.path, 'MediNote'));
    if (!await _recDir!.exists()) await _recDir!.create(recursive: true);

    // Audio session + interruptions
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      androidAudioAttributes: AndroidAudioAttributes(
        usage: AndroidAudioUsage.voiceCommunication,
        contentType: AndroidAudioContentType.speech,
      ),
      androidWillPauseWhenDucked: true,
    ));

    _interruptSub = session.interruptionEventStream.listen((event) async {
      if (event.begin) {
        if (_isRecording) {
          try {
            await _rec.pauseRecorder();
          } catch (_) {}
        }
      } else {
        if (_isRecording) {
          try {
            await _rec.resumeRecorder();
          } catch (_) {}
        }
      }
    });
  }

  Future<void> dispose() async {
    _ticker?.cancel();
    await _rec.closeRecorder();
    await _interruptSub.cancel();
  }

  Future<void> start() async {
    if (_isRecording) return;

    // Foreground (Android)
    await ForegroundSvc.start();

    // Create (or reuse) an upload session on the backend
    _sessionId ??= await _createUploadSession(
      patientId: patientId,
      userId: userId,
      patientName: patientName,
    );

    await _rec.openRecorder();
    _isRecording = true;
    _chunkNo = 0;

    // Kick off first chunk
    await _startNewChunk();

    // Every N seconds, rotate file
    _ticker = Timer.periodic(Duration(seconds: chunkSeconds), (_) async {
      if (!_isRecording) return;
      await _rotate();
    });
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    _isRecording = false;

    _ticker?.cancel();

    String? lastPath;
    try {
      lastPath = await _rec.stopRecorder();
    } catch (_) {}

    if (lastPath != null) {
      _chunkNo += 1;
      final ok = await _uploadChunk(
        sessionId: _sessionId!,
        chunkNumber: _chunkNo,
        filePath: lastPath,
        isLast: true, // flag final
      );
      if (ok) {
        try {
          await File(lastPath).delete();
        } catch (_) {}
      }
    }

    await _rec.closeRecorder();
    await ForegroundSvc.stop();
  }

  Future<void> _rotate() async {
    // Close current file -> upload -> start a new one
    final closedPath = await _rec.stopRecorder();
    if (closedPath != null) {
      _chunkNo += 1;
      final ok = await _uploadChunk(
        sessionId: _sessionId!,
        chunkNumber: _chunkNo,
        filePath: closedPath,
        isLast: false,
      );
      if (ok) {
        try {
          await File(closedPath).delete();
        } catch (_) {}
      }
    }
    await _startNewChunk();
  }

  Future<void> _startNewChunk() async {
    final fileName = 'rec_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.aac';
    final path = p.join(_recDir!.path, fileName);
    await _rec.startRecorder(
      toFile: path,
      codec: Codec.aacADTS,
      bitRate: 64000,
      sampleRate: 16000,
      numChannels: 1,
    );
  }

  // -------------------------------
  // Networking helpers (direct API)
  // -------------------------------

  Future<String> _createUploadSession({
    required String patientId,
    required String userId,
    required String patientName,
  }) async {
    final uri = Uri.parse('$apiBase/api/v1/upload-session');
    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'patientId': patientId,
        'userId': userId,
        'patientName': patientName,
        'status': 'recording',
        'startTime': DateTime.now().toUtc().toIso8601String(),
      }),
    );

    if (res.statusCode != 201) {
      throw Exception('upload-session failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final id = data['id'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('upload-session: missing id in response');
    }
    return id;
  }

  Future<bool> _uploadChunk({
    required String sessionId,
    required int chunkNumber,
    required String filePath,
    required bool isLast,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      print('[RollingRecorder] file not found: $filePath');
      return false;
    }

    try {
      // 1) get presigned/PUT URL
      final preUri = Uri.parse('$apiBase/api/v1/get-presigned-url');
      final preRes = await http.post(
        preUri,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sessionId': sessionId,
          'chunkNumber': chunkNumber,
          'mimeType': mimeType, // server stores .wav anyway; bytes matter
        }),
      );

      if (preRes.statusCode != 200) {
        print('[RollingRecorder] get-presigned-url failed: '
            '${preRes.statusCode} ${preRes.body}');
        return false;
      }

      final p = jsonDecode(preRes.body) as Map<String, dynamic>;
      final putUrl = p['url'] as String?;
      if (putUrl == null || putUrl.isEmpty) {
        print('[RollingRecorder] missing presigned PUT url');
        return false;
      }

      // 2) PUT raw bytes
      final bytes = await file.readAsBytes();
      final putRes = await http.put(
        Uri.parse(putUrl),
        headers: {
          // express.raw({ type: ["audio/*", "application/octet-stream"] })
          'Content-Type': mimeType,
        },
        body: bytes,
      );

      if (putRes.statusCode != 200) {
        print('[RollingRecorder] PUT failed: ${putRes.statusCode} ${putRes.body}');
        return false;
      }

      // 3) notify uploaded (and if last, server will flip to processing/completed)
      final notifyUri = Uri.parse('$apiBase/api/v1/notify-chunk-uploaded');
      final notifyRes = await http.post(
        notifyUri,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sessionId': sessionId,
          'chunkNumber': chunkNumber,
          'isLast': isLast,
        }),
      );

      if (notifyRes.statusCode != 200) {
        print('[RollingRecorder] notify failed: '
            '${notifyRes.statusCode} ${notifyRes.body}');
        return false;
      }

      print('[RollingRecorder] ✓ uploaded chunk $chunkNumber (isLast=$isLast) '
            'for session $sessionId');
      return true;
    } catch (e, st) {
      print('[RollingRecorder] upload exception: $e\n$st');
      return false;
    }
  }
}
