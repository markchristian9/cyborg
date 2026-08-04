import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(tiledFrame() ?? windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// `scripts/run.sh` 가 클라이언트를 여러 개 띄울 때 창이 서로 겹치지 않도록
  /// 바둑판 자리 하나를 계산한다.
  ///
  /// 자리는 실행 시점 환경변수로 받는다. 창 배치를 앱 밖에서(AppleScript 등)
  /// 옮기면 사람이 쓰고 있는 화면에 끼어들게 되므로, 자기 창은 자기가 놓는다.
  /// 환경변수가 없으면 nil 을 돌려 평소의 기본 창 크기를 그대로 쓴다.
  private func tiledFrame() -> NSRect? {
    let env = ProcessInfo.processInfo.environment
    guard let indexText = env["CYBORG_TILE_INDEX"],
          let index = Int(indexText), index >= 0,
          let visible = (self.screen ?? NSScreen.main)?.visibleFrame
    else { return nil }

    let width = CGFloat(Double(env["CYBORG_TILE_WIDTH"] ?? "") ?? 600)
    let height = CGFloat(Double(env["CYBORG_TILE_HEIGHT"] ?? "") ?? 500)

    // 한 줄에 몇 개가 들어가는지는 화면이 정한다. 창 크기는 요청받은 값 그대로
    // 두고, 자리 수만 화면에 맞춘다.
    let columns = max(1, Int(visible.width / width))
    let rows = max(1, Int(visible.height / height))
    let perScreen = columns * rows

    let slot = index % perScreen
    let column = slot % columns
    let row = slot / columns

    // 남는 여백은 창 사이에 고르게 나눈다. 한 줄(칸)뿐이면 나눌 틈이 없다.
    let gapX = columns > 1
      ? (visible.width - CGFloat(columns) * width) / CGFloat(columns - 1) : 0
    let gapY = rows > 1
      ? (visible.height - CGFloat(rows) * height) / CGFloat(rows - 1) : 0

    // 화면을 다 채우고도 남으면 처음 자리부터 조금씩 밀어 쌓는다. 완전히 겹치면
    // 뒤에 있는 창을 찾을 수가 없다.
    let cascade = CGFloat(index / perScreen) * 28

    let x = visible.minX + CGFloat(column) * (width + gapX) + cascade
    // macOS 좌표는 아래에서 위로 자란다. 첫 줄이 화면 위쪽에 오도록 뒤집는다.
    let y = visible.maxY - height - CGFloat(row) * (height + gapY) - cascade

    return NSRect(x: x, y: y, width: width, height: height)
  }
}
