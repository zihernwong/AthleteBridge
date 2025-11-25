// FirestoreService.swift
// Backwards compatibility wrapper - delegate to FirestoreManager

import Foundation

// Map the old name `FirestoreService` to the canonical `FirestoreManager` used across the app.
// This keeps any remaining @EnvironmentObject(FirestoreService) references working while
// ensuring there is only a single implementation (FirestoreManager) in the codebase.

typealias FirestoreService = FirestoreManager
