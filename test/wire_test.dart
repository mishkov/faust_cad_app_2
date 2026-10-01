import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  late Vertex a;
  late Vertex b;
  late Vertex c;

  Edge edge(Vertex begin, Vertex end) =>
      Edge(begin, end, curve: const LinearCadCurve());

  setUp(() {
    a = Vertex(Vector3.zero());
    b = Vertex(Vector3(1, 0, 0));
    c = Vertex(Vector3(1, 1, 0));
  });

  test('open wire preserves edge order and shared topology references', () {
    final ab = edge(a, b);
    final bc = edge(b, c);
    final wire = Wire([ab, bc]);
    final otherWire = Wire([bc]);

    expect(wire.edges, orderedEquals([ab, bc]));
    expect(wire.edges.first, same(ab));
    expect(wire.edges.last, same(otherWire.edges.single));
    expect(wire.edges.first.begin, same(a));
    expect(wire.edges.first.end, same(wire.edges.last.begin));
    expect(wire.edges.last.end, same(c));
    expect(wire.isClosed, isFalse);
  });

  test('closed wire returns to the same starting vertex instance', () {
    final wire = Wire([edge(a, b), edge(b, c), edge(c, a)]);

    expect(wire.isClosed, isTrue);
    expect(wire.edges.last.end, same(wire.edges.first.begin));
  });

  test('single edge may form an open or closed wire', () {
    expect(Wire([edge(a, b)]).isClosed, isFalse);
    expect(Wire([edge(a, a)]).isClosed, isTrue);
  });

  test('matching endpoint coordinates do not close a wire', () {
    final duplicateA = Vertex(a.vector.clone());
    final wire = Wire([edge(a, b), edge(b, duplicateA)]);

    expect(wire.isClosed, isFalse);
  });

  test('rejects disconnected, reversed, or unordered adjacent edges', () {
    expect(() => Wire([edge(a, b), edge(c, a)]), throwsArgumentError);
    expect(() => Wire([edge(a, b), edge(c, b)]), throwsArgumentError);
    expect(() => Wire([edge(b, c), edge(a, b)]), throwsArgumentError);
    expect(
      () => Wire([edge(a, b), edge(b, c), edge(a, c)]),
      throwsArgumentError,
    );
  });

  test('rejects duplicate connecting vertices with identical coordinates', () {
    final duplicateB = Vertex(b.vector.clone());

    expect(() => Wire([edge(a, b), edge(duplicateB, c)]), throwsArgumentError);
  });

  test('rejects an empty edge chain', () {
    expect(() => Wire([]), throwsArgumentError);
  });

  test('edge list cannot be changed after connectivity validation', () {
    final ab = edge(a, b);
    final bc = edge(b, c);
    final suppliedEdges = [ab, bc];
    final wire = Wire(suppliedEdges);

    suppliedEdges.clear();

    expect(wire.edges, orderedEquals([ab, bc]));
    expect(() => wire.edges.add(edge(c, a)), throwsUnsupportedError);
    expect(() => wire.edges[0] = bc, throwsUnsupportedError);
    expect(() => wire.edges.clear(), throwsUnsupportedError);
    expect(wire.isClosed, isFalse);
  });
}
