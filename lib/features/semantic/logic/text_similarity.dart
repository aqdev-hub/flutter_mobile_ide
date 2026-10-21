import 'dart:math' as math;

/// أقرب اسم من [candidates] لـ[name] لاقتراح "هل تقصد...؟".
///
/// - فرق حالة الأحرف فقط (AppColor/appColor) يُقترَح دائمًا.
/// - الأخطاء الإملائية (حذف/إضافة/استبدال/تبديل حرفين متجاورين) بمسافة 1
///   للأسماء القصيرة و2 للطويلة (8+)، ولا تُقترح للأسماء الأقصر من [minLength]
///   حتى لا نخلط بين أسماء قصيرة مختلفة فعلًا.
String? nearestName(String name, Iterable<String> candidates, {int minLength = 4}) {
  final lower = name.toLowerCase();
  String? best;
  var bestDistance = 1 << 30;
  for (final candidate in candidates) {
    if (candidate == name) continue;
    if (candidate.toLowerCase() == lower) return candidate;
    if (name.length < minLength || candidate.length < minLength) continue;
    final distance = _distance(name, candidate);
    final limit = name.length >= 8 ? 2 : 1;
    if (distance <= limit && distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

/// مسافة Levenshtein مع تبديل المتجاورَين (Optimal String Alignment).
int _distance(String a, String b) {
  final n = a.length;
  final m = b.length;
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = math.min(math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        v = math.min(v, d[i - 2][j - 2] + 1);
      }
      d[i][j] = v;
    }
  }
  return d[n][m];
}
