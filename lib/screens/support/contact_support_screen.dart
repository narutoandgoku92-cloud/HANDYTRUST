import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/support_ticket_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/support_ticket_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';

class ContactSupportScreen extends ConsumerStatefulWidget {
  const ContactSupportScreen({super.key});

  @override
  ConsumerState<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends ConsumerState<ContactSupportScreen> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // currentUserProvider streams /users/{uid}; it can briefly be null right
    // after navigation (profile doc still loading) or — rarely — permanently
    // null if profile creation failed during sign-up. Either way, silently
    // doing nothing here is what made the button look broken; surface it.
    final user = ref.read(currentUserProvider).asData?.value;
    if (user == null) {
      showErrorSnackbar(
        context,
        'Your profile is still loading. Please wait a moment and try again.',
      );
      return;
    }
    if (_subjectCtrl.text.trim().isEmpty || _messageCtrl.text.trim().isEmpty) {
      showErrorSnackbar(context, 'Please fill in both the subject and message.');
      return;
    }

    setState(() => _sending = true);
    try {
      await ref.read(supportTicketServiceProvider).createTicket(
            userId: user.uid,
            userName: user.name,
            subject: _subjectCtrl.text.trim(),
            message: _messageCtrl.text.trim(),
          );
      _subjectCtrl.clear();
      _messageCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket submitted. Our team will respond soon.')),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to submit ticket: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).asData?.value;
    final ticketsAsync =
        user == null ? const AsyncValue.data(<SupportTicketModel>[]) : ref.watch(userTicketsProvider(user.uid));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Help & Support',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
        backgroundColor: context.colors.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.colors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Submit a Ticket',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                const SizedBox(height: 12),
                TextField(
                  controller: _subjectCtrl,
                  decoration: const InputDecoration(hintText: 'Subject'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Describe your issue…'),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Submit'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Your Tickets',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textSecondary, fontFamily: 'Inter')),
          const SizedBox(height: 10),
          ticketsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (tickets) {
              if (tickets.isEmpty) {
                return Text('No tickets yet.',
                    style: TextStyle(color: context.colors.textTertiary, fontFamily: 'Inter'));
              }
              return Column(
                children: tickets.map((t) => _TicketTile(ticket: t)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  final SupportTicketModel ticket;

  const _TicketTile({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final resolved = ticket.status == 'resolved';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(ticket.subject,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: resolved ? context.colors.accentSurface : context.colors.warningSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  resolved ? 'Resolved' : 'Open',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: resolved ? context.colors.accent : context.colors.warning,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(ticket.message,
              style: TextStyle(fontSize: 13, color: context.colors.textSecondary, fontFamily: 'Inter')),
          if (ticket.adminResponse != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Support: ${ticket.adminResponse}',
                  style: TextStyle(fontSize: 13, color: context.colors.primary, fontFamily: 'Inter')),
            ),
          ],
        ],
      ),
    );
  }
}
