//
//  ShortCategoryView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 25/10/2022.
//
import Foundation
import SwiftUI
struct ShortCategoryView: View {
	let category: Category
	var body: some View {
		HStack {
			Text(category.name)
				.font(.headline)
				.foregroundColor(.primary)
			Spacer()
			Text("\(category.count)")
				.font(.subheadline)
				.foregroundColor(.secondary)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(category.name)
		.accessibilityValue("\(category.count) pozycji")
		.accessibilityHint("Dwukrotnie stuknij, aby otworzyć kategorię.")
		.accessibilityIdentifier("category.row.\(category.id)")
	}
}
