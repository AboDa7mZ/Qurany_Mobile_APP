import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/learning_plan_service.dart';
import '../../widgets/app_icons.dart';

class TrackPlanScreen extends StatelessWidget {
  final String? planId;
  const TrackPlanScreen({super.key, this.planId});

  @override
  Widget build(BuildContext context) {
    final planService = context.watch<LearningPlanService>();
    final plan = planId != null ? planService.getPlanById(planId!) : planService.activePlan;

    if (plan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('متابعة الخطة')),
        body: const Center(child: Text('لا توجد خطة نشطة')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('متابعة الخطة'),
        leading: AppIcons.backButton(context: context),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'إحصائيات الخطة',
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.planStats,
                arguments: {'planId': plan.id},
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: QuranyTheme.errorRed),
            tooltip: 'إلغاء الخطة',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('إلغاء الخطة؟'),
                  content: const Text('هل أنت متأكد من رغبتك في إلغاء هذه الخطة نهائياً؟'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
                    TextButton(
                      onPressed: () {
                        planService.deletePlan(plan.id);
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                      child: const Text('إلغاء الخطة', style: TextStyle(color: QuranyTheme.errorRed)),
                    ),
                  ],
                ),
              );
            },
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: QuranyTheme.primaryGreen,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  plan.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'نسبة الإنجاز: ${(plan.progressPercentage * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'اليوم ${plan.currentDay} من ${plan.totalDays}',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: plan.progressPercentage,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: plan.dailyTasks.length,
              itemBuilder: (context, index) {
                final task = plan.dailyTasks[index];
                final isToday = task.dayNumber == plan.currentDay;

                return Card(
                  elevation: isToday ? 4 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isToday
                        ? const BorderSide(color: QuranyTheme.primaryGreen, width: 2)
                        : BorderSide.none,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: task.isCompleted
                                    ? QuranyTheme.correctGreen
                                    : (isToday
                                        ? QuranyTheme.primaryGreen
                                            .withValues(alpha: 0.1)
                                        : Colors.grey.withValues(alpha: 0.1)),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: task.isCompleted
                                    ? const Icon(Icons.check, color: Colors.white)
                                    : Text(
                                        '${task.dayNumber}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isToday
                                              ? QuranyTheme.primaryGreen
                                              : Colors.grey,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'اليوم ${task.dayNumber}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: task.isCompleted
                                          ? Colors.grey
                                          : Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    task.description,
                                    style: TextStyle(
                                      color: task.isCompleted
                                          ? Colors.grey
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (task.isCompleted &&
                            planService.hasMuallimReport(
                                plan.id, task.dayNumber)) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () {
                                final report = planService.getMuallimReport(
                                  plan.id,
                                  task.dayNumber,
                                );
                                if (report == null) return;
                                final labels =
                                    (report['tashkeelAyahLabels'] as List?)
                                            ?.map((e) =>
                                                Map<String, dynamic>.from(
                                                    e as Map))
                                            .toList() ??
                                        const <Map<String, dynamic>>[];
                                final results =
                                    (report['analysisResults'] as List?)
                                            ?.map((e) =>
                                                Map<String, dynamic>.from(
                                                    e as Map))
                                            .toList() ??
                                        const <Map<String, dynamic>>[];
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.statistics,
                                  arguments: {
                                    'totalVerses': report['totalVerses'] ?? 0,
                                    'totalCorrectedFaults':
                                        report['totalCorrectedFaults'] ?? 0,
                                    'faultsDetail': Map<String, int>.from(
                                      (report['faultsDetail'] as Map?)?.map(
                                            (k, v) => MapEntry(
                                              k.toString(),
                                              (v as num).toInt(),
                                            ),
                                          ) ??
                                          {},
                                    ),
                                    'tashkeelAyahLabels': labels,
                                    'analysisResults': results,
                                  },
                                );
                              },
                              child: const Text(
                                'عرض النتائج',
                                style: TextStyle(
                                  color: QuranyTheme.primaryGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ] else if (task.isCompleted) ...[
                          const SizedBox(height: 8),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'مكتمل',
                              style: TextStyle(
                                color: QuranyTheme.correctGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ] else if (isToday) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.recitation,
                                  arguments: {
                                    'surahNumber': task.startSurah,
                                    'surahName': '',
                                    'mode': 'tahfeez',
                                    'planDayNumber': task.dayNumber,
                                    'planId': plan.id,
                                  },
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: QuranyTheme.primaryGreen,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('تسميع'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
