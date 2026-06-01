//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CompoundDesignTokens
import SwiftUI

// MARK: - Brand Palette

// ┌─────────────────────┬───────────┬───────────┐
// │ Role                │ Light     │ Dark      │
// ├─────────────────────┼───────────┼───────────┤
// │ deep-forest         │ #2F3A2E   │ #1E2620   │
// │ moss-green          │ #4A5B3E   │ #2A332B   │
// │ olive               │ #7A7F52   │ #3F4A3F   │
// │ warm-sand           │ #B2A77A   │ #B2A77A   │
// │ light-cream (bg)    │ #E7E1CF   │ #E7E1CF   │
// │ text-dark           │ #1A1A1A   │ #E7E1CF   │
// │ text-gray           │ #666666   │ #A8A395   │
// │ white (on-solid)    │ #FFFFFF   │ #121612   │
// │ divider             │ #D5CFBD   │ #3A433A   │
// └─────────────────────┴───────────┴───────────┘

private extension Color {
    // MARK: Hex helper

    /// Creates a `Color` from a CSS-style hex string such as `"#2F3A2E"`.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    // MARK: Adaptive colour helper

    /// Returns a `Color` that resolves to `light` in light mode and `dark` in dark mode.
    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }

    // MARK: Brand tokens (adaptive)

    /// Primary surface / solid button – darkest brand green.
    static let brandDeepForest   = adaptive(light: "#2F3A2E", dark: "#1E2620")
    /// Accent / secondary action – mid brand green.
    static let brandMossGreen    = adaptive(light: "#4A5B3E", dark: "#2A332B")
    /// Tertiary icon / subtle highlight – olive green.
    static let brandOlive        = adaptive(light: "#7A7F52", dark: "#3F4A3F")
    /// Warm sand – same in both modes (decorative highlights).
    static let brandWarmSand     = adaptive(light: "#B2A77A", dark: "#B2A77A")
    /// Page/canvas background – cream in light, deep green-black in dark.
    static let brandCanvas       = adaptive(light: "#E7E1CF", dark: "#121612")
    /// Card / elevated surface background.
    static let brandCard         = adaptive(light: "#F2EDE0", dark: "#1E2620")
    /// Chip / pill / subtle secondary background.
    static let brandChip         = adaptive(light: "#D5CFBD", dark: "#2A332B")
    /// Primary text – near-black in light, cream in dark.
    static let brandTextPrimary  = adaptive(light: "#1A1A1A", dark: "#E7E1CF")
    /// Secondary / placeholder text.
    static let brandTextSecondary = adaptive(light: "#666666", dark: "#A8A395")
    /// Disabled text – faded secondary.
    static let brandTextDisabled = adaptive(light: "#999999", dark: "#5A5F5A")
    /// Text on solid coloured surfaces (buttons, badges).
    static let brandTextOnSolid  = adaptive(light: "#FFFFFF", dark: "#E7E1CF")
    /// Divider / border.
    static let brandDivider      = adaptive(light: "#D5CFBD", dark: "#3A433A")
    /// Subtle disabled background.
    static let brandDisabledBg   = adaptive(light: "#E8E4D8", dark: "#2A2E2A")
}

// MARK: - Theme Application

@MainActor
enum AppTheme {
    /// Applies brand colour overrides to `Color.compound`.
    /// Call once at app launch before any UI is presented.
    static func apply() {
        let c = Color.compound

        // ── Canvas / Page backgrounds ─────────────────────────────────────────
        // Main scrollable background
        c.override(\.bgCanvasDefault,              with: .brandCanvas)
        c.override(\.bgCanvasDisabled,             with: .brandDisabledBg)

        // ── Card / Elevated surface backgrounds ───────────────────────────────
        // List rows, message bubbles, sheets, form cells
        c.override(\.bgSubtleSecondary,            with: .brandChip)       // cells / rows
        c.override(\.bgSubtlePrimary,              with: .brandCard)       // elevated cards

        // ── Action / Button backgrounds ───────────────────────────────────────
        c.override(\.bgActionPrimaryRest,          with: .brandDeepForest)
        c.override(\.bgActionPrimaryHovered,       with: .brandMossGreen)
        c.override(\.bgActionPrimaryPressed,       with: .brandDeepForest)
        c.override(\.bgActionPrimaryDisabled,      with: .brandDisabledBg)

        c.override(\.bgActionSecondaryRest,        with: .brandCanvas)
        c.override(\.bgActionTertiaryRest,         with: .brandCanvas)
        c.override(\.bgActionTertiarySelected,     with: .brandChip)

        // ── Accent / Selected state ───────────────────────────────────────────
        c.override(\.bgAccentRest,                 with: .brandMossGreen)
        c.override(\.bgAccentHovered,              with: .brandOlive)
        c.override(\.bgAccentPressed,              with: .brandDeepForest)
        c.override(\.bgAccentSelected,             with: Color.brandWarmSand.opacity(0.25))

        // ── Icon colours ──────────────────────────────────────────────────────
        c.override(\.iconPrimary,                  with: .brandTextPrimary)
        c.override(\.iconSecondary,                with: .brandMossGreen)
        c.override(\.iconTertiary,                 with: .brandOlive)
        c.override(\.iconQuaternary,               with: .brandTextSecondary)
        c.override(\.iconAccentPrimary,            with: .brandMossGreen)
        c.override(\.iconAccentTertiary,           with: .brandOlive)
        c.override(\.iconOnSolidPrimary,           with: .brandTextOnSolid)
        c.override(\.iconDisabled,                 with: .brandTextDisabled)

        // ── Text colours ──────────────────────────────────────────────────────
        c.override(\.textPrimary,                  with: .brandTextPrimary)
        c.override(\.textSecondary,                with: .brandTextSecondary)
        c.override(\.textActionPrimary,            with: .brandTextPrimary)
        c.override(\.textActionAccent,             with: .brandMossGreen)
        c.override(\.textOnSolidPrimary,           with: .brandTextOnSolid)
        c.override(\.textDisabled,                 with: .brandTextDisabled)
        c.override(\.textBadgeAccent,              with: .brandWarmSand)

        // ── Border / Divider colours ──────────────────────────────────────────
        c.override(\.borderDisabled,               with: .brandDivider)
        c.override(\.borderInteractivePrimary,     with: .brandOlive)
        c.override(\.borderInteractiveSecondary,   with: .brandDivider)
        c.override(\.borderInteractiveHovered,     with: .brandMossGreen)
        c.override(\.borderAccentSubtle,           with: .brandWarmSand)
    }
}
