import 'action_boundary.dart';

/// The single source of truth for what boundary every named action in
/// Atlas Operator belongs to. Nothing in the app should hardcode a
/// boundary inline — it looks it up here, so classification lives in
/// one place and can be reviewed on its own.
///
/// Right now every registered action is `read` because there is no
/// real backend (Phase 8) for the app to control anything with yet.
/// `controlled` and `highRisk` entries get added as Phase 8/9 wire up
/// real actions — do not add a highRisk action here without a
/// concrete, reviewed reason (see ADR-001: no phone button may ever
/// trigger terraform apply/destroy).
class ActionRegistry {
  static const Map<String, ActionBoundary> _actions = {
    'view_overview': ActionBoundary.read,
    'view_deployments': ActionBoundary.read,
    'view_workloads': ActionBoundary.read,
    'run_diagnostic_check': ActionBoundary.read,
  };

  static ActionBoundary boundaryFor(String actionId) {
    final boundary = _actions[actionId];
    if (boundary == null) {
      throw ArgumentError(
        'Unknown actionId "$actionId" — register it in ActionRegistry '
        'before using it, so its boundary is explicit and reviewable.',
      );
    }
    return boundary;
  }

  static bool isRegistered(String actionId) => _actions.containsKey(actionId);
}
