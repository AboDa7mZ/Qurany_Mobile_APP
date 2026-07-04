/// Sync fields aligned with the backend User schema in
/// `implementation_plan.md` (`updated_at`, `sync_status`, `is_deleted`).
class SyncStatus {
  SyncStatus._();

  static const synced = 'synced';
  static const pending = 'pending';
  static const conflict = 'conflict';
}

class SyncMetadata {
  final DateTime updatedAt;
  final String syncStatus;
  final bool isDeleted;

  const SyncMetadata({
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  });

  factory SyncMetadata.fresh() {
    return SyncMetadata(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );
  }

  /// Reads sync fields from an entity JSON map.
  ///
  /// Legacy records without sync fields are treated as already synced locally.
  factory SyncMetadata.fromJson(Map<String, dynamic> json) {
    final fallbackUpdatedAt = _parseDateTime(json['updatedAt']) ??
        _parseDateTime(json['dateTime']) ??
        _parseDateTime(json['createdAt']) ??
        DateTime.now();

    final hasSyncFields =
        json.containsKey('syncStatus') || json.containsKey('isDeleted');

    return SyncMetadata(
      updatedAt: fallbackUpdatedAt,
      syncStatus: json['syncStatus'] as String? ??
          (hasSyncFields ? SyncStatus.synced : SyncStatus.synced),
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'updatedAt': updatedAt.toIso8601String(),
        'syncStatus': syncStatus,
        'isDeleted': isDeleted,
      };

  SyncMetadata markPending({bool? isDeleted}) {
    return SyncMetadata(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  SyncMetadata markSynced() {
    return SyncMetadata(
      updatedAt: updatedAt,
      syncStatus: SyncStatus.synced,
      isDeleted: isDeleted,
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
