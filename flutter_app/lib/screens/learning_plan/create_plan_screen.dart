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
  int _totalDays = 30;

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
                    if (_startSurah > _endSurah) {
                      _endSurah = _startSurah;
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
                    // Disable items before startSurah
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
                  onChanged: (v) => setState(() => _endSurah = v ?? 114),
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
    int totalVerses = 0;
    
    for (int i = _startSurah; i <= _endSurah; i++) {
      totalVerses += AppConstants.surahVerseCount[i - 1];
    }

    double versesPerDay = totalVerses / _totalDays;
    
    int currentSurah = _startSurah;
    int currentVerse = 1;
    double exactAccumulator = 0.0;

    for (int day = 1; day <= _totalDays; day++) {
      exactAccumulator += versesPerDay;
      int targetVersesForToday = exactAccumulator.round();
      int versesAssignedToday = 0;
      
      int dayStartSurah = currentSurah;
      int dayStartVerse = currentVerse;

      // Assign verses until we meet today's target
      while (versesAssignedToday < targetVersesForToday && currentSurah <= _endSurah) {
        int versesLeftInSurah = AppConstants.surahVerseCount[currentSurah - 1] - currentVerse + 1;
        int needed = targetVersesForToday - versesAssignedToday;

        if (versesLeftInSurah <= needed) {
          versesAssignedToday += versesLeftInSurah;
          currentSurah++;
          currentVerse = 1;
        } else {
          versesAssignedToday += needed;
          currentVerse += needed;
        }
      }

      int dayEndSurah = currentSurah > _endSurah ? _endSurah : (currentVerse == 1 ? currentSurah - 1 : currentSurah);
      int dayEndVerse = currentSurah > _endSurah 
          ? AppConstants.surahVerseCount[_endSurah - 1] 
          : (currentVerse == 1 ? AppConstants.surahVerseCount[dayEndSurah - 1] : currentVerse - 1);

      exactAccumulator -= targetVersesForToday; // carry over fractional differences
      
      String desc = dayStartSurah == dayEndSurah
          ? 'سورة ${AppConstants.surahNames[dayStartSurah - 1]}: $dayStartVerse - $dayEndVerse'
          : 'سورة ${AppConstants.surahNames[dayStartSurah - 1]} آية $dayStartVerse إلى سورة ${AppConstants.surahNames[dayEndSurah - 1]} آية $dayEndVerse';

      tasks.add(DailyTask(
        dayNumber: day,
        startSurah: dayStartSurah,
        startVerse: dayStartVerse,
        endSurah: dayEndSurah,
        endVerse: dayEndVerse,
        description: desc,
      ));

      if (currentSurah > _endSurah) break;
    }

    final plan = LearningPlan(
      title: 'خطة حفظ (${_totalDays} يوم)',
      startSurah: _startSurah,
      endSurah: _endSurah,
      totalDays: tasks.length,
      dailyTasks: tasks,
    );

    await context.read<LearningPlanService>().savePlan(plan);
    if (!mounted) return;
    
    // Pop back to home, which will now show the new tab
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إنشاء الخطة بنجاح!')),
    );
  }
}
