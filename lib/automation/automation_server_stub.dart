import 'automation_controller.dart';

final class AutomationServer {
  AutomationServer(AutomationController controller);
  String? get endpoint => null;
  Future<String> start({String? token, int port = 47831}) async =>
      throw UnsupportedError('MCP control requires the desktop app.');
  Future<void> close() async {}
}
