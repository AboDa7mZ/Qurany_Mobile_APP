import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';

class StatisticsScreen extends StatelessWidget {
  final int totalVerses;
  final int totalCorrectedFaults;
  final Map<String, int> faultsDetail;

  const StatisticsScreen({
    super.key,
    this.totalVerses = 0,
    this.totalCorrectedFaults = 0,
    this.faultsDetail = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuranyTheme.background,
      appBar: AppBar(
        title: const Text('إحصائيات الجلسة'),
        automaticallyImplyLeading: false,
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
