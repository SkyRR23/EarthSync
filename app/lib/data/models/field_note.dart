/// A farmer's own field note (idea from OpenFarm's scouting observations,
/// simplified: no account, no upload — stored on the phone only).
enum NoteKind { pests, water, growth, weather, other }

class FieldNote {
  const FieldNote({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.text,
  });

  final String id;
  final DateTime createdAt;
  final NoteKind kind;
  final String text;

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'kind': kind.name,
    'text': text,
  };

  factory FieldNote.fromJson(Map<String, dynamic> j) => FieldNote(
    id: j['id'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    kind: NoteKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => NoteKind.other,
    ),
    text: j['text'] as String? ?? '',
  );
}
