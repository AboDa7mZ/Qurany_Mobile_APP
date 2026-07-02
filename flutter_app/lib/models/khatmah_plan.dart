import 'package:uuid/uuid.dart';

class KhatmahPlan {
  final String id;
  final int targetDays;
  final DateTime startDate;
  int currentPage;
  final int totalPages = 604;
  DateTime? lastReadDate;

  KhatmahPlan({
    String? id,
    required this.targetDays,
    DateTime? startDate,
    this.currentPage = 1,
    this.lastReadDate,
  })  : id = id ?? const Uuid().v4(),
        startDate = startDate ?? DateTime.now();

  int get pagesPerDay => (totalPages / targetDays).ceil();
  double get progressPercentage => currentPage / totalPages;
  bool get isCompleted => currentPage >= totalPages;

  int get expectedPageToday {
    final daysElapsed = DateTime.now().difference(startDate).inDays;
    return (daysElapsed * pagesPerDay).clamp(1, totalPages);
  }

  bool get isOnTrack => currentPage >= expectedPageToday;

  Map<String, dynamic> toJson() => {
        'id': id,
        'targetDays': targetDays,
        'startDate': startDate.toIso8601String(),
        'currentPage': currentPage,
        'lastReadDate': lastReadDate?.toIso8601String(),
      };

  factory KhatmahPlan.fromJson(Map<String, dynamic> json) => KhatmahPlan(
        id: json['id'],
        targetDays: json['targetDays'],
        startDate: DateTime.parse(json['startDate']),
        currentPage: json['currentPage'],
        lastReadDate: json['lastReadDate'] != null
            ? DateTime.parse(json['lastReadDate'])
            : null,
      );
}
