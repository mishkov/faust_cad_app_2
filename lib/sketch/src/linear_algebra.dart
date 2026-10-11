import 'dart:math' as math;

double dot(List<double> a, List<double> b) {
  var value = 0.0;
  for (var i = 0; i < a.length; i++) {
    value += a[i] * b[i];
  }
  return value;
}

// Row-normalized, pivoted modified Gram-Schmidt with reorthogonalization.
// Counts independent differential directions, never the number of equations.
int matrixRank(List<List<double>> rows, double tolerance) {
  final remaining = <List<double>>[];
  for (final row in rows) {
    final norm = math.sqrt(dot(row, row));
    if (!norm.isFinite) throw StateError('Nonfinite rank matrix');
    if (norm != 0) remaining.add(row.map((v) => v / norm).toList());
  }
  var rank = 0;
  while (remaining.isNotEmpty) {
    var pivot = 0;
    for (var i = 1; i < remaining.length; i++) {
      if (dot(remaining[i], remaining[i]) >
          dot(remaining[pivot], remaining[pivot])) {
        pivot = i;
      }
    }
    final row = remaining.removeAt(pivot);
    final norm = math.sqrt(dot(row, row));
    if (norm <= tolerance) break;
    rank++;
    final unit = row.map((v) => v / norm).toList();
    for (final other in remaining) {
      for (var pass = 0; pass < 2; pass++) {
        final projection = dot(other, unit);
        for (var i = 0; i < other.length; i++) {
          other[i] -= projection * unit[i];
        }
      }
    }
  }
  return rank;
}

List<double>? solveLinear(List<List<double>> matrix, List<double> rhs) {
  final n = rhs.length;
  final a = List.generate(n, (i) => [...matrix[i], rhs[i]]);
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var i = col + 1; i < n; i++) {
      if (a[i][col].abs() > a[pivot][col].abs()) pivot = i;
    }
    if (a[pivot][col] == 0 || !a[pivot][col].isFinite) return null;
    final swap = a[col];
    a[col] = a[pivot];
    a[pivot] = swap;
    for (var i = col + 1; i < n; i++) {
      final factor = a[i][col] / a[col][col];
      for (var j = col + 1; j <= n; j++) {
        a[i][j] -= factor * a[col][j];
      }
      a[i][col] = 0;
    }
  }
  final result = List.filled(n, 0.0);
  for (var i = n - 1; i >= 0; i--) {
    var value = a[i][n];
    for (var j = i + 1; j < n; j++) {
      value -= a[i][j] * result[j];
    }
    result[i] = value / a[i][i];
  }
  return result.every((v) => v.isFinite) ? result : null;
}
