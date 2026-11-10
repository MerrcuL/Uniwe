import 'package:flutter/material.dart';

/// A menu section of the canteen, as named by OpenMensa (German).
class MensaCategory {
  const MensaCategory(
    this.key,
    this.labelEn,
    this.labelDe,
    this.icon, [
    this.aliases = const [],
  ]);

  /// Stable identifier, also what is persisted for the user's ordering.
  final String key;
  final String labelEn;
  final String labelDe;
  final IconData icon;

  /// Other names the API uses for the same section.
  final List<String> aliases;

  String label({required bool german}) => german ? labelDe : labelEn;

  /// Default display order.
  static const List<MensaCategory> all = [
    MensaCategory('Essen', 'Main Dishes', 'Hauptgerichte',
        Icons.restaurant_rounded, ['Hauptgericht']),
    MensaCategory('Beilagen', 'Side Dishes', 'Beilagen', Icons.rice_bowl_outlined),
    MensaCategory('Suppen', 'Soups', 'Suppen', Icons.soup_kitchen_outlined),
    MensaCategory('Salat', 'Salads', 'Salate', Icons.eco_outlined),
    MensaCategory('Dessert', 'Desserts', 'Desserts', Icons.icecream_outlined),
    MensaCategory('Aktionen', 'Specials', 'Aktionen', Icons.star_outline_rounded),
    MensaCategory('Vorspeisen', 'Starters', 'Vorspeisen', Icons.tapas_outlined),
  ];

  /// The known category an API category name belongs to, if any. Tolerates
  /// singular/plural variants ("Suppe"/"Suppen", "Salat"/"Salate").
  static MensaCategory? match(String apiName) {
    final name = apiName.trim().toLowerCase();
    if (name.isEmpty) return null;
    for (final category in all) {
      for (final candidate in [category.key, ...category.aliases]) {
        final c = candidate.toLowerCase();
        if (name.startsWith(c) || c.startsWith(name)) return category;
      }
    }
    return null;
  }

  /// [all] arranged by the keys in [savedOrder]; categories missing from it
  /// keep their default position at the end.
  static List<MensaCategory> ordered(List<String> savedOrder) {
    final result = <MensaCategory>[];
    for (final key in savedOrder) {
      for (final category in all) {
        if (category.key == key && !result.contains(category)) {
          result.add(category);
        }
      }
    }
    for (final category in all) {
      if (!result.contains(category)) result.add(category);
    }
    return result;
  }
}
