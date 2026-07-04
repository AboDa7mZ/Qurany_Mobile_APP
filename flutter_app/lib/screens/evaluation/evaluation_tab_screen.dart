import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/recitation_session.dart';
import '../../services/audio_service.dart';
import '../../services/recitation_api_service.dart';
import '../../services/recitation_history_service.dart';
import '../../services/schedule_service.dart';

/// تقييم — upload or record Al-Baqara recitation with explicit ayah range.
class EvaluationTabScreen extends StatefulWidget {
  const EvaluationTabScreen({super.key});

  @override
  State<EvaluationTabScreen> createState() => _EvaluationTabScreenState();
}

class _EvaluationTabScreenState extends State<EvaluationTabScreen>
    with SingleTickerProviderStateMixin {
  static const int _surahNumber = 2;
  static const String _surahName = 'البقرة';
  static final int _maxAyah = AppConstants.surahVerseCount[1]; // Al-Baqara = 286

  final AudioService _audio = AudioService();
  final AudioPlayer _preview = AudioPlayer();

  String _riwayah = 'hafs';
  int _startAyah = 1;
  int _endAyah = 5;
  _InputMode _inputMode = _InputMode.record;
  String? _audioPath;
  String? _pickedFileName;
  bool _isRecording = false;
  bool _isAnalyzing = false;
  int _recordingSeconds = 0;
  _AnalysisPhase _phase = _AnalysisPhase.idle;
  String? _errorMessage;
  bool _serverOnline = true;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _audio.durationStream.listen((s) {
      if (mounted && _isRecording) setState(() => _recordingSeconds = s);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkServer());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _preview.dispose();
    _audio.dispose();
    super.dispose();
  }

  Future<void> _checkServer() async {
    final api = context.read<RecitationApiService>();
    final ok = await api.isHealthy(timeout: const Duration(seconds: 10));
    if (mounted) setState(() => _serverOnline = ok);
  }

  String get _serverUrl => context.read<RecitationApiService>().baseUrl;

  bool get _looksLikeEmulatorDefault => _serverUrl.contains('10.0.2.2');

  String get _riwayahLabel => _riwayah == 'bazzi' ? 'البزي عن ابن كثير' : 'حفص عن عاصم';

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'ogg', 'flac', 'webm'],
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    await _preview.stop();
    setState(() {
      _audioPath = path;
      _pickedFileName = result.files.single.name;
      _errorMessage = null;
      _inputMode = _InputMode.upload;
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audio.stopRecording();
      setState(() {
        _isRecording = false;
        _audioPath = path;
        _pickedFileName = null;
      });
      return;
    }

    await _preview.stop();
    final started = await _audio.startRecording();
    if (!started) {
      if (!mounted) return;
      final denied = await _audio.isPermanentlyDenied();
      setState(() {
        _errorMessage = denied
            ? 'يُرجى تفعيل إذن الميكروفون من إعدادات الجهاز'
            : 'تعذّر بدء التسجيل — تحقق من إذن الميكروفون';
      });
      return;
    }
    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
      _audioPath = null;
      _pickedFileName = null;
      _errorMessage = null;
      _inputMode = _InputMode.record;
    });
  }

  Future<void> _previewAudio() async {
    if (_audioPath == null) return;
    await _preview.stop();
    await _preview.play(DeviceFileSource(_audioPath!));
  }

  Future<void> _analyze() async {
    if (_audioPath == null) {
      setState(() => _errorMessage = 'سجّل تلاوة أو اختر ملفاً صوتياً أولاً');
      return;
    }
    if (_startAyah < 1 || _endAyah > _maxAyah || _startAyah > _endAyah) {
      setState(() => _errorMessage = 'حدّد نطاق آيات صحيحاً (من $_startAyah إلى $_endAyah)');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _phase = _AnalysisPhase.transcribing;
    });

    try {
      final api = context.read<RecitationApiService>();
      final ok = await api.isHealthy(timeout: const Duration(seconds: 12));
      if (!mounted) return;
      if (!ok) {
        final url = api.baseUrl;
        throw RecitationApiException(
          'تعذّر الاتصال بـ $url\n'
          '① شغّل الخادم على جهازك (python main.py)\n'
          '② في الإعدادات → عنوان الخادم → http://192.168.1.9:8000\n'
          '③ تأكد أن الهاتف والكمبيوتر على نفس شبكة الواي‑فاي',
        );
      }
      setState(() => _serverOnline = true);

      if (mounted) setState(() => _phase = _AnalysisPhase.loadingReference);

      final result = await api.analyzeRecitation(
        audioFilePath: _audioPath!,
        surahNumber: _surahNumber,
        riwayah: _riwayah,
        startAyah: _startAyah,
        endAyah: _endAyah,
        autoDetectAyahRange: false,
      );

      if (!mounted) return;
      setState(() => _phase = _AnalysisPhase.comparing);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final session = _sessionFromResult(result);
      if (!mounted) return;
      context.read<RecitationHistoryService>().addSession(session);
      try {
        if (mounted) context.read<ScheduleService>().updateStreak();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _phase = _AnalysisPhase.idle;
        _audioPath = null;
        _pickedFileName = null;
        _recordingSeconds = 0;
      });

      await Navigator.pushNamed(
        context,
        AppRoutes.evaluationResult,
        arguments: {
          'session': session.toJson(),
          'rawResult': result,
          'riwayahLabel': _riwayahLabel,
          'startAyah': _startAyah,
          'endAyah': _endAyah,
        },
      );
    } on RecitationApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _phase = _AnalysisPhase.idle;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _phase = _AnalysisPhase.idle;
        _errorMessage = 'حدث خطأ أثناء التحليل: $e';
      });
    }
  }

  RecitationSession _sessionFromResult(Map<String, dynamic> result) {
    final verses = _endAyah - _startAyah + 1;

    return RecitationSession(
      id: const Uuid().v4(),
      surahNumber: _surahNumber,
      surahName: _surahName,
      mode: 'evaluation',
      dateTime: DateTime.now(),
      similarityScore: (result['similarity_score'] ?? 0).toDouble(),
      totalWords: result['total_words'] ?? 0,
      matchedWords: result['matched_words'] ?? 0,
      mistakes: result['mistakes'] ?? 0,
      versesRecited: verses,
      transcribedText: result['transcribed_text']?.toString(),
      referenceText: result['reference_text']?.toString(),
      errors: _parseErrors(result['errors'] as List?),
      harakatScore: _numOrNull(result['harakatScore'] ?? result['harakat_score']),
      harakatMistakes: (result['harakatMistakes'] ?? result['harakat_mistakes'] as num?)?.toInt() ?? 0,
      harakatChecked: (result['harakatChecked'] ?? result['harakat_checked'] as num?)?.toInt() ?? 0,
    );
  }

  double? _numOrNull(dynamic v) =>
      v == null ? null : (v as num).toDouble();

  List<RecitationError> _parseErrors(List? raw) {
    if (raw == null) return const [];
    return raw.whereType<Map>().map((e) {
      return RecitationError(
        type: e['type']?.toString() ?? '',
        expectedWord: (e['expectedWord'] ?? e['expected_word'] ?? '').toString(),
        recitedWord: (e['recitedWord'] ?? e['recited_word'] ?? '').toString(),
        wordIndex: (e['wordIndex'] ?? e['word_index'] ?? 0) as int,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuranyTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildNoticeBanner()),
            if (!_serverOnline)
              SliverToBoxAdapter(child: _buildOfflineBanner()),
            SliverToBoxAdapter(child: _buildRiwayahSelector()),
            SliverToBoxAdapter(child: _buildAyahRangeSelector()),
            SliverToBoxAdapter(child: _buildInputSection()),
            if (_errorMessage != null)
              SliverToBoxAdapter(child: _buildErrorBanner()),
            SliverToBoxAdapter(child: _buildAnalyzeButton()),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [QuranyTheme.primary, QuranyTheme.primaryDark],
        ),
        borderRadius: BorderRadius.circular(QuranyTheme.cardRadius),
        boxShadow: [
          BoxShadow(
            color: QuranyTheme.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.fact_check_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تقييم التلاوة',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'تحليل دقيق للتلاوة حسب الرواية',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'حدّد نطاق الآيات التي تلاوتها، ثم سجّل أو ارفع الملف — '
            'يُقارن التسجيل بالنص المرجعي لتلك الآيات فقط.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 13,
              height: 1.5,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: QuranyTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: QuranyTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: QuranyTheme.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'متاح حالياً لسورة البقرة فقط — باقي السور قريباً إن شاء الله',
              style: TextStyle(
                color: QuranyTheme.darkGreen,
                fontSize: 12.5,
                height: 1.4,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuranyTheme.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: QuranyTheme.errorRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: QuranyTheme.errorRed, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'الخادم غير متصل',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              TextButton(onPressed: _checkServer, child: const Text('إعادة')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'العنوان: $_serverUrl',
            style: const TextStyle(fontSize: 12, color: QuranyTheme.textSecondary),
            textDirection: TextDirection.ltr,
          ),
          if (_looksLikeEmulatorDefault) ...[
            const SizedBox(height: 6),
            Text(
              'على الهاتف الحقيقي غيّر العنوان إلى IP جهازك (مثل http://192.168.1.9:8000)',
              style: TextStyle(fontSize: 11.5, color: QuranyTheme.errorRed, height: 1.35),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.pushNamed(context, AppRoutes.settings);
              if (mounted) _checkServer();
            },
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('فتح إعدادات عنوان الخادم'),
          ),
        ],
      ),
    );
  }

  Widget _buildRiwayahSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'اختر الرواية',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: QuranyTheme.darkGreen,
            ),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _riwayahChip('hafs', 'حفص عن عاصم', Icons.menu_book_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _riwayahChip('bazzi', 'البزي عن ابن كثير', Icons.auto_stories_rounded)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _riwayahChip(String value, String label, IconData icon) {
    final selected = _riwayah == value;
    return Material(
      color: selected ? QuranyTheme.primary : QuranyTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _isAnalyzing
            ? null
            : () => setState(() => _riwayah = value),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? QuranyTheme.primary : QuranyTheme.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.white : QuranyTheme.primary, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : QuranyTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAyahRangeSelector() {
    final span = _endAyah - _startAyah + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: QuranyTheme.surface,
          borderRadius: BorderRadius.circular(QuranyTheme.cardRadius),
          border: Border.all(color: QuranyTheme.border),
          boxShadow: [
            BoxShadow(
              color: QuranyTheme.shadow,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.format_list_numbered_rtl_rounded, color: QuranyTheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'نطاق الآيات — سورة $_surahName',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: QuranyTheme.darkGreen,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'اختر الآيات التي تلاوتها بالضبط — يُقارن التسجيل بهذا النص فقط',
              style: TextStyle(fontSize: 12, color: QuranyTheme.textMuted, height: 1.35),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 360;
                final fromStepper = _ayahStepper(
                  label: 'من آية',
                  value: _startAyah,
                  onChanged: (v) => setState(() {
                    _startAyah = v;
                    if (_endAyah < _startAyah) _endAyah = _startAyah;
                  }),
                );
                final toStepper = _ayahStepper(
                  label: 'إلى آية',
                  value: _endAyah,
                  onChanged: (v) => setState(() {
                    _endAyah = v;
                    if (_startAyah > _endAyah) _startAyah = _endAyah;
                  }),
                );
                if (stacked) {
                  return Column(
                    children: [
                      fromStepper,
                      const SizedBox(height: 12),
                      Icon(Icons.swap_vert_rounded, color: QuranyTheme.textMuted, size: 18),
                      const SizedBox(height: 12),
                      toStepper,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: fromStepper),
                    Padding(
                      padding: const EdgeInsets.only(top: 28),
                      child: Icon(Icons.arrow_back_rounded, color: QuranyTheme.textMuted, size: 18),
                    ),
                    Expanded(child: toStepper),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: QuranyTheme.surfaceSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_stories_outlined, size: 16, color: QuranyTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      _startAyah == _endAyah
                          ? 'الآية $_startAyah — $span آية'
                          : 'الآيات $_startAyah–$_endAyah — $span ${_ayahCountLabel(span)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: QuranyTheme.darkGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ayahCountLabel(int n) {
    if (n == 1) return 'آية';
    if (n == 2) return 'آيتان';
    if (n >= 3 && n <= 10) return 'آيات';
    return 'آية';
  }

  Widget _ayahStepper({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: QuranyTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: QuranyTheme.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: QuranyTheme.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepperButton(
                icon: Icons.remove_rounded,
                enabled: !_isAnalyzing && value > 1,
                onPressed: () => onChanged(value - 1),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _isAnalyzing ? null : () => _pickAyah(label, value, onChanged),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$value',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: QuranyTheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              _stepperButton(
                icon: Icons.add_rounded,
                enabled: !_isAnalyzing && value < _maxAyah,
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepperButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 20),
      ),
    );
  }

  Future<void> _pickAyah(
    String title,
    int current,
    ValueChanged<int> onChanged,
  ) async {
    var selected = current;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: QuranyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 180,
                  child: ListWheelScrollView.useDelegate(
                    itemExtent: 44,
                    perspective: 0.003,
                    diameterRatio: 1.4,
                    controller: FixedExtentScrollController(initialItem: current - 1),
                    onSelectedItemChanged: (i) => selected = i + 1,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: _maxAyah,
                      builder: (_, i) => Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: i + 1 == selected ? 22 : 16,
                            fontWeight: i + 1 == selected ? FontWeight.bold : FontWeight.normal,
                            color: i + 1 == selected ? QuranyTheme.primary : QuranyTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      onChanged(selected);
                      Navigator.pop(ctx);
                    },
                    child: const Text('تأكيد'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'مصدر الصوت',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: QuranyTheme.darkGreen,
            ),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _modeTab(
                  _InputMode.record,
                  'تسجيل مباشر',
                  Icons.mic_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _modeTab(
                  _InputMode.upload,
                  'رفع ملف',
                  Icons.upload_file_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_inputMode == _InputMode.record) _buildRecorderCard(),
          if (_inputMode == _InputMode.upload) _buildUploadCard(),
        ],
      ),
    );
  }

  Widget _modeTab(_InputMode mode, String label, IconData icon) {
    final selected = _inputMode == mode;
    return Material(
      color: selected ? QuranyTheme.surfaceSoft : QuranyTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _isAnalyzing ? null : () => setState(() => _inputMode = mode),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? QuranyTheme.primary : QuranyTheme.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? QuranyTheme.primary : QuranyTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? QuranyTheme.primary : QuranyTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecorderCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: QuranyTheme.surface,
        borderRadius: BorderRadius.circular(QuranyTheme.cardRadius),
        border: Border.all(color: QuranyTheme.border),
        boxShadow: [
          BoxShadow(color: QuranyTheme.shadow, blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          if (_isRecording)
            ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.08).animate(
                CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: QuranyTheme.errorRed.withValues(alpha: 0.15),
                  border: Border.all(color: QuranyTheme.errorRed, width: 3),
                ),
                child: const Icon(Icons.mic, color: QuranyTheme.errorRed, size: 40),
              ),
            )
          else
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: QuranyTheme.primary.withValues(alpha: 0.1),
                border: Border.all(color: QuranyTheme.primary.withValues(alpha: 0.4), width: 2),
              ),
              child: Icon(
                _audioPath != null ? Icons.check_circle_rounded : Icons.mic_none_rounded,
                color: QuranyTheme.primary,
                size: 40,
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _isRecording
                ? _formatDuration(_recordingSeconds)
                : _audioPath != null
                    ? 'تم التسجيل — جاهز للتحليل'
                    : 'اضغط للبدء بالتسجيل',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _isRecording ? QuranyTheme.errorRed : QuranyTheme.darkGreen,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'سورة $_surahName — الآيات $_startAyah–$_endAyah',
            style: const TextStyle(fontSize: 12, color: QuranyTheme.textMuted),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _isAnalyzing ? null : _toggleRecording,
                icon: Icon(_isRecording ? Icons.stop_rounded : Icons.fiber_manual_record),
                label: Text(_isRecording ? 'إيقاف' : 'تسجيل'),
                style: FilledButton.styleFrom(
                  backgroundColor: _isRecording ? QuranyTheme.errorRed : QuranyTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              if (_audioPath != null && !_isRecording) ...[
                const SizedBox(width: 10),
                IconButton.outlined(
                  onPressed: _previewAudio,
                  icon: const Icon(Icons.play_arrow_rounded),
                  tooltip: 'استماع',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard() {
    final hasFile = _audioPath != null;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: QuranyTheme.surface,
        borderRadius: BorderRadius.circular(QuranyTheme.cardRadius),
        border: Border.all(
          color: hasFile ? QuranyTheme.success.withValues(alpha: 0.4) : QuranyTheme.border,
        ),
      ),
      child: Column(
        children: [
          Icon(
            hasFile ? Icons.audio_file_rounded : Icons.cloud_upload_outlined,
            size: 52,
            color: hasFile ? QuranyTheme.success : QuranyTheme.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            hasFile ? (_pickedFileName ?? 'ملف محدد') : 'اختر ملفاً صوتياً',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: QuranyTheme.darkGreen,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'WAV · MP3 · M4A · AAC · OGG',
            style: TextStyle(fontSize: 11, color: QuranyTheme.textMuted),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _isAnalyzing ? null : _pickAudioFile,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(hasFile ? 'تغيير الملف' : 'اختيار ملف'),
              ),
              if (hasFile) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: _previewAudio,
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: QuranyTheme.errorRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: QuranyTheme.errorRed, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: QuranyTheme.errorRed, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    final canAnalyze = _audioPath != null && !_isRecording && !_isAnalyzing;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (_isAnalyzing) _buildProgressCard(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: canAnalyze ? _analyze : null,
              icon: _isAnalyzing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    )
                  : const Icon(Icons.analytics_rounded),
              label: Text(
                _isAnalyzing ? 'جاري التحليل...' : 'تحليل التلاوة',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: QuranyTheme.primary,
                disabledBackgroundColor: QuranyTheme.primary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(QuranyTheme.buttonRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QuranyTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _phaseRow(_AnalysisPhase.transcribing, 'تحويل الصوت إلى نص', Icons.hearing_rounded),
          _phaseRow(
            _AnalysisPhase.loadingReference,
            'تحميل نص الآيات $_startAyah–$_endAyah ($_riwayahLabel)',
            Icons.menu_book_rounded,
          ),
          _phaseRow(_AnalysisPhase.comparing, 'المقارنة بالنص المرجعي', Icons.compare_rounded),
        ],
      ),
    );
  }

  Widget _phaseRow(_AnalysisPhase phase, String label, IconData icon) {
    final done = _phase.index > phase.index;
    final active = _phase == phase;
    final color = done
        ? QuranyTheme.success
        : active
            ? QuranyTheme.primary
            : QuranyTheme.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : icon,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? QuranyTheme.darkGreen : QuranyTheme.textSecondary,
              ),
            ),
          ),
          if (active)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

enum _InputMode { record, upload }

enum _AnalysisPhase { idle, transcribing, loadingReference, comparing }
