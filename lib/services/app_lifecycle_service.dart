import 'package:flutter/widgets.dart';

class AppLifecycleService with WidgetsBindingObserver {
  final VoidCallback? onForeground;
  final VoidCallback? onBackground;

  AppLifecycleService({
    this.onForeground,
    this.onBackground,
  });

  void start() {
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onForeground?.call();
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        onBackground?.call();
        break;

      case AppLifecycleState.detached:
        break;
    }
  }
}
