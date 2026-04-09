import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

typedef TileLayerFactory = TileLayer Function();

class MapTileOption {
  const MapTileOption({
    required this.id,
    required this.label,
    required this.buildLayer,
  });

  final String id;
  final String label;
  final TileLayerFactory buildLayer;
}

BaseClient _retryingClient() => RetryClient(Client());

TileLayer _openStreetMapLayer() {
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'net_infra_saas',
    tileProvider: NetworkTileProvider(httpClient: _retryingClient()),
  );
}

TileLayer _openTopoMapLayer() {
  return TileLayer(
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: const ['a', 'b', 'c'],
    userAgentPackageName: 'net_infra_saas',
    tileProvider: NetworkTileProvider(httpClient: _retryingClient()),
  );
}

TileLayer _yandexMapLayer() {
  return TileLayer(
    urlTemplate:
        'https://core-renderer-tiles.maps.yandex.net/tiles?l=map&x={x}&y={y}&z={z}&lang=ru_RU',
    subdomains: const ['01', '02', '03', '04'],
    tileProvider: NetworkTileProvider(httpClient: _retryingClient()),
  );
}

TileLayer _yandexSatelliteLayer() {
  return TileLayer(
    urlTemplate:
        'https://core-sat.maps.yandex.net/tiles?l=map&x={x}&y={y}&z={z}&lang=ru_RU',
    subdomains: const ['01', '02', '03', '04'],
    tileProvider: NetworkTileProvider(httpClient: _retryingClient()),
  );
}

final List<MapTileOption> mapTileOptions = [
  MapTileOption(
    id: 'osm',
    label: 'OpenStreetMap',
    buildLayer: _openStreetMapLayer,
  ),
  MapTileOption(
    id: 'topo',
    label: 'OpenTopoMap',
    buildLayer: _openTopoMapLayer,
  ),
  MapTileOption(
    id: 'yandex_map',
    label: 'Yandex Map',
    buildLayer: _yandexMapLayer,
  ),
  MapTileOption(
    id: 'yandex_sat',
    label: 'Yandex Satellite',
    buildLayer: _yandexSatelliteLayer,
  ),
];

TileLayer tileLayerById(String id) {
  for (final option in mapTileOptions) {
    if (option.id == id) {
      return option.buildLayer();
    }
  }

  return _openStreetMapLayer();
}
