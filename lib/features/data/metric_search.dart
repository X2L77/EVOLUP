import '../../data/metrics/metric_models.dart';

/// Lowercase text without French accents, for search.
String normalizeSearch(String text) {
  const accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
    '’': "'",
  };
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    buffer.write(accents[char] ?? char);
  }
  return buffer.toString().trim();
}

/// Whether every word of [query] appears in the metric's name,
/// description, category or keywords.
bool matchesSearch(
  MetricDefinition definition,
  String categoryName,
  String query,
) {
  final words = normalizeSearch(query).split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return true;
  final haystack = normalizeSearch(
    [
      definition.name,
      definition.description,
      categoryName,
      ...definition.keywords,
    ].join(' '),
  );
  return words.every(haystack.contains);
}
