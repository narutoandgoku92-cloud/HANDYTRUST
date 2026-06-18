import 'audit_log_model.dart';
import '../core/errors/job_exceptions.dart';

/// Mandatory context carried by every [JobService] mutation.
///
/// Every state change in the system is attributed to an actor with a known
/// role and a declared intent (actionType). This makes every mutation
/// auditable, fraud-detectable, and override-safe.
///
/// Rules:
///   - [actorId] must be a real Firebase UID or 'system'.
///   - [isAdminOverride] requires [actorRole] == [ActorRole.admin].
///   - [overrideReason] is REQUIRED when [isAdminOverride] is true.
class JobMutationContext {
  final String actorId;
  final ActorRole actorRole;
  final JobActionType actionType;
  final String? reason;
  final bool isAdminOverride;
  final String? overrideReason;

  const JobMutationContext({
    required this.actorId,
    required this.actorRole,
    required this.actionType,
    this.reason,
    this.isAdminOverride = false,
    this.overrideReason,
  });

  /// Throws [JobStateConflictException] if this context does not carry valid
  /// admin override credentials. Called by [JobService.adminForceStatus].
  void assertAdminOverride() {
    if (!isAdminOverride) {
      throw const JobStateConflictException(
        'isAdminOverride must be true for admin override operations.',
      );
    }
    if (actorRole != ActorRole.admin) {
      throw const JobStateConflictException(
        'Admin override requires actorRole == ActorRole.admin.',
      );
    }
    if (overrideReason == null || overrideReason!.trim().isEmpty) {
      throw const JobStateConflictException(
        'overrideReason is required for admin override operations.',
      );
    }
  }

  /// Convenience factory for customer actions.
  factory JobMutationContext.customer({
    required String uid,
    required JobActionType actionType,
    String? reason,
  }) =>
      JobMutationContext(
        actorId: uid,
        actorRole: ActorRole.customer,
        actionType: actionType,
        reason: reason,
      );

  /// Convenience factory for artisan actions.
  factory JobMutationContext.artisan({
    required String uid,
    required JobActionType actionType,
    String? reason,
  }) =>
      JobMutationContext(
        actorId: uid,
        actorRole: ActorRole.artisan,
        actionType: actionType,
        reason: reason,
      );

  /// Convenience factory for admin actions, with optional override.
  factory JobMutationContext.admin({
    required String uid,
    required JobActionType actionType,
    String? reason,
    bool isOverride = false,
    String? overrideReason,
  }) =>
      JobMutationContext(
        actorId: uid,
        actorRole: ActorRole.admin,
        actionType: actionType,
        reason: reason,
        isAdminOverride: isOverride,
        overrideReason: overrideReason,
      );

  /// Convenience factory for system-initiated actions (webhooks, Cloud Functions).
  factory JobMutationContext.system(JobActionType actionType) =>
      JobMutationContext(
        actorId: 'system',
        actorRole: ActorRole.system,
        actionType: actionType,
      );
}
