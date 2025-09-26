import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivitySvc {
  final _controller = StreamController<bool>.broadcast();
  late final StreamSubscription _sub;

  Stream<bool> get online$ => _controller.stream;

  Future<void> init() async {
    _sub = Connectivity().onConnectivityChanged.listen((res) {
      final online = res != ConnectivityResult.none;
      _controller.add(online);
    });
    final first = await Connectivity().checkConnectivity();
    _controller.add(first != ConnectivityResult.none);
  }

  Future<void> dispose() async { await _sub.cancel(); await _controller.close(); }
}
