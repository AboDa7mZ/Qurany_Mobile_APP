import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/learning_plan.dart';

/// Learning plan service supporting multiple plans stored in SharedPreferences.
class LearningPlanService extends ChangeNotifier {
  static const String _storageKey = 'active_learning_plan'; // For old plan migration
  static const String _storageListKey = 'learning_plans_list';

  List<LearningPlan> _plans = [];
  final SharedPreferences _prefs;

  LearningPlanService(this._prefs) {
    _loadPlans();
  }

  /// Get all active (non-deleted) plans
  List<LearningPlan> get plans =>
      _plans.where((p) => !p.sync.isDeleted).toList();

  /// Check if there is at least one active plan
  bool get hasActivePlan => plans.isNotEmpty;

  /// For backward compatibility (returns first active plan if exists)
  LearningPlan? get activePlan => plans.isNotEmpty ? plans.first : null;

  void reloadFromStorage() {
    _loadPlans();
    notifyListeners();
  }

  void _loadPlans() {
    _plans = [];
    
    // 1. Load the list of plans
    final String? listData = _prefs.getString(_storageListKey);
    if (listData != null) {
      try {
        final List<dynamic> decoded = json.decode(listData);
        _plans = decoded.map((item) => LearningPlan.fromJson(item)).toList();
      } catch (e) {
        debugPrint('Error loading learning plans list: $e');
      }
    }

    // 2. Migrate legacy single plan if exists
    final String? oldData = _prefs.getString(_storageKey);
    if (oldData != null) {
      try {
        final oldPlan = LearningPlan.fromJson(json.decode(oldData));
        if (!_plans.any((p) => p.id == oldPlan.id)) {
          _plans.add(oldPlan);
          _savePlansToStorage();
        }
        _prefs.remove(_storageKey); // Clear after successful migration
      } catch (e) {
        debugPrint('Error migrating old plan: $e');
      }
    }
  }

  Future<void> _savePlansToStorage() async {
    final List<Map<String, dynamic>> jsonList =
        _plans.map((p) => p.toJson()).toList();
    await _prefs.setString(_storageListKey, json.encode(jsonList));
  }

  /// Get a specific plan by ID
  LearningPlan? getPlanById(String id) {
    try {
      return _plans.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Save or update a learning plan
  Future<void> savePlan(LearningPlan plan) async {
    final index = _plans.indexWhere((p) => p.id == plan.id);
    if (index != -1) {
      _plans[index] = plan;
    } else {
      _plans.add(plan);
    }
    await _savePlansToStorage();
    notifyListeners();
  }

  /// Delete a plan by ID
  Future<void> deletePlan(String id) async {
    _plans.removeWhere((p) => p.id == id);
    await _savePlansToStorage();
    notifyListeners();
  }

  /// Clear the active plan (fallback compatibility)
  Future<void> clearPlan() async {
    if (plans.isNotEmpty) {
      await deletePlan(plans.first.id);
    }
  }

  /// Mark a specific task complete inside a specific plan
  Future<void> markTaskCompleted(String planId, int dayNumber) async {
    final planIndex = _plans.indexWhere((p) => p.id == planId);
    if (planIndex == -1) return;

    final plan = _plans[planIndex];
    if (plan.sync.isDeleted) return;

    final taskIndex =
        plan.dailyTasks.indexWhere((t) => t.dayNumber == dayNumber);
    if (taskIndex != -1) {
      plan.dailyTasks[taskIndex].isCompleted = true;
      plan.dailyTasks[taskIndex].completedAt = DateTime.now();
      await savePlan(plan);
    }
  }
}

