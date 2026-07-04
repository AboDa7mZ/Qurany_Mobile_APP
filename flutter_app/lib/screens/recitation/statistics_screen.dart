import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';

/// One mistake extracted from an AI analysis result (letters or harakat).
class _RecitationMistake {
  final int verseNumber;
  final String type;
  final String expectedWord;
  final String recitedWord;
  final String? husaryAudioUrl;

  const _RecitationMistake({
    required this.verseNumber,
    required this.type,
    required this.expectedWord,
    required this.recitedWord,
    this.husaryAudioUrl,
  });

  bool get isHarakat => type == 'harakat';

  String get typeLabel {
    switch (type) {
      case 'harakat':
        return 'تشكيل';
      case 'substitution':
        return 'كلمة خاطئة';
      case 'omission':
        return 'كلمة ناقصة';
      case 'addition':
        return 'كلمة زائدة';
      case 'sequence':
        return 'ترتيب';
      default:
        return type;
    }
  }
}

class StatisticsScreen extends StatefulWidget {
  final int totalVerses;
  final int totalCorrectedFaults;
  final Map<String, int> faultsDetail;

  /// Pending per-ayah AI analysis results (queued in the background during
  /// the tahfeez session). Order matches [tashkeelAyahLabels].
  final List<Future<Map<String, dynamic>?>> tashkeelFutures;
  final List<Map<String, dynamic>> tashkeelAyahLabels;

  /// Pre-resolved server results (reopening a saved plan session).
  final List<Map<String, dynamic>>? analysisResults;

  const StatisticsScreen({
    super.key,
    this.totalVerses = 0,
    this.totalCorrectedFaults = 0,
    this.faultsDetail = const {},
    this.tashkeelFutures = const [],
    this.tashkeelAyahLabels = const [],
    this.analysisResults,
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
  List<_RecitationMistake> _tashkeelMistakes = const [];
  List<_RecitationMistake> _letterMistakes = const [];
  int _analyzedAyahCount = 0;

  final AudioPlayer _husaryPlayer = AudioPlayer();
  int? _playingVerseNumber;

  int get totalVerses => widget.totalVerses;
  int get totalCorrectedFaults => widget.totalCorrectedFaults;
  Map<String, int> get faultsDetail => widget.faultsDetail;

  @override
  void initState() {
    super.initState();
    if (widget.analysisResults != null && widget.analysisResults!.isNotEmpty) {
      _applyAnalysisResults(widget.analysisResults!);
    } else if (widget.tashkeelFutures.isNotEmpty) {
      _tashkeelLoading = true;
      _collectTashkeelResults();
    }
  }

  @override
  void dispose() {
    _husaryPlayer.dispose();
    super.dispose();
  }

  String? _husaryUrlForVerse(int verseNumber) {
    for (final label in widget.tashkeelAyahLabels) {
      if ((label['verseNumber'] as int?) == verseNumber) {
        return label['husaryAudioUrl'] as String?;
      }
    }
    return null;
  }

  Future<void> _playHusaryForVerse(int verseNumber) async {
    String? url = _husaryUrlForVerse(verseNumber);
    if (url == null || url.isEmpty) {
      for (final m in [..._letterMistakes, ..._tashkeelMistakes]) {
        if (m.verseNumber == verseNumber &&
            m.husaryAudioUrl != null &&
            m.husaryAudioUrl!.isNotEmpty) {
          url = m.husaryAudioUrl;
          break;
        }
      }
    }
    if (url == null || url.isEmpty) return;
    try {
      await _husaryPlayer.stop();
      setState(() => _playingVerseNumber = verseNumber);
      await _husaryPlayer.play(UrlSource(url));
      _husaryPlayer.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _playingVerseNumber = null);
      });
    } catch (_) {
      if (mounted) setState(() => _playingVerseNumber = null);
    }
  }

  void _applyAnalysisResults(List<Map<String, dynamic>> results) {
    int mistakes = 0;
    int checked = 0;
    final harakatCollected = <_RecitationMistake>[];
    final letterCollected = <_RecitationMistake>[];

    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final label =
          i < widget.tashkeelAyahLabels.length ? widget.tashkeelAyahLabels[i] : null;
      final verseNumber = (label?['verseNumber'] as int?) ??
          (result['detectedAyahStart'] as int?) ??
          (result['detected_ayah_start'] as int?) ??
          0;
      final husaryUrl = label?['husaryAudioUrl'] as String?;

      mistakes += (result['harakatMistakes'] as num?)?.toInt() ??
          (result['harakat_mistakes'] as num?)?.toInt() ??
          0;
      checked += (result['harakatChecked'] as num?)?.toInt() ??
          (result['harakat_checked'] as num?)?.toInt() ??
          0;

      final errors = result['errors'] as List? ?? const [];
      for (final e in errors) {
        if (e is! Map) continue;
        final type = (e['type'] ?? '') as String;
        final item = _RecitationMistake(
          verseNumber: verseNumber,
          type: type,
          expectedWord: (e['expectedWord'] ?? e['expected_word'] ?? '') as String,
          recitedWord: (e['recitedWord'] ?? e['recited_word'] ?? '') as String,
          husaryAudioUrl: husaryUrl,
        );
        if (type == 'harakat') {
          harakatCollected.add(item);
        } else {
          letterCollected.add(item);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _tashkeelLoading = false;
      _tashkeelAvailable = checked > 0 || harakatCollected.isNotEmpty;
      _tashkeelMistakeCount = mistakes;
      _tashkeelCheckedCount = checked;
      _analyzedAyahCount = results.length;
      _tashkeelScore = checked > 0
          ? ((checked - mistakes) / checked * 100).clamp(0.0, 100.0)
          : null;
      _tashkeelMistakes = harakatCollected;
      _letterMistakes = letterCollected;
    });
  }

  Future<void> _collectTashkeelResults() async {
    final results = await Future.wait(widget.tashkeelFutures);
    final nonNull = <Map<String, dynamic>>[];
    var failed = 0;
    for (final r in results) {
      if (r == null) {
        failed++;
      } else {
        nonNull.add(r);
      }
    }
    if (!mounted) return;
    setState(() => _tashkeelFailedCount = failed);
    _applyAnalysisResults(nonNull);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuranyTheme.background,
      appBar: AppBar(
        title: const Text('إحصائيات الجلسة'),
        automaticallyImplyLeading: widget.analysisResults != null,
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

              // Letter-level mistakes from server analysis (per ayah).
              if (_tashkeelLoading || _letterMistakes.isNotEmpty) ...[
                const SizedBox(height: 32),
                _buildLetterMistakesSection(),
              ],

              // Tashkeel (harakat) report from the fine-tuned AI model,
              // analyzed in the background during the session.
              if (_tashkeelLoading ||
                  _tashkeelAvailable ||
                  _tashkeelMistakes.isNotEmpty) ...[
                const SizedBox(height: 32),
                _buildTashkeelSection(),
              ],
              if (!_tashkeelLoading &&
                  widget.tashkeelFutures.isNotEmpty &&
                  _analyzedAyahCount == 0 &&
                  _tashkeelFailedCount > 0) ...[
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

  Widget _buildLetterMistakesSection() {
    if (_tashkeelLoading && _letterMistakes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'أخطاء الكلمات في التلاوة:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: QuranyTheme.darkGreen,
          ),
        ),
        const SizedBox(height: 12),
        if (_letterMistakes.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: QuranyTheme.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: QuranyTheme.success.withValues(alpha: 0.2)),
            ),
            child: const Text(
              'لا توجد أخطاء في الحروف في الآيات التي تم تحليلها.',
              style: TextStyle(fontSize: 13, color: QuranyTheme.success),
            ),
          )
        else
          ..._letterMistakes.map(_buildMistakeCard),
      ],
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
          ..._tashkeelMistakes.map(_buildMistakeCard),
        ] else if (!_tashkeelLoading && _tashkeelCheckedCount == 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: QuranyTheme.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: QuranyTheme.warning.withValues(alpha: 0.2)),
            ),
            child: const Text(
              'لم يتم فحص التشكيل — تأكد من تشغيل الخادم وتسجيل الصوت (وليس التعرف على الكلام فقط).',
              style: TextStyle(fontSize: 13, color: QuranyTheme.warning),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMistakeCard(_RecitationMistake m) {
    final accent = m.isHarakat ? Colors.teal : QuranyTheme.errorRed;
    final canPlay = (m.husaryAudioUrl ?? _husaryUrlForVerse(m.verseNumber)) != null;
    final isPlaying = _playingVerseNumber == m.verseNumber;

    return Container(
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
          Row(
            children: [
              Text(
                'آية ${m.verseNumber}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  m.typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
              const Spacer(),
              if (canPlay)
                IconButton(
                  tooltip: 'استمع للشيخ',
                  icon: Icon(
                    isPlaying ? Icons.pause_circle_filled : Icons.volume_up_rounded,
                    color: QuranyTheme.primaryGreen,
                  ),
                  onPressed: () => _playHusaryForVerse(m.verseNumber),
                ),
            ],
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
                      m.expectedWord.isEmpty ? '—' : m.expectedWord,
                      style: TextStyle(
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
              Icon(Icons.compare_arrows_rounded, color: accent, size: 20),
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
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: accent,
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
