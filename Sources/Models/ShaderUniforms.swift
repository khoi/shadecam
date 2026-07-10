protocol ShaderFloat4Storage {
    static var count: Int { get }
}

extension ShaderFloat4Storage {
    subscript(index: Int) -> SIMD4<Float> {
        get {
            precondition((0..<Self.count).contains(index))
            return withUnsafeBytes(of: self) {
                $0.load(fromByteOffset: index * MemoryLayout<SIMD4<Float>>.stride, as: SIMD4<Float>.self)
            }
        }
        set {
            precondition((0..<Self.count).contains(index))
            withUnsafeMutableBytes(of: &self) {
                $0.storeBytes(
                    of: newValue,
                    toByteOffset: index * MemoryLayout<SIMD4<Float>>.stride,
                    as: SIMD4<Float>.self
                )
            }
        }
    }
}

struct ShaderEventUniforms: ShaderFloat4Storage, Sendable {
    static let count = 8

    private var storage = SIMD32<Float>.zero
}

struct ShaderHandUniforms: ShaderFloat4Storage, Sendable {
    static let count = 42

    private var storage0 = SIMD64<Float>.zero
    private var storage1 = SIMD64<Float>.zero
    private var storage2 = SIMD32<Float>.zero
    private var storage3 = SIMD8<Float>.zero

    subscript(hand: Int, joint: Int) -> SIMD4<Float> {
        get {
            precondition((0..<2).contains(hand) && (0..<21).contains(joint))
            return self[hand * 21 + joint]
        }
        set {
            precondition((0..<2).contains(hand) && (0..<21).contains(joint))
            self[hand * 21 + joint] = newValue
        }
    }
}

struct ShaderBodyUniforms: ShaderFloat4Storage, Sendable {
    static let count = 19

    private var storage0 = SIMD64<Float>.zero
    private var storage1 = SIMD8<Float>.zero
    private var storage2 = SIMD4<Float>.zero
}

struct ShaderUniforms: Sendable {
    var iMouse: SIMD4<Float>
    var iFaceRect: SIMD4<Float>
    var iExpression: SIMD4<Float>
    var iAudio: SIMD4<Float>
    var iEvents: ShaderEventUniforms
    var iHands: ShaderHandUniforms
    var iBody: ShaderBodyUniforms
    var iResolution: SIMD2<Float>
    var iTime: Float
    var iTimeDelta: Float
    var iFrame: UInt32

    init(
        iMouse: SIMD4<Float>,
        iFaceRect: SIMD4<Float>,
        iExpression: SIMD4<Float> = .zero,
        iAudio: SIMD4<Float> = .zero,
        iEvents: ShaderEventUniforms = .init(),
        iHands: ShaderHandUniforms = .init(),
        iBody: ShaderBodyUniforms = .init(),
        iResolution: SIMD2<Float>,
        iTime: Float,
        iTimeDelta: Float,
        iFrame: UInt32
    ) {
        self.iMouse = iMouse
        self.iFaceRect = iFaceRect
        self.iExpression = iExpression
        self.iAudio = iAudio
        self.iEvents = iEvents
        self.iHands = iHands
        self.iBody = iBody
        self.iResolution = iResolution
        self.iTime = iTime
        self.iTimeDelta = iTimeDelta
        self.iFrame = iFrame
    }
}
