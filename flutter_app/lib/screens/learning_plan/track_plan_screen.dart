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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'نسبة الإنجاز: ${(plan.progressPercentage * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    Text(
                      'اليوم ${plan.currentDay} من ${plan.totalDays}',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
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
                final isPast = task.dayNumber < plan.currentDay;

                return Card(
                  elevation: isToday ? 4 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isToday
                        ? const BorderSide(color: QuranyTheme.primaryGreen, width: 2)
                        : BorderSide.none,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: task.isCompleted
                            ? QuranyTheme.correctGreen
                            : (isToday ? QuranyTheme.primaryGreen.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1)),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: task.isCompleted
                            ? const Icon(Icons.check, color: Colors.white)
                            : Text(
                                '${task.dayNumber}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isToday ? QuranyTheme.primaryGreen : Colors.grey,
                                ),
                              ),
                      ),
                    ),
                    title: Text(
                      'اليوم ${task.dayNumber}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: task.isCompleted ? Colors.grey : Colors.black,
                      ),
                    ),
                    subtitle: Text(
                      task.description,
                      style: TextStyle(
                        color: task.isCompleted ? Colors.grey : Colors.black87,
                      ),
                    ),
                    trailing: task.isCompleted
                        ? const Text('مكتمل', style: TextStyle(color: QuranyTheme.correctGreen, fontWeight: FontWeight.bold))
                        : (isToday
                            ? ElevatedButton(
                                onPressed: () {
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.recitation,
                                    arguments: {
                                      'surahNumber': task.startSurah,
                                      'surahName': '', // Re-fetched
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
                              )
                            : const SizedBox.shrink()),
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
