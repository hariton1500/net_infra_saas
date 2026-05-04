import 'package:net_infra_saas/src/core/app_i18n.dart';

const String employeePositionChiefEngineer = 'Chief Engineer';
const String employeePositionEngineer = 'Engineer';
const String employeePositionInstaller = 'Installer';

const Map<String, String> _employeePositionAliases = {
  'chief engineer': employeePositionChiefEngineer,
  'engineer': employeePositionEngineer,
  'installer': employeePositionInstaller,
  'главный инженер': employeePositionChiefEngineer,
  'инженер': employeePositionEngineer,
  'монтажник': employeePositionInstaller,
};

const List<String> employeePositions = [
  employeePositionChiefEngineer,
  employeePositionEngineer,
  employeePositionInstaller,
];

String employeePositionLabel(String position) {
  switch (normalizeEmployeePosition(position)) {
    case employeePositionChiefEngineer:
      return tr('Chief Engineer');
    case employeePositionEngineer:
      return tr('Engineer');
    case employeePositionInstaller:
      return tr('Installer');
    default:
      return position;
  }
}

String normalizeEmployeePosition(String position) {
  final normalized = position.trim();
  if (employeePositions.contains(normalized)) {
    return normalized;
  }

  return _employeePositionAliases[normalized.toLowerCase()] ?? normalized;
}

bool isSupportedEmployeePosition(String position) =>
    employeePositions.contains(normalizeEmployeePosition(position));

String? supportedEmployeePositionOrNull(String position) {
  final normalizedPosition = normalizeEmployeePosition(position);
  return employeePositions.contains(normalizedPosition)
      ? normalizedPosition
      : null;
}
