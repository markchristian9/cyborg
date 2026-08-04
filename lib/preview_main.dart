import 'package:flutter/material.dart';

import 'game/ui/cyborg_preview.dart';

/// 캐릭터 디자인 확인 전용 진입점.
///
/// 게임 본체(`main.dart`)와 완전히 분리되어 있으므로 다음처럼 실행한다.
///
/// ```sh
/// flutter run -t lib/preview_main.dart -d macos
/// flutter run -t lib/preview_main.dart -d chrome
/// ```
void main() {
  runApp(const CyborgPreviewApp());
}

/// 남성형·여성형 사이보그 프레임을 나란히 보여주는 앱.
class CyborgPreviewApp extends StatelessWidget {
  const CyborgPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cyborg Frame Preview',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const CyborgPreviewPage(),
    );
  }
}
