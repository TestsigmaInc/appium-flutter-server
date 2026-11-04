// ----- TESTSIGMA CHANGES START -----
import 'package:appium_flutter_server/src/ts_recorder/page_source/page_source_handler.dart';
import 'package:appium_flutter_server/src/ts_recorder/page_source/tree_walker.dart';
import 'package:appium_flutter_server/src/ts_recorder/tunnel/tunnel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'page_source_test_utils.dart';

void main() {
  group('TunnelRequest.parse', () {
    test('reads the op and the arguments', () {
      final request = TunnelRequest.parse(
          '{"v":1,"op":"page_source","maxNodes":50,"ifNoneMatch":"9f3a61c2"}');

      expect(request?.op, "page_source");
      expect(request?.args["maxNodes"], 50);
      expect(request?.args["ifNoneMatch"], "9f3a61c2");
    });

    test('gives null for text that is not a request', () {
      expect(TunnelRequest.parse(null), isNull);
      expect(TunnelRequest.parse("Log in"), isNull);
      expect(TunnelRequest.parse('["about"]'), isNull);
      expect(TunnelRequest.parse('{"op":"about"}'), isNull);
      expect(TunnelRequest.parse('{"v":2,"op":"about"}'), isNull);
      expect(TunnelRequest.parse('{"v":1,"op":3}'), isNull);
    });
  });

  group('pageSourceBody', () {
    testWidgets('sends only the hash when the client has this screen',
        (tester) async {
      await tester.pumpWidget(page(const Text("Hello")));
      final pageSource = readPageSource(tester);

      expect(
          pageSourceBody(pageSource,
              settled: true, ifNoneMatch: pageSource.hash),
          {"unchanged": true, "hash": pageSource.hash});
    });

    testWidgets('sends the full page source for another hash', (tester) async {
      await tester.pumpWidget(page(const Text("Hello")));
      final pageSource = readPageSource(tester);

      final body =
          pageSourceBody(pageSource, settled: true, ifNoneMatch: "00000000");

      expect(body["hash"], pageSource.hash);
      expect(body["nodes"], isNotEmpty);
    });
  });

  test('readMaxNodes uses the default for a missing or bad value', () {
    expect(readMaxNodes(50), 50);
    expect(readMaxNodes("50"), 50);
    expect(readMaxNodes(null), TreeWalker.defaultMaxNodes);
    expect(readMaxNodes("x"), TreeWalker.defaultMaxNodes);
    expect(readMaxNodes(0), TreeWalker.defaultMaxNodes);
  });
}
// ----- TESTSIGMA CHANGES END -----
