import 'package:ai_scribe_copilot/features/record/record_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get/get.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Allow UI <-> service messages (optional but good for sanity checks)
  FlutterForegroundTask.initCommunicationPort();

  // Request notification permission on Android 13+
  final perm = await FlutterForegroundTask.checkNotificationPermission();
  if (perm != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  // await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const GetMaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MediNote',
    home: RecordPage(),
  );
}
