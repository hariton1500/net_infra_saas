import 'package:flutter_test/flutter_test.dart';
import 'package:net_infra_saas/src/core/employee_positions.dart';
import 'package:net_infra_saas/src/core/project_scope.dart';

void main() {
  group('employee position normalization', () {
    test('accepts localized Russian positions saved in profiles', () {
      expect(
        normalizeEmployeePosition('Главный инженер'),
        employeePositionChiefEngineer,
      );
      expect(normalizeEmployeePosition('Инженер'), employeePositionEngineer);
      expect(normalizeEmployeePosition('Монтажник'), employeePositionInstaller);
    });

    test(
      'keeps task creation permissions for localized engineer positions',
      () {
        expect(canCreateProjectsForPosition('Главный инженер'), isTrue);
        expect(canCreateProjectsForPosition('Инженер'), isTrue);
        expect(canCreateProjectsForPosition('Монтажник'), isFalse);
      },
    );
  });
}
