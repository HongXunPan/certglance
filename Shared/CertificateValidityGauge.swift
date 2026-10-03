import SwiftUI

struct CertificateValidityGauge: View {
  let snapshot: CertificateSnapshot?
  let date: Date
  let size: CGFloat

  private var severity: CertificateSeverity {
    snapshot?.severity(at: date) ?? .unchecked
  }

  var body: some View {
    Group {
      if let snapshot, snapshot.checkState == .trusted,
        let remaining = snapshot.daysRemaining(at: date),
        let fraction = snapshot.validityRemainingFraction(at: date)
      {
        Gauge(value: fraction, in: 0...1) {
          EmptyView()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.accentColor)
        .overlay {
          VStack(spacing: 0) {
            Text(remaining <= 0 ? "0" : "\(remaining)")
              .font(.system(size: size * 0.27, weight: .bold, design: .rounded).monospacedDigit())
            Text("天")
              .font(.system(size: size * 0.13, weight: .medium))
          }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining <= 0 ? "证书已过期" : "证书剩余 \(remaining) 天")
        .accessibilityHint("圆环表示证书完整有效期中剩余的比例")
      } else if let snapshot, snapshot.checkState == .trusted,
        let remaining = snapshot.daysRemaining(at: date)
      {
        VStack(spacing: 1) {
          Text(remaining <= 0 ? "0" : "\(remaining)")
            .font(.system(size: size * 0.27, weight: .bold, design: .rounded).monospacedDigit())
          Text("天")
            .font(.system(size: size * 0.13, weight: .medium))
        }
        .frame(width: size, height: size)
        .background(.quaternary, in: Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining <= 0 ? "证书已过期，有效期比例待更新" : "证书剩余 \(remaining) 天，有效期比例待更新")
      } else {
        Image(systemName: severity.symbol)
          .font(.system(size: size * 0.38, weight: .semibold))
          .foregroundStyle(severity.tint)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.quaternary, in: Circle())
          .accessibilityLabel(severity.label)
      }
    }
    .frame(width: size, height: size)
  }
}
