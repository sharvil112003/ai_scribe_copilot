import 'dart:async';
import 'package:ai_scribe_copilot/features/recording/data/uploader_service.dart';
import 'package:ai_scribe_copilot/services/notifications_svc.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class BgService {
  static const _channelId = 'medinote_bg';
  static String? sessionIdForBg; // set from controller

  static Future<void> initialize() async {
    final service = FlutterBackgroundService();
    await service.configure(
      iosConfiguration: IosConfiguration(),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: false,
        initialNotificationTitle: 'MediNote',
        initialNotificationContent: 'Background uploading',
      ),
    );
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    final notif = NotificationsSvc();
    await notif.init();
    final uploader = UploaderService();

    Timer.periodic(const Duration(seconds: 20), (t) async {
      final sid = sessionIdForBg;
      if (sid != null) {
        await notif.showRecording(title: 'Uploading', body: 'Syncing audio chunks…');
        await uploader.pumpQueueOnce(sid);
      }
    });
  }

  static Future<void> start(String sessionId) async {
    sessionIdForBg = sessionId;
    await FlutterBackgroundService().startService();
  }

  static Future<void> stop() async {
    sessionIdForBg = null;
    FlutterBackgroundService().invoke('stopService');
  }
}
