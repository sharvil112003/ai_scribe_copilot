import 'dart:async';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import '../../recording/domain/models.dart';
import 'chunk_queue_db.dart';

class RecorderService {
  final _rec = FlutterSoundRecorder();
  StreamSubscription? _progSub;
  bool _isRecording = false;
  String? _currentPath;
  int _chunkNo = 0;
  final Duration chunkSpan;
  double meterDb = -60; // for UI

  RecorderService({this.chunkSpan = const Duration(seconds: 8)});

  Future<void> init() async {
    await _rec.openRecorder();
    await _rec.setSubscriptionDuration(const Duration(milliseconds: 200));
  }

  Future<void> start(String sessionId) async {
    _chunkNo = 0;
    await _startNewFile(sessionId);
    _isRecording = true;

    _progSub?.cancel();
    _progSub = _rec.onProgress?.listen((e) async {
      meterDb = e.decibels ?? -60;
      if (e.duration >= chunkSpan) {
        await rotateChunk(sessionId);
      }
    });
  }

  Future<void> _startNewFile(String sessionId) async {
    final dir = await getTemporaryDirectory();
    _currentPath = join(dir.path, 'rec_${sessionId}_${DateTime.now().millisecondsSinceEpoch}.wav');
    await _rec.startRecorder(
      toFile: _currentPath,
      codec: Codec.pcm16WAV,
      bitRate: 128000,
      sampleRate: 16000,
      numChannels: 1,
    );
  }

  Future<File?> rotateChunk(String sessionId) async {
    if (!_isRecording || _currentPath == null) return null;
    await _rec.stopRecorder();
    final finished = File(_currentPath!);

    // enqueue
    final item = ChunkItem(
      sessionId: sessionId,
      chunkNumber: _chunkNo++,
      filePath: finished.path,
      mimeType: 'audio/wav',
      status: 'pending',
      retries: 0,
      createdAt: DateTime.now(),
    );
    await ChunkQueueDb.insert(item);

    // start next
    await _startNewFile(sessionId);
    return finished;
  }

  Future<void> pause() async {
    if (_isRecording) { await _rec.pauseRecorder(); }
  }

  Future<void> resume() async {
    if (_rec.isPaused) { await _rec.resumeRecorder(); }
  }

  Future<void> stop() async {
    _isRecording = false;
    _progSub?.cancel();
    if (_rec.isRecording) await _rec.stopRecorder();
  }

  bool get isRecording => _isRecording;

  Future<void> dispose() async { await _rec.closeRecorder(); }
}
