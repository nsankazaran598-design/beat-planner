import 'dart:convert';

/// Одна запись журнала: изменение полей одной сущности.
///
/// В журнале хранится одной строкой JSON:
/// `{"h":"<hlc>","e":"task","i":"<id>","f":{"title":"…"}}`.
class Op {
  const Op({
    required this.hlc,
    required this.entity,
    required this.id,
    required this.fields,
  });

  final String hlc;
  final String entity;
  final String id;
  final Map<String, Object?> fields;

  static const deletedField = '_deleted';

  factory Op.fromJson(Map<String, Object?> json) => Op(
        hlc: json['h']! as String,
        entity: json['e']! as String,
        id: json['i']! as String,
        fields: Map<String, Object?>.from(json['f']! as Map),
      );

  Map<String, Object?> toJson() => {'h': hlc, 'e': entity, 'i': id, 'f': fields};

  String encode() => jsonEncode(toJson());

  /// Возвращает null для повреждённой строки (например, оборванной при сбое).
  static Op? tryDecode(String line) {
    if (line.trim().isEmpty) return null;
    try {
      return Op.fromJson(jsonDecode(line) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }
}
