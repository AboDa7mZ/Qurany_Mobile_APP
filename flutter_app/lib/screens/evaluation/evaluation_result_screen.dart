import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../models/recitation_session.dart';
import '../../widgets/app_icons.dart';

/// Deep evaluation report for explicit ayah-range Hafs/Bazzi analysis.
class EvaluationResultScreen extends StatefulWidget {
  final Map<String, dynamic> sessionJson;
  final Map<String, dynamic> rawResult;
  final String riwayahLabel;
  final int? startAyah;
  final int? endAyah;

  const EvaluationResultScreen({
    super.key,
    required this.sessionJson,
    required this.rawResult,
    required this.riwayahLabel,
    this.startAyah,
    this.endAyah,
  });

  @override
  State<EvaluationResultScreen> createState() => _EvaluationResultScreenState();
}

class _EvaluationResultScreenState extends State<EvaluationResultScreen>
    with SingleTickerProviderStateMixin {
  late final RecitationSession session;
  late final TabController _tabs;
  late final List<_DiffWord> _diffWords;

  int? get _rangeStart => widget.startAyah ??
      (widget.rawResult['detectedAyahStart'] ?? widget.rawResult['detected_ayah_start']) as int?;
  int? get _rangeEnd => widget.endAyah ??
      (widget.rawResult['detectedAyahEnd'] ?? widget.rawResult['detected_ayah_end']) as int?;

  bool get _explicitRange =>
      widget.startAyah != null && widget.endAyah != null;

  double? get _localizationScore {
    if (_explicitRange) return null;
    final v = widget.rawResult['localizationScore'] ?? widget.rawResult['localization_score'];
    return v == null ? null : (v as num).toDouble();
  }

  List<Map<String, dynamic>> get _tajweedNotes {
    final raw = widget.rawResult['tajweed_notes'] ?? widget.rawResult['tajweedNotes'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  @override
  void initState() {
    super.initState();
    session = RecitationSession.fromJson(widget.sessionJson);
    _tabs = TabController(length: 4, vsync: this);
    _diffWords = _buildDiffWords();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<_DiffWord> _buildDiffWords() {
    final refText = session.referenceText ?? '';
    final transText = session.transcribedText ?? '';
    if (refText.isEmpty) return [];

    final refWords = refText.split(RegExp(r'\s+'));
    final transWords = transText.split(RegExp(r'\s+'));
    final errorMap = <int, RecitationError>{};
    for (final err in session.errors) {
      errorMap[err.wordIndex] = err;
    }

    final result = <_DiffWord>[];
    var ti = 0;
    for (var ri = 0; ri < refWords.length; ri++) {
      if (errorMap.containsKey(ri)) {
        final err = errorMap[ri]!;
        result.add(_DiffWord(
          referenceWord: refWords[ri],
          recitedWord: err.recitedWord.isNotEmpty ? err.recitedWord : null,
          status: _statusFromType(err.type),
        ));
        if (err.type != 'omission') ti++;
      } else {
        result.add(_DiffWord(
          referenceWord: refWords[ri],
          recitedWord: ti < transWords.length ? transWords[ti] : null,
          status: _DiffStatus.correct,
        ));
        ti++;
      }
    }
    return result;
  }

  _DiffStatus _statusFromType(String type) {
    switch (type) {
      case 'omission':
        return _DiffStatus.omission;
      case 'addition':
        return _DiffStatus.addition;
      case 'sequence':
        return _DiffStatus.sequence;
      case 'harakat':
        return _DiffStatus.harakat;
      default:
        return _DiffStatus.substitution;
    }
  }

  Color _scoreColor(double score) {
    if (score >= 85) return QuranyTheme.correctGreen;
    if (score >= 70) return QuranyTheme.warningOrange;
    return QuranyTheme.errorRed;
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = _scoreColor(session.similarityScore);

    return Scaffold(
      backgroundColor: QuranyTheme.background,
      appBar: AppBar(
        title: const Text('تقرير التقييم'),
        leading: AppIcons.backButton(context: context),
      ),
      body: Column(
        children: [
          _buildHeroHeader(scoreColor),
          Material(
            color: QuranyTheme.surface,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: QuranyTheme.primary,
              unselectedLabelColor: QuranyTheme.textMuted,
              indicatorColor: QuranyTheme.primary,
              tabs: const [
                Tab(text: 'نظرة عامة'),
                Tab(text: 'المقارنة'),
                Tab(text: 'الأخطاء'),
                Tab(text: 'إحصائيات'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _overviewTab(scoreColor),
                _comparisonTab(),
                _errorsTab(),
                _statsTab(scoreColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(Color scoreColor) {
    final ayahLabel = (_rangeStart != null && _rangeEnd != null)
        ? (_rangeStart == _rangeEnd
            ? 'الآية $_rangeStart'
            : 'الآيات $_rangeStart – $_rangeEnd')
        : 'لم يُحدد نطاق الآيات';
    final rangeNote = _explicitRange ? ' (نطاق محدد)' : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scoreColor.withValues(alpha: 0.14),
            QuranyTheme.background,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          _scoreRing(scoreColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سورة ${session.surahName}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: QuranyTheme.darkGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$ayahLabel$rangeNote',
                  style: TextStyle(fontSize: 13, color: QuranyTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: QuranyTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.riwayahLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: QuranyTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreRing(Color color) {
    return Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: color, width: 3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${session.similarityScore.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text('دقة', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  Widget _overviewTab(Color scoreColor) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _metricGrid(scoreColor),
        if (_localizationScore != null) ...[
          const SizedBox(height: 14),
          _infoCard(
            icon: Icons.my_location_rounded,
            title: 'دقة تحديد الآيات',
            value: '${_localizationScore!.toStringAsFixed(0)}%',
            subtitle: 'مدى تطابق النص المُحوَّل مع موضع الآيات في السورة',
            color: QuranyTheme.primary,
          ),
        ],
        if (session.harakatScore != null) ...[
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.text_fields_rounded,
            title: 'دقة الحركات',
            value: '${session.harakatScore!.toStringAsFixed(0)}%',
            subtitle: '${session.harakatMistakes} خطأ من ${session.harakatChecked} حركة',
            color: Colors.teal,
          ),
        ],
        if (_tajweedNotes.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'ملاحظات تجويد',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: QuranyTheme.darkGreen),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 10),
          ..._tajweedNotes.map(_tajweedTile),
        ],
        if (session.transcribedText != null && session.transcribedText!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'ما سُمع في التسجيل',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: QuranyTheme.darkGreen),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: QuranyTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: QuranyTheme.border),
            ),
            child: Text(
              session.transcribedText!,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 16, height: 1.8),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metricGrid(Color scoreColor) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        _statTile('كلمات صحيحة', '${session.matchedWords}', Icons.check_circle_rounded, QuranyTheme.correctGreen),
        _statTile('أخطاء', '${session.mistakes}', Icons.cancel_rounded, QuranyTheme.errorRed),
        _statTile('إجمالي الكلمات', '${session.totalWords}', Icons.format_list_numbered_rounded, QuranyTheme.primary),
        _statTile('آيات', '${session.versesRecited}', Icons.auto_stories_rounded, scoreColor),
      ],
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuranyTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuranyTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: QuranyTheme.textMuted),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _tajweedTile(Map<String, dynamic> note) {
    final severity = note['severity']?.toString() ?? 'info';
    final color = severity == 'warning' ? QuranyTheme.warningOrange : QuranyTheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note['expectedWord'] != null)
                  Text(
                    note['expectedWord'].toString(),
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
                    textDirection: TextDirection.rtl,
                  ),
                Text(
                  note['message']?.toString() ?? '',
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _comparisonTab() {
    if (_diffWords.isEmpty) {
      return const Center(child: Text('لا يوجد نص للمقارنة', style: TextStyle(color: Colors.grey)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _legend(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: QuranyTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: QuranyTheme.border),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              textDirection: TextDirection.rtl,
              spacing: 4,
              runSpacing: 8,
              children: _diffWords.map(_diffChip).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      children: [
        _legendDot('صحيح', QuranyTheme.correctGreen),
        _legendDot('استبدال', QuranyTheme.errorRed),
        _legendDot('حذف', Colors.deepOrange),
        _legendDot('حركات', Colors.teal),
      ],
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _diffChip(_DiffWord w) {
    Color bg;
    Color fg;
    switch (w.status) {
      case _DiffStatus.correct:
        bg = QuranyTheme.correctGreen.withValues(alpha: 0.18);
        fg = QuranyTheme.correctGreen;
      case _DiffStatus.omission:
        bg = Colors.deepOrange.withValues(alpha: 0.18);
        fg = Colors.deepOrange.shade800;
      case _DiffStatus.harakat:
        bg = Colors.teal.withValues(alpha: 0.18);
        fg = Colors.teal.shade800;
      default:
        bg = QuranyTheme.errorRed.withValues(alpha: 0.18);
        fg = QuranyTheme.errorRed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            w.referenceWord,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 17),
            textDirection: TextDirection.rtl,
          ),
          if (w.recitedWord != null && w.status != _DiffStatus.correct)
            Text(
              w.recitedWord!,
              style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 11),
              textDirection: TextDirection.rtl,
            ),
        ],
      ),
    );
  }

  Widget _errorsTab() {
    if (session.errors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.celebration_rounded, size: 56, color: QuranyTheme.correctGreen.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            const Text('ما شاء الله — لا أخطاء!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    final letterErrors = session.errors.where((e) => e.type != 'harakat').toList();
    final harakatErrors = session.errors.where((e) => e.type == 'harakat').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (letterErrors.isNotEmpty) ...[
          _sectionTitle('أخطاء الحروف (${letterErrors.length})'),
          ...letterErrors.map(_errorTile),
        ],
        if (harakatErrors.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle('أخطاء الحركات (${harakatErrors.length})'),
          ...harakatErrors.map(_errorTile),
        ],
      ],
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: QuranyTheme.darkGreen),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _errorTile(RecitationError err) {
    final isHarakat = err.type == 'harakat';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuranyTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: QuranyTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isHarakat ? Colors.teal : QuranyTheme.errorRed).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              err.typeArabic,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isHarakat ? Colors.teal : QuranyTheme.errorRed,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  err.expectedWord,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  textDirection: TextDirection.rtl,
                ),
                if (err.recitedWord.isNotEmpty)
                  Text(
                    'قُرئ: ${err.recitedWord}',
                    style: const TextStyle(fontSize: 12, color: QuranyTheme.textMuted),
                    textDirection: TextDirection.rtl,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsTab(Color scoreColor) {
    final subs = session.errors.where((e) => e.type == 'substitution').length;
    final omits = session.errors.where((e) => e.type == 'omission').length;
    final adds = session.errors.where((e) => e.type == 'addition').length;
    final seq = session.errors.where((e) => e.type == 'sequence').length;
    final har = session.errors.where((e) => e.type == 'harakat').length;
    final accuracy = session.totalWords > 0
        ? (session.matchedWords / session.totalWords * 100)
        : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _barStat('نسبة الدقة', session.similarityScore, scoreColor),
        const SizedBox(height: 10),
        _barStat('الكلمات المطابقة', accuracy, QuranyTheme.correctGreen),
        if (session.harakatScore != null) ...[
          const SizedBox(height: 10),
          _barStat('الحركات', session.harakatScore!, Colors.teal),
        ],
        if (_localizationScore != null) ...[
          const SizedBox(height: 10),
          _barStat('تحديد الآيات', _localizationScore!, QuranyTheme.primary),
        ],
        const SizedBox(height: 24),
        const Text(
          'توزيع الأخطاء',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: QuranyTheme.darkGreen),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 12),
        _countRow('استبدال', subs, QuranyTheme.errorRed),
        _countRow('حذف', omits, Colors.deepOrange),
        _countRow('إضافة', adds, Colors.purple),
        _countRow('ترتيب', seq, Colors.indigo),
        _countRow('حركات', har, Colors.teal),
      ],
    );
  }

  Widget _barStat(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${value.toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.12),
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _countRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _DiffWord {
  final String referenceWord;
  final String? recitedWord;
  final _DiffStatus status;
  const _DiffWord({
    required this.referenceWord,
    this.recitedWord,
    required this.status,
  });
}

enum _DiffStatus { correct, substitution, omission, addition, sequence, harakat }
