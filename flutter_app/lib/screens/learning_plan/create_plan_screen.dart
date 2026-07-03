import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../models/learning_plan.dart';
import '../../services/learning_plan_service.dart';
import '../../widgets/app_icons.dart';

class CreatePlanScreen extends StatefulWidget {
  const CreatePlanScreen({super.key});

  @override
  State<CreatePlanScreen> createState() => _CreatePlanScreenState();
}

class _CreatePlanScreenState extends State<CreatePlanScreen> {
  int _startSurah = 1; // Al-Fatihah
  int _endSurah = 114; // An-Nas
  int _startAyah = 1;
  int _endAyah = 6;
  int _totalDays = 30;

  @override
  void initState() {
    super.initState();
    _startAyah = 1;
    _endAyah = AppConstants.surahVerseCount[_endSurah - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('خطة جديدة'),
        leading: AppIcons.backButton(context: context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'اختر نطاق السور',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Start Surah
            const Text('من سورة:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: QuranyTheme.primaryGreen.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _startSurah,
                  isExpanded: true,
                  items: List.generate(114, (i) {
                    return DropdownMenuItem(
                      value: i + 1,
                      child: Text('${i + 1}. ${AppConstants.surahNames[i]}'),
                    );
                  }),
                  onChanged: (v) => setState(() {
                    _startSurah = v ?? 1;
                    _startAyah = 1;
                    if (_startSurah > _endSurah) {
                      _endSurah = _startSurah;
                      _endAyah = AppConstants.surahVerseCount[_endSurah - 1];
                    } else if (_startSurah == _endSurah) {
                      _endAyah = AppConstants.surahVerseCount[_endSurah - 1];
                    }
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Start Ayah
            const Text('من آية:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: QuranyTheme.primaryGreen.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _startAyah,
                  isExpanded: true,
                  items: List.generate(AppConstants.surahVerseCount[_startSurah - 1], (i) {
                    return DropdownMenuItem(
                      value: i + 1,
                      child: Text('${i + 1}'),
                    );
                  }),
                  onChanged: (v) => setState(() {
                    _startAyah = v ?? 1;
                    if (_startSurah == _endSurah && _startAyah > _endAyah) {
                      _endAyah = _startAyah;
                    }
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // End Surah
            const Text('إلى سورة:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: QuranyTheme.primaryGreen.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _endSurah,
                  isExpanded: true,
                  items: List.generate(114, (i) {
                    bool disabled = (i + 1) < _startSurah;
                    return DropdownMenuItem(
                      value: i + 1,
                      enabled: !disabled,
                      child: Text(
                        '${i + 1}. ${AppConstants.surahNames[i]}',
                        style: TextStyle(
                          color: disabled ? Colors.grey : Colors.black,
                        ),
                      ),
                    );
                  }),
                  onChanged: (v) => setState(() {
                    _endSurah = v ?? 114;
                    _endAyah = AppConstants.surahVerseCount[_endSurah - 1];
                    if (_startSurah == _endSurah && _startAyah > _endAyah) {
                      _startAyah = 1;
                    }
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // End Ayah
            const Text('إلى آية:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: QuranyTheme.primaryGreen.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _endAyah,
                  isExpanded: true,
                  items: List.generate(AppConstants.surahVerseCount[_endSurah - 1], (i) {
                    bool disabled = _startSurah == _endSurah && (i + 1) < _startAyah;
                    return DropdownMenuItem(
                      value: i + 1,
                      enabled: !disabled,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: disabled ? Colors.grey : Colors.black,
                        ),
                      ),
                    );
                  }),
                  onChanged: (v) => setState(() => _endAyah = v ?? 1),
                ),
              ),
            ),
            const SizedBox(height: 32),

            const Text(
              'المدة الزمنية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Duration Input
            TextFormField(
              initialValue: _totalDays.toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'المدة (بالأيام)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: QuranyTheme.primaryGreen.withValues(alpha: 0.3)),
                ),
                suffixText: 'يوم',
              ),
              onChanged: (val) {
                final intVal = int.tryParse(val);
                if (intVal != null && intVal > 0) {
                  setState(() => _totalDays = intVal);
                }
              },
            ),
            
            const SizedBox(height: 48),

            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _generatePlan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: QuranyTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'إنشاء الخطة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _generatePlan() async {
    final List<DailyTask> tasks = [];
    final List<MapEntry<int, int>> allVerses = [];

    // Collect all verses in range
    if (_startSurah == _endSurah) {
      for (int v = _startAyah; v <= _endAyah; v++) {
        allVerses.add(MapEntry(_startSurah, v));
      }
    } else {
      // First surah verses
      for (int v = _startAyah; v <= AppConstants.surahVerseCount[_startSurah - 1]; v++) {
        allVerses.add(MapEntry(_startSurah, v));
      }
      // Middle surahs verses
      for (int s = _startSurah + 1; s < _endSurah; s++) {
        for (int v = 1; v <= AppConstants.surahVerseCount[s - 1]; v++) {
          allVerses.add(MapEntry(s, v));
        }
      }
      // Last surah verses
      for (int v = 1; v <= _endAyah; v++) {
        allVerses.add(MapEntry(_endSurah, v));
      }
    }

    int totalVerses = allVerses.length;
    double versesPerDay = totalVerses / _totalDays;
    int currentIndex = 0;

    for (int day = 1; day <= _totalDays; day++) {
      if (currentIndex >= totalVerses) break;

      int dayStartIndex = currentIndex;
      int targetEndIndex = (day * versesPerDay).round();
      if (targetEndIndex > totalVerses) {
        targetEndIndex = totalVerses;
      }
      if (targetEndIndex <= dayStartIndex) {
        targetEndIndex = dayStartIndex + 1;
      }

      int dayEndIndex = targetEndIndex - 1;
      currentIndex = targetEndIndex;

      final startV = allVerses[dayStartIndex];
      final endV = allVerses[dayEndIndex];

      String desc = startV.key == endV.key
          ? 'سورة ${AppConstants.surahNames[startV.key - 1]}: آية ${startV.value} - ${endV.value}'
          : 'سورة ${AppConstants.surahNames[startV.key - 1]} آية ${startV.value} إلى سورة ${AppConstants.surahNames[endV.key - 1]} آية ${endV.value}';

      tasks.add(DailyTask(
        dayNumber: day,
        startSurah: startV.key,
        startVerse: startV.value,
        endSurah: endV.key,
        endVerse: endV.value,
        description: desc,
      ));
    }

    // Title includes surah names and ayah range for clarity
    String planTitle = 'خطة حفظ: ';
    if (_startSurah == _endSurah) {
      planTitle += '${AppConstants.surahNames[_startSurah - 1]} (${_startAyah}-${_endAyah})';
    } else {
      planTitle += '${AppConstants.surahNames[_startSurah - 1]} (${_startAyah}) إلى ${AppConstants.surahNames[_endSurah - 1]} (${_endAyah})';
    }

    final plan = LearningPlan(
      title: planTitle,
      startSurah: _startSurah,
      endSurah: _endSurah,
      totalDays: tasks.length,
      dailyTasks: tasks,
    );

    await context.read<LearningPlanService>().savePlan(plan);
    if (!mounted) return;
    
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إنشاء الخطة بنجاح!')),
    );
  }
}
