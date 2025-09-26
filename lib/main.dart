import 'package:ai_scribe_copilot/features/bg/bg_service.dart';
import 'package:ai_scribe_copilot/features/bg/workmanager_task.dart';
import 'package:ai_scribe_copilot/features/recording/presentation/screen/record_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:workmanager/workmanager.dart';
import 'services/notifications_svc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BgService.initialize();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await NotificationsSvc().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => GetMaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MediNote',
    home: RecordScreen(),
  );
}
