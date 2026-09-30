import Testing

@testable import loom

@Test func desktopPlacesIconsInResponsiveTerminalCellGrid() {
    var desktop = Desktop(
        viewport: Rect(width: 80, height: 20),
        icons: [
            DesktopIcon(id: "chat", label: "CHAT", symbol: "◇", launchTarget: "chat"),
            DesktopIcon(id: "code", label: "CODE", symbol: "□", launchTarget: "code"),
            DesktopIcon(id: "files", label: "FILES", symbol: "▣", launchTarget: "files"),
        ])
    #expect(desktop.iconArea(for: "chat") == Rect(x: 2, y: 1, width: 16, height: 4))
    #expect(desktop.iconArea(for: "code") == Rect(x: 21, y: 1, width: 16, height: 4))
    #expect(desktop.iconArea(for: "files") == Rect(x: 40, y: 1, width: 16, height: 4))
    #expect(desktop.iconArea(for: "missing") == nil)
    #expect(desktop.icon(at: Point(x: 22, y: 2))?.id == "code")
    #expect(desktop.icon(at: Point(x: 19, y: 2)) == nil)

    desktop.resizeViewport(to: Rect(width: 20, height: 20))
    #expect(desktop.iconArea(for: "chat") == Rect(x: 2, y: 1, width: 16, height: 4))
    #expect(desktop.iconArea(for: "code") == Rect(x: 2, y: 6, width: 16, height: 4))
    #expect(desktop.iconArea(for: "files") == Rect(x: 2, y: 11, width: 16, height: 4))
}

@Test func desktopMouseSelectsLaunchesAndClearsHover() {
    var desktop = Desktop(
        viewport: Rect(width: 50, height: 12),
        icons: [
            DesktopIcon(id: "chat", label: "CHAT", symbol: "◇", launchTarget: "chat"),
            DesktopIcon(id: "code", label: "CODE", symbol: "□", launchTarget: "code-viewer"),
        ])
    let codePoint = Point(x: 22, y: 2)
    #expect(desktop.handleMouse(MouseEvent(kind: .move, position: codePoint)) == nil)
    #expect(desktop.hoveredIconID == "code")
    #expect(desktop.selectedIconID == nil)
    #expect(desktop.handleMouse(MouseEvent(kind: .down, position: codePoint)) == "code-viewer")
    #expect(desktop.selectedIconID == "code")
    #expect(desktop.activateSelected() == "code-viewer")
    #expect(desktop.handleMouse(MouseEvent(kind: .up, position: codePoint)) == nil)

    desktop.clearHover()
    #expect(desktop.hoveredIconID == nil)
    #expect(desktop.selectedIconID == "code")
    #expect(desktop.handleMouse(MouseEvent(kind: .down, position: Point(x: 0, y: 0))) == nil)
    #expect(desktop.selectedIconID == nil)
    #expect(desktop.hoveredIconID == nil)
    #expect(desktop.activateSelected() == nil)
}

@Test func desktopKeyboardSelectionWrapsAndRemainsVisibleAfterResize() {
    let icons = (0..<5).map { index in
        DesktopIcon(id: "icon-\(index)", label: "ICON \(index)", symbol: "□", launchTarget: "target-\(index)")
    }
    var desktop = Desktop(viewport: Rect(width: 80, height: 20), icons: icons)
    desktop.moveSelection(by: -1)
    #expect(desktop.selectedIconID == "icon-4")
    #expect(desktop.activateSelected() == "target-4")
    desktop.moveSelection(by: 1)
    #expect(desktop.selectedIconID == "icon-0")
    desktop.moveSelection(by: -1)
    desktop.resizeViewport(to: Rect(width: 20, height: 10))
    #expect(desktop.selectedIconID == "icon-4")
    #expect(desktop.iconArea(for: "icon-4") == Rect(x: 2, y: 6, width: 16, height: 4))
    #expect(desktop.iconArea(for: "icon-0") == nil)

    desktop.setIcons(Array(icons.dropFirst()))
    #expect(desktop.selectedIconID == "icon-4")
    desktop.setIcons(Array(icons.dropLast()))
    #expect(desktop.selectedIconID == nil)
    desktop.moveSelection(by: 1)
    #expect(desktop.selectedIconID == "icon-0")
    desktop.clearSelection()
    #expect(desktop.selectedIconID == nil)
}

@Test func desktopRendersLabelsAndDistinctSelectionAndHoverStyles() {
    var desktop = Desktop(
        viewport: Rect(width: 50, height: 12),
        icons: [
            DesktopIcon(id: "chat", label: "CHAT", symbol: "◇", launchTarget: "chat"),
            DesktopIcon(id: "code", label: "CODE", symbol: "□", launchTarget: "code"),
        ])
    desktop.style = Style(foreground: .indexed(1), background: .indexed(0))
    desktop.selectionStyle = Style(foreground: .indexed(2), background: .indexed(0), bold: true)
    desktop.hoverStyle = Style(foreground: .indexed(3), background: .indexed(0), underlined: true)
    desktop.moveSelection(by: 1)
    _ = desktop.handleMouse(MouseEvent(kind: .move, position: Point(x: 22, y: 2)))
    var buffer = Buffer(width: 50, height: 12)
    desktop.render(in: desktop.viewport, buffer: &buffer)

    #expect(buffer[9, 1].symbol == "◇")
    #expect(buffer[8, 3].symbol == "C")
    #expect(buffer[9, 1].style.foreground == .indexed(2))
    #expect(buffer[28, 1].symbol == "□")
    #expect(buffer[27, 3].symbol == "C")
    #expect(buffer[28, 1].style.foreground == .indexed(3))
    #expect(buffer[28, 1].style.underlined)
}

@Test func desktopKeepsTinyAndEmptyViewportsSafe() {
    var desktop = Desktop(
        viewport: Rect(width: 3, height: 1),
        icons: [DesktopIcon(id: "chat", label: "CHAT", symbol: "◇", launchTarget: "chat")])
    #expect(desktop.iconArea(for: "chat") == Rect(x: 1, y: 0, width: 1, height: 1))
    var buffer = Buffer(width: 3, height: 1)
    desktop.render(in: desktop.viewport, buffer: &buffer)
    #expect(buffer[1, 0].symbol == "C")
    desktop.resizeViewport(to: Rect(width: 0, height: 0))
    #expect(desktop.iconArea(for: "chat") == nil)
    #expect(desktop.icon(at: Point(x: 0, y: 0)) == nil)
    #expect(desktop.handleMouse(MouseEvent(kind: .down, position: Point(x: 0, y: 0))) == nil)
}
