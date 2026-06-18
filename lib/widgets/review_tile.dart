import 'package:flutter/material.dart';
import '../models/review_model.dart';
import '../theme/app_theme.dart';
import 'star_rating.dart';

/// Read-only display of a single review. Reviewer identity is intentionally
/// not shown (reviews are tied to a verified booking, not a public profile).
class ReviewTile extends StatelessWidget {
  final ReviewModel review;
  final Widget? trailing;

  const ReviewTile({super.key, required this.review, this.trailing});

  @override
  Widget build(BuildContext context) {
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
            children: [
              StarRating(rating: review.rating.toDouble(), size: 14),
              const Spacer(),
              Text(
                _relativeDate(review.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                  fontFamily: 'Inter',
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _relativeDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    return 'Just now';
  }
}
