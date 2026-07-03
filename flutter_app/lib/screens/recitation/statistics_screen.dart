import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';

/// One harakat (tashkeel) mistake extracted from an AI analysis result.
class _TashkeelMistake {
  final int verseNumber;
  final String expectedWord;
  final String recitedWord;

  const _TashkeelMistake({
    required this.verseNumber,
    required this.expectedWord,
    required this.recitedWord,
  });
}

class StatisticsScreen extends StatefulWidget {
  final int totalVerses;
  final int totalCorrectedFaults;
  final Map<String, int> faultsDetail;

  /// Pending per-ayah AI analysis results (queued in the background during
  /// the tahfeez session). Order matches [tashkeelAyahLabels].
  final List<Future<Map<String, dynamic>?>> tashkeelFutures;
  final List<Map<String, dynamic>> tashkeelAyahLabels;

  const StatisticsScreen({
    super.key,
    this.totalVerses = 0,
    this.totalCorrectedFaults = 0,
    this.faultsDetail = const {},
    this.tashkeelFutures = const [],
    this.tashkeelAyahLabels = const [],
  });

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  bool _tashkeelLoading = false;
  bool _tashkeelAvailable = false;
  double? _tashkeelScore;
  int _tashkeelMistakeCount = 0;
  int _tashkeelCheckedCount = 0;
  int _tashkeelFailedCount = 0;
  List<_TashkeelMistake> _tashkeelMistakes = const [];

  int get totalVerses => widget.totalVerses;
  int get totalCorrectedFaults => widget.totalCorrectedFaults;
  Map<String, int> get faultsDetail => widget.faultsDetail;

  @override
  void initState() {
    super.initState();
    if (widget.tashkeelFutures.isNotEmpty) {
      _tashkeelLoading = true;
      _collectTashkeelResults();
    }
  }

  Future<void> _collectTashkeelResults() async {
    // Most futures resolved during the session (while Husary recited the
    // next ayah); typically only the last ayah is still processing here.
    final results = await Future.wait(widget.tashkeelFutures);

    int mistakes = 0;
    int checked = 0;
    int failed = 0;
    final collected = <_TashkeelMistake>[];

    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      if (result == null) {
        // Analysis failed (backend unreachable or errored) -- surfaced in
        // the UI rather than silently shrinking the checked-ayah count.
        failed++;
        continue;
      }

      final label =
          i < widget.tashkeelAyahLabels.length ? widget.tashkeelAyahLabels[i] : null;
      final verseNumber = (label?['verseNumber'] as int?) ??
          (result['detectedAyahStart'] as int?) ??
          0;

      mistakes += (result['harakatMistakes'] as num?)?.toInt() ?? 0;
      checked += (result['harakatChecked'] as num?)?.toInt() ?? 0;

      final errors = result['errors'] as List? ?? const [];
      for (final e in errors) {
        if (e is Map && e['type'] == 'harakat') {
          collected.add(_TashkeelMistake(
            verseNumber: verseNumber,
            expectedWord: (e['expectedWord'] ?? '') as String,
            recitedWord: (e['recitedWord'] ?? '') as String,
          ));
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _tashkeelLoading = false;
      _tashkeelAvailable = checked > 0;
      _tashkeelMistakeCount = mistakes;
      _tashkeelCheckedCount = checked;
      _tashkeelFailedCount = failed;
      _tashkeelScore = checked > 0
          ? ((checked - mistakes) / checked * 100).clamp(0.0, 100.0)
          : null;
      _tashkeelMistakes = collected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuranyTheme.background,
      appBar: AppBar(
        title: const Text('إحصائيات الجلسة'),
        automaticallyImplyLeading: false,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Badge & Congrats Section
              Center(
                child: Column(
                  children: [
                    Icon(
                      totalCorrectedFaults == 0 ? Icons.emoji_events_rounded : Icons.check_circle_rounded,
                      size: 90,
                      color: totalCorrectedFaults == 0 ? QuranyTheme.warning : QuranyTheme.success,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'أحسنت القراءة والتعلم!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: QuranyTheme.darkGreen,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'لقد أكملت قراءة نطاق الآيات المحدد بنجاح.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Summary stats row
              Row(
                children: [
                  Expanded(
                    child: _buildStatSummaryCard(
                      title: 'الآيات المكتملة',
                      value: '$totalVerses',
                      icon: Icons.menu_book_rounded,
                      color: QuranyTheme.primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatSummaryCard(
                      title: 'أخطاء تم تصحيحها',
                      value: '$totalCorrectedFaults',
                      icon: Icons.build_circle_outlined,
                      color: totalCorrectedFaults == 0 ? QuranyTheme.success : QuranyTheme.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Detail List header
              if (totalCorrectedFaults > 0) ...[
                const Text(
                  'تفاصيل الأخطاء التي تم تصحيحها بمساعدة الشيخ:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: QuranyTheme.darkGreen,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Fault details list
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: faultsDetail.length,
                  itemBuilder: (context, index) {
                    final key = faultsDetail.keys.elementAt(index);
                    final val = faultsDetail[key]!;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: QuranyTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: QuranyTheme.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: QuranyTheme.warning, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                key,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: QuranyTheme.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'حاولت $val ${val == 1 ? 'مرة' : 'مرات'}',
                              style: const TextStyle(
                                color: QuranyTheme.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ] else ...[
                // Perfectly correct message
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: QuranyTheme.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: QuranyTheme.success.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.stars_rounded, color: QuranyTheme.success, size: 28),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'تلاوة ممتازة! لم تقع في أي أخطاء وتمت القراءة من المرة الأولى بنجاح.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: QuranyTheme.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Tashkeel (harakat) report from the fine-tuned AI model,
              // analyzed in the background during the session.
              if (_tashkeelLoading || _tashkeelAvailable) ...[
                const SizedBox(height: 32),
                _buildTashkeelSection(),
              ],
              if (!_tashkeelLoading && _tashkeelFailedCount > 0) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off,
                        size: 18, color: QuranyTheme.errorRed),
                    const SizedBox(width: 6),
                    Text(
                      'تعذر تحليل $_tashkeelFailedCount ${_tashkeelFailedCount == 1 ? 'آية' : 'آيات'} على الخادم — تحقق من عنوان الخادم في الإعدادات',
                      style: const TextStyle(
                        fontSize: 13,
                        color: QuranyTheme.errorRed,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 48),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppRoutes.home,
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: QuranyTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'العودة للرئيسية',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTashkeelSection() {
    if (_tashkeelLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: QuranyTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: QuranyTheme.border),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'جاري تحليل التشكيل بالذكاء الاصطناعي...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: QuranyTheme.darkGreen,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final score = _tashkeelScore ?? 0.0;
    final scoreColor = score >= 85
        ? QuranyTheme.success
        : score >= 70
            ? QuranyTheme.warning
            : QuranyTheme.errorRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'نتيجة التشكيل (الحركات):',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: QuranyTheme.darkGreen,
          ),
        ),
        const SizedBox(height: 12),

        // Overall tashkeel score card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: QuranyTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: QuranyTheme.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 6,
                      backgroundColor: QuranyTheme.border,
                      valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                    ),
                    Text(
                      '${score.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: scoreColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'دقة التشكيل',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: QuranyTheme.darkGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tashkeelMistakeCount == 0
                          ? 'تشكيل سليم في جميع الكلمات التي تم فحصها ($_tashkeelCheckedCount كلمة)'
                          : '$_tashkeelMistakeCount ${_tashkeelMistakeCount == 1 ? 'خطأ' : 'أخطاء'} في التشكيل من أصل $_tashkeelCheckedCount كلمة',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Per-word harakat mistakes
        if (_tashkeelMistakes.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._tashkeelMistakes.map(
            (m) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: QuranyTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: QuranyTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'آية ${m.verseNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'الصحيح',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.expectedWord,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: QuranyTheme.success,
                                fontFamily: 'MeQuran',
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.compare_arrows_rounded,
                          color: Colors.grey, size: 20),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'قراءتك',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.recitedWord.isEmpty ? '—' : m.recitedWord,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: QuranyTheme.errorRed,
                                fontFamily: 'MeQuran',
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QuranyTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: QuranyTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
