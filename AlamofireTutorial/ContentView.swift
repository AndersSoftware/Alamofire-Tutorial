import SwiftUI

struct ContentView: View {
    @State private var message = "Hello, world!"
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(message)
            
            Button("Fetch Data") {
                fetchData()
            }
        }
        .padding()
    }
    
    private func fetchData() {
        APIManager.shared.execute(
            serverUrl: "https://jsonplaceholder.typicode.com/posts",
            httpBody: nil,
            success: { response in
                DispatchQueue.main.async {
                    self.message = response.value ?? "No data"
                }
            },
            failure: { error in
                DispatchQueue.main.async {
                    self.message = "Error occurred"
                }
            }
        )
    }
}
