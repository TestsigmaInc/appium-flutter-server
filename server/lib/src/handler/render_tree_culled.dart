import 'dart:io';

import 'package:appium_flutter_server/src/driver.dart';
import 'package:appium_flutter_server/src/handler/request/request_handler.dart';
import 'package:appium_flutter_server/src/models/api/appium_response.dart';
import 'package:appium_flutter_server/src/models/api/render_tree_culled.dart';
import 'package:appium_flutter_server/src/utils/element_helper.dart';
import 'package:appium_flutter_server/src/utils/ui_serialization/element_serializer.dart';

import 'package:shelf_plus/shelf_plus.dart';

/// The widget tree reduced to what a recorder can use: on-screen interaction candidates with their
/// ancestors, sized by the screen rather than by how big the app is. /element/render_tree is left
/// untouched for anything that needs the full tree.
class RenderTreeCulledHandler extends RequestHandler {
  RenderTreeCulledHandler(super.route);

  @override
  Future<AppiumResponse> handle(Request request) async {
    final Map<String, dynamic>? bodyParams = await request.body.asJson;
    final options = RenderTreeCulledModel.fromJson(bodyParams);

    try {
      // Let a running transition finish first. Captured mid route change, the tree legitimately
      // holds both screens, and the consumer would show the old one's elements over the new.
      await ElementHelper.pumpAndTrySettle(
        timeout: const Duration(milliseconds: 800),
      );

      final rootElement = FlutterDriver.instance.tester.binding.rootElement;
      if (rootElement == null) {
        return AppiumResponse(getSessionId(request), <Map<String, dynamic>>[]);
      }
      final widgetTree =
          await ElementSerializer.serializeCulled(rootElement, options);

      return AppiumResponse(getSessionId(request), widgetTree);
    } catch (e) {
      return AppiumResponse.withError(
        getSessionId(request),
        'Error: ${e.toString()}',
        null,
        HttpStatus.internalServerError,
      );
    }
  }
}
