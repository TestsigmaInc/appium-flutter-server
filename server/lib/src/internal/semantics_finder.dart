import 'package:appium_flutter_server/src/utils/ui_serialization/semantics_index.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finders over Flutter's live semantics tree.
///
/// flutter_test's own semantics finders read RenderObject.debugSemantics, which is null in a release
/// build, so they match nothing in the builds a device runs. Reading the live tree keeps a locator
/// resolvable and agreeing with what the page source reported.
class LiveSemanticsFinder {
  const LiveSemanticsFinder._();

  /// Elements carrying the given semantics label, one per rectangle.
  static Finder byLabel(String label) {
    final Set<Element> owners = _owners((values) => values.label == label);
    return find.byElementPredicate(owners.contains, skipOffstage: false);
  }

  /// Nested render objects share one rectangle, so matching on the rectangle alone counts a single
  /// widget many times over and the recorder then discards the locator as ambiguous. The deepest
  /// element at a rectangle is the one the semantics describe, the rule the page source merge
  /// already follows.
  static Set<Element> _owners(bool Function(SemanticsValues) matches) {
    final Element? root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return const <Element>{};
    }
    final SemanticsIndex index = SemanticsIndex.build();
    if (index.isEmpty) {
      return const <Element>{};
    }

    final deepest = <String, Element>{};
    for (final Element element
        in collectAllElementsFrom(root, skipOffstage: false)) {
      _consider(element, index, matches, deepest);
    }
    return deepest.values.toSet();
  }

  static void _consider(Element element, SemanticsIndex index,
      bool Function(SemanticsValues) matches, Map<String, Element> deepest) {
    if (element is! RenderObjectElement) {
      return;
    }
    final Rect? rect = SemanticsIndex.globalRect(element.renderObject);
    if (rect == null) {
      return;
    }
    final SemanticsValues? values = index.atRect(rect);
    if (values == null || !matches(values)) {
      return;
    }

    final String key = SemanticsIndex.keyOf(rect);
    final Element? held = deepest[key];
    if (held == null || element.depth > held.depth) {
      deepest[key] = element;
    }
  }
}
