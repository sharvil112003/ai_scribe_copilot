import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationsSvc {
  final _fln = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _fln.initialize(const InitializationSettings(android: android));
  }

  Future<void> showRecording({required String title, required String body}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'rec_channel', 'Recording', importance: Importance.low, priority: Priority.low,
        ongoing: true, onlyAlertOnce: true, showWhen: true,
      ),
    );
    await _fln.show(1001, title, body, details);
  }

  Future<void> clearRecording() => _fln.cancel(1001);
}
