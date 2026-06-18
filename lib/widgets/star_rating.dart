import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StarRating extends StatelessWidget {
  final double rating;
  final int maxStars;
  final double size;
  final bool showValue;

  const StarRating({
    super.key,
    required this.rating,
    this.maxStars = 5,
    this.size = 16,
    this.showValue = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(maxStars, (i) {
          final filled = i < rating.floor();
          final half = !filled && i < rating;
          return Icon(
            half ? Icons.star_half_rounded : Icons.star_rounded,
            size: size,
            color: (filled || half) ? context.colors.ratingGold : context.colors.border,
          );
        }),
        if (showValue) ...[
          const SizedBox(width: 4),
          Text(
            rating == 0 ? 'New' : rating.toStringAsFixed(1),
            style: TextStyle(
              fontSize: size * 0.75,
              fontWeight: FontWeight.w600,
              color: rating == 0 ? context.colors.textTertiary : context.colors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ],
    );
  }
}

class InteractiveStarRating extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  const InteractiveStarRating({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < value;
        return GestureDetector(
          onTap: () => onChanged(i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              Icons.star_rounded,
              size: size,
              color: filled ? context.colors.ratingGold : context.colors.border,
            ),
          ),
        );
      }),
    );
  }
}
