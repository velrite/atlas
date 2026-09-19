import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/configuration/environment.dart';

/// Tappable environment badge. Per ADR-001 / build rule 8, the current
/// mode must always be visible in UI chrome -- this widget already did
/// that. What it never did is let the user actually SWITCH modes; that
/// control never existed anywhere in the app. This adds it as a tap
/// gesture on the same badge, cycling OFFLINE -> INTEGRATION -> LIVE ->
/// OFFLINE, so there's no new widget, no new screen -- just the one
/// missing piece of wiring on an existing element.
class EnvironmentBadge extends ConsumerWidget {
  const EnvironmentBadge({super.key});

  Environment _next(Environment current) => switch (current) {
        Environment.offline => Environment.integration,
        Environment.integration => Environment.live,
        Environment.live => Environment.offline,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(environmentProvider);
    final color = switch (env) {
      Environment.offline => Colors.grey,
      Environment.integration => Colors.amber,
      Environment.live => Colors.green,
    };

    return GestureDetector(
      onTap: () => ref.read(environmentProvider.notifier).setEnvironment(_next(env)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          env.label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );
  }
}
