import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/palette.dart';

/// 계정·캐릭터 화면이 공유하는 배경.
///
/// 게임 안 지형과 같은 색조(어두운 금속 + 청록 회로)를 써서, 로그인 화면에서
/// 게임으로 넘어갈 때 다른 앱처럼 보이지 않게 한다.
class CyborgBackdrop extends StatelessWidget {
  const CyborgBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.55),
          radius: 1.1,
          colors: [Color(0xFF161E2A), GamePalette.voidColor],
        ),
      ),
      child: CustomPaint(
        painter: _GridPainter(),
        child: SafeArea(child: child),
      ),
    );
  }
}

/// 배경에 깔리는 원근 격자. 발밑에 바닥이 있다는 느낌만 준다.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GamePalette.floorGrid.withValues(alpha: 0.30)
      ..strokeWidth = 1;

    // 지평선 아래쪽만 격자를 깐다. 화면 전체에 깔면 글자 읽기를 방해한다.
    final horizon = size.height * 0.58;

    for (var i = 0; i <= 14; i++) {
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

/// 청록 테두리의 반투명 패널. 화면의 모든 내용은 이 안에 담긴다.
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
          color: GamePalette.hudBorder.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(4),
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
      borderSide: BorderSide(color: Color(0xFF2E3A4A)),
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
      cursorColor: GamePalette.playerAccent,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFF11161F),
        labelStyle: const TextStyle(color: GamePalette.textDim, fontSize: 13),
        hintStyle: TextStyle(
          color: GamePalette.textDim.withValues(alpha: 0.5),
          fontSize: 13,
        ),
        enabledBorder: border,
        border: border,
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: GamePalette.playerAccent, width: 1.5),
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
    this.accent = GamePalette.playerAccent,
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
        foregroundColor: const Color(0xFF07131A),
        disabledBackgroundColor: accent.withValues(alpha: 0.25),
        disabledForegroundColor: const Color(0xFF07131A),
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
                color: Color(0xFF07131A),
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
        color: GamePalette.floorHazard.withValues(alpha: 0.55),
        border: Border.all(
          color: GamePalette.floorHazardGlow.withValues(alpha: 0.6),
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
        ..color = GamePalette.playerAccent
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
