// OfflineBanner.swift
// cashbox — Offline-Hinweisband (TSE-Signatur ausstehend)

import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.jakarta(12, weight: .semibold))
            Text("Offline — TSE-Signatur ausstehend")
                .font(.jakarta(12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange)
    }
}

#Preview {
    VStack {
        OfflineBanner()
        Spacer()
    }
}
