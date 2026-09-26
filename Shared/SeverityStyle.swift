import SwiftUI

extension CertificateSeverity {
  var tint: Color {
    switch self {
    case .expired, .checkFailed, .untrusted, .critical: return .red
    case .soon: return .orange
    case .watch: return .orange
    case .healthy: return .green
    case .unchecked: return .secondary
    }
  }
}
