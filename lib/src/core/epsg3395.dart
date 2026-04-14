import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class Epsg3395 extends Crs {
  static const double _scale = 0.5 / (math.pi * _EllipticalMercator.r);

  const Epsg3395()
      : super(
          code: 'EPSG:3395',
          infinite: false,
          wrapLng: const (-180, 180),
        );

  @override
  Projection get projection => const _EllipticalMercator();

  @override
  (double, double) transform(double x, double y, double scale) {
    return (_scale * x * scale + 0.5 * scale, -_scale * y * scale + 0.5 * scale);
  }

  @override
  (double, double) untransform(double x, double y, double scale) {
    return ((x / scale - 0.5) / _scale, (y / scale - 0.5) / -_scale);
  }

  @override
  (double, double) latLngToXY(LatLng latlng, double scale) {
    final (x, y) = projection.projectXY(latlng);
    return transform(x, y, scale);
  }

  @override
  Point<double> latLngToPoint(LatLng latlng, double zoom) {
    final (x, y) = latLngToXY(latlng, scale(zoom));
    return Point<double>(x, y);
  }

  @override
  LatLng pointToLatLng(Point point, double zoom) {
    final (x, y) = untransform(
      point.x.toDouble(),
      point.y.toDouble(),
      scale(zoom),
    );
    return projection.unprojectXY(x, y);
  }

  @override
  Bounds<double>? getProjectedBounds(double zoom) {
    final bounds = projection.bounds;
    if (bounds == null) {
      return null;
    }

    final scaleValue = scale(zoom);
    final (minX, minY) = transform(bounds.min.x, bounds.min.y, scaleValue);
    final (maxX, maxY) = transform(bounds.max.x, bounds.max.y, scaleValue);
    return Bounds<double>(
      Point<double>(minX, minY),
      Point<double>(maxX, maxY),
    );
  }
}

class _EllipticalMercator extends Projection {
  static const int r = 6378137;
  static const double rMinor = 6356752.314245179;

  static const Bounds<double> _bounds = Bounds<double>.unsafe(
    Point<double>(-20037508.34279, -15496570.73972),
    Point<double>(20037508.34279, 18764656.23138),
  );

  const _EllipticalMercator() : super(_bounds);

  @override
  (double, double) projectXY(LatLng latlng) {
    const degreesToRadians = math.pi / 180;
    var y = latlng.latitude * degreesToRadians;
    final axisRatio = rMinor / r;
    final eccentricity = math.sqrt(1 - axisRatio * axisRatio);
    final con = eccentricity * math.sin(y);

    final ts =
        math.tan(math.pi / 4 - y / 2) /
        math.pow((1 - con) / (1 + con), eccentricity / 2);
    y = -r * math.log(math.max(ts, 1e-10));

    return (latlng.longitude * degreesToRadians * r, y);
  }

  @override
  LatLng unprojectXY(double x, double y) {
    const radiansToDegrees = 180 / math.pi;
    final axisRatio = rMinor / r;
    final eccentricity = math.sqrt(1 - axisRatio * axisRatio);
    final ts = math.exp(-y / r);
    var phi = math.pi / 2 - 2 * math.atan(ts);

    for (var i = 0; i < 15; i++) {
      final con = eccentricity * math.sin(phi);
      final deltaPhi =
          math.pi / 2 -
          2 * math.atan(
            ts * math.pow((1 - con) / (1 + con), eccentricity / 2),
          ) -
          phi;
      phi += deltaPhi;
      if (deltaPhi.abs() <= 1e-7) {
        break;
      }
    }

    return LatLng(phi * radiansToDegrees, x * radiansToDegrees / r);
  }
}
