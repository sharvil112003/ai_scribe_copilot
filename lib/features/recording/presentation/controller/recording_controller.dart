import 'dart:async';
import 'package:ai_scribe_copilot/features/bg/bg_service.dart';
import 'package:ai_scribe_copilot/features/recording/data/recorder_service.dart';
import 'package:ai_scribe_copilot/features/recording/data/uploader_service.dart';
import 'package:ai_scribe_copilot/services/connectivity_svc.dart';
import 'package:get/get.dart';

class RecordingController extends GetxController {
  final recorder = RecorderService();
  final uploader = UploaderService();
  final connectivity = ConnectivitySvc();

  final isRecording = false.obs;
  final levelDb = (-60.0).obs;
  String? sessionId;

  @override
  void onInit() {
    super.onInit();
    connectivity.init();
    // upload when back online
    connectivity.online$.listen((online) async {
      if (online && sessionId != null) {
        await uploader.pumpQueueOnce(sessionId!);
      }
    });
  }

  Future<void> start(String sid) async {
    sessionId = sid;
    await recorder.init();
    await recorder.start(sid);
    isRecording.value = true;
    // start BG service
    await BgService.start(sid);
    // meter tick
    Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (!isRecording.value) t.cancel();
      levelDb.value = recorder.meterDb;
    });
  }

  Future<void> pause() => recorder.pause();
  Future<void> resume() => recorder.resume();

  Future<void> stop({bool markLast = true}) async {
    await recorder.stop();
    isRecording.value = false;
    await BgService.stop();

    if (markLast && sessionId != null) {
      // best-effort: pump remaining queue quickly
      await uploader.pumpQueueOnce(sessionId!);
    }
  }
}
