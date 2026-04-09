import 'package:flutter_map/flutter_map.dart';

final TileLayer openStreetMapTileLayer = TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'net_infra_saas',
);

final TileLayer openTopoMapTileLayer = TileLayer(
  urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
  subdomains: const ['a', 'b', 'c'],
  userAgentPackageName: 'net_infra_saas',
);
