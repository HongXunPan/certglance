import SwiftUI

struct CertificateCountdownGauge: View {
  let snapshot: CertificateSnapshot?
  let date: Date
  let size: CGFloat

  private var severity: CertificateSeverity {
    snapshot?.severity(at: date) ?? .unchecked
  }

  var body: some View {
    Group {
      if let snapshot, snapshot.checkState == .trusted,
        let remaining = snapshot.daysRemaining(at: date)
      {
        Gauge(value: Double(min(30, max(0, remaining))), in: 0...30) {
          EmptyView()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(severity.tint)
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
        .accessibilityHint("圆环表示距离到期日在 30 天窗口内的位置；超过 30 天时显示满环")
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
