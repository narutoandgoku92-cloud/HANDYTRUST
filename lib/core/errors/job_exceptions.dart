import '../../models/job_model.dart';

/// Base type for all job lifecycle errors.
/// Use typed subclasses for error handling in UI and providers.
sealed class JobException implements Exception {
  final String message;
  const JobException(this.message);

  @override
  String toString() => message;
}

/// The requested job document does not exist in Firestore.
final class JobNotFoundException extends JobException {
  final String jobId;
  JobNotFoundException(this.jobId) : super('Job not found: $jobId');
}

/// A state transition was attempted that is not permitted by the state machine.
/// Check [JobService.allowedTransitions] for the valid set from [from].
final class InvalidJobTransitionException extends JobException {
  final JobStatus from;
  final JobStatus to;

  InvalidJobTransitionException({required this.from, required this.to})
      : super('Invalid job transition: ${from.name} → ${to.name}');
}

/// The job is in the correct status but another field constraint prevents the
/// write — e.g. a negotiation message outside of inChat status.
final class JobStateConflictException extends JobException {
  const JobStateConflictException(super.message);
}
