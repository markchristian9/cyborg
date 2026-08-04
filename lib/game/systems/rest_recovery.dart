/// 안전지대·아지트에서 쉬는 동안의 회복을 계산한다.
///
/// 사이보그의 몸체 내구도와 마력 회로는 용량이 커서 야전에서는 거의 차지
/// 않는다. 대신 적이 들어올 수 없는 구역으로 물러나 잠시 쉬면 정비 설비가
/// 붙어 빠르게 채워진다. 지금은 월드 한가운데의 안전지대가 유일한 거점이며,
/// 나중에 아지트가 생기면 같은 규칙을 그대로 쓴다.
class RestRecovery {
  /// 마지막으로 피해를 입은 뒤 이만큼 지나야 회복이 시작된다(초).
  ///
  /// 밖에서 얻어맞고 안전지대로 뛰어드는 즉시 만신창이가 낫는 것을 막는다.
  static const double warmupAfterDamage = 1.5;

  /// 쉬는 동안 1초에 채워지는 최대 체력의 비율.
  static const double hpPerSecond = 0.12;

  /// 쉬는 동안 1초에 채워지는 최대 마력의 비율.
  static const double mpPerSecond = 0.15;

  /// 거점 밖에서 1초에 저절로 차는 마력의 비율. 거의 차지 않는다.
  static const double fieldMpPerSecond = 0.005;

  /// 지금 거점 안에 있는지.
  bool _sheltered = false;

  /// 피격 후 남은 대기 시간.
  double _warmup = 0;

  /// 회복이 실제로 진행 중인지. HUD 표시에 쓴다.
  bool _recovering = false;

  bool get isSheltered => _sheltered;

  bool get isRecovering => _recovering;

  /// 피격 대기가 끝나기까지 남은 시간(초). 0이면 바로 회복할 수 있다.
  double get warmupRemaining => _warmup < 0 ? 0 : _warmup;

  /// 피해를 입었다고 알린다. 대기 시간이 다시 채워진다.
  void notifyDamaged() => _warmup = warmupAfterDamage;

  /// 이번 프레임의 상태를 갱신한다.
  ///
  /// [sheltered]는 플레이어가 안전지대 안에 있는지 여부다.
  void update(double dt, {required bool sheltered}) {
    _sheltered = sheltered;
    if (_warmup > 0) _warmup -= dt;
    _recovering = sheltered && _warmup <= 0;
  }

  /// 이번 프레임에 채울 체력. 쉬는 중이 아니면 0이다.
  double hpGain(double dt, double maxHp) =>
      _recovering ? maxHp * hpPerSecond * dt : 0;

  /// 이번 프레임에 채울 마력.
  ///
  /// 거점 안에서는 빠르게, 밖에서는 아주 느리게 찬다.
  double mpGain(double dt, double maxMp) {
    if (_recovering) return maxMp * mpPerSecond * dt;
    return maxMp * fieldMpPerSecond * dt;
  }

  void reset() {
    _sheltered = false;
    _warmup = 0;
    _recovering = false;
  }
}
