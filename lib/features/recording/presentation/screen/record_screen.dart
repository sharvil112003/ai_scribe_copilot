import 'dart:io';

import 'package:ai_scribe_copilot/features/recording/presentation/controller/recording_controller.dart';
import 'package:ai_scribe_copilot/services/api_client.dart';
import 'package:ai_scribe_copilot/app_config.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class RecordScreen extends StatelessWidget {
  RecordScreen({super.key});

  final c = Get.put(RecordingController());
  final api = ApiClient();

  // ---- helpers --------------------------------------------------------------

  Future<bool> _ensurePermissions() async {
    // Microphone
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      Get.snackbar('Permission required', 'Microphone permission is needed to record.',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    // Android 13+ notifications (for foreground service / status)
    if (Platform.isAndroid) {
      final notif = await Permission.notification.request();
      // It's okay if the user denies; we just won't show status notifications.
      if (notif.isPermanentlyDenied) {
        Get.snackbar('Notifications blocked',
            'Status notifications are disabled; you can enable them in Settings.',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
    return true;
  }

  Future<String?> _createSessionSafe() async {
    try {
      final res = await api.dio.post('/api/v1/upload-session', data: {
        'patientId': 'patient_123',
        'userId': 'user_123',
        'patientName': 'Alice Johnson',
        'status': 'recording',
        'startTime': DateTime.now().toIso8601String(),
        'templateId': 'template_123',
      });
      return res.data['id'] as String;
    } catch (e) {
      Get.snackbar('Network', 'Session creation failed: $e',
          snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 4));
      return null;
    }
  }

  Future<void> _pingBackend() async {
    try {
      final res = await api.dio.get('/health');
      Get.snackbar('Backend OK', '${res.data}',
          snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 2));
    } catch (e) {
      Get.snackbar('Backend unreachable', '$e',
          snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 4));
    }
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MediNote Recorder'),
        actions: [
          Tooltip(
            message: 'Ping backend',
            child: IconButton(
              icon: const Icon(Icons.wifi_tethering),
              onPressed: _pingBackend,
            ),
          ),
        ],
      ),
      body: Obx(() {
        final db = c.levelDb.value;
        final isRec = c.isRecording.value;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Backend URL helper (so you know what the app is targeting)
              _badge('Backend', AppConfig.backendBaseUrl),
              const SizedBox(height: 12),

              // Meter
              const SizedBox(height: 12),
              Text('Input level: ${db.toStringAsFixed(1)} dB',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              _meter(db),

              const Spacer(),

              if (!isRec)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text('Start Recording'),
                    onPressed: () async {
                      final ok = await _ensurePermissions();
                      if (!ok) return;

                      // Try to create a session; if backend fails, fallback to local session id
                      String? sid = await _createSessionSafe();
                      sid ??= DateTime.now().millisecondsSinceEpoch.toString();

                      await c.start(sid);
                      Get.snackbar('Recording started', 'Session: $sid',
                          snackPosition: SnackPosition.BOTTOM,
                          duration: const Duration(seconds: 2));
                    },
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                        onPressed: c.pause,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Resume'),
                        onPressed: c.resume,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop & Flush'),
                        onPressed: () async {
                          await c.stop(); // markLast=true by default -> triggers final flush
                          Get.snackbar('Stopped', 'Finalizing & uploading remaining chunks',
                              snackPosition: SnackPosition.BOTTOM,
                              duration: const Duration(seconds: 2));
                        },
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),
            ],
          ),
        );
      }),
    );
  }

  // ---- widgets --------------------------------------------------------------

  Widget _badge(String title, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.2)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87),
          children: [
            TextSpan(
                text: '$title: ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _meter(double db) {
    // normalize -60 dB .. 0 dB -> 0 .. 1
    final norm = ((db + 60.0) / 60.0).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      height: 22,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: norm,
          child: Container(
            decoration: BoxDecoration(
              color: norm > 0.85 ? Colors.redAccent
                  : norm > 0.6 ? Colors.orange
                  : Colors.green,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}
