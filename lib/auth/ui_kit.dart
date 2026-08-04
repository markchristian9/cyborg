import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/palette.dart';

/// 계정·캐릭터 화면이 공유하는 배경.
///
/// 게임 무대와 같은 톤(눈부시게 밝은 데이터 공간, 청록 격자)을 쓴다. 로그인
/// 화면에서 게임으로 넘어갈 때 다른 앱처럼 보이지 않게 하려는 것이다 —
/// 색은 전부 [GamePalette] 에서 가져오므로 무대 톤이 바뀌면 여기도 따라간다.
class CyborgBackdrop extends StatelessWidget {
  const CyborgBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GamePalette.skyHigh, GamePalette.skyLow],
            ),
          ),
          child: CustomPaint(
            painter: _GridPainter(),
            child: SafeArea(child: child),
          ),
        ),
      ),
    );
  }

  /// 이 화면들에 강제하는 테마.
  ///
  /// 앱 전체 테마와 무관하게 여기서 못을 박아, Material 기본 위젯(다이얼로그·
  /// 팝업 메뉴·텍스트 선택 핸들)이 무대 톤에서 벗어나지 않게 한다.
  static final ThemeData _theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: GamePalette.hudBorder,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: GamePalette.skyHigh,
  );
}

/// 배경에 깔리는 원근 격자. 발밑에 데이터 플레이트가 있다는 느낌을 준다.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GamePalette.floorGrid.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    // 지평선 아래쪽에만 격자를 깐다. 화면 전체에 깔면 글자 읽기를 방해한다.
    final horizon = size.height * 0.58;

    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      Paint()
        ..color = GamePalette.horizonGlow.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );

    for (var i = 1; i <= 14; i++) {
      final t = i / 14;
      // 아래로 갈수록 간격이 벌어져 원근이 생긴다.
      final y = horizon + (size.height - horizon) * t * t;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final vanishing = Offset(size.width / 2, horizon);
    for (var i = -8; i <= 8; i++) {
      final x = size.width / 2 + i * size.width / 8;
      canvas.drawLine(vanishing, Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// 화면 상단의 제목 블록.
class CyborgHeading extends StatelessWidget {
  const CyborgHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: GamePalette.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 5,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(
              color: GamePalette.textDim,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// 반투명 글래스 패널. 화면의 내용은 이 안에 담긴다.
class CyborgPanel extends StatelessWidget {
  const CyborgPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: GamePalette.hudBackground,
        border: Border.all(
          color: GamePalette.hudBorder.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: GamePalette.shadow.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 이 화면들이 쓰는 텍스트 입력.
class CyborgField extends StatelessWidget {
  const CyborgField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.enabled = true,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderSide: BorderSide(color: GamePalette.floorGrid),
      borderRadius: BorderRadius.all(Radius.circular(3)),
    );

    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: GamePalette.textPrimary, fontSize: 15),
      cursorColor: GamePalette.hudBorder,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: GamePalette.floorBase,
        labelStyle: const TextStyle(color: GamePalette.textDim, fontSize: 13),
        hintStyle: TextStyle(
          color: GamePalette.textDim.withValues(alpha: 0.6),
          fontSize: 13,
        ),
        enabledBorder: border,
        border: border,
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: GamePalette.hudBorder, width: 1.5),
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
      ),
    );
  }
}

/// 화면의 주요 동작 버튼.
class CyborgButton extends StatelessWidget {
  const CyborgButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.accent = GamePalette.hudBorder,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;

  /// 진행 중이면 표시를 바꾸고 입력을 막는다.
  final bool busy;
  final Color accent;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    final button = FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: accent.withValues(alpha: 0.28),
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// 서버가 거절한 이유를 보여주는 줄.
///
/// 비어 있을 때 자리를 차지하지 않도록 [message] 가 null 이면 아무것도 그리지
/// 않는다.
class CyborgError extends StatelessWidget {
  const CyborgError({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GamePalette.floorHazard,
        border: Border.all(
          color: GamePalette.floorHazardGlow.withValues(alpha: 0.65),
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 17,
            color: GamePalette.floorHazardGlow,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: GamePalette.floorHazardGlow,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 화면 내용의 최대 폭을 제한하고 가운데 정렬한다.
///
/// 데스크톱·웹에서 입력칸이 화면 끝까지 늘어나면 읽기 어렵다.
class CyborgCenter extends StatelessWidget {
  const CyborgCenter({super.key, required this.child, this.maxWidth = 420});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// 회전하는 육각형 스피너. 연결 대기 화면에 쓴다.
class CyborgSpinner extends StatefulWidget {
  const CyborgSpinner({super.key, this.size = 56});

  final double size;

  @override
  State<CyborgSpinner> createState() => _CyborgSpinnerState();
}

class _CyborgSpinnerState extends State<CyborgSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _SpinnerPainter(_controller.value),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;

    canvas.drawPath(
      _hexagon(center, radius),
      Paint()
        ..color = GamePalette.floorGrid
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * math.pi * 2);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawPath(
      _hexagon(center, radius * 0.62),
      Paint()
        ..color = GamePalette.hudBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  Path _hexagon(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 2;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.progress != progress;
}
