/// Request options for the culled render tree. Every field is optional and defaults to what a
/// recorder wants: only what is on screen, a bounded response, and text included.
class RenderTreeCulledModel {
  static const int defaultMaxElements = 500;

  final bool viewportOnly;
  final List<String>? candidateTypes;
  final int maxElements;
  final bool includeText;

  RenderTreeCulledModel({
    this.viewportOnly = true,
    this.candidateTypes,
    this.maxElements = defaultMaxElements,
    this.includeText = true,
  });

  factory RenderTreeCulledModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return RenderTreeCulledModel();
    }
    final types = json['candidateTypes'];
    return RenderTreeCulledModel(
      viewportOnly: json['viewportOnly'] as bool? ?? true,
      candidateTypes: types is List
          ? types.map((type) => type.toString()).toList(growable: false)
          : null,
      maxElements: json['maxElements'] as int? ?? defaultMaxElements,
      includeText: json['includeText'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'viewportOnly': viewportOnly,
        'candidateTypes': candidateTypes,
        'maxElements': maxElements,
        'includeText': includeText,
      };
}
