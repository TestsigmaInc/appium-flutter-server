// ----- TESTSIGMA CHANGES START -----
import 'package:appium_flutter_server/src/driver.dart';
import 'package:appium_flutter_server/src/handler/request/request_handler.dart';
import 'package:appium_flutter_server/src/models/api/appium_response.dart';
import 'package:appium_flutter_server/src/ts_recorder/page_source/screen.dart';
import 'package:appium_flutter_server/src/ts_recorder/page_source/tree_walker.dart';
import 'package:appium_flutter_server/src/utils/element_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

// RequestHandler checks the session id in the path before this handler runs.
class PageSourceHandler extends RequestHandler {
  PageSourceHandler(super.route);

  @override
  Future<AppiumResponse> handle(Request request) async {
    final Map<String, String> query = request.url.queryParameters;
    return AppiumResponse(
        getSessionId(request),
        await readPageSourceBody(
            maxNodes: readMaxNodes(query["maxNodes"]),
            ifNoneMatch: query["ifNoneMatch"]));
  }
}

// Read the screen. The HTTP route and the render_tree tunnel send the same body.
Future<Map<String, dynamic>> readPageSourceBody(
    {required int maxNodes, String? ifNoneMatch}) async {
  await ElementHelper.pumpAndTrySettle();
  final WidgetTester tester = FlutterDriver.instance.tester;

  // A frame is still scheduled when an animation did not stop.
  final bool settled = !tester.binding.hasScheduledFrame;

  final PageSource pageSource =
      TreeWalker(screen: Screen.fromView(tester.view), maxNodes: maxNodes)
          .walk(tester.binding.rootElement!);
  return pageSourceBody(pageSource,
      settled: settled, ifNoneMatch: ifNoneMatch);
}

// Send only the hash when the client already has this screen. A cloud lab then sends less data.
Map<String, dynamic> pageSourceBody(PageSource pageSource,
    {required bool settled, String? ifNoneMatch}) {
  final Map<String, dynamic> json = pageSource.toJson(settled: settled);
  if (ifNoneMatch != null && json["hash"] == ifNoneMatch) {
    return {"unchanged": true, "hash": ifNoneMatch};
  }
  return json;
}

// Use the default when the value is missing or not a positive number.
int readMaxNodes(Object? value) {
  final int? parsed = value is int ? value : int.tryParse("${value ?? ""}");
  if (parsed == null || parsed < 1) return TreeWalker.defaultMaxNodes;
  return parsed;
}
// ----- TESTSIGMA CHANGES END -----
