/// Action boundaries classify what a button/action is allowed to do to
/// real Atlas infrastructure. This is scaffolding only right now —
/// Atlas has zero auth today (verified fact), and the Operations API
/// that would let Atlas Operator DO anything to the live cluster does
/// not exist yet (Phase 8). No boundary here currently gates a real
/// infrastructure action.
enum ActionBoundary {
  /// Reads data only. Never changes Atlas's state. Safe to run anytime,
  /// offline or online, without confirmation.
  read,

  /// Would change something inside Atlas (e.g. trigger a diagnostic run
  /// against the live cluster, requeue a job) but does not touch
  /// infrastructure lifecycle. Requires explicit user confirmation once
  /// wired to a real backend.
  controlled,

  /// Would affect infrastructure lifecycle or cost (anything touching
  /// terraform apply/destroy, scaling the cluster). Per ADR-001 this
  /// app must NEVER expose a highRisk action that can actually execute
  /// — this boundary exists so any future action is forced to be
  /// explicitly classified and, if highRisk, blocked at the UI layer
  /// rather than silently allowed.
  highRisk,
}

extension ActionBoundaryLabel on ActionBoundary {
  String get label {
    switch (this) {
      case ActionBoundary.read:
        return 'Read';
      case ActionBoundary.controlled:
        return 'Controlled';
      case ActionBoundary.highRisk:
        return 'High risk';
    }
  }
}
