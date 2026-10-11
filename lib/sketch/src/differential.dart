import 'dart:math' as math;

// Forward automatic differentiation keeps rank analysis independent of a
// finite-difference step size and gives the optimizer the same equations.
final class Differential {
  Differential(this.value, this.gradient);
  final double value;
  final List<double> gradient;

  factory Differential.constant(double value, int n) =>
      Differential(value, List.filled(n, 0));
  factory Differential.variable(double value, int n, int index) =>
      Differential(value, List.generate(n, (i) => i == index ? 1.0 : 0.0));

  Differential operator +(Differential b) => Differential(
    value + b.value,
    List.generate(gradient.length, (i) => gradient[i] + b.gradient[i]),
  );
  Differential operator -(Differential b) => Differential(
    value - b.value,
    List.generate(gradient.length, (i) => gradient[i] - b.gradient[i]),
  );
  Differential operator *(Differential b) => Differential(
    value * b.value,
    List.generate(
      gradient.length,
      (i) => gradient[i] * b.value + value * b.gradient[i],
    ),
  );
  Differential operator /(Differential b) => Differential(
    value / b.value,
    List.generate(
      gradient.length,
      (i) => (gradient[i] - value / b.value * b.gradient[i]) / b.value,
    ),
  );

  static Differential norm(Differential x, Differential y) {
    final magnitude = math.sqrt(x.value * x.value + y.value * y.value);
    // At zero, choose a deterministic subgradient to allow a positive distance
    // to grow from coincident initial coordinates. Zero-distance constraints
    // themselves use two linear coordinate equations instead.
    if (magnitude == 0) return Differential(0, List.of(x.gradient));
    return Differential(
      magnitude,
      List.generate(
        x.gradient.length,
        (i) =>
            x.value / magnitude * x.gradient[i] +
            y.value / magnitude * y.gradient[i],
      ),
    );
  }
}
