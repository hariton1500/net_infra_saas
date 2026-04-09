import 'package:geolocator/geolocator.dart';

Future<Position> determinePosition() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Службы геолокации отключены на устройстве.');
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied) {
    throw Exception('Доступ к геолокации отклонён пользователем.');
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception(
      'Доступ к геолокации навсегда запрещён. Разрешите его в настройках системы.',
    );
  }

  return Geolocator.getCurrentPosition();
}
