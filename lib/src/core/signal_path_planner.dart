import 'app_i18n.dart';

class SignalPortRef {
  const SignalPortRef({
    required this.cabinetId,
    required this.switchId,
    required this.portIndex,
  });

  final int cabinetId;
  final int switchId;
  final int portIndex;
}

class SignalPathPlan {
  const SignalPathPlan({
    required this.sourceLabel,
    required this.targetLabel,
    required this.steps,
    required this.actions,
    required this.blockers,
  });

  final String sourceLabel;
  final String targetLabel;
  final List<String> steps;
  final List<String> actions;
  final List<String> blockers;

  bool get isBuildable => blockers.isEmpty && actions.isNotEmpty;
}

class _SignalEntityRef {
  const _SignalEntityRef(this.type, this.id);

  final String type;
  final int id;

  String get key => '$type:$id';
}

class _SignalRouteEdge {
  const _SignalRouteEdge({
    required this.from,
    required this.to,
    required this.fromCableId,
    required this.fromCableName,
    required this.toCableId,
    required this.toCableName,
    required this.routeId,
  });

  final _SignalEntityRef from;
  final _SignalEntityRef to;
  final int fromCableId;
  final String fromCableName;
  final int toCableId;
  final String toCableName;
  final int routeId;
}

class _SignalPathNode {
  const _SignalPathNode({required this.entity, required this.edges});

  final _SignalEntityRef entity;
  final List<_SignalRouteEdge> edges;
}

class _SignalFiberEndpoint {
  const _SignalFiberEndpoint({
    required this.entity,
    required this.cableId,
    required this.fiberIndex,
  });

  final _SignalEntityRef entity;
  final int cableId;
  final int fiberIndex;

  String get key => '${entity.key}:fiber:$cableId:$fiberIndex';
}

class SignalPathPlanner {
  SignalPathPlanner({
    required List<Map<String, dynamic>> muffs,
    required List<Map<String, dynamic>> cabinets,
  }) : _records = _buildRecords(muffs: muffs, cabinets: cabinets);

  final Map<String, Map<String, dynamic>> _records;

  SignalPathPlan buildPlan({
    required SignalPortRef source,
    required int targetMuffId,
    String targetEntityType = 'muff',
  }) {
    final sourceEntity = _SignalEntityRef('cabinet', source.cabinetId);
    final targetEntity = _SignalEntityRef(targetEntityType, targetMuffId);
    final sourceRecord = _records[sourceEntity.key];
    final targetRecord = _records[targetEntity.key];
    final sourceLabel = _sourcePortLabel(sourceRecord, source);
    final targetLabel = _entityName(targetRecord, fallback: 'Closure');

    if (sourceRecord == null) {
      return SignalPathPlan(
        sourceLabel: sourceLabel,
        targetLabel: targetLabel,
        steps: const [],
        actions: const [],
        blockers: const ['Source cabinet was not found.'],
      );
    }
    if (targetRecord == null) {
      return SignalPathPlan(
        sourceLabel: sourceLabel,
        targetLabel: targetLabel,
        steps: const [],
        actions: const [],
        blockers: const ['Target closure was not found.'],
      );
    }
    if (_isCopperPort(sourceRecord, source.switchId, source.portIndex)) {
      return SignalPathPlan(
        sourceLabel: sourceLabel,
        targetLabel: targetLabel,
        steps: const [],
        actions: const [],
        blockers: [tr('Copper ports cannot feed optical cable fibers.')],
      );
    }

    final path = _findEntityPath(sourceEntity, targetEntity);
    if (path == null) {
      return SignalPathPlan(
        sourceLabel: sourceLabel,
        targetLabel: targetLabel,
        steps: const [],
        actions: const [],
        blockers: [tr('No cable route chain reaches this closure.')],
      );
    }

    final actions = <String>[];
    final steps = <String>[
      tr('Source: {value}', {'value': sourceLabel}),
    ];
    var previousCableId = 0;
    var previousFiberIndex = 0;
    var previousCableName = '';

    final connectedSource = _connectedCableFiberForPort(
      sourceRecord,
      source.switchId,
      source.portIndex,
    );
    if (path.edges.isEmpty) {
      return SignalPathPlan(
        sourceLabel: sourceLabel,
        targetLabel: targetLabel,
        steps: steps,
        actions: const [],
        blockers: [tr('The selected closure is the source cabinet object.')],
      );
    }

    for (var index = 0; index < path.edges.length; index++) {
      final edge = path.edges[index];
      final fromRecord = _records[edge.from.key];
      final toRecord = _records[edge.to.key];
      if (fromRecord == null || toRecord == null) {
        return _blocked(sourceLabel, targetLabel, steps, actions, [
          tr('A route endpoint record is missing.'),
        ]);
      }

      final fiberIndex = index == 0 && connectedSource != null
          ? connectedSource.fiberIndex
          : _firstAvailableRouteFiber(edge, allowedPort: source);
      if (fiberIndex == null) {
        return _blocked(sourceLabel, targetLabel, steps, actions, [
          tr('No usable fiber without another port signal on {from} -> {to}.', {
            'from': edge.fromCableName,
            'to': edge.toCableName,
          }),
        ]);
      }

      if (index == 0) {
        if (connectedSource == null) {
          if (!_canUseCableFiberForSignal(
            edge.from,
            fromRecord,
            edge.fromCableId,
            fiberIndex,
            allowedPort: source,
          )) {
            return _blocked(sourceLabel, targetLabel, steps, actions, [
              tr(
                '{cable}, fiber {fiber}: already carries another port signal.',
                {'cable': edge.fromCableName, 'fiber': '${fiberIndex + 1}'},
              ),
            ]);
          }
          actions.add(
            tr('{object}: connect {source} to {cable}, fiber {fiber}.', {
              'object': _entityName(fromRecord),
              'source': sourceLabel,
              'cable': edge.fromCableName,
              'fiber': '${fiberIndex + 1}',
            }),
          );
        } else if (connectedSource.cableId != edge.fromCableId) {
          return _blocked(sourceLabel, targetLabel, steps, actions, [
            tr('The selected port is already connected to another cable.'),
          ]);
        } else {
          steps.add(
            tr(
              '{object}: port is already connected to {cable}, fiber {fiber}.',
              {
                'object': _entityName(fromRecord),
                'cable': edge.fromCableName,
                'fiber': '${fiberIndex + 1}',
              },
            ),
          );
        }
      } else {
        final alreadyConnected = _hasCableFiberConnection(
          fromRecord,
          previousCableId,
          previousFiberIndex,
          edge.fromCableId,
          fiberIndex,
        );
        if (alreadyConnected) {
          steps.add(
            tr(
              '{object}: already spliced: {leftCable}, fiber {leftFiber} -> {rightCable}, fiber {rightFiber}.',
              {
                'object': _entityName(fromRecord),
                'leftCable': previousCableName,
                'leftFiber': '${previousFiberIndex + 1}',
                'rightCable': edge.fromCableName,
                'rightFiber': '${fiberIndex + 1}',
              },
            ),
          );
        } else {
          if (!_canUseCableFiberForSignal(
            edge.from,
            fromRecord,
            edge.fromCableId,
            fiberIndex,
            allowedPort: source,
          )) {
            return _blocked(sourceLabel, targetLabel, steps, actions, [
              tr(
                '{cable}, fiber {fiber}: already carries another port signal in {object}.',
                {
                  'cable': edge.fromCableName,
                  'fiber': '${fiberIndex + 1}',
                  'object': _entityName(fromRecord),
                },
              ),
            ]);
          }
          actions.add(
            tr(
              '{object}: connect {leftCable}, fiber {leftFiber} to {rightCable}, fiber {rightFiber}.',
              {
                'object': _entityName(fromRecord),
                'leftCable': previousCableName,
                'leftFiber': '${previousFiberIndex + 1}',
                'rightCable': edge.fromCableName,
                'rightFiber': '${fiberIndex + 1}',
              },
            ),
          );
        }
      }

      steps.add(
        tr(
          'Route {route}: {fromCable}, fiber {fromFiber} -> {toCable}, fiber {toFiber}.',
          {
            'route': '${edge.routeId}',
            'fromCable': edge.fromCableName,
            'fromFiber': '${fiberIndex + 1}',
            'toCable': edge.toCableName,
            'toFiber': '${fiberIndex + 1}',
          },
        ),
      );
      previousCableId = edge.toCableId;
      previousCableName = edge.toCableName;
      previousFiberIndex = fiberIndex;

      if (index == path.edges.length - 1) {
        steps.add(
          tr('{object}: signal arrives on {cable}, fiber {fiber}.', {
            'object': _entityName(toRecord),
            'cable': edge.toCableName,
            'fiber': '${fiberIndex + 1}',
          }),
        );
      }
    }

    return SignalPathPlan(
      sourceLabel: sourceLabel,
      targetLabel: targetLabel,
      steps: steps,
      actions: actions,
      blockers: const [],
    );
  }

  SignalPathPlan _blocked(
    String sourceLabel,
    String targetLabel,
    List<String> steps,
    List<String> actions,
    List<String> blockers,
  ) {
    return SignalPathPlan(
      sourceLabel: sourceLabel,
      targetLabel: targetLabel,
      steps: List.unmodifiable(steps),
      actions: List.unmodifiable(actions),
      blockers: List.unmodifiable(blockers),
    );
  }

  _SignalPathNode? _findEntityPath(
    _SignalEntityRef source,
    _SignalEntityRef target,
  ) {
    final queue = <_SignalPathNode>[
      _SignalPathNode(entity: source, edges: const []),
    ];
    final visited = <String>{};

    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      if (!visited.add(node.entity.key)) {
        continue;
      }
      if (node.entity.key == target.key) {
        return node;
      }
      for (final edge in _edgesFrom(node.entity)) {
        if (!visited.contains(edge.to.key)) {
          queue.add(
            _SignalPathNode(entity: edge.to, edges: [...node.edges, edge]),
          );
        }
      }
    }
    return null;
  }

  Iterable<_SignalRouteEdge> _edgesFrom(_SignalEntityRef entity) sync* {
    final record = _records[entity.key];
    if (record == null) {
      return;
    }
    for (final cable in _cablesOf(record)) {
      final routeId = _asInt(cable['route_id']);
      final peerType = cable['peer_entity_type']?.toString().trim();
      final peerId = _asInt(cable['peer_entity_id']);
      final peerCableId = _asInt(cable['peer_cable_id']);
      if (routeId == null ||
          peerType == null ||
          peerType.isEmpty ||
          peerId == null ||
          peerCableId == null) {
        continue;
      }
      final peer = _SignalEntityRef(peerType, peerId);
      if (!_records.containsKey(peer.key)) {
        continue;
      }
      yield _SignalRouteEdge(
        from: entity,
        to: peer,
        fromCableId: _asInt(cable['id']) ?? 0,
        fromCableName: _nameOf(cable, fallback: 'Cable'),
        toCableId: peerCableId,
        toCableName:
            cable['peer_cable_name']?.toString().trim().isNotEmpty == true
            ? cable['peer_cable_name'].toString().trim()
            : 'Cable',
        routeId: routeId,
      );
    }
  }

  int? _firstAvailableRouteFiber(
    _SignalRouteEdge edge, {
    SignalPortRef? allowedPort,
  }) {
    final fromRecord = _records[edge.from.key];
    final toRecord = _records[edge.to.key];
    if (fromRecord == null || toRecord == null) {
      return null;
    }
    final fromCable = _cableById(fromRecord, edge.fromCableId);
    final toCable = _cableById(toRecord, edge.toCableId);
    final fibers = [
      _asInt(fromCable?['fibers']) ?? 1,
      _asInt(toCable?['fibers']) ?? 1,
    ].reduce((a, b) => a < b ? a : b);
    for (var index = 0; index < fibers; index++) {
      if (_canUseCableFiberForSignal(
            edge.from,
            fromRecord,
            edge.fromCableId,
            index,
            allowedPort: allowedPort,
          ) &&
          _canUseCableFiberForSignal(
            edge.to,
            toRecord,
            edge.toCableId,
            index,
            allowedPort: allowedPort,
          )) {
        return index;
      }
    }
    return null;
  }

  _CableFiber? _connectedCableFiberForPort(
    Map<String, dynamic> cabinet,
    int switchId,
    int portIndex,
  ) {
    for (final connection in _connectionsOf(cabinet)) {
      final firstPort = _portEndpointOf(
        connection,
        true,
      )?.matches(switchId, portIndex);
      final secondPort = _portEndpointOf(
        connection,
        false,
      )?.matches(switchId, portIndex);
      if (firstPort == true) {
        return _fiberEndpointOf(connection, false);
      }
      if (secondPort == true) {
        return _fiberEndpointOf(connection, true);
      }
    }
    return null;
  }

  bool _hasCableFiberConnection(
    Map<String, dynamic> record,
    int leftCableId,
    int leftFiberIndex,
    int rightCableId,
    int rightFiberIndex,
  ) {
    return _connectionsOf(record).any((connection) {
      final left = _fiberEndpointOf(connection, true);
      final right = _fiberEndpointOf(connection, false);
      return (left?.matches(leftCableId, leftFiberIndex) == true &&
              right?.matches(rightCableId, rightFiberIndex) == true) ||
          (left?.matches(rightCableId, rightFiberIndex) == true &&
              right?.matches(leftCableId, leftFiberIndex) == true);
    });
  }

  bool _canUseCableFiberForSignal(
    _SignalEntityRef entity,
    Map<String, dynamic> record,
    int cableId,
    int fiberIndex, {
    SignalPortRef? allowedPort,
  }) {
    return !_fiberChainReachesPort(
      _SignalFiberEndpoint(
        entity: entity,
        cableId: cableId,
        fiberIndex: fiberIndex,
      ),
      allowedPort: allowedPort,
    );
  }

  bool _fiberChainReachesPort(
    _SignalFiberEndpoint start, {
    SignalPortRef? allowedPort,
  }) {
    final queue = <_SignalFiberEndpoint>[start];
    final visited = <String>{};

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!visited.add(current.key)) {
        continue;
      }
      final record = _records[current.entity.key];
      if (record == null) {
        continue;
      }

      for (final connection in _connectionsOf(record)) {
        final leftFiber = _fiberEndpointOf(connection, true);
        final rightFiber = _fiberEndpointOf(connection, false);
        if (leftFiber?.matches(current.cableId, current.fiberIndex) == true) {
          final rightPort = _portEndpointOf(connection, false);
          if (rightPort != null &&
              !_isAllowedPortSignal(current.entity, rightPort, allowedPort)) {
            return true;
          }
          if (rightFiber != null) {
            queue.add(
              _SignalFiberEndpoint(
                entity: current.entity,
                cableId: rightFiber.cableId,
                fiberIndex: rightFiber.fiberIndex,
              ),
            );
          }
        }
        if (rightFiber?.matches(current.cableId, current.fiberIndex) == true) {
          final leftPort = _portEndpointOf(connection, true);
          if (leftPort != null &&
              !_isAllowedPortSignal(current.entity, leftPort, allowedPort)) {
            return true;
          }
          if (leftFiber != null) {
            queue.add(
              _SignalFiberEndpoint(
                entity: current.entity,
                cableId: leftFiber.cableId,
                fiberIndex: leftFiber.fiberIndex,
              ),
            );
          }
        }
      }

      final cable = _cableById(record, current.cableId);
      final peerType = cable?['peer_entity_type']?.toString().trim();
      final peerId = _asInt(cable?['peer_entity_id']);
      final peerCableId = _asInt(cable?['peer_cable_id']);
      if (peerType != null &&
          peerType.isNotEmpty &&
          peerId != null &&
          peerCableId != null) {
        final peer = _SignalEntityRef(peerType, peerId);
        if (_records.containsKey(peer.key)) {
          queue.add(
            _SignalFiberEndpoint(
              entity: peer,
              cableId: peerCableId,
              fiberIndex: current.fiberIndex,
            ),
          );
        }
      }
    }

    return false;
  }

  bool _isAllowedPortSignal(
    _SignalEntityRef entity,
    _PortEndpoint port,
    SignalPortRef? allowedPort,
  ) {
    return allowedPort != null &&
        entity.type == 'cabinet' &&
        entity.id == allowedPort.cabinetId &&
        port.switchId == allowedPort.switchId &&
        port.portIndex == allowedPort.portIndex;
  }

  _PortEndpoint? _portEndpointOf(Map<String, dynamic> connection, bool first) {
    final endpoint = connection[first ? 'endpoint1' : 'endpoint2'];
    if (endpoint is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(endpoint);
    final switchId = _asInt(map['switchId']);
    final portIndex = _asInt(map['portIndex']);
    if (switchId != null && portIndex != null) {
      return _PortEndpoint(switchId, portIndex);
    }
    return null;
  }

  _CableFiber? _fiberEndpointOf(Map<String, dynamic> connection, bool first) {
    final endpoint = connection[first ? 'endpoint1' : 'endpoint2'];
    if (endpoint is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(endpoint);
    final cableId = _asInt(map['cableId']);
    final fiberIndex = _asInt(map['fiberIndex']);
    if (cableId != null && fiberIndex != null) {
      return _CableFiber(cableId, fiberIndex);
    }
    return null;
  }

  bool _isCopperPort(
    Map<String, dynamic> cabinet,
    int switchId,
    int portIndex,
  ) {
    final sw = _switchById(cabinet, switchId);
    if (sw == null) {
      return false;
    }
    final portTypes = List<String>.from(sw['port_types'] ?? const []);
    if (portIndex < 0 || portIndex >= portTypes.length) {
      return false;
    }
    return portTypes[portIndex] == 'copper';
  }

  String _sourcePortLabel(Map<String, dynamic>? cabinet, SignalPortRef source) {
    final sw = cabinet == null ? null : _switchById(cabinet, source.switchId);
    final cabinetName = _entityName(cabinet, fallback: 'Cabinet');
    final switchName = _nameOf(sw, fallback: 'Switch');
    return '$cabinetName / $switchName / ${tr('port {value}', {'value': '${source.portIndex + 1}'})}';
  }

  static Map<String, Map<String, dynamic>> _buildRecords({
    required List<Map<String, dynamic>> muffs,
    required List<Map<String, dynamic>> cabinets,
  }) {
    final records = <String, Map<String, dynamic>>{};
    for (final muff in muffs) {
      if (muff['deleted'] == true) {
        continue;
      }
      final id = _asInt(muff['id']);
      if (id == null) {
        continue;
      }
      final type = muff['is_pon_box'] == true ? 'pon_box' : 'muff';
      records['$type:$id'] = muff;
    }
    for (final cabinet in cabinets) {
      if (cabinet['deleted'] == true) {
        continue;
      }
      final id = _asInt(cabinet['id']);
      if (id != null) {
        records['cabinet:$id'] = cabinet;
      }
    }
    return records;
  }

  static List<Map<String, dynamic>> _cablesOf(Map<String, dynamic> record) {
    return List<Map<String, dynamic>>.from(record['cables'] ?? const []);
  }

  static List<Map<String, dynamic>> _connectionsOf(
    Map<String, dynamic> record,
  ) {
    return List<Map<String, dynamic>>.from(record['connections'] ?? const []);
  }

  static Map<String, dynamic>? _cableById(
    Map<String, dynamic> record,
    int cableId,
  ) {
    for (final cable in _cablesOf(record)) {
      if (_asInt(cable['id']) == cableId) {
        return cable;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _switchById(
    Map<String, dynamic> cabinet,
    int switchId,
  ) {
    for (final sw in List<Map<String, dynamic>>.from(
      cabinet['switches'] ?? const [],
    )) {
      if (_asInt(sw['id']) == switchId) {
        return sw;
      }
    }
    return null;
  }

  static String _entityName(
    Map<String, dynamic>? record, {
    String fallback = 'Object',
  }) {
    return _nameOf(record, fallback: fallback);
  }

  static String _nameOf(
    Map<String, dynamic>? record, {
    required String fallback,
  }) {
    final name = record?['name']?.toString().trim();
    if (name == null || name.isEmpty) {
      return fallback;
    }
    return name;
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

class _CableFiber {
  const _CableFiber(this.cableId, this.fiberIndex);

  final int cableId;
  final int fiberIndex;

  bool matches(int otherCableId, int otherFiberIndex) {
    return cableId == otherCableId && fiberIndex == otherFiberIndex;
  }
}

class _PortEndpoint {
  const _PortEndpoint(this.switchId, this.portIndex);

  final int switchId;
  final int portIndex;

  bool matches(int switchId, int portIndex) {
    return this.switchId == switchId && this.portIndex == portIndex;
  }
}
