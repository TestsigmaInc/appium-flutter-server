import 'package:appium_flutter_server/src/models/api/render_tree_culled.dart';
import 'package:appium_flutter_server/src/utils/ui_serialization/semantics_index.dart';
import 'package:flutter/material.dart';

/// Caps how many elements one culled response may carry.
class _CullBudget {
  _CullBudget(this._remaining);

  int _remaining;
  bool truncated = false;

  bool take() {
    if (_remaining <= 0) {
      truncated = true;
      return false;
    }
    _remaining--;
    return true;
  }
}

/// The overlay's private wrapper around one entry, the only place a disabled ticker means the
/// subtree is covered rather than merely paused.
const String _overlayEntryWidget = '_OverlayEntryWidget';

class ElementSerializer {
  static Future<Map<String, dynamic>> serialize(
    Element element, {
    Set<Element>? visited,
    int depth = 0,
  }) async {
    visited ??= <Element>{};
    if (visited.contains(element)) {
      return {};
    }
    visited.add(element);

    final widget = element.widget;
    final rect = _globalPaintBounds(element.renderObject);

    final children =
        await _serializeChildren(element, visited: visited, depth: depth);

    final attributes = await _serializeAttributes(widget);
    final visualProperties = await _serializeVisualProperties(widget);
    final stateProperties = _serializeStateProperties(widget);

    final node = <String, dynamic>{
      'type': widget.runtimeType.toString(),
      'elementType': element.runtimeType.toString(),
      'description': widget.toStringShort(),
      'depth': depth,
      if (widget.key != null) 'key': widget.key.toString(),
      'attributes': attributes,
      'visual': visualProperties,
      'state': stateProperties,
      if (rect != null)
        'rect': {
          'x': rect.left,
          'y': rect.top,
          'width': rect.width,
          'height': rect.height,
        },
      'children': children,
    };
    // The root call owns the join, so the semantics tree is walked once per request.
    if (depth == 0) {
      _stampSemantics(node);
    }
    return node;
  }

  /// The widget tree pruned to the recordable widgets, in the same shape [serialize] returns so a
  /// consumer needs one parser. A single [ElevatedButton] is around 40 nested widgets and a list
  /// builds rows past the fold, so a full tree scales with the app rather than with the screen.
  static Future<List<Map<String, dynamic>>> serializeCulled(
    Element root,
    RenderTreeCulledModel options,
  ) async {
    final viewport = _globalPaintBounds(root.renderObject) ?? Rect.largest;
    final budget = _CullBudget(options.maxElements);
    final candidateTypes =
        (options.candidateTypes ?? _defaultCandidateTypes).toSet();

    final kept = await _cull(root, options, candidateTypes, viewport, budget, 0);
    final node = kept.isEmpty ? null : kept.first;
    if (node == null) {
      return <Map<String, dynamic>>[];
    }
    if (budget.truncated) {
      // Never truncate silently: a capped response must not look like a complete one.
      node['truncated'] = true;
      node['maxElements'] = options.maxElements;
    }
    _stampSemantics(node);
    return [node];
  }

  /// A route an opaque route was pushed over. The overlay keeps it built and laid out on screen and
  /// only turns its tickers off, so nothing on the route itself says it is hidden.
  static bool _isCoveredOverlayEntry(Element element, List<Element> children) {
    if (element.widget.runtimeType.toString() != _overlayEntryWidget) {
      return false;
    }
    // Only in this position does a disabled ticker mean hidden. An app may pause the animations of
    // a widget the user is still looking at.
    return children.any((child) {
      final widget = child.widget;
      return widget is TickerMode && !widget.enabled;
    });
  }

  /// Nodes this subtree contributes. A dropped node contributes its kept descendants, so removing
  /// framework plumbing never breaks the hierarchy.
  static Future<List<Map<String, dynamic>>> _cull(
    Element element,
    RenderTreeCulledModel options,
    Set<String> candidateTypes,
    Rect viewport,
    _CullBudget budget,
    int depth,
  ) async {
    final widget = element.widget;
    final state = _serializeStateProperties(widget);

    // An invisible subtree contributes nothing at all, not even its children. The unselected tabs of
    // an IndexedStack and the routes a navigator pushed away stay laid out on top of what the user
    // is looking at, so re-parenting their children would bury every visible element under twins.
    if (state['visible'] == false) {
      return <Map<String, dynamic>>[];
    }

    final List<Element> childElements = <Element>[];
    element.visitChildren(childElements.add);

    if (_isCoveredOverlayEntry(element, childElements)) {
      return <Map<String, dynamic>>[];
    }

    final List<Map<String, dynamic>> children = <Map<String, dynamic>>[];
    for (final child in childElements) {
      children.addAll(await _cull(
          child, options, candidateTypes, viewport, budget, depth + 1));
    }

    final rect = _globalPaintBounds(element.renderObject);
    if (options.viewportOnly && rect != null && !rect.overlaps(viewport)) {
      return children;
    }

    final attributes = await _serializeAttributes(widget);
    if (!options.includeText) {
      attributes.remove('text');
    }
    // The root is kept whether or not it is a candidate: it carries the viewport rect a consumer
    // scales every other coordinate by, and dropping it promotes an arbitrary widget to root.
    final isRoot = depth == 0;
    if (!isRoot && !_isCandidate(widget, attributes, candidateTypes)) {
      return children;
    }
    if (!isRoot && !budget.take()) {
      return children;
    }

    final node = <String, dynamic>{
      'type': widget.runtimeType.toString(),
      'elementType': element.runtimeType.toString(),
      'description': widget.toStringShort(),
      'depth': depth,
      if (widget.key != null) 'key': widget.key.toString(),
      'attributes': attributes,
      'visual': await _serializeVisualProperties(widget),
      'state': state,
      if (rect != null)
        'rect': {
          'x': rect.left,
          'y': rect.top,
          'width': rect.width,
          'height': rect.height,
        },
      'children': children,
    };
    return [_mergeByRect(node, candidateTypes)];
  }

  /// Kept by identity, never by exclusion: Flutter has hundreds of internal widget types and they
  /// change between SDK releases, so a deny-list rots on the next upgrade.
  static bool _isCandidate(
      Widget widget, Map<String, String?> attributes, Set<String> candidateTypes) {
    // Only a string key is one a test can be written against. The framework keys its own plumbing
    // with enums and objects, and those nodes would outrank the widget the user sees.
    if (widget.key is ValueKey<String>) {
      return true;
    }
    if (attributes.isNotEmpty) {
      return true;
    }
    final type = widget.runtimeType.toString();
    final generic = type.indexOf('<');
    return candidateTypes.contains(generic < 0 ? type : type.substring(0, generic));
  }

  /// One visual element surfaces as several widgets sharing a rect: a Text and its RichText, a
  /// button and its InkWell. Folding them keeps each contributor's data on one node.
  static Map<String, dynamic> _mergeByRect(
      Map<String, dynamic> node, Set<String> candidateTypes) {
    while (true) {
      final children = node['children'] as List<Map<String, dynamic>>;
      if (children.length != 1) {
        return node;
      }
      final child = children.first;
      if (!_sameRect(node['rect'], child['rect']) || !_mergeable(node, child)) {
        return node;
      }
      node['key'] ??= child['key'];
      (node['attributes'] as Map<String, String?>)
          .addAll(child['attributes'] as Map<String, String?>);
      node['children'] = child['children'];
      // A wrapper gives up its type so an IconButton inside a Semantics stays an IconButton, and so
      // does any plumbing that folded a widget the recorder knows into itself.
      if (_wrapperTypes.contains(node['type']) ||
          (!candidateTypes.contains(node['type']) &&
              candidateTypes.contains(child['type']))) {
        node['type'] = child['type'];
      }
    }
  }

  static bool _sameRect(dynamic first, dynamic second) =>
      first is Map && second is Map &&
      first['x'] == second['x'] &&
      first['y'] == second['y'] &&
      first['width'] == second['width'] &&
      first['height'] == second['height'];

  /// Only fold when nothing is lost: a differing key or text means two distinct elements.
  static bool _mergeable(
      Map<String, dynamic> node, Map<String, dynamic> child) {
    if (node['key'] != null && child['key'] != null &&
        node['key'] != child['key']) {
      return false;
    }
    final nodeAttributes = node['attributes'] as Map<String, String?>;
    final childAttributes = child['attributes'] as Map<String, String?>;
    for (final entry in childAttributes.entries) {
      final existing = nodeAttributes[entry.key];
      if (existing != null && existing != entry.value) {
        return false;
      }
    }
    return true;
  }

  static const Set<String> _wrapperTypes = {
    'Semantics',
    'InkWell',
    'InkResponse',
    'GestureDetector',
    'MouseRegion',
    'Listener',
    'Focus',
    'FocusScope',
    'Tooltip',
  };

  static const Set<String> _defaultCandidateTypes = {
    // interactive
    'ElevatedButton', 'FilledButton', 'TextButton', 'OutlinedButton', 'IconButton',
    'FloatingActionButton', 'CupertinoButton', 'BackButton', 'CloseButton',
    'SegmentedButton', 'DropdownButton', 'DropdownButtonFormField', 'DropdownMenuItem',
    'PopupMenuButton', 'PopupMenuItem', 'MenuItemButton', 'ToggleButtons', 'InkWell',
    'GestureDetector', 'Checkbox', 'CheckboxListTile', 'Radio', 'RadioListTile',
    'Switch', 'SwitchListTile', 'CupertinoSwitch', 'Slider', 'Draggable', 'DragTarget',
    'Dismissible', 'Stepper', 'TextField', 'TextFormField', 'EditableText',
    'CupertinoTextField', 'Autocomplete',
    // content
    'Text', 'RichText', 'SelectableText', 'Icon', 'Image', 'CircleAvatar', 'Tooltip',
    'Badge', 'CircularProgressIndicator', 'LinearProgressIndicator',
    // platform views hosting a webview
    'PlatformViewLink', 'PlatformViewSurface', 'AndroidView', 'AndroidViewSurface',
    'UiKitView', 'HtmlElementView',
    // structure
    'Scaffold', 'AppBar', 'SliverAppBar', 'BottomNavigationBar', 'NavigationBar',
    'NavigationRail', 'TabBar', 'TabBarView', 'Tab', 'Drawer', 'ListView', 'GridView',
    'PageView', 'SingleChildScrollView', 'CustomScrollView', 'ReorderableListView',
    'ListTile', 'Card', 'ExpansionTile', 'ExpansionPanel', 'DataTable', 'Table', 'Form',
    'AlertDialog', 'Dialog', 'SimpleDialog', 'BottomSheet', 'SnackBar', 'Chip',
    'ActionChip', 'ChoiceChip', 'FilterChip', 'InputChip',
  };

  /// Screen rect of a render object. [RenderObject.paintBounds] is defined as
  /// `Offset.zero & size`, so on its own it reports every element at (0,0).
  /// Joins the semantics onto the tree and records what was there to join with, so a response
  /// carrying none says whether the tree was empty or the rectangles did not line up.
  static void _stampSemantics(Map<String, dynamic> node) {
    final index = SemanticsIndex.build();
    _applySemantics(node, index);
    node['semanticsNodes'] = index.length;
    node['semanticsEnabled'] = SemanticsIndex.semanticsEnabled;
    node['semanticsSample'] = index.sample(6);
  }

  /// Carries Flutter's own semantics onto the widgets that produced it, matched by exact rectangle.
  /// A widget tree alone cannot say which node holds an identifier, and the platform tree only says
  /// so on Android.
  static void _applySemantics(Map<String, dynamic> node, SemanticsIndex index) {
    if (index.isEmpty) {
      return;
    }
    final values = index.at(node['rect'] as Map<String, dynamic>?);
    final attributes = node['attributes'];
    if (values != null && attributes is Map<String, String?>) {
      if (values.identifier.isNotEmpty) {
        attributes['semanticsIdentifier'] = values.identifier;
      }
      // The semantics tree wins over the Semantics widget: it also holds the implicit labels a
      // Text or a button contributes without anyone authoring one.
      if (values.label.isNotEmpty) {
        attributes['semanticsLabel'] = values.label;
      }
      if (values.value.isNotEmpty) {
        attributes['semanticsValue'] = values.value;
      }
    }
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map<String, dynamic>) {
          _applySemantics(child, index);
        }
      }
    }
  }

  static Rect? _globalPaintBounds(RenderObject? renderObject) {
    if (renderObject == null || !renderObject.attached) {
      return null;
    }
    try {
      // The transform rather than localToGlobal, so a scaled or rotated ancestor stays correct.
      return MatrixUtils.transformRect(
          renderObject.getTransformTo(null), renderObject.paintBounds);
    } catch (_) {
      // getTransformTo throws for an element that was never laid out.
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _serializeChildren(
    Element element, {
    required Set<Element> visited,
    required int depth,
  }) async {
    final List<Map<String, dynamic>> children = [];
    final List<Future<Map<String, dynamic>>> childrenFutures = [];
    element.visitChildren((child) {
      childrenFutures.add(serialize(child, visited: visited, depth: depth + 1));
    });
    final resolvedChildren = await Future.wait(childrenFutures);
    for (final childJson in resolvedChildren) {
      if (childJson.isNotEmpty) {
        children.add(childJson);
      }
    }
    return children;
  }

  static Future<Map<String, String?>> _serializeAttributes(
      Widget widget) async {
    final String? text = _readText(widget);

    String? semanticsLabel;
    String? tooltip;
    String? hintText;

    if (widget is Semantics) {
      semanticsLabel = widget.properties.label;
    } else if (widget is Tooltip) {
      tooltip = widget.message;
    } else if (widget is TextField) {
      hintText = widget.decoration?.hintText;
    }

    return {
      if (text?.isNotEmpty ?? false) 'text': text,
      if (semanticsLabel != null) 'semanticsLabel': semanticsLabel,
      if (tooltip != null) 'tooltip': tooltip,
      if (hintText != null) 'hintText': hintText,
    };
  }

  /// Text straight off the widget. The finder this replaces collected every element from the root
  /// for each node, which made serializing a tree of N nodes cost O(N squared) visits.
  static String? _readText(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is RichText) {
      return widget.text.toPlainText();
    }
    if (widget is EditableText) {
      return widget.controller.text;
    }
    if (widget is TextField) {
      return widget.controller?.value.text;
    }
    if (widget is TextFormField) {
      return widget.controller?.text;
    }
    return null;
  }

  static Future<Map<String, dynamic>> _serializeVisualProperties(
      Widget widget) async {
    double? fontSize;
    String? fontWeight;
    String? fontStyle;
    String? backgroundColor;
    String? color;

    if (widget is Text) {
      final style = widget.style;
      fontSize = style?.fontSize;
      fontWeight = style?.fontWeight?.toString();
      fontStyle = style?.fontStyle?.toString();
      color = style?.color?.toString();
    } else if (widget is Container) {
      if (widget.decoration is BoxDecoration) {
        backgroundColor =
            (widget.decoration as BoxDecoration).color?.toString();
      }
    } else if (widget is ElevatedButton) {
      final backgroundColorProperty = widget.style?.backgroundColor;
      final resolvedColor = backgroundColorProperty?.resolve(<WidgetState>{});
      if (resolvedColor != null) {
        backgroundColor = resolvedColor.toString();
      }
    }

    return {
      if (fontSize != null) 'fontSize': fontSize,
      if (fontWeight != null) 'fontWeight': fontWeight,
      if (fontStyle != null) 'fontStyle': fontStyle,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (color != null) 'color': color,
    };
  }

  static Map<String, dynamic> _serializeStateProperties(Widget widget) {
    bool? enabled;
    bool? focused;
    bool? visible;

    if (widget is EditableText) {
      focused = widget.focusNode.hasFocus;
    } else if (widget is TextField) {
      enabled = widget.enabled ?? true;
      focused = widget.focusNode?.hasFocus ?? false;
    } else if (widget is Visibility) {
      visible = widget.visible;
    } else if (widget is Offstage) {
      // A route the navigator pushed away, or any offstage subtree, is still laid out at its old
      // rect. Reporting it lets a consumer drop what the user cannot see or touch.
      visible = !widget.offstage;
    } else if (widget is Opacity && widget.opacity == 0) {
      visible = false;
    }

    return {
      if (enabled != null) 'enabled': enabled,
      if (focused != null) 'focused': focused,
      if (visible != null) 'visible': visible,
    };
  }
}
