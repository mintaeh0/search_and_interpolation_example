import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:search_and_interpolation_example/geoid_point.dart';

class GeoidCalculate {
  List<GeoidPoint> geoidPoints = [];

  // .dat 파일에서 지오이드 데이터 로딩
  Future<void> loadGeoidData(String assetPath) async {
    try {
      String content = await rootBundle.loadString(assetPath);
      List<String> lines = content.split('\n');

      geoidPoints.clear();

      for (String line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        // 공백으로 분리 (여러 공백 포함)
        List<String> parts = line.split(RegExp(r'\s+'));

        if (parts.length >= 5) {
          try {
            GeoidPoint point = GeoidPoint(
              id: int.parse(parts[0]),
              latitude: double.parse(parts[1]),
              longitude: double.parse(parts[2]),
              // parts[3]은 사용하지 않음 (항상 0.000)
              geoidHeight: double.parse(parts[4]),
            );

            geoidPoints.add(point);
          } catch (e) {
            log('Error parsing line: $line - $e');
          }
        }
      }
    } catch (e) {
      log('Error loading geoid data: $e');
      rethrow;
    }
  }

  // 지오이드 고도 계산
  double getGeoidHeight(LatLng latLng) {
    final double lat = latLng.latitude;
    final double lon = latLng.longitude;

    final List<GeoidPoint> points = _findBoundingPoints3(lat, lon); // 선형탐색 버전
    // final List<GeoidPoint> points = _findBoundingPoints2(lat, lon); // 이진탐색 버전
    return _bilinearInterpolation(lat, lon, points);
  }

  // 선형탐색으로 주어진 포인트를 감싸는 4개의 꼭짓점 찾기
  List<GeoidPoint> _findBoundingPoints(double lat, double lon) {
    // Set 사용 중복 제거
    final Set<double> latSet = geoidPoints.map((p) => p.latitude).toSet();
    final Set<double> lonSet = geoidPoints.map((p) => p.longitude).toSet();

    // 주어진 위경도 범위에 해당하는 수치 구하기
    final double? lat1 = latSet
        .where((v) => v <= lat)
        .maxOrNull; // 위도보다 작은 값들 중 가장 큰 값
    final double? lat2 = latSet
        .where((v) => v >= lat)
        .minOrNull; // 위도보다 큰 값들 중 가장 작은 값
    final double? lon1 = lonSet
        .where((v) => v <= lon)
        .maxOrNull; // 경도보다 작은 값들 중 가장 큰 값
    final double? lon2 = lonSet
        .where((v) => v >= lon)
        .minOrNull; // 경도보다 큰 값들 중 가장 작은 값

    // 하나라도 null인 경우
    if ([lat1, lat2, lon1, lon2].any((v) => v == null)) {
      throw Exception("좌표를 구할 수 없습니다.");
    }

    // 하나씩 조합하여 좌표값으로 저장
    final GeoidPoint? p11 = geoidPoints.firstWhereOrNull(
      (p) => p.latitude == lat1 && p.longitude == lon1,
    );
    final GeoidPoint? p12 = geoidPoints.firstWhereOrNull(
      (p) => p.latitude == lat1 && p.longitude == lon2,
    );
    final GeoidPoint? p21 = geoidPoints.firstWhereOrNull(
      (p) => p.latitude == lat2 && p.longitude == lon1,
    );
    final GeoidPoint? p22 = geoidPoints.firstWhereOrNull(
      (p) => p.latitude == lat2 && p.longitude == lon2,
    );

    final List<GeoidPoint?> bounding = [p11, p12, p21, p22];

    // 하나라도 null인 경우
    if (bounding.any((p) => p == null)) {
      throw Exception("4개의 꼭짓점 중 하나 이상이 누락되었습니다.");
    }

    return bounding.cast<GeoidPoint>();
  }

  // 이진탐색으로 주어진 포인트를 감싸는 4개의 꼭짓점 찾기
  List<GeoidPoint> _findBoundingPoints2(double lat, double lon) {
    if (geoidPoints.isEmpty) {
      throw Exception("데이터가 로드되지 않았습니다.");
    }

    // 1. 위도 경계 (lat1, lat2) 찾기
    // 데이터는 위도 내림차순으로 정렬되어 있음
    // lat1: 주어진 lat보다 크거나 같은 위도 중 가장 가까운 위도 (target lat의 상위 경계)
    // lat2: 주어진 lat보다 작거나 같은 위도 중 가장 가까운 위도 (target lat의 하위 경계)

    // 'targetLat'보다 작거나 같은 첫 번째 지점 (내림차순이므로)의 인덱스를 찾음
    // 이 지점의 위도는 lat2가 될 가능성이 높음
    int lowerLatIndex = -1;
    int low = 0;
    int high = geoidPoints.length - 1;

    while (low <= high) {
      int mid = low + ((high - low) ~/ 2);
      if (geoidPoints[mid].latitude == lat) {
        // 정확히 일치하는 위도를 찾았으면, 해당 위도 라인에서 경도 탐색으로 넘어갑니다.
        lowerLatIndex = mid;
        break;
      } else if (geoidPoints[mid].latitude > lat) {
        // 현재 위도가 target lat보다 크면, 더 작은 위도를 찾아야 하므로 high를 이동
        low = mid + 1;
      } else {
        // geoidPoints[mid].latitude < lat
        // 현재 위도가 target lat보다 작으면, 이 위도는 lat2가 될 수 있음
        // 더 큰 위도를 찾아야 하므로 lowerLatIndex를 업데이트하고 high를 이동
        lowerLatIndex = mid;
        high = mid - 1;
      }
    }

    if (lowerLatIndex == -1) {
      // lat보다 작은 위도를 찾지 못했다면, lat이 가장 작은 위도보다도 작음
      throw Exception("주어진 위도가 지오이드 데이터의 최저 위도보다 낮습니다. ($lat)");
    }

    final double lat2 =
        geoidPoints[lowerLatIndex].latitude; // target lat보다 작거나 같은 가장 가까운 위도

    // lat1 찾기: lat2보다 크면서 target lat보다 크거나 같은 위도
    double? lat1;
    // 위도 내림차순이므로, lat2를 찾은 인덱스부터 앞으로(위로) 가면서 찾음
    for (int i = lowerLatIndex; i >= 0; i--) {
      if (geoidPoints[i].latitude >= lat) {
        lat1 = geoidPoints[i].latitude;
        break;
      }
    }

    // lat1을 찾지 못했다면, lat2가 최고 위도일 가능성
    lat1 ??= lat2; // 이 경우 단일 위도 라인 처리

    // 범위 검사
    if (lat > geoidPoints.first.latitude || lat < geoidPoints.last.latitude) {
      throw Exception(
        "주어진 위도($lat)가 지오이드 데이터의 범위를 벗어납니다. (Min: ${geoidPoints.last.latitude}, Max: ${geoidPoints.first.latitude})",
      );
    }

    // 2. 경도 경계 (lon1, lon2)와 4개의 꼭짓점 찾기
    // lat1과 lat2에 해당하는 GeoidPoint들을 효율적으로 가져오기
    List<GeoidPoint> pointsAtLat1 = [];
    List<GeoidPoint> pointsAtLat2 = [];

    // 최적화를 위해, 전체 리스트를 순회하지 않고, lat1/lat2를 포함하는 범위만 탐색
    // lat1과 lat2에 해당하는 데이터는 리스트에 연속적으로 존재할 가능성이 높으므로
    // 한 번의 순회로 두 위도 라인의 데이터를 필터링
    for (var point in geoidPoints) {
      if (point.latitude == lat1) {
        pointsAtLat1.add(point);
      } else if (point.latitude == lat2) {
        pointsAtLat2.add(point);
      }
      // 이미 필요한 위도 라인을 모두 찾았거나, 더 이상 의미 없는 위도에 도달하면 중단
      if (pointsAtLat1.isNotEmpty &&
          pointsAtLat2.isNotEmpty &&
          point.latitude < lat2) {
        break;
      }
    }

    // 각 위도 라인의 경도도 오름차순으로 정렬되어 있음
    GeoidPoint? p11, p12, p21, p22;

    // lat1 라인에서 lon1, lon2 찾기
    // lon1: lon보다 작거나 같은 가장 큰 경도
    // lon2: lon보다 크거나 같은 가장 작은 경도
    p11 = pointsAtLat1.lastWhereOrNull((p) => p.longitude <= lon);
    p12 = pointsAtLat1.firstWhereOrNull((p) => p.longitude >= lon);

    if (p11 == null || p12 == null) {
      throw Exception("위도 $lat1에서 경도 경계점을 찾을 수 없습니다.");
    }

    // lat1 == lat2인 경우 (단일 위도 라인)
    if (lat1 == lat2) {
      // 경도 범위 검사 (추가)
      if (lon > p12.longitude || lon < p11.longitude) {
        throw Exception(
          "주어진 경도($lon)가 단일 위도 라인($lat1)의 경도 범위를 벗어납니다. (Min: ${p11.longitude}, Max: ${p12.longitude})",
        );
      }
      return [p11, p12, p11, p12]; // p21, p22를 p11, p12와 동일하게 설정 (수직 보간 생략)
    }

    // lat2 라인에서 lon1, lon2 찾기
    p21 = pointsAtLat2.lastWhereOrNull((p) => p.longitude <= lon);
    p22 = pointsAtLat2.firstWhereOrNull((p) => p.longitude >= lon);

    if (p21 == null || p22 == null) {
      throw Exception("위도 $lat2에서 경도 경계점을 찾을 수 없습니다.");
    }

    // 최종 4개의 꼭짓점
    final bounding = [p11, p12, p21, p22];

    if (bounding.any((p) => p == null)) {
      throw Exception(
        "4개의 꼭짓점 중 하나 이상이 누락되었습니다. (lat: $lat, lon: $lon, lat1: $lat1, lat2: $lat2)",
      );
    }

    return bounding.cast<GeoidPoint>();
  }

  // 그리드 간격을 이용한 탐색
  List<GeoidPoint> _findBoundingPoints3(double lat, double lon) {
    final startLat = geoidPoints.first.latitude; // 최대 위도 - 내림차순이기 때문에 처음 값
    final endLat = geoidPoints.last.latitude; // 최소 위도
    final startLon = geoidPoints.first.longitude; // 최소 경도
    final endLon = geoidPoints.last.longitude; // 최대 경도

    final step = 0.01636; // 위,경도 간격
    final lonCountPerRow = 490; // 행 offset

    // 데이터 범위 내 좌표인지 확인
    if (lat > startLat || lat < endLat || lon < startLon || lon > endLon) {
      log("$startLat");
      log("$endLat");
      log("$startLon");
      log("$endLon");
      throw Exception("요청 좌표가 데이터 범위를 벗어났습니다 ($lat, $lon)");
    }

    // 그리드 간격으로 나눠서 인덱스 추출
    final rowIndex = ((startLat - lat) / step).floor();
    final colIndex = ((lon - startLon) / step).floor();

    // 1차원 리스트의 인덱스 계산 (결과 사각형의 좌상단 점)
    final p11Index = (rowIndex * lonCountPerRow) + colIndex;

    // 계산된 인덱스가 데이터 크기를 초과하지 않는지 최종 확인
    if (p11Index + lonCountPerRow + 1 >= geoidPoints.length) {
      throw Exception("계산된 인덱스가 데이터 크기를 초과합니다. 경계에 매우 가까운 좌표일 수 있습니다.");
    }

    // 4. 4개의 꼭짓점 데이터를 인덱스로 직접 추출
    return [
      geoidPoints[p11Index], // p11 (좌상단)
      geoidPoints[p11Index + 1], // p12 (우상단)
      geoidPoints[p11Index + lonCountPerRow], // p21 (좌하단)
      geoidPoints[p11Index + lonCountPerRow + 1], // p22 (우하단)
    ];
  }

  // 이중선형 보간 작업
  double _bilinearInterpolation(double lat, double lon, List<GeoidPoint> pts) {
    final p11 = pts[0]; // (lat1, lon1)
    final p12 = pts[1]; // (lat1, lon2)
    final p21 = pts[2]; // (lat2, lon1)
    final p22 = pts[3]; // (lat2, lon2)

    final lat1 = p11.latitude;
    final lat2 = p22.latitude;
    final lon1 = p11.longitude;
    final lon2 = p22.longitude;

    // 경도 기준 1차 보간
    final f1 = _lerp(lon, lon1, lon2, p11.geoidHeight, p12.geoidHeight);
    final f2 = _lerp(lon, lon1, lon2, p21.geoidHeight, p22.geoidHeight);

    // 위도 기준 2차 보간
    return _lerp(lat, lat1, lat2, f1, f2);
  }

  // 보간 함수
  double _lerp(double x, double x1, double x2, double h1, double h2) {
    if ((x2 - x1).abs() < 1e-10) return h1; // 0 나눗셈 방지
    return h1 + (h2 - h1) * ((x - x1) / (x2 - x1));
  }
}
