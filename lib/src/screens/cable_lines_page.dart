import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/map_tile_providers.dart';

class CableLinesPage extends StatefulWidget {
  const CableLinesPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<CableLinesPage> createState() => _CableLinesPageState();
}

class _CableLineRoute {
  const _CableLineRoute({
    required this.id,
    required this.name,
    required this.points,
    required this.meta,
  });

  final int id;
  final String name;
  final List<LatLng> points;
  final Map<String, String> meta;
}

class _CableLinesPageState extends State<CableLinesPage> {
  static const String _moduleKey = 'cable_lines';
  static const String _cacheKey = 'cable_lines.routes.v1';

  final MapController _mapController = MapController();
  late final CompanyModuleSyncRepository _syncRepository;

  bool _loading = true;
  String? _errorMessage;
  double _mapZoom = 13;
  String _selectedTileLayerId = 'osm';
  List<_CableLineRoute> _routes = const [];
  int? _selectedRouteId;

  @override
  void initState() {
    super.initState();
    _syncRepository = CompanyModuleSyncRepository(
      client: widget.controller.client,
    );
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    final companyId = widget.controller.membership?.companyId;
    if (companyId == null) {
      setState(() {
        _loading = false;
        _errorMessage = 'Компания не найдена для текущего пользователя.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      var records = await _syncRepository.readCache(_cacheKey);

      try {
        records = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: _moduleKey,
          localRecords: records,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Не удалось обновить кабельные линии из Supabase.',
          source: 'cable_lines.pull_merge',
          error: error,
          stackTrace: stackTrace,
        );
      }

      final nextRoutes = records
          .where((record) => record['deleted'] != true)
          .map(_routeFromRecord)
          .whereType<_CableLineRoute>()
          .toList(growable: false)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) {
        return;
      }

      setState(() {
        _routes = nextRoutes;
        _selectedRouteId = nextRoutes.isEmpty ? null : nextRoutes.first.id;
        _loading = false;
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось загрузить кабельные линии.',
        source: 'cable_lines.load',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Не удалось открыть раздел кабельных линий.';
      });
    }
  }

  _CableLineRoute? _routeFromRecord(Map<String, dynamic> record) {
    final points = _extractRoutePoints(record);
    if (points.length < 2) {
      return null;
    }

    final name = (record['name'] as String?)?.trim();
    final status = (record['status'] as String?)?.trim();
    final cableType = (record['cable_type'] as String?)?.trim();
    final note = (record['note'] as String?)?.trim();

    return _CableLineRoute(
      id: (record['id'] as int?) ?? 0,
      name: name?.isNotEmpty == true ? name! : 'Кабельная линия',
      points: points,
      meta: {
        'Точек маршрута': '${points.length}',
        if (status != null && status.isNotEmpty) 'Статус': status,
        if (cableType != null && cableType.isNotEmpty) 'Тип': cableType,
        if (note != null && note.isNotEmpty) 'Примечание': note,
      },
    );
  }

  List<LatLng> _extractRoutePoints(Map<String, dynamic> record) {
    final rawPoints =
        record['route_points'] ??
        record['points'] ??
        record['coordinates'] ??
        record['route'] ??
        record['path'];

    if (rawPoints is! List) {
      return const [];
    }

    final points = <LatLng>[];
    for (final item in rawPoints) {
      if (item is! Map) {
        continue;
      }

      final rawLat = item['lat'] ?? item['latitude'];
      final rawLng = item['lng'] ?? item['lon'] ?? item['longitude'];
      final lat = _asDouble(rawLat);
      final lng = _asDouble(rawLng);
      if (lat == null || lng == null) {
        continue;
      }

      points.add(LatLng(lat, lng));
    }

    return points;
  }

  double? _asDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  _CableLineRoute? get _selectedRoute {
    if (_selectedRouteId == null) {
      return null;
    }

    for (final route in _routes) {
      if (route.id == _selectedRouteId) {
        return route;
      }
    }

    return null;
  }

  void _selectRoute(_CableLineRoute route) {
    setState(() {
      _selectedRouteId = route.id;
    });
    _mapController.move(route.points.first, _mapZoom < 15 ? 15 : _mapZoom);
  }

  Color _routeColor(_CableLineRoute route) {
    if (route.id == _selectedRouteId) {
      return const Color(0xFF1EDDC5);
    }

    return const Color(0xFF60A5FA);
  }

  Widget _buildLegendCard() {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Кабельные линии',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _LegendLineRow(
                    color: Color(0xFF1EDDC5),
                    label: 'Выбранная линия',
                  ),
                  const SizedBox(height: 8),
                  const _LegendLineRow(
                    color: Color(0xFF60A5FA),
                    label: 'Остальные маршруты',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Всего линий: ${_routes.length}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final initialPoint = _selectedRoute?.points.first ?? _routes.first.points.first;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialPoint,
            initialZoom: _mapZoom,
            maxZoom: 19,
            onPositionChanged: (position, _) {
              _mapZoom = position.zoom;
            },
          ),
          children: [
            tileLayerById(_selectedTileLayerId),
            PolylineLayer(
              polylines: _routes
                  .map(
                    (route) => Polyline(
                      points: route.points,
                      strokeWidth: route.id == _selectedRouteId ? 5 : 3,
                      color: _routeColor(route).withValues(
                        alpha: route.id == _selectedRouteId ? 0.95 : 0.72,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            MarkerLayer(
              markers: _routes
                  .expand((route) {
                    final color = _routeColor(route);
                    final first = route.points.first;
                    final last = route.points.last;
                    return [
                      Marker(
                        point: first,
                        width: 20,
                        height: 20,
                        child: _RouteEndpointMarker(color: color, filled: true),
                      ),
                      Marker(
                        point: last,
                        width: 20,
                        height: 20,
                        child: _RouteEndpointMarker(
                          color: color,
                          filled: false,
                        ),
                      ),
                    ];
                  })
                  .toList(growable: false),
            ),
          ],
        ),
        _buildLegendCard(),
      ],
    );
  }

  Widget _buildRouteList() {
    final selectedRoute = _selectedRoute;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF071526),
        border: Border(top: BorderSide(color: Color(0xFF1D3F63))),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        scrollDirection: Axis.horizontal,
        itemCount: _routes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final route = _routes[index];
          final isSelected = route.id == selectedRoute?.id;
          final color = _routeColor(route);

          return SizedBox(
            width: 280,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _selectRoute(route),
              child: Ink(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isSelected ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: color.withValues(alpha: isSelected ? 0.55 : 0.24),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timeline_rounded, color: color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              route.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final entry in route.meta.entries.take(3)) ...[
                        _CableLineMetaRow(
                          label: entry.key,
                          value: entry.value,
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_errorMessage!),
        ),
      );
    }

    if (_routes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              'Маршруты пока не найдены. Для отображения линий добавьте записи в модуль '
              '`cable_lines` с массивом координат в одном из полей: `route_points`, `points`, `coordinates`, `route` или `path`.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: _buildMap()),
        SizedBox(height: 172, child: _buildRouteList()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кабельные линии'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Слой карты',
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
            tooltip: 'Обновить',
            onPressed: _loading ? null : _loadRoutes,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class _LegendLineRow extends StatelessWidget {
  const _LegendLineRow({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }
}

class _RouteEndpointMarker extends StatelessWidget {
  const _RouteEndpointMarker({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: filled ? color : const Color(0xFF071526),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}

class _CableLineMetaRow extends StatelessWidget {
  const _CableLineMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}
