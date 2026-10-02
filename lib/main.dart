import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vittix_irc/core/app_navigator.dart';
import 'package:vittix_irc/models/app_settings.dart';
import 'package:vittix_irc/screens/server/server_list_screen.dart';
import 'package:vittix_irc/services/history_cleanup_service.dart';
import 'package:vittix_irc/services/app_settings_service.dart';
import 'package:vittix_irc/services/notification_service.dart';
import 'package:vittix_irc/services/share_intent_service.dart';
import 'package:vittix_irc/state/session_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.instance.init();
  ShareIntentService.instance.init();

  SessionManager.instance.startLifecycleHandling();

  final settings = await AppSettingsService().getSettings();
  await HistoryCleanupService().cleanupIfNeeded();

  runApp(IrcMobileApp(initialSettings: settings));
}

class IrcMobileApp extends StatefulWidget {
  final AppSettings initialSettings;

  const IrcMobileApp({
    super.key,
    required this.initialSettings,
  });

  @override
  State<IrcMobileApp> createState() => _IrcMobileAppState();
}

class _IrcMobileAppState extends State<IrcMobileApp> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  void _updateSettings(AppSettings settings) {
    setState(() => _settings = settings);
    SessionManager.instance.reloadSettingsForAll();
  }

  Future<void> _markTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showcase_tutorial_seen', true);
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      enableShowcase: true,
      onFinish: _markTutorialSeen,
      builder: (context) => MaterialApp(
        navigatorKey: AppNavigator.navigatorKey,
        title: 'VIRC',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: _settings.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: ServerListScreen(
          onSettingsChanged: _updateSettings,
        ),
      ),
    );
  }
}
