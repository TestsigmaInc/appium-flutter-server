// ----- TESTSIGMA CHANGES START -----
import 'dart:convert';

import 'package:appium_flutter_server/src/models/api/appium_response.dart';
import 'package:appium_flutter_server/src/ts_recorder/about/about_handler.dart';
import 'package:appium_flutter_server/src/ts_recorder/page_source/page_source_handler.dart';

// The recorder routes inside the stock render_tree command. A cloud lab forwards only stock commands.
class TsRecorderTunnel {
  // The reserved widget type. No real widget has this type.
  static const String marker = "__ts_recorder__";

  // The request version that this server reads.
  static const int requestVersion = 1;

  // The text field holds the request as JSON: {v, op, ...arguments}.
  static Future<AppiumResponse> handle(String sessionId, String? text) async {
    final TunnelRequest? request = TunnelRequest.parse(text);
    if (request == null) {
      return AppiumResponse(sessionId,
          ArgumentError("The recorder tunnel request is not valid: $text"));
    }
    switch (request.op) {
      case "about":
        return AppiumResponse(sessionId, aboutBody());
      case "page_source":
        return AppiumResponse(
            sessionId,
            await readPageSourceBody(
                maxNodes: readMaxNodes(request.args["maxNodes"]),
                ifNoneMatch: request.args["ifNoneMatch"] as String?));
      default:
        return AppiumResponse(sessionId,
            ArgumentError("The recorder tunnel has no op \"${request.op}\""));
    }
  }
}

// One tunnel request. Null when the text is not JSON or has another version.
class TunnelRequest {
  final String op;
  final Map<String, dynamic> args;

  TunnelRequest(this.op, this.args);

  static TunnelRequest? parse(String? text) {
    if (text == null) return null;
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    if (json["v"] != TsRecorderTunnel.requestVersion) return null;
    final Object? op = json["op"];
    if (op is! String) return null;
    return TunnelRequest(op, json);
  }
}
// ----- TESTSIGMA CHANGES END -----
