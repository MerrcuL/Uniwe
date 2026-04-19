import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = Platform.localeName.startsWith('de') ? const Locale('de') : const Locale('en');
  bool _useDynamicColor = false;
  String _campus = 'WH';
  bool _amoledTheme = false;
  bool _showWeekends = false;
  String _mensaPriceCategory = 'students';
  bool _compactMensaView = false;
  List<String> _mensaCategoryOrder = [];
  bool _hapticsEnabled = true;
  bool _showBreakTime = true;
  bool _compactTimetableView = false;
  bool _animationsEnabled = true;
  bool _timetableIsWeekView = false;
  bool _hideLabels = false;
  bool _lsfOnEmailLongPress = false;

  bool _isLoaded = false;

  // Cached prefs instance — avoids repeated getInstance() on every write
  SharedPreferences? _prefs;

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  bool get useDynamicColor => _useDynamicColor;
  String get campus => _campus;
  int get canteenId => _campus == 'TA' ? 2036 : 2037;
  bool get amoledTheme => _amoledTheme;
  bool get showWeekends => _showWeekends;
  String get mensaPriceCategory => _mensaPriceCategory;
  bool get compactMensaView => _compactMensaView;
  List<String> get mensaCategoryOrder => _mensaCategoryOrder;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get showBreakTime => _showBreakTime;
  bool get compactTimetableView => _compactTimetableView;
  bool get animationsEnabled => _animationsEnabled;
  bool get timetableIsWeekView => _timetableIsWeekView;
  bool get hideLabels => _hideLabels;
  bool get lsfOnEmailLongPress => _lsfOnEmailLongPress;
  bool get isLoaded => _isLoaded;

  SettingsService();

  Future<void> loadSettings() async {
    if (_isLoaded) return;
    _prefs = await SharedPreferences.getInstance();

    final themeString = _prefs!.getString('themeMode');
    _themeMode = switch (themeString) {
      'light' => ThemeMode.light,
      'dark'  => ThemeMode.dark,
      _       => ThemeMode.system,
    };

    final localeString = _prefs!.getString('locale');
    if (localeString != null) {
      _locale = Locale(localeString);
    }

    final savedCampus = _prefs!.getString('campus');
    if (savedCampus != null) {
      _campus = savedCampus;
    } else {
      final oldCanteenId = _prefs!.getInt('canteenId');
      _campus = oldCanteenId == 2036 ? 'TA' : 'WH';
      _prefs!.setString('campus', _campus);
      _prefs!.remove('canteenId');
    }
    _useDynamicColor = _prefs!.getBool('useDynamicColor') ?? false;
    _amoledTheme     = _prefs!.getBool('amoledTheme')     ?? false;
    _showWeekends    = _prefs!.getBool('showWeekends')    ?? false;
    _mensaPriceCategory = _prefs!.getString('mensaPriceCategory') ?? 'students';
    _compactMensaView   = _prefs!.getBool('compactMensaView')    ?? false;
    _hapticsEnabled     = _prefs!.getBool('hapticsEnabled')      ?? true;
    _showBreakTime       = _prefs!.getBool('showBreakTime')       ?? true;
    _compactTimetableView = _prefs!.getBool('compactTimetableView') ?? false;
    _animationsEnabled     = _prefs!.getBool('animationsEnabled')      ?? true;
    _timetableIsWeekView   = _prefs!.getBool('timetableIsWeekView')    ?? false;
    _hideLabels            = _prefs!.getBool('hideLabels')             ?? false;
    _lsfOnEmailLongPress   = _prefs!.getBool('lsfOnEmailLongPress')    ?? false;
    final savedOrder    = _prefs!.getStringList('mensaCategoryOrder');
    _mensaCategoryOrder = savedOrder ?? [];

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode newThemeMode) async {
    if (newThemeMode == _themeMode) return;
    _themeMode = newThemeMode;
    notifyListeners();
    await _prefs?.setString('themeMode', newThemeMode.name);
  }

  Future<void> updateLocale(Locale newLocale) async {
    if (newLocale == _locale) return;
    _locale = newLocale;
    notifyListeners();
    await _prefs?.setString('locale', newLocale.languageCode);
  }

  Future<void> updateUseDynamicColor(bool use) async {
    if (use == _useDynamicColor) return;
    _useDynamicColor = use;
    notifyListeners();
    await _prefs?.setBool('useDynamicColor', use);
  }

  Future<void> updateCampus(String newCampus) async {
    if (newCampus == _campus) return;
    _campus = newCampus;
    notifyListeners();
    await _prefs?.setString('campus', newCampus);
  }

  Future<void> updateAmoledTheme(bool amoled) async {
    if (amoled == _amoledTheme) return;
    _amoledTheme = amoled;
    notifyListeners();
    await _prefs?.setBool('amoledTheme', amoled);
  }

  Future<void> updateShowWeekends(bool show) async {
    if (show == _showWeekends) return;
    _showWeekends = show;
    notifyListeners();
    await _prefs?.setBool('showWeekends', show);
  }

  Future<void> updateMensaPriceCategory(String category) async {
    if (category == _mensaPriceCategory) return;
    _mensaPriceCategory = category;
    notifyListeners();
    await _prefs?.setString('mensaPriceCategory', category);
  }

  Future<void> updateCompactMensaView(bool compact) async {
    if (compact == _compactMensaView) return;
    _compactMensaView = compact;
    notifyListeners();
    await _prefs?.setBool('compactMensaView', compact);
  }

  Future<void> updateMensaCategoryOrder(List<String> order) async {
    _mensaCategoryOrder = order;
    notifyListeners();
    await _prefs?.setStringList('mensaCategoryOrder', order);
  }

  Future<void> updateHapticsEnabled(bool enabled) async {
    if (enabled == _hapticsEnabled) return;
    _hapticsEnabled = enabled;
    notifyListeners();
    await _prefs?.setBool('hapticsEnabled', enabled);
  }

  Future<void> updateShowBreakTime(bool show) async {
    if (show == _showBreakTime) return;
    _showBreakTime = show;
    notifyListeners();
    await _prefs?.setBool('showBreakTime', show);
  }

  Future<void> updateCompactTimetableView(bool compact) async {
    if (compact == _compactTimetableView) return;
    _compactTimetableView = compact;
    notifyListeners();
    await _prefs?.setBool('compactTimetableView', compact);
  }

  Future<void> updateAnimationsEnabled(bool enabled) async {
    if (enabled == _animationsEnabled) return;
    _animationsEnabled = enabled;
    notifyListeners();
    await _prefs?.setBool('animationsEnabled', enabled);
  }

  Future<void> updateTimetableIsWeekView(bool isWeekView) async {
    if (isWeekView == _timetableIsWeekView) return;
    _timetableIsWeekView = isWeekView;
    notifyListeners();
    await _prefs?.setBool('timetableIsWeekView', isWeekView);
  }

  Future<void> updateHideLabels(bool hide) async {
    if (hide == _hideLabels) return;
    _hideLabels = hide;
    notifyListeners();
    await _prefs?.setBool('hideLabels', hide);
  }

  Future<void> updateLsfOnEmailLongPress(bool isEnabled) async {
    if (isEnabled == _lsfOnEmailLongPress) return;
    _lsfOnEmailLongPress = isEnabled;
    notifyListeners();
    await _prefs?.setBool('lsfOnEmailLongPress', isEnabled);
  }

}
