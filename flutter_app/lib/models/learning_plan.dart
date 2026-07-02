import 'package:uuid/uuid.dart';

import 'sync_metadata.dart';

class DailyTask {
  final int dayNumber;
  final int startSurah;
  final int startVerse;
  final int endSurah;
  final int endVerse;
  final String description;
  bool isCompleted;
  DateTime? completedAt;

  DailyTask({
    required this.dayNumber,
    required this.startSurah,
    required this.startVerse,
    required this.endSurah,
    required this.endVerse,
    required this.description,
    this.isCompleted = false,
    this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'dayNumber': dayNumber,
        'startSurah': startSurah,
        'startVerse': startVerse,
        'endSurah': endSurah,
        'endVerse': endVerse,
        'description': description,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
      };

  factory DailyTask.fromJson(Map<String, dynamic> json) => DailyTask(
        dayNumber: json['dayNumber'],
        startSurah: json['startSurah'],
        startVerse: json['startVerse'],
        endSurah: json['endSurah'],
        endVerse: json['endVerse'],
        description: json['description'],
        isCompleted: json['isCompleted'] ?? false,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'])
            : null,
      );
}

class LearningPlan {
  final String id;
  final String title;
  final int startSurah;
  final int endSurah;
  final int totalDays;
  final DateTime createdAt;
  final List<DailyTask> dailyTasks;
  final SyncMetadata sync;

  LearningPlan({
    String? id,
    required this.title,
    required this.startSurah,
    required this.endSurah,
    required this.totalDays,
    DateTime? createdAt,
    required this.dailyTasks,
    SyncMetadata? sync,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        sync = sync ?? SyncMetadata.fresh();

  int get currentDay {
    for (int i = 0; i < dailyTasks.length; i++) {
      if (!dailyTasks[i].isCompleted) return dailyTasks[i].dayNumber;
    }
    return totalDays;
  }

  double get progressPercentage {
    if (totalDays == 0) return 0.0;
    final completedCount =
        dailyTasks.where((task) => task.isCompleted).length;
    return completedCount / totalDays;
  }

  bool get isCompleted => progressPercentage >= 1.0;

  LearningPlan copyWith({
    List<DailyTask>? dailyTasks,
    SyncMetadata? sync,
  }) {
    return LearningPlan(
      id: id,
      title: title,
      startSurah: startSurah,
      endSurah: endSurah,
      totalDays: totalDays,
      createdAt: createdAt,
      dailyTasks: dailyTasks ?? this.dailyTasks,
      sync: sync ?? this.sync,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startSurah': startSurah,
        'endSurah': endSurah,
        'totalDays': totalDays,
        'createdAt': createdAt.toIso8601String(),
        'dailyTasks': dailyTasks.map((t) => t.toJson()).toList(),
        ...sync.toJson(),
      };

  factory LearningPlan.fromJson(Map<String, dynamic> json) => LearningPlan(
        id: json['id'],
        title: json['title'],
        startSurah: json['startSurah'],
        endSurah: json['endSurah'],
        totalDays: json['totalDays'],
        createdAt: DateTime.parse(json['createdAt']),
        dailyTasks: (json['dailyTasks'] as List)
            .map((t) => DailyTask.fromJson(t))
            .toList(),
        sync: SyncMetadata.fromJson(json),
      );
}
