import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';

class IncidentsListScreen extends StatelessWidget {
  const IncidentsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'Вызовы',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => context.push('/call-history'),
                    icon: const Icon(Icons.history,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Incidents list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _demoIncidents.length,
                itemBuilder: (context, index) {
                  final item = _demoIncidents[index];
                  return _IncidentCard(
                    incident: item,
                    onTap: () => context.push('/incident-detail'),
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

class _IncidentCard extends StatelessWidget {
  final _DemoIncident incident;
  final VoidCallback onTap;

  const _IncidentCard({required this.incident, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        incident.statusColor.withValues(alpha: 0.7),
                        incident.statusColor.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      incident.name[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              incident.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            incident.time,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        incident.type,
                        style: TextStyle(
                          fontSize: 13,
                          color: incident.statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            incident.address,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right,
                    color: AppColors.textHint, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoIncident {
  final String name;
  final String type;
  final String address;
  final String time;
  final Color statusColor;

  const _DemoIncident({
    required this.name,
    required this.type,
    required this.address,
    required this.time,
    required this.statusColor,
  });
}

const _demoIncidents = [
  _DemoIncident(
    name: 'Алексей Петров',
    type: 'Кража',
    address: 'ул. Абая 42',
    time: '14:35',
    statusColor: AppColors.danger,
  ),
  _DemoIncident(
    name: 'Мария Иванова',
    type: 'ДТП',
    address: 'пр. Назарбаева 12',
    time: '13:20',
    statusColor: AppColors.warning,
  ),
  _DemoIncident(
    name: 'Сергей Ким',
    type: 'Нарушение порядка',
    address: 'ул. Жандосова 8',
    time: '12:45',
    statusColor: AppColors.danger,
  ),
  _DemoIncident(
    name: 'Елена Смирнова',
    type: 'Пожар',
    address: 'ул. Тимирязева 23',
    time: '11:15',
    statusColor: AppColors.danger,
  ),
  _DemoIncident(
    name: 'Дмитрий Волков',
    type: 'Подозрительная активность',
    address: 'ул. Гагарина 5',
    time: '10:30',
    statusColor: AppColors.warning,
  ),
];
