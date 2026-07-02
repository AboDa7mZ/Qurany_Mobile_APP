import 'package:uuid/uuid.dart';

class KhatmahPlan {
  final String id;
  final int? targetDays;
  final DateTime startDate;
  int currentPage;
  final int startPage;
  final int endPage;
  DateTime? lastReadDate;

  KhatmahPlan({
    String? id,
    this.targetDays,
    DateTime? startDate,
    this.startPage = 1,
    this.endPage = 604,
    int? currentPage,
    this.lastReadDate,
  })  : id = id ?? const Uuid().v4(),
        startDate = startDate ?? DateTime.now(),
        currentPage = currentPage ?? startPage;

  int get totalPages => (endPage - startPage) + 1;
  int get pagesPerDay => targetDays != null ? (totalPages / targetDays!).ceil() : 0;
  double get progressPercentage => totalPages > 0 ? ((currentPage - startPage) / totalPages).clamp(0.0, 1.0) : 0.0;
  bool get isCompleted => currentPage >= endPage;

  int get expectedPageToday {
    if (targetDays == null) return endPage;
    final daysElapsed = DateTime.now().difference(startDate).inDays;
    return (startPage + (daysElapsed * pagesPerDay)).clamp(startPage, endPage);
  }

  bool get isOnTrack => targetDays == null ? true : currentPage >= expectedPageToday;
  Map<String, dynamic> toJson() => {
        'id': id,
        'targetDays': targetDays,
        'startDate': startDate.toIso8601String(),
        'currentPage': currentPage,
        'startPage': startPage,
        'endPage': endPage,
        'lastReadDate': lastReadDate?.toIso8601String(),
      };

  factory KhatmahPlan.fromJson(Map<String, dynamic> json) => KhatmahPlan(
        id: json['id'],
        targetDays: json['targetDays'],
        startDate: DateTime.parse(json['startDate']),
        currentPage: json['currentPage'],
        startPage: json['startPage'] ?? 1,
        endPage: json['endPage'] ?? 604,
        lastReadDate: json['lastReadDate'] != null
            ? DateTime.parse(json['lastReadDate'])
            : null,
      );
}
