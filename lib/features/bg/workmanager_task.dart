import 'package:ai_scribe_copilot/features/recording/data/uploader_service.dart';
import 'package:workmanager/workmanager.dart';
import '../bg/bg_service.dart';

const taskName = 'chunk_retry_task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final sid = BgService.sessionIdForBg;
    if (sid != null) {
      final up = UploaderService();
      await up.pumpQueueOnce(sid);
    }
    return true;
  });
}
