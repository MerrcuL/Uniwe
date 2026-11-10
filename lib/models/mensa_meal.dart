class MensaMeal {
  final int id;
  final String name;
  final List<String> notes;
  final Map<String, double> prices;
  final String category;

  /// Cached diet flags — computed once from [notes].
  late final bool isVegan = notes.any((n) => n.toLowerCase().contains('vegan'));
  late final bool isVegetarian = !isVegan &&
      notes.any((n) {
        final l = n.toLowerCase();
        return l.contains('vegetarisch') || l.contains('ovo-lacto');
      });

  static final RegExp _notePrefix = RegExp(
    r'^(allergens?|allergene?|additives?|zusatzstoffe?)\s*:\s*',
    caseSensitive: false,
  );
  static final RegExp _noteCode = RegExp(r'^\d+[a-z]?\s+(?=\S)');

  /// A note as shown to the user: OpenMensa delivers labels such as
  /// "Allergens: 27 Sellerie"; the category prefix and the list number are
  /// noise on a tag, so only "Sellerie" remains.
  static String cleanNote(String note) => note
      .trim()
      .replaceFirst(_notePrefix, '')
      .replaceFirst(_noteCode, '')
      .trim();

  static final RegExp _codeAtStart = RegExp(r'^(\d+[a-z]?)(?=\s|$)');

  /// The list numbers of the allergens and additives in [notes], e.g.
  /// `['21a', '25', '28']` — the short form used by the compact menu.
  late final List<String> noteCodes = () {
    final seen = <String>{};
    return [
      for (final note in notes)
        if (_codeAtStart
                .firstMatch(note.trim().replaceFirst(_notePrefix, ''))
                ?.group(1)
            case final code? when seen.add(code))
          code,
    ];
  }();

  /// The allergens and additives in [notes], cleaned for display: without
  /// the diet labels (those are shown
  /// as their own tag) and without duplicates.
  late final List<String> displayNotes = () {
    final seen = <String>{};
    return [
      for (final note in notes)
        if (_isAllergenNote(note) && !_isDietNote(note))
          if (cleanNote(note) case final clean
              when clean.isNotEmpty && seen.add(clean))
            clean,
    ];
  }();

  /// Allergens and additives are the notes OpenMensa tags with a category
  /// prefix and/or a list number. Everything else (traffic-light rating,
  /// water and CO₂ footprint texts …) is marketing copy, not a label.
  static bool _isAllergenNote(String note) {
    final trimmed = note.trim();
    return _notePrefix.hasMatch(trimmed) || _codeAtStart.hasMatch(trimmed);
  }

  static bool _isDietNote(String note) {
    final lower = note.toLowerCase();
    return lower.contains('vegan') ||
        lower.contains('vegetarisch') ||
        lower.contains('ovo-lacto');
  }

  /// Neither vegan nor vegetarian (meat or fish).
  bool get isMeat => !isVegan && !isVegetarian;

  /// Whether the meal passes the diet [filters] ('vegetarian', 'vegan',
  /// 'meat'). No filter shows everything; several filters are alternatives.
  /// Vegan meals also count as vegetarian.
  bool matchesDiet(Set<String> filters) {
    if (filters.isEmpty) return true;
    return (filters.contains('vegan') && isVegan) ||
        (filters.contains('vegetarian') && (isVegetarian || isVegan)) ||
        (filters.contains('meat') && isMeat);
  }

  MensaMeal({
    required this.id,
    required this.name,
    required this.notes,
    required this.prices,
    required this.category,
  });

  factory MensaMeal.fromJson(Map<String, dynamic> json) {
    Map<String, double> parsedPrices = {};
    if (json['prices'] != null) {
      json['prices'].forEach((key, value) {
        if (value != null) {
          parsedPrices[key] = (value as num).toDouble();
        }
      });
    }

    return MensaMeal(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      notes: json['notes'] != null ? List<String>.from(json['notes']) : [],
      prices: parsedPrices,
      category: json['category'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'notes': notes,
    'prices': prices,
    'category': category,
  };
}
