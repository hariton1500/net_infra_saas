import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/map_tile_providers.dart';

class InfrastructureMapPage extends StatefulWidget {
  const InfrastructureMapPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<InfrastructureMapPage> createState() => _InfrastructureMapPageState();
}

enum _InfrastructureEntityType { muff, ponBox, cabinet }

class _InfrastructureEntity {
  const _InfrastructureEntity({
    required this.type,
    required this.id,
    required this.name,
    required this.location,
    required this.point,
    required this.subtitle,
    required this.meta,
  });

  final _InfrastructureEntityType type;
  final int id;
  final String name;
  final String location;
  final LatLng point;
  final String subtitle;
  final Map<String, String> meta;
}

class _InfrastructureMapPageState extends State<InfrastructureMapPage> {
  static const _muffsCacheKey = 'muff_notebook.muffs.v3';
  static const _cabinetsCacheKey = 'network_cabinet.cabinets.v1';

  final MapController _mapController = MapController();
  late final CompanyModuleSyncRepository _syncRepository;

  bool _loading = true;
  String? _errorMessage;
  double _mapZoom = 13;
  String _selectedTileLayerId = 'osm';
  List<_InfrastructureEntity> _entities = const [];

  @override
  void initState() {
    super.initState();
    _syncRepository = CompanyModuleSyncRepository(
      client: widget.controller.client,
    );
    _loadEntities();
  }

  Future<void> _loadEntities() async {
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
      var muffs = await _syncRepository.readCache(_muffsCacheKey);
      var cabinets = await _syncRepository.readCache(_cabinetsCacheKey);

      try {
        muffs = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: 'muff_notebook',
          localRecords: muffs,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Не удалось обновить муфты для карты.',
          source: 'infrastructure_map.muffs',
          error: error,
          stackTrace: stackTrace,
        );
      }

      try {
        cabinets = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: 'network_cabinet',
          localRecords: cabinets,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Не удалось обновить шкафы для карты.',
          source: 'infrastructure_map.cabinets',
          error: error,
          stackTrace: stackTrace,
        );
      }

      final nextEntities = <_InfrastructureEntity>[
        ..._muffEntities(muffs),
        ..._cabinetEntities(cabinets),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) {
        return;
      }

      setState(() {
        _entities = nextEntities;
        _loading = false;
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось загрузить сущности инфраструктуры.',
        source: 'infrastructure_map.load',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Не удалось загрузить карту инфраструктуры.';
      });
    }
  }

  List<_InfrastructureEntity> _muffEntities(
    List<Map<String, dynamic>> records,
  ) {
    return records
        .where((record) => record['deleted'] != true)
        .where(
          (record) =>
              record['location_lat'] is double &&
              record['location_lng'] is double,
        )
        .map((record) {
          final cables = List<Map<String, dynamic>>.from(
            record['cables'] ?? const [],
          );
          final connections = List<Map<String, dynamic>>.from(
            record['connections'] ?? const [],
          );
          final isPonBox = record['is_pon_box'] == true;
          final district = (record['district'] as String?)?.trim() ?? '';

          return _InfrastructureEntity(
            type: isPonBox
                ? _InfrastructureEntityType.ponBox
                : _InfrastructureEntityType.muff,
            id: (record['id'] as int?) ?? 0,
            name: (record['name'] as String?)?.trim().isNotEmpty == true
                ? (record['name'] as String).trim()
                : 'Без названия',
            location: (record['location'] as String?)?.trim() ?? '',
            point: LatLng(
              record['location_lat'] as double,
              record['location_lng'] as double,
            ),
            subtitle: isPonBox ? 'PON бокс' : 'Муфта',
            meta: {
              if (district.isNotEmpty) 'Район': district,
              'Кабели': '${cables.length}',
              'Соединения': '${connections.length}',
            },
          );
        })
        .toList(growable: false);
  }

  List<_InfrastructureEntity> _cabinetEntities(
    List<Map<String, dynamic>> records,
  ) {
    return records
        .where((record) => record['deleted'] != true)
        .where(
          (record) =>
              record['location_lat'] is double &&
              record['location_lng'] is double,
        )
        .map((record) {
          final switches = List<Map<String, dynamic>>.from(
            record['switches'] ?? const [],
          );
          final cables = List<Map<String, dynamic>>.from(
            record['cables'] ?? const [],
          );

          return _InfrastructureEntity(
            type: _InfrastructureEntityType.cabinet,
            id: (record['id'] as int?) ?? 0,
            name: (record['name'] as String?)?.trim().isNotEmpty == true
                ? (record['name'] as String).trim()
                : 'Без названия',
            location: (record['location'] as String?)?.trim() ?? '',
            point: LatLng(
              record['location_lat'] as double,
              record['location_lng'] as double,
            ),
            subtitle: 'Сетевой шкаф',
            meta: {
              'Коммутаторы': '${switches.length}',
              'Кабели': '${cables.length}',
            },
          );
        })
        .toList(growable: false);
  }

  void _showEntitySheet(_InfrastructureEntity entity) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _entityChip(entity),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entity.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (entity.location.isNotEmpty) Text(entity.location),
              const SizedBox(height: 6),
              Text(
                '${entity.point.latitude.toStringAsFixed(6)}, ${entity.point.longitude.toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              for (final entry in entity.meta.entries) ...[
                _MapMetaRow(label: entry.key, value: entry.value),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _entityColor(_InfrastructureEntityType type) {
    switch (type) {
      case _InfrastructureEntityType.ponBox:
        return const Color(0xFF29D39A);
      case _InfrastructureEntityType.cabinet:
        return const Color(0xFF60A5FA);
      case _InfrastructureEntityType.muff:
        return const Color(0xFFFF7A59);
    }
  }

  IconData _entityIcon(_InfrastructureEntityType type) {
    switch (type) {
      case _InfrastructureEntityType.ponBox:
        return Icons.hub_outlined;
      case _InfrastructureEntityType.cabinet:
        return Icons.dns_rounded;
      case _InfrastructureEntityType.muff:
        return Icons.scatter_plot_outlined;
    }
  }

  Widget _entityChip(_InfrastructureEntity entity) {
    final color = _entityColor(entity.type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_entityIcon(entity.type), size: 16, color: color),
          const SizedBox(width: 6),
          Text(entity.subtitle, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget _buildLegendCard() {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Сущности на карте',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LegendRow(
                    color: _entityColor(_InfrastructureEntityType.muff),
                    icon: _entityIcon(_InfrastructureEntityType.muff),
                    label: 'Муфты',
                  ),
                  const SizedBox(height: 8),
                  _LegendRow(
                    color: _entityColor(_InfrastructureEntityType.ponBox),
                    icon: _entityIcon(_InfrastructureEntityType.ponBox),
                    label: 'PON боксы',
                  ),
                  const SizedBox(height: 8),
                  _LegendRow(
                    color: _entityColor(_InfrastructureEntityType.cabinet),
                    icon: _entityIcon(_InfrastructureEntityType.cabinet),
                    label: 'Сетевые шкафы',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Всего точек: ${_entities.length}',
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

    if (_entities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'На карте пока нет сущностей с координатами. Добавьте геопозицию у муфт или шкафов.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final center = _entities.first.point;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _mapZoom,
            maxZoom: 19,
            onPositionChanged: (position, _) {
              _mapZoom = position.zoom;
            },
          ),
          children: [
            tileLayerById(_selectedTileLayerId),
            MarkerLayer(
              markers: _entities
                  .map((entity) {
                    final color = _entityColor(entity.type);
                    return Marker(
                      point: entity.point,
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showEntitySheet(entity),
                        child: Container(
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color.withValues(alpha: 0.6),
                              width: 2,
                            ),
                          ),
                          child: Icon(_entityIcon(entity.type), color: color),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        ),
        _buildLegendCard(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта инфраструктуры'),
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
            onPressed: _loading ? null : _loadEntities,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }
}

class _MapMetaRow extends StatelessWidget {
  const _MapMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}
