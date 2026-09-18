import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/core/security/action_boundary.dart';
import 'package:atlas_operator/core/security/action_registry.dart';

void main() {
  test('known actions resolve to read boundary today', () {
    expect(ActionRegistry.boundaryFor('view_overview'), ActionBoundary.read);
    expect(ActionRegistry.boundaryFor('run_diagnostic_check'), ActionBoundary.read);
  });

  test('unregistered action throws instead of silently defaulting', () {
    expect(
      () => ActionRegistry.boundaryFor('trigger_terraform_apply'),
      throwsArgumentError,
    );
  });

  test('isRegistered reflects the registry contents', () {
    expect(ActionRegistry.isRegistered('view_overview'), isTrue);
    expect(ActionRegistry.isRegistered('trigger_terraform_apply'), isFalse);
  });
}
