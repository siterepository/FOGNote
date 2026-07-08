import SwiftUI
import SwiftData

/// Obsidian-style backlink graph of [[note links]], laid out with a small
/// force simulation and drawn on Canvas. Click a node to open the note.
struct GraphViewWindow: View {
    @Environment(AppState.self) private var appState
    @Query private var allNotes: [Note]

    struct Node: Identifiable {
        let id: PersistentIdentifier
        let title: String
        var position: CGPoint = .zero
        var velocity: CGVector = .zero
        var degree: Int = 0
    }

    @State private var nodes: [Node] = []
    @State private var edges: [(Int, Int)] = []
    @State private var hoveredID: PersistentIdentifier?

    var body: some View {
        Group {
            if nodes.isEmpty {
                ContentUnavailableView(
                    "No Links Yet",
                    systemImage: "circle.hexagongrid",
                    description: Text("Type [[Note Title]] inside a note to link it. Linked notes appear here as a graph.")
                )
            } else {
                GeometryReader { proxy in
                    canvas(size: proxy.size)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .navigationTitle("Note Graph")
        .onAppear(perform: buildGraph)
    }

    private func canvas(size: CGSize) -> some View {
        Canvas { context, _ in
            for (a, b) in edges {
                var path = Path()
                path.move(to: nodes[a].position)
                path.addLine(to: nodes[b].position)
                context.stroke(path, with: .color(Color.fogAccent.opacity(0.35)), lineWidth: 1)
            }
            for node in nodes {
                let radius = CGFloat(6 + min(node.degree, 6) * 2)
                let rect = CGRect(
                    x: node.position.x - radius, y: node.position.y - radius,
                    width: radius * 2, height: radius * 2
                )
                let isHovered = node.id == hoveredID
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(isHovered ? Color.fogWarn : Color.fogAccent)
                )
                context.draw(
                    Text(node.title.isEmpty ? "Untitled" : node.title)
                        .font(.system(size: isHovered ? 11 : 9))
                        .foregroundStyle(isHovered ? Color.primary : Color.secondary),
                    at: CGPoint(x: node.position.x, y: node.position.y + radius + 9)
                )
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hoveredID = nodes.first { hypot($0.position.x - point.x, $0.position.y - point.y) < 16 }?.id
            case .ended:
                hoveredID = nil
            }
        }
        .onTapGesture { point in
            if let node = nodes.first(where: { hypot($0.position.x - point.x, $0.position.y - point.y) < 16 }) {
                appState.sidebarSelection = .allNotes
                appState.selectedNoteID = node.id
                NSApp.windows.first { $0.title == "FOGNote" }?.makeKeyAndOrderFront(nil)
            }
        }
        .onAppear { layout(in: size) }
        .onChange(of: size) { layout(in: size) }
    }

    private func buildGraph() {
        let active = allNotes.filter { !$0.isTrashed && !$0.isTemplate }
        var titleIndex: [String: Int] = [:]
        var built: [Node] = []
        for note in active {
            titleIndex[note.title.lowercased()] = built.count
            built.append(Node(id: note.persistentModelID, title: note.title))
        }
        var builtEdges: [(Int, Int)] = []
        for (sourceIndex, note) in active.enumerated() {
            for target in NoteInfoView.linkTitles(in: note.bodyPlainText) {
                if let targetIndex = titleIndex[target.lowercased()], targetIndex != sourceIndex {
                    builtEdges.append((sourceIndex, targetIndex))
                    built[sourceIndex].degree += 1
                    built[targetIndex].degree += 1
                }
            }
        }
        // Only show connected notes.
        let connected = Set(builtEdges.flatMap { [$0.0, $0.1] })
        var remap: [Int: Int] = [:]
        var filtered: [Node] = []
        for index in connected.sorted() {
            remap[index] = filtered.count
            filtered.append(built[index])
        }
        nodes = filtered
        edges = builtEdges.compactMap { edge in
            guard let a = remap[edge.0], let b = remap[edge.1] else { return nil }
            return (a, b)
        }
    }

    /// Simple spring/repulsion layout, run to convergence once (no animation
    /// loop needed for a personal graph's size).
    private func layout(in size: CGSize) {
        guard !nodes.isEmpty, size.width > 50 else { return }
        var localNodes = nodes
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Seed on a circle for determinism.
        for index in localNodes.indices {
            let angle = 2 * .pi * Double(index) / Double(localNodes.count)
            localNodes[index].position = CGPoint(
                x: center.x + Foundation.cos(angle) * min(size.width, size.height) * 0.3,
                y: center.y + Foundation.sin(angle) * min(size.width, size.height) * 0.3
            )
        }
        let repulsion: CGFloat = 6000
        let springLength: CGFloat = 110
        let springK: CGFloat = 0.02
        for _ in 0..<250 {
            var forces = Array(repeating: CGVector.zero, count: localNodes.count)
            for i in localNodes.indices {
                for j in localNodes.indices where j > i {
                    let dx = localNodes[j].position.x - localNodes[i].position.x
                    let dy = localNodes[j].position.y - localNodes[i].position.y
                    let distSq = max(dx * dx + dy * dy, 25)
                    let dist = distSq.squareRoot()
                    let force = repulsion / distSq
                    let fx = force * dx / dist, fy = force * dy / dist
                    forces[i].dx -= fx; forces[i].dy -= fy
                    forces[j].dx += fx; forces[j].dy += fy
                }
            }
            for (a, b) in edges {
                let dx = localNodes[b].position.x - localNodes[a].position.x
                let dy = localNodes[b].position.y - localNodes[a].position.y
                let dist = max(hypot(dx, dy), 1)
                let force = springK * (dist - springLength)
                let fx = force * dx / dist, fy = force * dy / dist
                forces[a].dx += fx; forces[a].dy += fy
                forces[b].dx -= fx; forces[b].dy -= fy
            }
            for index in localNodes.indices {
                // Gentle pull to center keeps disconnected clusters on screen.
                forces[index].dx += (center.x - localNodes[index].position.x) * 0.005
                forces[index].dy += (center.y - localNodes[index].position.y) * 0.005
                localNodes[index].position.x += max(-8, min(8, forces[index].dx))
                localNodes[index].position.y += max(-8, min(8, forces[index].dy))
                localNodes[index].position.x = max(30, min(size.width - 30, localNodes[index].position.x))
                localNodes[index].position.y = max(30, min(size.height - 30, localNodes[index].position.y))
            }
        }
        nodes = localNodes
    }
}
