import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../services/tafsir_service.dart';

/// Opens a bottom sheet that loads and displays Jalalayn tafsir for an ayah.
Future<void> showTafsirSheet(
  BuildContext context, {
  required int surahNumber,
  required int ayahNumber,
  String? verseLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TafsirSheetContent(
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      verseLabel: verseLabel ?? '$surahNumber:$ayahNumber',
    ),
  );
}

class _TafsirSheetContent extends StatefulWidget {
  final int surahNumber;
  final int ayahNumber;
  final String verseLabel;

  const _TafsirSheetContent({
    required this.surahNumber,
    required this.ayahNumber,
    required this.verseLabel,
  });

  @override
  State<_TafsirSheetContent> createState() => _TafsirSheetContentState();
}

class _TafsirSheetContentState extends State<_TafsirSheetContent> {
  late Future<String> _tafsirFuture;

  @override
  void initState() {
    super.initState();
    _tafsirFuture = context.read<TafsirService>().getAyahTafsir(
          widget.surahNumber,
          widget.ayahNumber,
        );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'الآية ${widget.verseLabel}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              AppConstants.tafsirEditionName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: QuranyTheme.primaryGreen,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: FutureBuilder<String>(
                future: _tafsirFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: QuranyTheme.errorRed,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'تعذر تحميل التفسير. تأكد من اتصالك بالإنترنت.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _tafsirFuture = context
                                    .read<TafsirService>()
                                    .getAyahTafsir(
                                      widget.surahNumber,
                                      widget.ayahNumber,
                                    );
                              });
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    );
                  }

                  final tafsirText = snapshot.data ?? '';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              tafsirText,
                              style: const TextStyle(
                                fontSize: 18,
                                height: 1.9,
                              ),
                              textAlign: TextAlign.right,
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(
                          Icons.copy,
                          color: QuranyTheme.primaryGreen,
                        ),
                        title: const Text('نسخ التفسير'),
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: tafsirText),
                          );
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم نسخ التفسير')),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
