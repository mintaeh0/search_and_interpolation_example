import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:search_and_interpolation_example/geoid_view_model.dart';

class GeoidView extends StatefulWidget {
  const GeoidView({super.key});

  @override
  State<GeoidView> createState() => _GeoidViewState();
}

class _GeoidViewState extends State<GeoidView> {
  @override
  void initState() {
    super.initState();
    final geoidViewModel = context.read<GeoidViewModel>();
    geoidViewModel.init(); // 초기화 함수
  }

  @override
  Widget build(BuildContext context) {
    final geoidViewModel = context.watch<GeoidViewModel>();

    // 에러 메시지가 있을 경우 스낵바로 표시
    if (geoidViewModel.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(geoidViewModel.errorMessage!)));

        geoidViewModel.errorMessage = null; // 에러 메시지 초기화
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text("GPS, 탐색, 보간 예제")),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            Text("위도 : ${geoidViewModel.position?.latitude ?? 0.0}"),
            Text("경도 : ${geoidViewModel.position?.longitude ?? 0.0}"),
            Text("지오이드 고도 : ${geoidViewModel.geoidHeight ?? 0.0}"),
          ],
        ),
      ),
    );
  }
}
