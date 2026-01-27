import SwiftUI

struct AppMenuModifier: ViewModifier {
	@State private var shouldShowFavorites = false

	func body(content: Content) -> some View {
		content
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Menu {
						Button {
							shouldShowFavorites = true
						} label: {
							Label("Ulubione", systemImage: "star.fill")
						}
						.accessibilityIdentifier("app.menu.favorites")
					} label: {
						Image(systemName: "line.3.horizontal")
					}
					.accessibilityLabel("Menu")
					.accessibilityHint("Otwiera menu aplikacji.")
					.accessibilityIdentifier("app.menu")
				}
			}
			.sheet(isPresented: $shouldShowFavorites) {
				FavoritesSheet()
			}
	}
}

extension View {
	func withAppMenu() -> some View {
		modifier(AppMenuModifier())
	}
}

private struct FavoritesSheet: View {
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			FavoritesView()
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Zamknij") {
							dismiss()
						}
						.accessibilityIdentifier("favorites.close")
					}
				}
		}
	}
}

