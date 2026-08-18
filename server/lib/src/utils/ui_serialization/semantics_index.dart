import 'package:flutter/rendering.dart';

/// The identifying values one semantics node carries.
class SemanticsValues {
  const SemanticsValues(this.identifier, this.label, this.value, this.depth);

  final String identifier;
  final String label;
  final String value;
  final int depth;

  bool get isEmpty => identifier.isEmpty && label.isEmpty && value.isEmpty;
}

/// Flutter's own semantics tree, indexed by global rectangle.
///
/// The platform accessibility tree carries the same identifiers, but a platform only publishes it
/// once it turns its accessibility bridge on, which iOS does not do for an automation session.
/// Flutter's tree is release safe and reads the same on both platforms.
class SemanticsIndex {
  SemanticsIndex._(this._byRect);

  final Map<String, SemanticsValues?> _byRect;

  /// Whether Flutter is producing semantics at all, which needs a handle to be held somewhere.
  static bool get semanticsEnabled => SemanticsBinding.instance.semanticsEnabled;

  /// Walks the live tree. An app holding no semantics handle yields an empty index.
  ///
  /// The binding's own pipelineOwner is the root of the owner tree and carries no render tree of its
  /// own, so every semantics owner has to be collected from the views and from the owner tree below
  /// it instead.
  static SemanticsIndex build() {
    final byRect = <String, SemanticsValues?>{};
    for (final _OwnerScale entry in _owners()) {
      final SemanticsNode? root = entry.owner.rootSemanticsNode;
      if (root != null) {
        _index(root, Matrix4.identity(), 0, entry.scale, byRect);
      }
    }
    return SemanticsIndex._(byRect);
  }

  static List<_OwnerScale> _owners() {
    final entries = <_OwnerScale>[];
    final seen = <SemanticsOwner>{};
    double viewScale = 1.0;
    for (final RenderView view in RendererBinding.instance.renderViews) {
      viewScale = view.configuration.devicePixelRatio;
      final SemanticsOwner? owner = view.owner?.semanticsOwner;
      if (owner != null && seen.add(owner)) {
        entries.add(_OwnerScale(owner, viewScale));
      }
    }
    _collectOwners(RendererBinding.instance.rootPipelineOwner, viewScale, seen, entries);
    return entries;
  }

  static void _collectOwners(PipelineOwner owner, double scale,
      Set<SemanticsOwner> seen, List<_OwnerScale> out) {
    final SemanticsOwner? semantics = owner.semanticsOwner;
    if (semantics != null && seen.add(semantics)) {
      out.add(_OwnerScale(semantics, scale));
    }
    owner.visitChildren((child) {
      _collectOwners(child, scale, seen, out);
    });
  }

  /// A sample of what was indexed, so a response that joined nothing still shows the rectangles the
  /// semantics tree reported and in which space.
  List<String> sample(int limit) {
    final out = <String>[];
    for (final entry in _byRect.entries) {
      if (out.length >= limit) {
        break;
      }
      final v = entry.value;
      if (v == null) {
        continue;
      }
      final String name = v.identifier.isNotEmpty ? v.identifier : v.label;
      out.add('${entry.key} ${name.length > 24 ? name.substring(0, 24) : name}');
    }
    return out;
  }

  bool get isEmpty => _byRect.isEmpty;

  int get length => _byRect.length;

  /// Values for a render object's own rectangle, so a finder matches exactly what the page source
  /// reported for that widget.
  SemanticsValues? atRect(Rect? rect) =>
      rect == null ? null : _byRect[_key(rect)];

  /// The rectangle a render object occupies, in the space the widget tree reports.
  static Rect? globalRect(RenderObject? renderObject) {
    if (renderObject == null || !renderObject.attached) {
      return null;
    }
    try {
      return MatrixUtils.transformRect(
          renderObject.getTransformTo(null), renderObject.paintBounds);
    } catch (_) {
      return null;
    }
  }

  /// Values for a serialized node's rect, or null when nothing matched or the match was ambiguous.
  SemanticsValues? at(Map<String, dynamic>? rect) {
    if (rect == null) {
      return null;
    }
    final double? x = _asDouble(rect['x']);
    final double? y = _asDouble(rect['y']);
    final double? width = _asDouble(rect['width']);
    final double? height = _asDouble(rect['height']);
    if (x == null || y == null || width == null || height == null) {
      return null;
    }
    return _byRect[_key(Rect.fromLTWH(x, y, width, height))];
  }

  static void _index(SemanticsNode node, Matrix4 inherited, int depth, double scale,
      Map<String, SemanticsValues?> byRect) {
    final Matrix4 global = node.transform == null
        ? inherited
        : (inherited.clone()..multiply(node.transform!));
    final Rect rect = MatrixUtils.transformRect(global, node.rect);
    // The view scales its children by the device pixel ratio, so these rects are physical while the
    // widget tree reports logical ones below the view. Both spaces are indexed rather than guessed.
    _record(node, rect, depth, byRect);
    if (scale != 1.0 && scale > 0) {
      _record(node, _scaled(rect, 1 / scale), depth, byRect);
    }

    // A node merging its descendants has no child nodes to walk: its own label already spans them.
    node.visitChildren((child) {
      _index(child, global, depth + 1, scale, byRect);
      return true;
    });
  }

  static Rect _scaled(Rect rect, double factor) => Rect.fromLTRB(
      rect.left * factor,
      rect.top * factor,
      rect.right * factor,
      rect.bottom * factor);

  static void _record(SemanticsNode node, Rect rect, int depth,
      Map<String, SemanticsValues?> byRect) {
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }
    final values =
        SemanticsValues(node.identifier, node.label, node.value, depth);
    if (values.isEmpty) {
      return;
    }

    final String key = _key(rect);
    if (!byRect.containsKey(key)) {
      byRect[key] = values;
      return;
    }
    final SemanticsValues? held = byRect[key];
    if (held == null) {
      return;
    }
    // Deepest wins the rectangle, and two nodes at one depth are refused rather than guessed between.
    if (values.depth > held.depth) {
      byRect[key] = values;
    } else if (values.depth == held.depth && !_same(values, held)) {
      byRect[key] = null;
    }
  }

  static bool _same(SemanticsValues first, SemanticsValues second) =>
      first.identifier == second.identifier &&
      first.label == second.label &&
      first.value == second.value;

  /// The index key for a rectangle, so a caller can group render objects the same way.
  static String keyOf(Rect rect) => _key(rect);

  /// Whole logical pixels, so the join is not lost to a rounding difference.
  static String _key(Rect rect) =>
      '${rect.left.round()},${rect.top.round()},${rect.right.round()},${rect.bottom.round()}';

  static double? _asDouble(dynamic value) =>
      value is num ? value.toDouble() : null;
}

/// One semantics owner and the device pixel ratio its rectangles are measured in.
class _OwnerScale {
  const _OwnerScale(this.owner, this.scale);

  final SemanticsOwner owner;
  final double scale;
}
