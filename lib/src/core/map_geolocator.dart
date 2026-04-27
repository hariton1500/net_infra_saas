import 'package:geolocator/geolocator.dart';

Future<Position> determinePosition() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Location services are disabled on the device.');
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied) {
    throw Exception('Location access was denied by the user.');
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception(
      'Location access is permanently denied. Enable it in system settings.',
    );
  }

  return Geolocator.getCurrentPosition();
}
