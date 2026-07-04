import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Ephemeral mushaf-page recitation report (not persisted).
class MushafSessionResultSheet extends StatelessWidget {
  final Map<String, dynamic>? result;
  final int pageNumber;
  final bool loading;
  final String? error;
  final bool partial;

  const MushafSessionResultSheet({
    super.key,
    required this.result,
    required this.pageNumber,
    this.loading = false,
    this.error,
    this.partial = false,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic>? result,
    required int pageNumber,
    bool loading = false,
    String? error,
    bool partial = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MushafSessionResultSheet(
        result: result,
        pageNumber: pageNumber,
        loading: loading,
        error: error,
        partial: partial,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: QuranyTheme.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'نتيجة التلاوة — صفحة $pageNumber',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: QuranyTheme.darkGreen,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: QuranyTheme.errorRed),
                                ),
                              ),
                            )
                          : _ResultBody(
                              result: result!,
                              scrollController: scrollController,
                              partial: partial,
                              isLocal: result!['source'] == 'local',
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  final Map<String, dynamic> result;
  final ScrollController scrollController;
  final bool partial;
  final bool isLocal;

  const _ResultBody({
    required this.result,
    required this.scrollController,
    this.partial = false,
    this.isLocal = false,
  });

  String _typeLabel(String type) {
    switch (type) {
      case 'harakat':
        return 'تشكيل';
      case 'substitution':
        return 'كلمة خاطئة';
      case 'omission':
        return 'كلمة ناقصة';
      case 'addition':
        return 'كلمة زائدة';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final similarity =
        ((result['similarity_score'] as num?) ?? 0).toDouble();
    final harakatMistakes = (result['harakatMistakes'] as num?)?.toInt() ??
        (result['harakat_mistakes'] as num?)?.toInt() ??
        0;
    final harakatChecked = (result['harakatChecked'] as num?)?.toInt() ??
        (result['harakat_checked'] as num?)?.toInt() ??
        0;
    final errors = (result['errors'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    final letterErrors =
        errors.where((e) => e['type']?.toString() != 'harakat').toList();
    final harakatErrors =
        errors.where((e) => e['type']?.toString() == 'harakat').toList();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
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
                      value: similarity / 100,
                      strokeWidth: 6,
                      backgroundColor: QuranyTheme.border,
                      valueColor: AlwaysStoppedAnimation(
                        similarity >= 80
                            ? QuranyTheme.success
                            : similarity >= 60
                                ? QuranyTheme.warning
                                : QuranyTheme.errorRed,
                      ),
                    ),
                    Text(
                      '${similarity.toStringAsFixed(0)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'دقة التلاوة',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${letterErrors.length} ${letterErrors.length == 1 ? 'خطأ' : 'أخطاء'} في الكلمات'
                      '${harakatChecked > 0 ? ' • $harakatMistakes ${harakatMistakes == 1 ? 'خطأ' : 'أخطاء'} في التشكيل' : ''}'
                      '${partial ? ' • تلاوة جزئية' : ''}',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (letterErrors.isNotEmpty) ...[
          const Text(
            'أخطاء الكلمات:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...letterErrors.map((e) => _mistakeTile(e)),
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: QuranyTheme.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'لا توجد أخطاء في الكلمات حسب تحليل الخادم.',
              style: TextStyle(color: QuranyTheme.success),
            ),
          ),
        const SizedBox(height: 20),
        if (harakatErrors.isNotEmpty || harakatChecked > 0) ...[
          const Text(
            'أخطاء التشكيل:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (harakatErrors.isEmpty)
            const Text(
              'تشكيل سليم في الكلمات التي فُحصت.',
              style: TextStyle(color: QuranyTheme.success, fontSize: 13),
            )
          else
            ...harakatErrors.map((e) => _mistakeTile(e)),
        ],
        const SizedBox(height: 12),
        Text(
          isLocal
              ? 'نتيجة من التصحيح المباشر على الجهاز (الجلسة الحالية فقط).'
              : partial
                  ? 'تم تحليل ما قرأته حتى الآن — لا يلزم إكمال الصفحة.'
                  : 'هذه النتيجة للجلسة الحالية فقط ولن تُحفظ.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _mistakeTile(Map<String, dynamic> e) {
    final type = e['type']?.toString() ?? '';
    final expected =
        (e['expectedWord'] ?? e['expected_word'] ?? '') as String;
    final recited = (e['recitedWord'] ?? e['recited_word'] ?? '') as String;
    final isHarakat = type == 'harakat';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuranyTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QuranyTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _typeLabel(type),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isHarakat ? Colors.teal : QuranyTheme.errorRed,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('الصحيح', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      expected.isEmpty ? '—' : expected,
                      style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'MeQuran',
                        color: QuranyTheme.success,
                      ),
                    ),
                  ],
                ),
              ),
              if (recited.isNotEmpty) ...[
                const Icon(Icons.compare_arrows, size: 18),
                Expanded(
                  child: Column(
                    children: [
                      const Text('قراءتك', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(
                        recited,
                        style: TextStyle(
                          fontSize: 18,
                          fontFamily: 'MeQuran',
                          color: isHarakat ? Colors.teal : QuranyTheme.errorRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
