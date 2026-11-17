// ----- TESTSIGMA CHANGES START -----
import 'package:appium_flutter_server/src/driver.dart';
import 'package:appium_flutter_server/src/utils/element_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A DropdownButton keeps every item offstage to size itself, so each item text has an offstage twin.
  testWidgets('finds a dropdown item by text while its offstage twin exists',
      (tester) async {
    FlutterDriver.instance.initialize(
      tester: tester,
      binding: binding,
      appInfo: PackageInfo(
          appName: 'test', packageName: 'test', version: '1', buildNumber: '1'),
      serverVersion: 'test',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DropdownButton<String>(
          value: 'India',
          items: const ['India', 'Japan']
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.tap(find.text('India'));
    await tester.pumpAndSettle();

    // The lookup strategies search offstage widgets too (element_lookup_strategy.dart).
    final found = await ElementHelper.findElements(
        find.text('Japan', skipOffstage: false));

    expect(found, isNotEmpty);
    expect(tester.getRect(found.first).height, greaterThan(0));
  });
}
// ----- TESTSIGMA CHANGES END -----
