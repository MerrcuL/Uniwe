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
