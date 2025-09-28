import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';

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
  String? _currentlyPlayingPath;

  Future<void> initialize() async {
    await permissionHandler();
    const krecDirectory = '/storage/emulated/0/Download/MediNote';
    _recordingDirectory = Directory(krecDirectory);

    if(!await _recordingDirectory!.exists()){
      // Directory does not exist, create it
      await _recordingDirectory?.create(recursive: true);
    }
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
    if(!recorderInit) await permissionHandler();

    if(recorderInit && !isRecording) {
      if(await Permission.microphone.isGranted){
        String fileName = 'recording_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.aac';
        String path = '${_recordingDirectory?.path}/$fileName';
      await _audioRecorder.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
        );

        setState(() {
          isRecording = true;
          _elapsedSeconds = 0;
        });
        _startTimer();
      }
    }
  }

  void _startTimer()  {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  Future<String> getAudioDuration(String path) async {
    final audioPlayer = FlutterSoundPlayer();
    await audioPlayer.openPlayer();
    final duration = await audioPlayer.startPlayer(fromURI: path);
    await audioPlayer.stopPlayer();
    await audioPlayer.closePlayer();
    final d = duration??Duration.zero;
    return '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  }

  Future<void> stopRecording() async{
      await _audioRecorder.stopRecorder();
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
    recorderInit = false;
    super.dispose();
  }

  void _stopTimer(){
    timer?.cancel();
  }

  void _loadRecordings() async {

    setState(() {
      isLoading = true;
    });

    final files = _recordingDirectory!.listSync();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    
    Map<String, String> durations = {};
    for(var file in files){
      if(file is File){
        final duration = await getAudioDuration(file.path);
        durations[file.path] = duration;
      }
    }
    
    setState(() {
      _recordings = files;
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
            final filesizeInKB = (File(path).lengthSync()/1024).toStringAsFixed(1);
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
                  IconButton(onPressed: () async{
                    await File(recording.path).delete();
                    _loadRecordings();
                  }, icon: Icon(Icons.delete, size: 16,)),
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