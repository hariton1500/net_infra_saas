const String employeePositionChiefEngineer = 'Главный инженер';
const String employeePositionEngineer = 'Инженер';
const String employeePositionInstaller = 'Монтажник';

const Map<String, String> _employeePositionAliases = {
  'chief engineer': employeePositionChiefEngineer,
  'engineer': employeePositionEngineer,
  'installer': employeePositionInstaller,
};

const List<String> employeePositions = [
  employeePositionChiefEngineer,
  employeePositionEngineer,
  employeePositionInstaller,
];

String employeePositionLabel(String position) {
  switch (normalizeEmployeePosition(position)) {
    case employeePositionChiefEngineer:
      return 'Chief Engineer';
    case employeePositionEngineer:
      return 'Engineer';
    case employeePositionInstaller:
      return 'Installer';
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
