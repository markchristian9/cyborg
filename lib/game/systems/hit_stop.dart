/// 타격의 무게를 만드는 아주 짧은 슬로우모션과, 그것이 스스로를 연장하지
/// 못하게 막는 잠금.
///
/// 히트스톱은 **덮어쓰기**다. 한 번 걸린 슬로우가 남아 있어도 새 타격이 들어오면
/// 처음부터 다시 채워진다. 잠금이 없으면 이 성질이 게임을 멈춘다 — 여러 대에게
/// 둘러싸여 연속으로 얻어맞거나 적을 연달아 처치하는 난전에서 슬로우가 끊이지
/// 않아, 화면이 1/4 속도로 기어 다닌다. 플레이어에게 그것은 연출이 아니라
/// "게임이 멈췄다"로 보인다.
///
/// 그래서 한 번 건 뒤에는 [recovery] 만큼 **정상 속도로** 흐르기 전까지 다시
/// 걸지 않는다. 연출 하나를 건너뛰는 대신 난전에서도 게임이 계속 굴러간다.
class HitStop {
  /// 슬로우가 풀린 뒤 다음 히트스톱까지 반드시 흘러야 하는 정상 속도 시간(초).
  static const double recovery = 0.18;

  /// 슬로우가 걸렸을 때 시간이 흐르는 배율.
  static const double timeScale = 0.25;

  double _remaining = 0;
  double _lock = 0;

  /// 지금 시간이 느려져 있는지.
  bool get isActive => _remaining > 0;

  /// 남은 슬로우 시간(초).
  double get remaining => _remaining;

  /// 지금 히트스톱을 걸 수 없는 상태인지.
  bool get isLocked => _lock > 0;

  /// [duration]초짜리 슬로우를 건다. 잠금 중이면 조용히 무시한다.
  void trigger(double duration) {
    if (_lock > 0 || duration <= 0) return;
    _remaining = duration;
    _lock = duration + recovery;
  }

  /// 실제로 흐른 [dt]를 넘기면 게임이 써야 할 dt를 돌려준다.
  ///
  /// 내부 타이머는 **감쇠 전 [dt]** 로 줄인다. 느려진 dt로 줄이면 슬로우가
  /// 네 배 오래 가고 잠금도 네 배 늦게 풀려, 히트스톱이 스스로를 연장한다.
  double advance(double dt) {
    if (_lock > 0) _lock -= dt;
    if (_remaining <= 0) return dt;
    _remaining -= dt;
    return dt * timeScale;
  }

  /// 전부 초기화한다. 재시작·리스폰처럼 판을 새로 여는 시점에 쓴다.
  void reset() {
    _remaining = 0;
    _lock = 0;
  }
}
