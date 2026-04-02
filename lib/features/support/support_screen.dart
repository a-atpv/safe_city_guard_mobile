import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_colors.dart';
import 'support_repository.dart';

final supportRepoProvider = Provider((ref) => SupportRepository());

final supportContactsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.read(supportRepoProvider);
  return repo.getContacts();
});

final supportFaqProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final repo = ref.read(supportRepoProvider);
  return repo.getFAQ();
});

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(supportContactsProvider);
    final faqAsync = ref.watch(supportFaqProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_ios,
                        color: AppColors.textPrimary, size: 20),
                  ),
                  const Expanded(
                    child: Text(
                      'Поддержка',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    // Support icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.headset_mic_outlined,
                        color: AppColors.accent,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Нужна помощь?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Свяжитесь с нами удобным способом',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Contact options from API
                    contactsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: AppColors.accent),
                      ),
                      error: (e, _) => _buildFallbackContacts(),
                      data: (contacts) {
                        final whatsapp = contacts['whatsapp'] as String?;
                        final phone = contacts['phone'] as String?;
                        final email = contacts['email'] as String?;

                        return Column(
                          children: [
                            if (whatsapp != null && whatsapp.isNotEmpty)
                              _buildContactButton(
                                icon: Icons.chat,
                                label: 'WhatsApp',
                                subtitle: whatsapp,
                                color: const Color(0xFF25D366),
                                onTap: () => _launchUrl('https://wa.me/$whatsapp'),
                              ),
                            if (whatsapp != null && whatsapp.isNotEmpty)
                              const SizedBox(height: 12),
                            if (phone != null && phone.isNotEmpty)
                              _buildContactButton(
                                icon: Icons.phone,
                                label: 'Позвонить',
                                subtitle: phone,
                                color: AppColors.accent,
                                onTap: () => _launchUrl('tel:$phone'),
                              ),
                            if (phone != null && phone.isNotEmpty)
                              const SizedBox(height: 12),
                            if (email != null && email.isNotEmpty)
                              _buildContactButton(
                                icon: Icons.email_outlined,
                                label: 'Email',
                                subtitle: email,
                                color: AppColors.info,
                                onTap: () => _launchUrl('mailto:$email'),
                              ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // FAQ Section
                    faqAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (items) {
                        if (items.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Часто задаваемые вопросы',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...items.map((item) => _FAQTile(
                                  question: item['question'] ?? '',
                                  answer: item['answer'] ?? '',
                                )),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackContacts() {
    return Column(
      children: [
        _buildContactButton(
          icon: Icons.chat,
          label: 'WhatsApp',
          subtitle: '+7 777 000 0000',
          color: const Color(0xFF25D366),
          onTap: () {},
        ),
        const SizedBox(height: 12),
        _buildContactButton(
          icon: Icons.phone,
          label: 'Позвонить',
          subtitle: '+7 777 000 0000',
          color: AppColors.accent,
          onTap: () {},
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.cardDark,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FAQTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FAQTile({required this.question, required this.answer});

  @override
  State<_FAQTile> createState() => _FAQTileState();
}

class _FAQTileState extends State<_FAQTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.textHint,
                      size: 22,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  Text(
                    widget.answer,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
