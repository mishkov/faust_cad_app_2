import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'profile_lineage.dart';

/// A document-storable cell reference scoped to its authored profile producer.
final class ProfileReference extends Equatable {
  /// Validates a directed boundary signature without retaining an arrangement.
  ProfileReference({required this.sourceId, required String signature})
    : signature = ProfileLineage.canonicalSignature(jsonDecode(signature)) {
    if (sourceId.isEmpty) {
      throw ArgumentError('Profile source ID must not be empty');
    }
  }

  /// Restores supported versioned value data; unsupported schemas throw.
  factory ProfileReference.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1 || json['sourceId'] is! String) {
      throw const FormatException('Unsupported profile reference');
    }
    return ProfileReference(
      sourceId: json['sourceId'] as String,
      signature: jsonEncode(json['signature']),
    );
  }

  /// The stable sketch feature/output identity that owns the entity IDs.
  final String sourceId;

  /// The canonical outer/hole traversal, authored directions, and junctions.
  final String signature;

  /// The authored boundary source IDs, used only to exclude unrelated candidates.
  Set<String> get boundarySourceIds {
    final value = jsonDecode(signature) as List;
    final loops = [value[0], ...(value[1] as List)];
    return Set.unmodifiable({
      for (final loop in loops)
        for (final span in loop as List)
          for (final source in (span as List)[1] as List)
            (source as List)[0] as String,
    });
  }

  /// Exports finite value data suitable for document parameters and JSON storage.
  Map<String, Object?> toJson() => {
    'version': 1,
    'sourceId': sourceId,
    'signature': jsonDecode(signature),
  };

  @override
  List<Object> get props => [sourceId, signature];
}
