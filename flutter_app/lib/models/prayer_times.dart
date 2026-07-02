import 'package:flutter/material.dart';

enum PrayerName {
  fajr,
  sunrise,
  dhuhr,
  asr,
  maghrib,
  isha;

  static const List<PrayerName> salahOrder = [
    PrayerName.fajr,
    PrayerName.dhuhr,
    PrayerName.asr,
    PrayerName.maghrib,
    PrayerName.isha,
  ];

  static const List<PrayerName> displayOrder = [
    PrayerName.fajr,
    PrayerName.sunrise,
    PrayerName.dhuhr,
    PrayerName.asr,
    PrayerName.maghrib,
    PrayerName.isha,
  ];
}

extension PrayerNameX on PrayerName {
  String get apiKey {
    switch (this) {
      case PrayerName.fajr:
        return 'Fajr';
      case PrayerName.sunrise:
        return 'Sunrise';
      case PrayerName.dhuhr:
        return 'Dhuhr';
      case PrayerName.asr:
        return 'Asr';
      case PrayerName.maghrib:
        return 'Maghrib';
      case PrayerName.isha:
        return 'Isha';
    }
  }

  String get label => apiKey;

  IconData get icon {
    switch (this) {
      case PrayerName.fajr:
        return Icons.wb_twilight_rounded;
      case PrayerName.sunrise:
        return Icons.wb_sunny_outlined;
      case PrayerName.dhuhr:
        return Icons.light_mode_outlined;
      case PrayerName.asr:
        return Icons.wb_cloudy_outlined;
      case PrayerName.maghrib:
        return Icons.wb_twilight_outlined;
      case PrayerName.isha:
        return Icons.nightlight_round_outlined;
    }
  }
}

class PrayerTimeEntry {
  final PrayerName name;
  final DateTime time;

  const PrayerTimeEntry({required this.name, required this.time});

  String get formatted12h {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:$minute $period';
  }
}

class PrayerTimesDay {
  final String city;
  final String country;
  final String timezone;
  final List<PrayerTimeEntry> entries;
  final DateTime fetchedAt;

  const PrayerTimesDay({
    required this.city,
    required this.country,
    required this.timezone,
    required this.entries,
    required this.fetchedAt,
  });

  PrayerTimeEntry? get nextPrayer {
    final now = DateTime.now();
    for (final prayer in PrayerName.salahOrder) {
      final entry = _entryFor(prayer);
      if (entry != null && entry.time.isAfter(now)) {
        return entry;
      }
    }
    final fajr = _entryFor(PrayerName.fajr);
    if (fajr == null) return null;
    return PrayerTimeEntry(
      name: PrayerName.fajr,
      time: fajr.time.add(const Duration(days: 1)),
    );
  }

  PrayerTimeEntry? _entryFor(PrayerName name) {
    for (final entry in entries) {
      if (entry.name == name) return entry;
    }
    return null;
  }

  List<PrayerTimeEntry> get displayEntries {
    return PrayerName.displayOrder
        .map(_entryFor)
        .whereType<PrayerTimeEntry>()
        .toList();
  }
}
