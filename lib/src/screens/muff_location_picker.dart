import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_logger.dart';
import '../core/map_geolocator.dart';
import '../core/map_tile_providers.dart';

class MuffLocationPickerPage extends StatefulWidget {
  const MuffLocationPickerPage({super.key, this.initial});

  final LatLng? initial;

  @override
  State<MuffLocationPickerPage> createState() => _MuffLocationPickerPageState();
}

class _MuffLocationPickerPageState extends State<MuffLocationPickerPage> {
  final MapController _mapController = MapController();
  LatLng? _selected;
  double _zoom = 16;
  String _selectedTileLayerId = 'osm';

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected ?? const LatLng(44.9521, 34.1024);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбор геопозиции муфты'),
        actions: [
          IconButton(
            tooltip: 'Моё местоположение',
            onPressed: _goToCurrentLocation,
            icon: const Icon(Icons.my_location_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Выбрать слой карты',
            initialValue: _selectedTileLayerId,
            onSelected: (value) {
              setState(() {
                _selectedTileLayerId = value;
              });
            },
            icon: const Icon(Icons.layers_outlined),
            itemBuilder: (context) => mapTileOptions
                .map(
                  (option) => CheckedPopupMenuItem<String>(
                    value: option.id,
                    checked: option.id == _selectedTileLayerId,
                    child: Text(option.label),
                  ),
                )
                .toList(growable: false),
          ),
          IconButton(
            tooltip: 'Сохранить точку',
            onPressed: _selected == null
                ? null
                : () => Navigator.of(context).pop(_selected),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _zoom,
              maxZoom: 19,
              minZoom: 3,
              onTap: (_, point) {
                setState(() {
                  _selected = point;
                });
              },
              onPositionChanged: (position, _) {
                _zoom = position.zoom;
              },
            ),
            children: [
              tileLayerById(_selectedTileLayerId),
              if (_selected != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.place_rounded,
                        color: Colors.redAccent,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выбранная точка',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selected == null
                          ? 'Коснитесь карты, чтобы выбрать координаты.'
                          : 'lat: ${_selected!.latitude.toStringAsFixed(6)}, '
                                'lng: ${_selected!.longitude.toStringAsFixed(6)}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _goToCurrentLocation() async {
    try {
      final position = await determinePosition();
      final point = LatLng(position.latitude, position.longitude);
      _mapController.move(point, _zoom);
      setState(() {
        _selected = point;
      });
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }

      final message = 'Не удалось определить позицию: $error';
      logUserFacingError(
        message,
        source: 'muff.location_picker',
        error: error,
        stackTrace: stackTrace,
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
