import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/api_client.dart';
import '../../core/upload_queue.dart';
import '../../services/recording/rolling_recorder.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {

 @override
  void initState() {
    super.initState();
    initialize(); // <-- make sure we actually set up directory & permissions
  }

  late final ApiClient _api;
  late final UploadQueue _queue;
  RollingRecorder? _rolling;

  final FlutterSoundPlayer _audioPlayer = FlutterSoundPlayer();

  Timer? timer;
  bool isRecording = false;
  bool recorderInit = false;
  bool isLoading = false;
  bool isPlaying = false;
  List<FileSystemEntity> _recordings = [];
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  Directory? _recordingDirectory;
  int _elapsedSeconds = 0;
  Map<String, String> _durations = {};
  Map<String, int> _sizes = {}; // bytes

  String? _currentlyPlayingPath;

  Future<void> initialize() async {
      await permissionHandler();

  // Use app-specific dir (safer for scoped storage)
  final baseDir =Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
  _recordingDirectory = Directory(p.join(baseDir!.path, 'MediNote'));
  if (!await _recordingDirectory!.exists()) {
    await _recordingDirectory!.create(recursive: true);
  }

  // Backend clients
    final backendUrl = 'http://localhost:3001';
    _api = ApiClient(
      baseUrl: backendUrl,
      authToken: 'demo_token_123',
    );
  _queue = UploadQueue(_api);

_rolling = RollingRecorder(
  queue: _queue,
  api: _api,
  userId: 'user_123',
  patientId: 'patient_123',
  patientName: 'Alice Johnson',
  chunkSeconds: 5,
  apiBase: backendUrl,      // <-- add
  authToken: "demo_token_123",  // <-- add
);

  await _rolling!.init();

  // player init (optional)
  await _audioPlayer.openPlayer();

  // preload any existing files
  _loadRecordings();
  }

  Future<void> permissionHandler() async{
    var status = await Permission.microphone.status;
    if(status.isDenied || status.isPermanentlyDenied){
      status = await Permission.microphone.request();
    }
    if(status.isGranted){
      Get.snackbar("Permission Status", "Microphone permission granted");
      _audioRecorder.openRecorder();
      setState(() {
        recorderInit = true;
      });
    } else if(status.isPermanentlyDenied) {
      openAppSettings();
    }else{
      Get.snackbar("Permission Status", "Microphone permission denied");
    }
  }

  Future<void> startRecording() async{
  if (!recorderInit) await permissionHandler();
  if (!(await Permission.microphone.isGranted)) return;

  await _rolling?.start();

  setState(() {
    isRecording = true;
    _elapsedSeconds = 0;
  });
  _startTimer();
  }

  void _startTimer()  {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

 String formatDurationFromBytes(int bytes, {int bitrateBps = 64000}) {
  // duration (s) = bits / bps
  final seconds = (bytes * 8) / bitrateBps;
  final total = seconds.isFinite ? seconds : 0.0;
  final s = total.round(); // display whole seconds
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}


  Future<void> stopRecording() async{
  await _rolling?.stop();
  _stopTimer();
  setState(() {
    isRecording = false;
    _elapsedSeconds = 0;
  });
  _loadRecordings();
    } 
  @override
  void dispose(){
  timer?.cancel();
  _audioPlayer.closePlayer();
  _rolling?.dispose();
  recorderInit = false;
  super.dispose();
  }

  void _stopTimer(){
    timer?.cancel();
  }

void _loadRecordings() async {
  setState(() => isLoading = true);

  final dir = _recordingDirectory;
  if (dir == null) {
    setState(() => isLoading = false);
    return;
  }

  // Snapshot *.aac that actually exist
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.aac'))
      .where((f) => f.existsSync())
      .toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

  final sizes = <String, int>{};
  final durations = <String, String>{};

  for (final f in files) {
    try {
      if (!f.existsSync()) continue;
      final bytes = f.lengthSync();
      sizes[f.path] = bytes;
      durations[f.path] = formatDurationFromBytes(bytes);
    } catch (_) {
      // file might disappear mid-iteration; skip
    }
  }

  if (!mounted) return;
  setState(() {
    _recordings = files;
    _sizes = sizes;
    _durations = durations;
    isLoading = false;
  });
}


  String get formattedTime {

    final Duration duration = Duration(seconds: _elapsedSeconds);
    final hours = (duration.inHours);
    final minutes = (duration.inMinutes);
    final seconds = (duration.inSeconds );
    return [hours, minutes%60, seconds%60].map((seg)=>seg.toString().padLeft(2,'0')).join(':');
  }

  Future<void> _playorPauseRecording(String path) async{
    if(_currentlyPlayingPath == path && isPlaying){
      await _audioPlayer.pausePlayer();
      setState(() {
        isPlaying = false;
      });
    } else if(_currentlyPlayingPath == path && !isPlaying){
      await _audioPlayer.resumePlayer();
      setState(() {
        isPlaying = true;
      });
    } else {
        await _audioPlayer.stopPlayer();
      await _audioPlayer.openPlayer();

      await _audioPlayer.setSubscriptionDuration(const Duration(milliseconds: 100));
      await _audioPlayer.startPlayer(
        fromURI: path,
        whenFinished: () async{
          await _audioPlayer.stopPlayer();
          setState(() {
            isPlaying = false;
            _currentlyPlayingPath = null;
          });
        }
      );
      setState(() {
        isPlaying = true;
        _currentlyPlayingPath = path;
      });
    }
  }

  void _renameFile(FileSystemEntity file) async{
    final oldPath = file.path;
    final directory = file.parent;
    final oldName = oldPath.split('/').last;
    final controller = TextEditingController(text: oldName.replaceAll('.aac', ''));

    await showDialog(context: context, builder: (context){
      return AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New File Name',
          ),
        ),
        actions: [
          TextButton(onPressed: (){
            Navigator.of(context).pop();
          }, child: const Text('Cancel')),
          TextButton(onPressed: () async{
            final newName = controller.text.trim();
            if(newName.isNotEmpty){
              final newPath = '${directory.path}/$newName.aac';
              await file.rename(newPath);
              _loadRecordings();
              // Navigator.of(context).pop();
            }
          }, child: const Text('Rename')),
        ],
      );
    });
  }

  Future<void> _safeDelete(String path) async {
  try {
    if (_currentlyPlayingPath == path) {
      try { await _audioPlayer.stopPlayer(); } catch (_) {}
      setState(() {
        isPlaying = false;
        _currentlyPlayingPath = null;
      });
    }
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  } catch (_) {
    // ignore "not found" etc.
  } finally {
    _loadRecordings();
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Page'),
      ),
      body: Column(
        children: [
          ElevatedButton(onPressed: isRecording ? stopRecording : startRecording,  child: Text(isRecording ? 'Stop Recording' : 'Start Recording')),
          Text( formattedTime, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),),
          if(isLoading) const CircularProgressIndicator(),
          Expanded(child: ListView.builder(itemCount: _recordings.length, itemBuilder: (context, index){
            final recording = _recordings[index];
            final path = recording.path;
            final name = path.split('/').last;
            final isthisplaying = _currentlyPlayingPath == path && isPlaying;
            final bytes = _sizes[path];
            final filesizeInKB = bytes != null ? (bytes / 1024).toStringAsFixed(1) : '--';

            return ListTile(
              title: Text(name),
              subtitle: Column(
                children: [
                  Row(children: [
                    Text(_durations[path] ?? '00:00', style: const TextStyle(fontSize: 12),),
                    Text('$filesizeInKB KB', style: const TextStyle(fontSize: 12),)
                  ],)
                  ,
                  if(_currentlyPlayingPath== path)
                  StreamBuilder<PlaybackDisposition>(stream: _audioPlayer.onProgress, builder: (_, snapshot) {  
                    final value = snapshot.data?.position.inMilliseconds ?? 0;
                    final duration = snapshot.data?.duration.inMilliseconds ?? 1;
                    return Slider(value: value.toDouble().clamp(0.0, duration.toDouble()), 
                    max: duration.toDouble(),
                    onChanged: (value) async{
                     await  _audioPlayer.seekToPlayer(Duration(milliseconds: value.toInt()));
                    });
                  }),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(onPressed: () => _renameFile(recording), icon: Icon(Icons.edit, size: 16,)),
                  IconButton(onPressed: () => _safeDelete(recording.path), icon: Icon(Icons.delete, size: 16,)),
                ],
              ),
              leading: IconButton(onPressed: () => _playorPauseRecording(path), icon: Icon(isthisplaying ? Icons.pause : Icons.play_arrow)),
            );
          }))
        ],
      )
    );
  }
}