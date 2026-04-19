import 'package:flutter/services.dart';

class HapticService {
  /// CLOCK_TICK equivalent for segmented buttons
  static Future<void> selection(bool enabled) async {
    if (!enabled) return;
    await HapticFeedback.selectionClick();
  }
  
  /// TOGGLE_ON for switches
  static Future<void> toggleOn(bool enabled) async {
    if (!enabled) return;
    await HapticFeedback.lightImpact();
  }

  /// TOGGLE_OFF for switches
  static Future<void> toggleOff(bool enabled) async {
    if (!enabled) return;
    await HapticFeedback.lightImpact();
  }

  /// CONFIRM for all buttons
  static Future<void> confirm(bool enabled) async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
  }
}
