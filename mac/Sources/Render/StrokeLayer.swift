import AppKit

// ================= 긋는 중인 획 전용 그림 (설계도 7절, D4) =================
// 긋는 획은 여기에 **불투명하게** 쌓고, 판에 합칠 때 획 진하기를 곱해 얹는다.
// 그러면 반투명 획도 새 토막 자리만 다시 그리면 되고(지나온 자리 전체를 다시 그리지 않는다),
// 같은 자리를 여러 번 지나가도 이음매가 진해지지 않는다.
// 화면(InkView) 하나에 하나씩, 첫 획을 긋는 순간 만들고 드로잉을 끄면 버린다.
final class StrokeLayer {
    let ctx: CGContext
    let image: CGImage      // 그림 메모리를 그대로 들여다본다 — 획을 더할 때마다 복사본을 만들지 않는다
    private let origin: CGPoint
    private let size: CGSize

    // size·origin: 이 화면의 크기(포인트)와 전역 좌표 원점
    init?(size: CGSize, scale: CGFloat, origin: CGPoint) {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = c.data else { return nil }
        let rowBytes = c.bytesPerRow
        // 그림 자료는 컨텍스트가 들고 있으므로 해제하지 않는다 (이 클래스가 컨텍스트와 함께 산다)
        guard let provider = CGDataProvider(dataInfo: nil, data: data, size: rowBytes * h, releaseData: { _, _, _ in }),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: space,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: -origin.x, y: -origin.y)
        ctx = c; image = img; self.origin = origin; self.size = size
    }

    var frame: CGRect { CGRect(origin: origin, size: size) }

    func clear(_ global: CGRect) {
        let r = global.intersection(frame)
        if !r.isNull && !r.isEmpty { ctx.clear(r) }
    }

    // 획 하나(또는 한 토막)를 불투명하게 더한다
    func add(_ item: InkItem) {
        guard item.bounds.intersects(frame) else { return }
        var opaque = item
        opaque.alpha = 1
        renderInk(opaque, in: ctx)
    }
}
