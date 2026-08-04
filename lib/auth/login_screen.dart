import 'package:flutter/material.dart';

import '../game/palette.dart';
import 'cyborg_session.dart';
import 'ui_kit.dart';

/// 로그인과 회원가입을 한 화면에서 처리한다.
///
/// 두 화면으로 나누면 "가입하려다 로그인 화면에 있는" 상태에서 뒤로가기를
/// 몇 번 눌러야 하는지가 헷갈린다. 입력칸이 거의 같으므로 모드만 바꾼다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final CyborgSession session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();

  bool _registering = false;

  /// 서버에 보내기 전에 이 화면에서 먼저 잡은 문제.
  ///
  /// 서버 응답을 기다렸다 알려 주면 왕복만큼 늦고, 오프라인이면 아예 알려 줄 수
  /// 없다. 서버도 같은 검사를 하므로 이건 중복이 아니라 앞당김이다.
  String? _localError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _registering = !_registering;
      _localError = null;
      _passwordConfirm.clear();
    });
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _localError = '이메일과 비밀번호를 모두 입력해라.');
      return;
    }
    if (_registering) {
      if (password.length < 8) {
        setState(() => _localError = '비밀번호는 최소 8자다.');
        return;
      }
      if (password != _passwordConfirm.text) {
        setState(() => _localError = '비밀번호 확인이 일치하지 않는다.');
        return;
      }
    }

    setState(() => _localError = null);

    // 성공하면 view 가 갱신되고 상위 화면이 알아서 캐릭터 선택으로 넘어간다.
    // 이 화면은 화면 전환을 직접 하지 않는다 — 전환의 근거는 언제나 서버 상태다.
    if (_registering) {
      await widget.session.register(email, password);
    } else {
      await widget.session.login(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final busy = session.busy;

    return CyborgBackdrop(
      child: CyborgCenter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CyborgHeading(
              title: 'CYBORG',
              subtitle: 'AI 로봇이 점령한 세계.\n남은 인간은 기계의 몸으로 싸운다.',
            ),
            const SizedBox(height: 28),
            CyborgPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _registering ? '새 요원 등록' : '요원 접속',
                    style: const TextStyle(
                      color: GamePalette.playerAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 20),
                  CyborgField(
                    controller: _email,
                    label: '이메일',
                    hint: 'operative@resistance.net',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    enabled: !busy,
                    autofocus: true,
                  ),
                  const SizedBox(height: 14),
                  CyborgField(
                    controller: _password,
                    label: '비밀번호',
                    hint: _registering ? '8자 이상' : null,
                    obscure: true,
                    enabled: !busy,
                    textInputAction: _registering
                        ? TextInputAction.next
                        : TextInputAction.done,
                    autofillHints: [
                      _registering
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onSubmitted: _registering ? null : (_) => _submit(),
                  ),
                  if (_registering) ...[
                    const SizedBox(height: 14),
                    CyborgField(
                      controller: _passwordConfirm,
                      label: '비밀번호 확인',
                      obscure: true,
                      enabled: !busy,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  CyborgError(message: _localError ?? session.error),
                  const SizedBox(height: 22),
                  CyborgButton(
                    label: _registering ? '등록하고 시작' : '접속',
                    busy: busy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: busy ? null : _toggleMode,
                    style: TextButton.styleFrom(
                      foregroundColor: GamePalette.textDim,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: Text(
                      _registering
                          ? '이미 계정이 있다 — 접속하기'
                          : '계정이 없다 — 새 요원 등록',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
