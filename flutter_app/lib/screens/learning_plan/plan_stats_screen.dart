import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/learning_plan_service.dart';
import '../../widgets/app_icons.dart';

class PlanStatsScreen extends StatelessWidget {
  final String? planId;

  const PlanStatsScreen({super.key, this.planId});

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} - ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final planService = context.watch<LearningPlanService>();
    final plan = planId != null ? planService.getPlanById(planId!) : planService.activePlan;

    if (plan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('إحصائيات الخطة')),
        body: const Center(child: Text('الخطة غير موجودة')),
      );
    }

    final totalDays = plan.totalDays;
    final completedDays = plan.dailyTasks.where((t) => t.isCompleted).length;

    return Scaffold(
      backgroundColor: QuranyTheme.background,
      appBar: AppBar(
        title: const Text('إحصائيات الخطة'),
        leading: AppIcons.backButton(context: context),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: QuranyTheme.primary,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: QuranyTheme.shadow,
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'مدة الخطة: $totalDays يوم',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تاريخ الإنشاء: ${_formatDateTime(plan.createdAt)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Overview Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      title: 'التقدم الكلي',
                      value: '${(plan.progressPercentage * 100).toStringAsFixed(1)}%',
                      icon: Icons.donut_large_rounded,
                      color: QuranyTheme.success,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricCard(
                      title: 'الأيام المنجزة',
                      value: '$completedDays / $totalDays',
                      icon: Icons.check_circle_outline_rounded,
                      color: QuranyTheme.primaryGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Tasks Timeline / History Section
              const Text(
                'سجل المهام اليومية والتقدم',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: QuranyTheme.darkGreen,
                ),
              ),
              const SizedBox(height: 12),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: plan.dailyTasks.length,
                itemBuilder: (context, index) {
                  final task = plan.dailyTasks[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: task.isCompleted
                          ? QuranyTheme.correctGreen.withValues(alpha: 0.08)
                          : QuranyTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: task.isCompleted
                            ? QuranyTheme.correctGreen.withValues(alpha: 0.3)
                            : QuranyTheme.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: task.isCompleted
                                ? QuranyTheme.correctGreen
                                : Colors.grey.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: task.isCompleted
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : Text(
                                    '${task.dayNumber}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'اليوم ${task.dayNumber}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: task.isCompleted
                                      ? QuranyTheme.correctGreen
                                      : QuranyTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                task.description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: QuranyTheme.textSecondary,
                                ),
                              ),
                              if (task.isCompleted && task.completedAt != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'تم التلاوة والتسميع في: ${_formatDateTime(task.completedAt!)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
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
