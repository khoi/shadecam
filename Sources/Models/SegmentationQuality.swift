enum SegmentationQuality: String, CaseIterable, Identifiable {
    case fast
    case balanced

    var id: Self {
        self
    }

    var name: String {
        rawValue.capitalized
    }
}
