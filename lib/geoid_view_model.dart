import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:search_and_interpolation_example/geoid_calculate.dart';

class GeoidViewModel extends ChangeNotifier {
  GeoidCalculate geoidCalculate = GeoidCalculate();
  StreamSubscription? gpsPositionSubscription;
  String? errorMessage;
  LatLng? position;
  double? geoidHeight;

  Future<void> init() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('위치 서비스가 비활성화되었습니다');
      }

      // 위치 권한 요청
      LocationPermission permission = await Geolocator.checkPermission();

      // 권한이 거부된 경우
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('위치 권한이 거부되었습니다');
        }
      }

      // 영구적으로 거부된 경우
      if (permission == LocationPermission.deniedForever) {
        throw Exception('위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 권한을 허용해주세요');
      }

      // 지오이드 데이터 로드
      await geoidCalculate.loadGeoidData('assets/KNGeoid24.dat');

      // 위치 업데이트 시작
      gpsPositionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(_updateGpsPosition);
      //
    } catch (e) {
      errorMessage = "$e";
      notifyListeners();
    }
  }

  // GPS 사용자 위치 좌표 업데이트
  void _updateGpsPosition(Position gpsPosition) {
    position = LatLng(gpsPosition.latitude, gpsPosition.longitude); // 위경도
    geoidHeight = geoidCalculate.getGeoidHeight(position!); // 지오이도 고도 계산
    notifyListeners();
  }

  @override
  void dispose() async {
    super.dispose();

    // 구독 해제
    if (gpsPositionSubscription != null) {
      await gpsPositionSubscription?.cancel();
    }
  }
}
