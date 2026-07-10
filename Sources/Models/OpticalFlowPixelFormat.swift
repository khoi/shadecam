import CoreVideo
import Metal

enum OpticalFlowPixelFormat {
    case float16
    case float32

    init?(cvPixelFormat: OSType) {
        switch cvPixelFormat {
        case kCVPixelFormatType_TwoComponent16Half: self = .float16
        case kCVPixelFormatType_TwoComponent32Float: self = .float32
        default: return nil
        }
    }

    var cvPixelFormat: OSType {
        switch self {
        case .float16: kCVPixelFormatType_TwoComponent16Half
        case .float32: kCVPixelFormatType_TwoComponent32Float
        }
    }

    var metalPixelFormat: MTLPixelFormat {
        switch self {
        case .float16: .rg16Float
        case .float32: .rg32Float
        }
    }

    var bytesPerPixel: Int {
        switch self {
        case .float16: 4
        case .float32: 8
        }
    }
}
