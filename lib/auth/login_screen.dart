import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dev/dev_login.dart';
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
  void initState() {
    super.initState();

    // 개발용 자동 로그인. 사람의 키보드를 자동화로 가로채는 대신 앱이 스스로
    // 입력칸을 채우고 제출 핸들러를 부른다([dev_login.dart] 참고). 값이 주어지지
    // 않으면 이 블록은 그냥 지나간다.
    if (devLoginEnabled) {
      _email.text = kDevLoginEmail;
      _password.text = kDevLoginPassword;
      _passwordConfirm.text = kDevLoginPassword;
      devLog('로그인 화면 진입 — $kDevLoginEmail 로 자동 제출한다');

      // 첫 프레임이 그려진 뒤에 부른다. build 도중에 상태를 바꾸면 안 된다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoSubmit();
      });
    }
  }

  /// 자동 로그인. 계정이 없으면 그 자리에서 만든다.
  ///
  /// 여러 클라이언트를 한꺼번에 띄울 때 계정을 미리 다 만들어 둘 수는 없으므로,
  /// **접속을 먼저 시도하고 거절당하면 등록으로 넘어간다**. 순서를 반대로 하면
  /// 이미 있는 계정마다 "이미 가입된 이메일" 거절을 한 번씩 받고 시작한다.
  Future<void> _autoSubmit() async {
    final email = kDevLoginEmail;
    final password = kDevLoginPassword;
    final session = widget.session;

    if (await session.login(email, password)) {
      devLog('접속 성공');
      return;
    }
    devLog('접속 거절됨(${session.error}) — 새 계정으로 등록한다');
    if (!mounted) return;

    // 등록에 성공하면 서버가 같은 트랜잭션에서 세션까지 붙여 준다. 따로 다시
    // 로그인할 필요가 없다.
    if (await session.register(email, password)) {
      devLog('등록 성공');
      return;
    }

    // 여기까지 왔다면 등록도 거절됐다는 뜻이다. 비밀번호가 틀린 계정이거나,
    // 같은 이메일로 뜬 다른 인스턴스가 방금 먼저 등록했거나 둘 중 하나다.
    // 후자는 한 번 더 접속하면 통과하므로 마지막으로 한 번 시도한다.
    devLog('등록도 거절됨(${session.error}) — 접속을 한 번 더 시도한다');
    if (!mounted) return;
    final ok = await session.login(email, password);
    devLog(ok ? '접속 성공' : '자동 접속 실패: ${session.error}');
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  void _toggleMode() {
    // 서버가 준 거절 사유도 함께 지운다. 남겨 두면 "로그인 실패" 문구가 가입
    // 화면까지 따라와, 아직 아무것도 안 눌렀는데 실패한 것처럼 보인다.
    widget.session.clearError();
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
    final ok = _registering
        ? await widget.session.register(email, password)
        : await widget.session.login(email, password);

    devLog(ok ? '제출 성공' : '제출 거절됨: ${widget.session.error}');

    // 로그인이 실제로 통과한 뒤에야 비밀번호 관리자에게 저장을 제안한다.
    // 실패한 조합을 저장하게 두면 다음 로그인이 그 값으로 채워져 또 실패한다.
    if (ok) TextInput.finishAutofillContext();
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
              // 이메일·비밀번호를 한 묶음으로 보여 줘야 기기의 비밀번호 관리자가
              // 둘을 짝지어 저장하고 다음 로그인에 함께 채워 넣는다.
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _registering ? '새 요원 등록' : '요원 접속',
                      style: const TextStyle(
                        // 발광용 청록(playerAccent)은 밝은 배경에서 흐리게 보인다.
                        // UI 에는 한 단계 진한 hudBorder 를 쓴다.
                        color: GamePalette.hudBorder,
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
                        _registering ? '이미 계정이 있다 — 접속하기' : '계정이 없다 — 새 요원 등록',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
