import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/camera_side.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/view_cube.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/selection/principal_plane_views.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';

Future<void> startSketch(
  WidgetTester tester, {
  PrincipalPlane plane = PrincipalPlane.xy,
}) async {
  await tester.tap(find.byKey(const Key('start-sketch')));
  await tester.pump();
  if (plane == PrincipalPlane.yz &&
      tester.widget<CadScene>(find.byType(CadScene)).cameraConfig.yaw.abs() <
          1e-9) {
    tester.widget<ViewCube>(find.byType(ViewCube)).onSelected(CameraSide.right);
    await tester.pumpAndSettle();
  }
  final scene = tester.widget<CadScene>(find.byType(CadScene));
  final rect = tester.getRect(find.byType(CadScene));
  final projection = CameraProjection(scene.cameraConfig);
  final center = PrincipalPlaneViews.frame(plane)
      .localToWorld(Vector2(26, plane == PrincipalPlane.xy ? 38 : 26));
  final screen = projection.project(
    projection.toCameraSpace(center),
    screen: rect.size,
  );
  await tester.tapAt(rect.topLeft + Offset(screen.x, screen.y));
  await tester.pumpAndSettle();
}
