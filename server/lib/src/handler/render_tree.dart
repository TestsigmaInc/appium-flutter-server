import 'dart:io';

import 'package:appium_flutter_server/src/handler/request/request_handler.dart';
import 'package:appium_flutter_server/src/models/api/appium_response.dart';
import 'package:appium_flutter_server/src/utils/element_helper.dart';
// ----- TESTSIGMA CHANGES START -----
import 'package:appium_flutter_server/src/ts_recorder/tunnel/tunnel.dart';
// ----- TESTSIGMA CHANGES END -----

import 'package:shelf_plus/shelf_plus.dart';

class RenderTreeHandler extends RequestHandler {
  RenderTreeHandler(super.route);

  @override
  Future<AppiumResponse> handle(Request request) async {
    final Map<String, dynamic>? bodyParams = await request.body.asJson;

    final String? widgetType = bodyParams?['widgetType'] as String?;
    final String? text = bodyParams?['text'] as String?;
    final String? key = bodyParams?['key'] as String?;

    // ----- TESTSIGMA CHANGES START -----
    // A cloud lab forwards only stock commands. The reserved type carries a recorder request.
    if (widgetType == TsRecorderTunnel.marker) {
      return TsRecorderTunnel.handle(getSessionId(request), text);
    }
    // ----- TESTSIGMA CHANGES END -----

    try {
      final widgetTree = await ElementHelper.getRenderTreeByType(
        widgetType: widgetType,
        text: text,
        key: key,
      );

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
