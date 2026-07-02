import 'package:uuid/uuid.dart';

import 'sync_metadata.dart';

/// Local user profile aligned with the backend `users` table.
class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final int dailyStreak;
  final int totalScore;
  final DateTime createdAt;
  final SyncMetadata sync;

  UserProfile({
    String? id,
    required this.email,
    required this.fullName,
    this.dailyStreak = 0,
    this.totalScore = 0,
    DateTime? createdAt,
    SyncMetadata? sync,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        sync = sync ?? SyncMetadata.fresh();

  bool get isGuest => email.isEmpty;

  UserProfile copyWith({
    String? email,
    String? fullName,
    int? dailyStreak,
    int? totalScore,
    SyncMetadata? sync,
  }) {
    return UserProfile(
      id: id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      dailyStreak: dailyStreak ?? this.dailyStreak,
      totalScore: totalScore ?? this.totalScore,
      createdAt: createdAt,
      sync: sync ?? this.sync,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String?,
      email: json['email'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      dailyStreak: json['dailyStreak'] as int? ?? 0,
      totalScore: json['totalScore'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      sync: SyncMetadata.fromJson(json),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'dailyStreak': dailyStreak,
        'totalScore': totalScore,
        'createdAt': createdAt.toIso8601String(),
        ...sync.toJson(),
      };
}
