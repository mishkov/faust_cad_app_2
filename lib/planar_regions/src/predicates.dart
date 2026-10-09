import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart' show Vector2;

// Topological decisions use the exact dyadic values of finite input doubles.
// Constructing intersection coordinates still uses floating point; an uncertain
// construction is diagnosed rather than altering the exact contact decision.
class _Dyadic {
  _Dyadic(this.n, this.e);
  factory _Dyadic.of(double value) {
    final bytes = ByteData(8)..setFloat64(0, value, Endian.big);
    final high = bytes.getUint32(0, Endian.big);
    final low = bytes.getUint32(4, Endian.big);
    final exponent = (high >> 20) & 0x7ff;
    var mantissa = (BigInt.from(high & 0xfffff) << 32) | BigInt.from(low);
    if (exponent != 0) mantissa |= BigInt.one << 52;
    return _Dyadic(
      (high & 0x80000000) == 0 ? mantissa : -mantissa,
      exponent == 0 ? -1074 : exponent - 1023 - 52,
    );
  }
  final BigInt n;
  final int e;
  _Dyadic operator +(_Dyadic b) {
    final exponent = e < b.e ? e : b.e;
    return _Dyadic((n << (e - exponent)) + (b.n << (b.e - exponent)), exponent);
  }

  _Dyadic operator -(_Dyadic b) => this + _Dyadic(-b.n, b.e);
  _Dyadic operator *(_Dyadic b) => _Dyadic(n * b.n, e + b.e);
  _Dyadic get squared => this * this;
  int get sign => n.sign;
}

_Dyadic _x(Vector2 p) => _Dyadic.of(p.x);
_Dyadic _y(Vector2 p) => _Dyadic.of(p.y);
_Dyadic _cross(Vector2 a, Vector2 b, Vector2 c, Vector2 d) =>
    (_x(b) - _x(a)) * (_y(d) - _y(c)) - (_y(b) - _y(a)) * (_x(d) - _x(c));

/// Returns the exact orientation sign of three finite input points.
int orientation(Vector2 a, Vector2 b, Vector2 c) => _cross(a, b, a, c).sign;

/// Returns the exact cross-product sign of two original segment directions.
int directionCross(Vector2 a, Vector2 b, Vector2 c, Vector2 d) =>
    _cross(a, b, c, d).sign;

/// Tests exact closed segment intersection, including collinear overlap.
bool segmentsMeet(Vector2 a, Vector2 b, Vector2 c, Vector2 d) {
  if (!boundsMeet(a, b, c, d)) return false;
  final ac = orientation(a, b, c), ad = orientation(a, b, d);
  final ca = orientation(c, d, a), cb = orientation(c, d, b);
  return ac * ad <= 0 && ca * cb <= 0;
}

/// Tests inclusive axis-aligned endpoint bounds without any proximity tolerance.
bool boundsMeet(Vector2 a, Vector2 b, Vector2 c, Vector2 d) {
  bool overlap(double a, double b, double c, double d) {
    final loA = a < b ? a : b, hiA = a > b ? a : b;
    final loB = c < d ? c : d, hiB = c > d ? c : d;
    return loA <= hiB && loB <= hiA;
  }

  return overlap(a.x, b.x, c.x, d.x) && overlap(a.y, b.y, c.y, d.y);
}

/// Compares squared center distance against outer and inner circle contacts.
(int, int) circleContacts(Vector2 a, double ra, Vector2 b, double rb) {
  final distance2 = (_x(a) - _x(b)).squared + (_y(a) - _y(b)).squared;
  final radiusA = _Dyadic.of(ra), radiusB = _Dyadic.of(rb);
  return (
    (distance2 - (radiusA + radiusB).squared).sign,
    (distance2 - (radiusA - radiusB).squared).sign,
  );
}

/// Returns the exact discriminant sign for a line's infinite support and circle.
int lineCircleContact(Vector2 a, Vector2 b, Vector2 center, double radius) {
  final length2 = (_x(b) - _x(a)).squared + (_y(b) - _y(a)).squared;
  return (_Dyadic.of(radius).squared * length2 -
          _cross(a, b, a, center).squared)
      .sign;
}
