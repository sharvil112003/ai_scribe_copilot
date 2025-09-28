import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Top-level entrypoint required by flutter_foreground_task.
@pragma('vm:entry-point')
void medinoteForegroundStart() {
  FlutterForegroundTask.setTaskHandler(_MediNoteTaskHandler());
}

/// Your TaskHandler – runs in the service isolate.
class _MediNoteTaskHandler extends TaskHandler {
  // Example: keep a ticker or do periodic work in onRepeatEvent.
  int _tick = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Called once when service starts or restarts.
    FlutterForegroundTask.updateService(
      notificationTitle: 'MediNote recording',
      notificationText: 'Preparing…',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick++;
    // You can push data back to UI if you called initCommunicationPort() in main():
    // FlutterForegroundTask.sendDataToMain({'tick': _tick});
    FlutterForegroundTask.updateService(
      notificationTitle: 'MediNote recording',
      notificationText: 'Running • $_tick',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Cleanup if needed.
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Handle actions from `notificationButtons` if you add any.
  }

  @override
  void onNotificationPressed() {
    // Bring app to foreground when notification tapped.
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    // Optional: react to swipe-away.
  }

  @override
  void onReceiveData(Object data) {
    // Optional: handle messages from UI isolate (send via sendDataToTask).
  }
}

/// Simple façade so your app code just calls ForegroundSvc.start()/stop().
class ForegroundSvc {
  static bool _inited = false;

  /// Call once (e.g., when starting a long-running task).
  static Future<void> init() async {
    if (_inited) return;

    // (Optional but recommended) Ask for notification permission on Android 13+.
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Battery/optimization helpers (Android 12+). Safe to ignore on iOS.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      // Requires android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS in manifest.
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    // Configure the foreground service.
    FlutterForegroundTask.init(
      androidNotificationOptions:  AndroidNotificationOptions(
        channelId: 'medinote_rec_channel',
        channelName: 'MediNote Recording',
        channelDescription: 'Recording is active',
        // Other options you can set here: onlyAlertOnce, persistent, showWhen, etc.
        // priority and importance are managed by the notification channel.
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions:  ForegroundTaskOptions(
        // v8 uses an *event action* rather than `interval`.
        eventAction: ForegroundTaskEventAction.repeat(5000), // every 5s
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _inited = true;
  }

  /// Start (or restart) the service with your handler.
  static Future<ServiceRequestResult> start() async {
    await init();

    if (await FlutterForegroundTask.isRunningService) {
      // If already running, restart to refresh notification/handler if needed.
      return FlutterForegroundTask.restartService();
    }

    return FlutterForegroundTask.startService(
      serviceId: 256, // any 0–65535; keep consistent for your app
      notificationTitle: 'MediNote recording',
      notificationText: 'Tap to return to MediNote',
      notificationIcon: null, // or provide a custom NotificationIcon
      notificationButtons: const <NotificationButton>[
        // Example: NotificationButton(id: 'pause', text: 'Pause'),
      ],
      notificationInitialRoute: '/', // route to open when tapping notification
      callback: medinoteForegroundStart, // MUST be the top-level function above
    );
  }

  static Future<ServiceRequestResult> stop() {
    return FlutterForegroundTask.stopService();
  }
}
