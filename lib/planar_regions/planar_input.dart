/// Independently identified local 2D geometry, separate from sketch or topology.
abstract class PlanarInput {
  /// Creates an input with a caller-owned stable, nonempty identity.
  PlanarInput(this.id) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'Must be nonempty');
  }

  /// The semantic identity; callers must retain it across geometric edits.
  final String id;
}
