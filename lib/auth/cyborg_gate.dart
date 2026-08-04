import 'package:flutter/material.dart';

import '../game/palette.dart';
import '../main.dart' show GameScreen;
import '../spacetime/generated/player_character.dart';
import 'character_select_screen.dart';
import 'cyborg_session.dart';
import 'login_screen.dart';
import 'ui_kit.dart';

/// 게임 앞단의 관문. 연결 → 로그인 → 캐릭터 선택 → 게임 순서를 관장한다.
///
/// 어떤 화면을 보여줄지는 **전부 서버 상태에서 도출한다**. 화면 전환을 각
/// 화면이 직접 하지 않고 여기서 한곳에 모아 두면, 다른 기기에서 로그아웃하거나
/// 세션이 끊겨도 화면이 저절로 제자리를 찾는다.
class CyborgGate extends StatefulWidget {
  const CyborgGate({super.key});

  @override
  State<CyborgGate> createState() => _CyborgGateState();
}

class _CyborgGateState extends State<CyborgGate> {
  final CyborgSession _session = CyborgSession();

  /// 게임 화면에 들어갔는지. 캐릭터를 골랐다고 바로 들어가지는 않는다 —
  /// 사용자가 "출격" 을 눌러야 한다.
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    _session.boot();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _launch(PlayerCharacter character) {
    setState(() => _launched = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        // 로그아웃하거나 연결이 끊기면 게임에 머물 이유가 없다.
        if (_launched && !_session.isLoggedIn) {
          _launched = false;
        }

        return switch (_session.phase) {
          ConnectionPhase.connecting => const _BootView(),
          ConnectionPhase.failed => _FailedView(session: _session),
          ConnectionPhase.ready => _readyView(),
        };
      },
    );
  }

  Widget _readyView() {
    if (!_session.isLoggedIn) {
      return LoginScreen(session: _session);
    }
    if (_launched) {
      return const GameScreen();
    }
    return CharacterSelectScreen(session: _session, onStart: _launch);
  }
}

/// 서버에 붙는 동안 보여 주는 화면.
class _BootView extends StatelessWidget {
  const _BootView();

  @override
  Widget build(BuildContext context) {
    return const CyborgBackdrop(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CyborgSpinner(),
            SizedBox(height: 22),
            Text(
              '데이터 공간에 접속 중',
              style: TextStyle(
                color: GamePalette.textDim,
                fontSize: 13,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 연결에 실패했을 때. 다시 시도할 수 있게 한다.
class _FailedView extends StatelessWidget {
  const _FailedView({required this.session});

  final CyborgSession session;

  @override
  Widget build(BuildContext context) {
    return CyborgBackdrop(
      child: CyborgCenter(
        child: CyborgPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: GamePalette.floorHazardGlow,
                size: 34,
              ),
              const SizedBox(height: 16),
              const Text(
                '서버에 닿지 않는다',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: GamePalette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                session.error ?? '알 수 없는 이유로 연결이 끊겼다.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: GamePalette.textDim,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              CyborgButton(label: '다시 시도', onPressed: session.boot),
            ],
          ),
        ),
      ),
    );
  }
}
