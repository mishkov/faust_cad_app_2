import 'package:equatable/equatable.dart';

import 'profile_reference.dart';

/// An atomic persistent selection of cells from one authored profile producer.
final class ProfileSelectionReference extends Equatable {
  /// Freezes and canonicalizes a nonempty selection, removing duplicates.
  ProfileSelectionReference(Iterable<ProfileReference> references)
    : references = List.unmodifiable(
        references.toSet().toList()
          ..sort((a, b) => a.signature.compareTo(b.signature)),
      ) {
    if (this.references.isEmpty ||
        this.references.map((r) => r.sourceId).toSet().length != 1) {
      throw ArgumentError('Select cells from exactly one profile producer');
    }
  }

  /// Restores supported selection data without topology or arrangement objects.
  factory ProfileSelectionReference.fromJson(Map<String, Object?> json) {
    final values = json['profiles'];
    if (json['version'] != 1 ||
        values is! List ||
        values.any((v) => v is! Map<String, Object?>)) {
      throw const FormatException('Unsupported profile selection');
    }
    return ProfileSelectionReference(
      values.map((v) => ProfileReference.fromJson(v as Map<String, Object?>)),
    );
  }

  /// The selected cell values in canonical order.
  final List<ProfileReference> references;

  /// Exports finite value data for document storage.
  Map<String, Object?> toJson() => {
    'version': 1,
    'profiles': references.map((r) => r.toJson()).toList(),
  };

  @override
  List<Object> get props => [references];
}
