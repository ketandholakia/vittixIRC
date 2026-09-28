import 'package:vittix_irc/state/irc_session_controller.dart';

class ActiveSessionRegistry {
  static IrcSessionController? activeController;

  static void setActive(IrcSessionController controller) {
    activeController = controller;
  }

  static void clear(IrcSessionController controller) {
    if (activeController == controller) {
      activeController = null;
    }
  }
}
