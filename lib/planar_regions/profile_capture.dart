import 'profile_reference.dart';
import 'region_reference.dart';

/// The explicit outcome of capturing a persistable profile identity.
final class ProfileCapture {
  /// Records a reference only when the current cell is uniquely identifiable.
  const ProfileCapture(this.status, {this.reference});

  /// The capture outcome; ambiguous and unsupported cells publish no reference.
  final RegionResolutionStatus status;

  /// The document value, present only for a resolved capture.
  final ProfileReference? reference;
}
