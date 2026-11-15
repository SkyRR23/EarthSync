/// A farmer's own field note (idea from OpenFarm's scouting observations):
/// what they saw, optional words and an optional photo. Kept on the phone,
/// and copied to the farmer's Firebase space when signed in.
enum NoteKind { pests, water, growth, weather, soil, other }

class FieldNote {
  const FieldNote({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.text,
    this.photo,
    this.cloudPhoto,
    this.simulated = false,
  });

  final String id;
  final DateTime createdAt;
  final NoteKind kind;
  final String text;
  final bool simulated;

  /// Photo file name in the app's photo folder (null = no photo).
  final String? photo;

  /// Firebase Storage path once uploaded (null = not uploaded yet).
  final String? cloudPhoto;

  FieldNote withCloudPhoto(String path) => FieldNote(
    id: id,
    createdAt: createdAt,
    kind: kind,
    text: text,
    photo: photo,
    cloudPhoto: path,
    simulated: simulated,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'kind': kind.name,
    'text': text,
    'photo': photo,
    'cloud_photo': cloudPhoto,
    'simulated': simulated,
  };

  factory FieldNote.fromJson(Map<String, dynamic> j) => FieldNote(
    id: j['id'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    kind: NoteKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => NoteKind.other,
    ),
    text: j['text'] as String? ?? '',
    photo: j['photo'] as String?,
    cloudPhoto: j['cloud_photo'] as String?,
    simulated: j['simulated'] == true,
  );
}
