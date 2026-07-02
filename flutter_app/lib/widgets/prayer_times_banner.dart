import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/prayer_times.dart';

class PrayerTimesBanner extends StatelessWidget {
  final PrayerTimesDay? day;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  const PrayerTimesBanner({
    super.key,
    required this.day,
    required this.isLoading,
    this.error,
    this.onRetry,
  });

  static const _bannerGreen = Color(0xFF1B4332);
  static const _bannerText = Color(0xFFF4F1E6);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: _bannerGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: isLoading
            ? const SizedBox(
                height: 96,
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _bannerText,
                    ),
                  ),
                ),
              )
            : error != null
                ? _ErrorContent(message: error!, onRetry: onRetry)
                : day == null
                    ? _ErrorContent(
                        message: 'Prayer times unavailable.',
                        onRetry: onRetry,
                      )
                    : _PrayerContent(day: day!),
      ),
    );
  }
}

class _PrayerContent extends StatelessWidget {
  final PrayerTimesDay day;

  const _PrayerContent({required this.day});

  @override
  Widget build(BuildContext context) {
    final next = day.nextPrayer;
    final entries = day.displayEntries;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 118,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mosque_outlined, color: PrayerTimesBanner._bannerText.withValues(alpha: 0.9), size: 28),
              const SizedBox(height: 10),
              Text(
                'Next Prayer',
                style: TextStyle(
                  fontSize: 12,
                  color: PrayerTimesBanner._bannerText.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                next?.name.label ?? '—',
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: PrayerTimesBanner._bannerText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                next?.formatted12h ?? '',
                style: TextStyle(
                  fontSize: 14,
                  color: PrayerTimesBanner._bannerText.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 1,
          height: 92,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: PrayerTimesBanner._bannerText.withValues(alpha: 0.18),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in entries) ...[
                  _PrayerChip(
                    entry: entry,
                    isNext: next?.name == entry.name,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PrayerChip extends StatelessWidget {
  final PrayerTimeEntry entry;
  final bool isNext;

  const _PrayerChip({
    required this.entry,
    required this.isNext,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = PrayerTimesBanner._bannerText;
    final bg = isNext
        ? textColor.withValues(alpha: 0.14)
        : Colors.transparent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            entry.name.icon,
            size: 22,
            color: textColor.withValues(alpha: isNext ? 1 : 0.82),
          ),
          const SizedBox(height: 6),
          Text(
            entry.name.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isNext ? FontWeight.w700 : FontWeight.w500,
              color: textColor.withValues(alpha: isNext ? 1 : 0.82),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entry.formatted12h,
            style: TextStyle(
              fontSize: 11,
              color: textColor.withValues(alpha: isNext ? 0.95 : 0.72),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorContent({
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          Icon(
            Icons.mosque_outlined,
            color: PrayerTimesBanner._bannerText.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: PrayerTimesBanner._bannerText.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: QuranyTheme.background,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
