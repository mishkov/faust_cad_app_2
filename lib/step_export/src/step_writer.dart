import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../cad_scene/cad_curves/circular_cad_curve.dart';
import '../../cad_scene/cad_curves/linear_cad_curve.dart';
import '../../cad_scene/cad_primitivies/edge.dart';
import '../../cad_scene/cad_primitivies/face.dart';
import '../../cad_scene/cad_primitivies/face_orientation.dart';
import '../../cad_scene/cad_primitivies/shell.dart';
import '../../cad_scene/cad_primitivies/solid.dart';
import '../../cad_scene/cad_primitivies/vertex.dart';
import '../../cad_scene/cad_primitivies/wire.dart';
import '../../cad_scene/cad_surfaces/cad_surface.dart';
import '../../cad_scene/cad_surfaces/cylinder_surface.dart';
import '../../cad_scene/cad_surfaces/plane_surface.dart';
import '../../cad_scene/geometry/planar_frame.dart';
import '../../cad_scene/geometry/src/vector_validation.dart';

// Entity references retain topology identity; coincident vertices are not merged.
final class StepWriter {
  final _data = StringBuffer();
  var _nextId = 1;
  final _vertices = Map<Vertex, String>.identity();
  final _edges = Map<Vertex, List<({Edge edge, String ref})>>.identity();
  final _circles = Map<CircularCadCurve, String>.identity();
  final _surfaces = Map<CadSurface, String>.identity();

  String write(List<Solid> solids, DateTime timestamp) {
    final length = _entity(
      '(LENGTH_UNIT()NAMED_UNIT(*)SI_UNIT(.MILLI.,.METRE.))',
    );
    final angle = _entity(
      '(NAMED_UNIT(*)PLANE_ANGLE_UNIT()SI_UNIT(\$, .RADIAN.))',
    );
    final solidAngle = _entity(
      '(NAMED_UNIT(*)SI_UNIT(\$,.STERADIAN.)SOLID_ANGLE_UNIT())',
    );
    final uncertainty = _entity(
      "UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-8),$length,"
      "'distance_accuracy_value','')",
    );
    final context = _entity(
      '(GEOMETRIC_REPRESENTATION_CONTEXT(3)'
      'GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT(($uncertainty))'
      'GLOBAL_UNIT_ASSIGNED_CONTEXT(($length,$angle,$solidAngle))'
      "REPRESENTATION_CONTEXT('','3D'))",
    );
    final application = _entity("APPLICATION_CONTEXT('automotive design')");
    _entity(
      "APPLICATION_PROTOCOL_DEFINITION('international standard',"
      "'automotive_design',2000,$application)",
    );
    final productContext = _entity(
      "PRODUCT_CONTEXT('',$application,'mechanical')",
    );
    final product = _entity("PRODUCT('model','Model','',($productContext))");
    final formation = _entity("PRODUCT_DEFINITION_FORMATION('','',$product)");
    final definitionContext = _entity(
      "PRODUCT_DEFINITION_CONTEXT('part definition',$application,'design')",
    );
    final definition = _entity(
      "PRODUCT_DEFINITION('design','',$formation,$definitionContext)",
    );
    final shape = _entity("PRODUCT_DEFINITION_SHAPE('','',$definition)");
    final bodies = [
      for (var i = 0; i < solids.length; i++) _solid(solids[i], i + 1),
    ];
    final placement = _placement(PlanarFrame.xy());
    final representation = _entity(
      "ADVANCED_BREP_SHAPE_REPRESENTATION('Model',"
      '($placement,${bodies.join(',')}),$context)',
    );
    _entity('SHAPE_DEFINITION_REPRESENTATION($shape,$representation)');
    final date = timestamp.toUtc().toIso8601String();
    return 'ISO-10303-21;\nHEADER;\n'
        "FILE_DESCRIPTION(('Analytic solid bodies'),'2;1');\n"
        "FILE_NAME('model.step','$date',(''),(''),'Faust CAD','Faust CAD','');\n"
        "FILE_SCHEMA(('AUTOMOTIVE_DESIGN'));\n"
        'ENDSEC;\nDATA;\n$_data'
        'ENDSEC;\nEND-ISO-10303-21;\n';
  }

  String _solid(Solid solid, int index) {
    final outer = _shell(solid.shells.first);
    final voids = [
      for (final shell in solid.shells.skip(1))
        // Cavity faces point into the void in the app. STEP stores an outward
        // closed shell, then reverses it through ORIENTED_CLOSED_SHELL.
        _entity(
          "ORIENTED_CLOSED_SHELL('',*,${_shell(shell, reverse: true)},.F.)",
        ),
    ];
    return voids.isEmpty
        ? _entity("MANIFOLD_SOLID_BREP('Body $index',$outer)")
        : _entity("BREP_WITH_VOIDS('Body $index',$outer,(${voids.join(',')}))");
  }

  String _shell(Shell shell, {bool reverse = false}) {
    if (!shell.isClosed) {
      throw StateError('A solid boundary is no longer a closed manifold.');
    }
    final faces = [for (final face in shell.faces) _face(face, reverse)];
    return _entity("CLOSED_SHELL('',(${faces.join(',')}))");
  }

  String _face(Face face, bool reverse) {
    final forward = (face.orientation == FaceOrientation.forward) != reverse;
    final bounds = [
      _bound(face.outerWire, forward, outer: true),
      for (final wire in face.innerWires) _bound(wire, forward),
    ];
    return _entity(
      "ADVANCED_FACE('',(${bounds.join(',')}),${_surface(face.surface)},"
      '${_boolean(forward)})',
    );
  }

  String _bound(Wire wire, bool forward, {bool outer = false}) {
    final edges = [for (final edge in wire.edges) _orientedEdge(edge)];
    final loop = _entity("EDGE_LOOP('',(${edges.join(',')}))");
    return _entity(
      "${outer ? 'FACE_OUTER_BOUND' : 'FACE_BOUND'}('',"
      '$loop,${_boolean(forward)})',
    );
  }

  String _orientedEdge(Edge edge) {
    // The same boundary may be represented by distinct reversed Edge instances.
    // Bucket by endpoint identity, then compare trims to keep complementary arcs.
    for (final existing
        in _edges[edge.begin] ?? <({Edge edge, String ref})>[]) {
      if (edge.hasSameBoundary(existing.edge)) {
        final forward = identical(edge.begin, existing.edge.begin);
        return _entity(
          "ORIENTED_EDGE('',*,*,${existing.ref},${_boolean(forward)})",
        );
      }
    }
    final begin = _vertex(edge.begin);
    final end = _vertex(edge.end);
    final curve = edge.curve;
    late String geometry;
    var sameSense = true;
    if (curve is LinearCadCurve) {
      final delta = edge.end.vector - edge.begin.vector;
      final direction = _direction(normalizedVector3(delta, 'linear edge'));
      final vector = _entity("VECTOR('',$direction,1.)");
      geometry = _entity("LINE('',${_point(edge.begin.vector)},$vector)");
    } else if (curve is CircularCadCurve) {
      if (!edge.hasValidCircularEndpoints) {
        throw StateError('A circular edge has inconsistent endpoints.');
      }
      geometry = _circles.putIfAbsent(
        curve,
        () => _entity(
          "CIRCLE('',${_placement(curve.frame)},${_real(curve.radius)})",
        ),
      );
      sameSense = edge.trim!.sweepAngle > 0;
    } else {
      throw UnsupportedError(
        'STEP export does not support ${curve.runtimeType}.',
      );
    }
    final ref = _entity(
      "EDGE_CURVE('',$begin,$end,$geometry,${_boolean(sameSense)})",
    );
    for (final vertex in [edge.begin, edge.end]) {
      (_edges[vertex] ??= []).add((edge: edge, ref: ref));
    }
    return _entity("ORIENTED_EDGE('',*,*,$ref,.T.)");
  }

  String _vertex(Vertex vertex) => _vertices.putIfAbsent(
    vertex,
    () => _entity("VERTEX_POINT('',${_point(vertex.vector)})"),
  );

  String _surface(CadSurface surface) => _surfaces.putIfAbsent(surface, () {
    if (surface is PlaneSurface) {
      final frame = PlanarFrame.fromPlane(
        plane: surface,
        preferredDirection: surface.normal.x.abs() < 0.9
            ? Vector3(1, 0, 0)
            : Vector3(0, 1, 0),
      );
      return _entity("PLANE('',${_placement(frame)})");
    }
    if (surface is CylinderSurface) {
      return _entity(
        "CYLINDRICAL_SURFACE('',${_placement(surface.frame)},"
        '${_real(surface.radius)})',
      );
    }
    throw UnsupportedError(
      'STEP export does not support ${surface.runtimeType}.',
    );
  });

  String _placement(PlanarFrame frame) => _entity(
    "AXIS2_PLACEMENT_3D('',${_point(frame.origin)},"
    '${_direction(frame.normal)},${_direction(frame.xAxis)})',
  );

  String _point(Vector3 point) =>
      _entity("CARTESIAN_POINT('',${_coordinates(point)})");
  String _direction(Vector3 direction) =>
      _entity("DIRECTION('',${_coordinates(direction)})");
  String _coordinates(Vector3 v) =>
      '(${_real(v.x)},${_real(v.y)},${_real(v.z)})';
  String _boolean(bool value) => value ? '.T.' : '.F.';

  String _real(double value) {
    if (!value.isFinite) throw StateError('STEP coordinates must be finite.');
    // STEP real literals require a decimal point and an uppercase exponent.
    final text = (value == 0 ? 0.0 : value).toString().toUpperCase();
    if (text.contains('.')) return text;
    return text.replaceFirst('E', '.E');
  }

  String _entity(String definition) {
    final reference = '#${_nextId++}';
    _data.writeln('$reference=$definition;');
    return reference;
  }
}
