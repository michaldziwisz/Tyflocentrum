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
							.accessibilityHidden(true)
					}
					.accessibilityLabel("Menu")
					.accessibilityHint("Otwiera menu aplikacji.")
					.accessibilityIdentifier("app.menu")
				}
			}
			.background(
				NavigationLink(destination: FavoritesView(), isActive: $shouldShowFavorites) {
					EmptyView()
				}
				.hidden()
			)
	}
}

extension View {
	func withAppMenu() -> some View {
		modifier(AppMenuModifier())
	}
}
