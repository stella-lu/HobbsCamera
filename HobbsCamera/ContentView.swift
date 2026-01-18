import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("Library")
        }
    }
}

struct LibraryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ContentUnavailableView(
                "No photos yet",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Photos you take in HobbsCamera stay only inside this app unless you export them.")
            )

            NavigationLink {
                CameraView()
            } label: {
                Label("Open Camera", systemImage: "camera")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
    }
}

#Preview {
    ContentView()
}
