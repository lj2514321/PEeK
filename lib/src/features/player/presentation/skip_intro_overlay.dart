import 'dart:ui';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/material.dart';

class SkipIntroOverlay extends StatelessWidget {
  const SkipIntroOverlay({
    super.key,
    required this.label,
    required this.onSkip,
    this.countdownSeconds,
    this.onClose,
  });

  final String label;
  final VoidCallback onSkip;
  final int? countdownSeconds;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: AppGlass.visionOSDecoration(
          radius: 99,
          elevated: true,
          glowColor: const Color(0x404A90E2),
          borderOpacity: 0.35,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: InkWell(
              onTap: onSkip,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fast_forward_rounded,
                      color: AppColors.spotlight,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      countdownSeconds != null
                          ? '$label (${countdownSeconds}s)'
                          : label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (onClose != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: onClose,
                        borderRadius: BorderRadius.circular(99),
                        child: const Padding(
                          padding: EdgeInsets.all(2.0),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white60,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
