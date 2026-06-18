import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/job_model.dart';
import '../theme/app_theme.dart';

/// Vertical step-by-step timeline showing the job's progress through the
/// 8-state main path, plus terminal branch nodes for disputed/cancelled.
class JobTimelineWidget extends StatelessWidget {
  final JobModel job;

  const JobTimelineWidget({super.key, required this.job});

  // Ordered main linear path
  static const _mainPath = [
    JobStatus.requested,
    JobStatus.matched,
    JobStatus.inChat,
    JobStatus.paymentPending,
    JobStatus.escrowLocked,
    JobStatus.inProgress,
    JobStatus.submitted,
    JobStatus.completed,
  ];

  static const _labels = {
    JobStatus.requested: 'Job Posted',
    JobStatus.matched: 'Artisan Matched',
    JobStatus.inChat: 'In Negotiation',
    JobStatus.paymentPending: 'Payment Pending',
    JobStatus.escrowLocked: 'Escrow Secured',
    JobStatus.inProgress: 'Work In Progress',
    JobStatus.submitted: 'Work Submitted',
    JobStatus.completed: 'Completed',
  };

  static const _icons = {
    JobStatus.requested: Icons.post_add_rounded,
    JobStatus.matched: Icons.handshake_outlined,
    JobStatus.inChat: Icons.chat_bubble_outline_rounded,
    JobStatus.paymentPending: Icons.payment_outlined,
    JobStatus.escrowLocked: Icons.lock_outline_rounded,
    JobStatus.inProgress: Icons.construction_outlined,
    JobStatus.submitted: Icons.assignment_turned_in_outlined,
    JobStatus.completed: Icons.verified_rounded,
  };

  /// Uses available timestamps to determine how far the job actually progressed
  /// on the main path — handles branch states (disputed/cancelled) correctly.
  int _resolvedMainIndex() {
    if (job.completedAt != null) return 7;
    if (job.submittedAt != null) return 6;
    if (job.startedAt != null) return 5;
    if (job.escrowLockedAt != null) return 4;
    if (job.matchedAt != null) {
      // After matched: inChat or paymentPending may have been reached
      final onPath = _mainPath.indexOf(job.status);
      return onPath > 1 ? onPath : 2; // at least inChat
    }
    return 0;
  }

  DateTime? _timestampFor(JobStatus s) => switch (s) {
        JobStatus.requested => job.createdAt,
        JobStatus.matched => job.matchedAt,
        JobStatus.escrowLocked => job.escrowLockedAt,
        JobStatus.inProgress => job.startedAt,
        JobStatus.submitted => job.submittedAt,
        JobStatus.completed => job.completedAt,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final reachedIndex = _resolvedMainIndex();
    final isOnMainPath = _mainPath.contains(job.status);

    // How to interpret each main-path step:
    // - index <  reachedIndex → completed (past)
    // - index == reachedIndex && on main path → active
    // - index == reachedIndex && NOT on main path (branch) → completed (we passed it)
    // - index >  reachedIndex → pending (future)
    _StepState stateFor(int i) {
      if (i < reachedIndex) return _StepState.completed;
      if (i == reachedIndex) return isOnMainPath ? _StepState.active : _StepState.completed;
      return _StepState.pending;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROGRESS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary,
              letterSpacing: 0.8,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 14),

          // Main 8-step path
          ...List.generate(_mainPath.length, (i) {
            final s = _mainPath[i];
            final state = stateFor(i);
            final ts = _timestampFor(s);

            // Only draw connector line if not the last visible step
            final isLastMain = i == _mainPath.length - 1;
            final hasTerminalBelow = job.status == JobStatus.disputed ||
                job.status == JobStatus.resolved ||
                job.status == JobStatus.cancelled;
            final drawLine = !isLastMain || hasTerminalBelow;

            return _TimelineRow(
              icon: _icons[s]!,
              label: _labels[s]!,
              timestamp: ts,
              state: state,
              drawConnector: drawLine,
              suffix: s == JobStatus.submitted &&
                      job.autoReleaseAt != null &&
                      job.status == JobStatus.submitted
                  ? _AutoReleaseChip(releaseAt: job.autoReleaseAt!)
                  : null,
            );
          }),

          // Dispute branch
          if (job.status == JobStatus.disputed ||
              job.status == JobStatus.resolved) ...[
            _TimelineRow(
              icon: Icons.gavel_outlined,
              label: 'Dispute Raised',
              state: _StepState.active,
              drawConnector: job.status == JobStatus.resolved,
              color: context.colors.error,
            ),
            if (job.status == JobStatus.resolved)
              _TimelineRow(
                icon: Icons.balance_outlined,
                label: 'Dispute Resolved',
                state: _StepState.completed,
                drawConnector: false,
                color: context.colors.accent,
              ),
          ],

          // Cancelled terminal
          if (job.status == JobStatus.cancelled)
            _TimelineRow(
              icon: Icons.cancel_outlined,
              label: 'Job Cancelled',
              state: _StepState.active,
              drawConnector: false,
              color: context.colors.error,
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

enum _StepState { completed, active, pending }

class _TimelineRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final DateTime? timestamp;
  final _StepState state;
  final bool drawConnector;
  final Color? color;
  final Widget? suffix;

  const _TimelineRow({
    required this.icon,
    required this.label,
    required this.state,
    required this.drawConnector,
    this.timestamp,
    this.color,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        switch (state) {
          _StepState.completed => context.colors.accent,
          _StepState.active => context.colors.primary,
          _StepState.pending => context.colors.textTertiary,
        };

    final bgColor = switch (state) {
      _StepState.completed => context.colors.accent,
      _StepState.active => context.colors.primary,
      _StepState.pending => context.colors.surfaceVariant,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indicator column (circle + line)
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                    border: state == _StepState.pending
                        ? Border.all(color: context.colors.border)
                        : null,
                    boxShadow: state == _StepState.active
                        ? [
                            BoxShadow(
                              color: effectiveColor.withValues(alpha: 0.3),
                              blurRadius: 6,
                              spreadRadius: 1,
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    state == _StepState.completed
                        ? Icons.check_rounded
                        : icon,
                    size: 14,
                    color: state == _StepState.pending
                        ? context.colors.textTertiary
                        : Colors.white,
                  ),
                ),
                if (drawConnector)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: state == _StepState.completed
                          ? context.colors.accent.withValues(alpha: 0.4)
                          : context.colors.borderLight,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Content column
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: drawConnector ? 14 : 0,
                top: 4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: state == _StepState.active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: state == _StepState.pending
                                ? context.colors.textTertiary
                                : context.colors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                      if (timestamp != null)
                        Text(
                          _fmt(timestamp!),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textTertiary,
                            fontFamily: 'Inter',
                          ),
                        ),
                    ],
                  ),
                  if (suffix != null) ...[
                    const SizedBox(height: 4),
                    suffix!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) => DateFormat('d MMM, HH:mm').format(dt);
}

class _AutoReleaseChip extends StatelessWidget {
  final DateTime releaseAt;

  const _AutoReleaseChip({required this.releaseAt});

  @override
  Widget build(BuildContext context) {
    final remaining = releaseAt.difference(DateTime.now());
    final isOverdue = remaining.isNegative;

    final label = isOverdue
        ? 'Auto-release imminent'
        : _formatDuration(remaining);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOverdue
            ? context.colors.errorSurface
            : context.colors.warningSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOverdue
              ? context.colors.error.withValues(alpha: 0.3)
              : context.colors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 11,
            color: isOverdue ? context.colors.error : context.colors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isOverdue ? context.colors.error : context.colors.warning,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays >= 1) {
      final hours = d.inHours - d.inDays * 24;
      return 'Auto-release in ${d.inDays}d ${hours}h';
    }
    if (d.inHours >= 1) {
      return 'Auto-release in ${d.inHours}h ${d.inMinutes % 60}m';
    }
    return 'Auto-release in ${d.inMinutes}m';
  }
}
