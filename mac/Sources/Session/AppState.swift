import Foundation

// 앱이 "지금 무엇이 켜져 있는가"의 유일한 출처. 값만 든다 — 강조·클릭 링·위젯·설정 창이 따로 기억하지 않는다.
// 값이 바뀌면 onChange가 불리고, AppDelegate가 함수 하나(applyState)로 모든 보임을 다시 정한다.
// 설정값(색·크기)은 여기 없다 — 그건 Settings가 든다.
@MainActor final class AppState {
    static let shared = AppState()

    var onChange: () -> Void = {}

    var spotOn = false { didSet { if spotOn != oldValue { onChange() } } }               // 강조를 켰는가 (F8)
    var drawOn = false { didSet { if drawOn != oldValue { onChange() } } }               // 드로잉 중인가 (F9)
    var widgetVisible = true { didSet { if widgetVisible != oldValue { onChange() } } }  // 위젯을 보이기로 했는가 (설정의 "위젯 표시")
    var settingsHiddenByDraw = false { didSet { if settingsHiddenByDraw != oldValue { onChange() } } } // 드로잉 때문에 숨겨 둔 설정 창이 있는가

    // 강조 원과 클릭 링이 화면에 보이는가 — 드로잉 중에는 강조와 함께 쉰다. 이 한 곳에서만 정한다.
    var highlightVisible: Bool { spotOn && !drawOn }
}
