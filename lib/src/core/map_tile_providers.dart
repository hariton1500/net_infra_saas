import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

import 'epsg3395.dart';

typedef TileLayerFactory = TileLayer Function();

class MapTileOption {
  const MapTileOption({
    required this.id,
    required this.label,
    required this.crs,
    required this.buildLayer,
  });

  final String id;
  final String label;
  final Crs crs;
  final TileLayerFactory buildLayer;
}

BaseClient _buildHttpClient() => RetryClient(Client());

TileLayer _openStreetMapLayer() {
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'net_infra_saas',
    tileProvider: NetworkTileProvider(httpClient: _buildHttpClient()),
  );
}

TileLayer _openTopoMapLayer() {
  return TileLayer(
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: const ['a', 'b', 'c'],
    userAgentPackageName: 'net_infra_saas',
    tileProvider: NetworkTileProvider(httpClient: _buildHttpClient()),
  );
}

TileLayer _yandexMapLayer() {
  return TileLayer(
    urlTemplate:
        'https://core-renderer-tiles.maps.yandex.net/tiles?l=map&x={x}&y={y}&z={z}&lang=ru_RU',
    subdomains: const ['01', '02', '03', '04'],
    tileProvider: NetworkTileProvider(httpClient: _buildHttpClient()),
  );
}

TileLayer _yandexSatelliteLayer() {
  return TileLayer(
    urlTemplate:
        'https://core-sat.maps.yandex.net/tiles?l=map&x={x}&y={y}&z={z}&lang=ru_RU',
    subdomains: const ['01', '02', '03', '04'],
    tileProvider: NetworkTileProvider(httpClient: _buildHttpClient()),
  );
}

final List<MapTileOption> mapTileOptions = [
  MapTileOption(
    id: 'osm',
    label: 'OpenStreetMap',
    crs: const Epsg3857(),
    buildLayer: _openStreetMapLayer,
  ),
  MapTileOption(
    id: 'topo',
    label: 'OpenTopoMap',
    crs: const Epsg3857(),
    buildLayer: _openTopoMapLayer,
  ),
  MapTileOption(
    id: 'yandex_map',
    label: 'Yandex Map',
    crs: const Epsg3395(),
    buildLayer: _yandexMapLayer,
  ),
  MapTileOption(
    id: 'yandex_sat',
    label: 'Yandex Satellite',
    crs: const Epsg3395(),
    buildLayer: _yandexSatelliteLayer,
  ),
];

MapTileOption _optionById(String id) {
  for (final option in mapTileOptions) {
    if (option.id == id) {
      return option;
    }
  }
  return mapTileOptions.first;
}

TileLayer tileLayerById(String id) => _optionById(id).buildLayer();

Crs mapCrsById(String id) => _optionById(id).crs;
