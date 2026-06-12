String cleanGeneratedText(String value) {
  var text = value;

  text = text
      .replaceAllMapped(
        RegExp(r'\\\[(.*?)\\\]', dotAll: true),
        (match) => match.group(1) ?? '',
      )
      .replaceAllMapped(
        RegExp(r'\\\((.*?)\\\)', dotAll: true),
        (match) => match.group(1) ?? '',
      )
      .replaceAllMapped(
        RegExp(r'\$\$(.*?)\$\$', dotAll: true),
        (match) => match.group(1) ?? '',
      )
      .replaceAllMapped(
        RegExp(r'\$(.*?)\$', dotAll: true),
        (match) => match.group(1) ?? '',
      );

  text = text
      .replaceAllMapped(
        RegExp(r'\\frac\s*\{([^{}]+)\}\s*\{([^{}]+)\}'),
        (match) => '${match.group(1)}/${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'\\(vec|bar|hat|tilde)\s*\{([^{}]+)\}'),
        (match) => '${match.group(1)}(${match.group(2)})',
      )
      .replaceAllMapped(
        RegExp(r'\\(vec|bar|hat|tilde)\s*\(([^()]*)\)'),
        (match) => '${match.group(1)}(${match.group(2)})',
      );

  const replacements = {
    r'\cdot': '·',
    r'\times': '×',
    r'\leq': '≤',
    r'\le': '≤',
    r'\geq': '≥',
    r'\ge': '≥',
    r'\neq': '≠',
    r'\approx': '≈',
    r'\infty': '∞',
    r'\alpha': 'alpha',
    r'\beta': 'beta',
    r'\gamma': 'gamma',
    r'\delta': 'delta',
    r'\theta': 'theta',
    r'\lambda': 'lambda',
    r'\mu': 'mu',
    r'\sigma': 'sigma',
  };
  for (final entry in replacements.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }

  text = text
      .replaceAll(
        RegExp(r'\n\s*(출처|Source)\s*:\s*mat_[A-Za-z0-9_,\s]+$', dotAll: true),
        '',
      )
      .replaceAllMapped(
        RegExp(r'\\([A-Za-z]+)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();

  return text;
}
