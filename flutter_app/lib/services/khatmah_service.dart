import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/khatmah_plan.dart';

class KhatmahService extends ChangeNotifier {
  static const String _storageKey = 'active_khatmah';
  KhatmahPlan? _activeKhatmah;
  final SharedPreferences _prefs;

  KhatmahService(this._prefs) {
    _loadKhatmah();
  }

  KhatmahPlan? get activeKhatmah => _activeKhatmah;
  bool get hasActiveKhatmah => _activeKhatmah != null;

  void _loadKhatmah() {
    final String? data = _prefs.getString(_storageKey);
    if (data != null) {
      try {
        _activeKhatmah = KhatmahPlan.fromJson(json.decode(data));
      } catch (e) {
        debugPrint('Error loading khatmah: $e');
        _activeKhatmah = null;
      }
    }
  }

  Future<void> createKhatmah(int targetDays) async {
    _activeKhatmah = KhatmahPlan(targetDays: targetDays);
    await _saveKhatmah();
    notifyListeners();
  }

  Future<void> updateProgress(int page) async {
    if (_activeKhatmah != null && page > _activeKhatmah!.currentPage) {
      _activeKhatmah!.currentPage = page;
      _activeKhatmah!.lastReadDate = DateTime.now();
      await _saveKhatmah();
      notifyListeners();
    }
  }

  Future<void> _saveKhatmah() async {
    if (_activeKhatmah != null) {
      await _prefs.setString(_storageKey, json.encode(_activeKhatmah!.toJson()));
    }
  }

  Future<void> clearKhatmah() async {
    _activeKhatmah = null;
    await _prefs.remove(_storageKey);
    notifyListeners();
  }
}
