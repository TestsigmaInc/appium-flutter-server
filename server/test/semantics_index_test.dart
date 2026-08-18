import 'package:appium_flutter_server/src/utils/ui_serialization/semantics_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('carries identifier and label at the widget rectangle',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Semantics(
          identifier: 'ts_send',
          label: 'Send',
          child: const SizedBox(width: 40, height: 20),
        ),
      ),
    ));

    final SemanticsIndex index = SemanticsIndex.build();
    final values = index.atRect(tester.getRect(find.byType(SizedBox)));

    expect(index.isEmpty, isFalse);
    expect(values, isNotNull);
    expect(values!.identifier, 'ts_send');
    expect(values.label, 'Send');
    handle.dispose();
  });

  testWidgets('indexes the physical rectangle as well as the logical one',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Semantics(
          label: 'Scaled',
          child: const SizedBox(width: 40, height: 20),
        ),
      ),
    ));

    final double ratio = tester.view.devicePixelRatio;
    final Rect logical = tester.getRect(find.byType(SizedBox));
    final Rect physical = Rect.fromLTRB(logical.left * ratio,
        logical.top * ratio, logical.right * ratio, logical.bottom * ratio);
    final SemanticsIndex index = SemanticsIndex.build();

    expect(ratio, greaterThan(1), reason: 'the test view must be scaled');
    expect(index.atRect(logical)?.label, 'Scaled');
    expect(index.atRect(physical)?.label, 'Scaled');
    handle.dispose();
  });

  testWidgets('refuses two indistinguishable nodes rather than guessing',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 40,
          height: 20,
          child: Stack(
            children: [
              Semantics(label: 'First', child: const SizedBox.expand()),
              Semantics(label: 'Second', child: const SizedBox.expand()),
            ],
          ),
        ),
      ),
    ));

    final SemanticsIndex index = SemanticsIndex.build();
    final Rect rect = tester.getRect(find.byType(Stack));

    expect(index.atRect(rect), isNull);
    handle.dispose();
  });

  testWidgets('is empty while no widget carries semantics', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: SizedBox(width: 10, height: 10)),
    ));

    expect(SemanticsIndex.build().isEmpty, isTrue);
    handle.dispose();
  });

  // The label a Text contributes on its own is the reason for reading the semantics tree: the
  // Semantics widget property this replaces reports nothing for it.
  testWidgets('carries an implicit label no Semantics widget authored',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: Text('Send')),
    ));

    final SemanticsIndex index = SemanticsIndex.build();

    expect(index.atRect(tester.getRect(find.byType(Text)))?.label, 'Send');
    handle.dispose();
  });
}
