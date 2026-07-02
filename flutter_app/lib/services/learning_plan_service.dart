import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/learning_plan.dart';

class LearningPlanService extends ChangeNotifier {
  static const String _storageKey = 'active_learning_plan';
  LearningPlan? _activePlan;
  final SharedPreferences _prefs;

  LearningPlanService(this._prefs) {
    _loadPlan();
  }

  LearningPlan? get activePlan => _activePlan;
  bool get hasActivePlan => _activePlan != null;

  void _loadPlan() {
    final String? data = _prefs.getString(_storageKey);
    if (data != null) {
      try {
        _activePlan = LearningPlan.fromJson(json.decode(data));
      } catch (e) {
        debugPrint('Error loading learning plan: $e');
        _activePlan = null;
      }
    }
  }

  Future<void> savePlan(LearningPlan plan) async {
    _activePlan = plan;
    await _prefs.setString(_storageKey, json.encode(plan.toJson()));
    notifyListeners();
  }

  Future<void> clearPlan() async {
    _activePlan = null;
    await _prefs.remove(_storageKey);
    notifyListeners();
  }

  Future<void> markTaskCompleted(int dayNumber) async {
    if (_activePlan == null) return;
    
    final taskIndex = _activePlan!.dailyTasks.indexWhere((t) => t.dayNumber == dayNumber);
    if (taskIndex != -1) {
      _activePlan!.dailyTasks[taskIndex].isCompleted = true;
      _activePlan!.dailyTasks[taskIndex].completedAt = DateTime.now();
      await savePlan(_activePlan!);
    }
  }
}
