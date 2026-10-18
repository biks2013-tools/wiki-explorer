import Foundation

/// The part of the window a tour step points at.
public enum TourTarget: String, CaseIterable, Sendable {
    case wikiList, pageList, searchField, pageBody, pageActions, relations, askButton, askPanel, graphToggle, graphView, addSourcesButton, checkSourcesButton
}

/// One step of the guided tour. A step without a target is shown in the middle of the window.
public struct TourStep: Sendable, Identifiable, Equatable {
    public let id: String
    public let target: TourTarget?
    public let title: String
    public let body: String
    /// A suggestion for something to try inside the highlighted area (clicks pass through it).
    public let tryIt: String?

    public init(id: String, target: TourTarget?, title: String, body: String, tryIt: String? = nil) {
        self.id = id; self.target = target; self.title = title; self.body = body; self.tryIt = tryIt
    }
}

public enum Tour {
    public static let steps: [TourStep] = [
        TourStep(id: "welcome", target: nil, title: "Welcome to Wiki Explorer",
                 body: "Wiki Explorer shows the wikis that llm-wiki builds from your documents: read their pages, follow the links between them, ask questions, and add new material. This tour takes about a minute.\n\nUse → and ← (or the buttons) to move, and Esc to stop. You can click inside the highlighted area to try things out."),
        TourStep(id: "wikis", target: .wikiList, title: "Your wikis",
                 body: "Every wiki registered with llm-wiki is listed here, with its format (HTML or MD) and number of pages. The star marks the current wiki of the command line.",
                 tryIt: "Select a wiki. Right-click it to show its folder in Finder or, for an HTML wiki, open its index in the browser. “New Wiki” (⇧⌘N) creates another."),
        TourStep(id: "pages", target: .pageList, title: "The pages",
                 body: "The pages of the selected wiki, grouped by kind: overview, entities, concepts, syntheses and answers, and one summary page per source document.",
                 tryIt: "Click a page, or move with ↑ and ↓. Right-click a page to open it in the browser or show it in Finder."),
        TourStep(id: "search", target: .searchField, title: "Search",
                 body: "Full-text search over the pages and the original sources of this wiki, or of all wikis (tick “Search all wikis” in the results). ⌘F jumps here.",
                 tryIt: "Type a word and pick a result."),
        TourStep(id: "page", target: .pageBody, title: "Reading a page",
                 body: "The page as the wiki has it, with its pictures. Coloured links lead to other pages and to the original documents; ⌘[ and ⌘] go back and forward."),
        TourStep(id: "actions", target: .pageActions, title: "Open outside the app",
                 body: "“Open in Browser” opens the page file of an HTML wiki in your web browser, where its links keep working. “Show in Finder” selects the page file in its folder; markdown pages also open in your editor.",
                 tryIt: "⇧⌘O opens in the browser, ⌥⌘R shows in Finder."),
        TourStep(id: "relations", target: .relations, title: "Links and sources",
                 body: "“Linked from” lists the pages that point here, “Links to” the pages this one points to, and “Sources” the documents it was written from.",
                 tryIt: "Click a source to open the original document; right-click it to show it in Finder."),
        TourStep(id: "graph", target: .graphToggle, title: "The graph",
                 body: "Switch between the open page and the graph of the whole wiki (⌘G): every page is a bubble, every link a thread, and pages of the same kind flow together into one coloured pool. ⇧⌘G shows the open page in the graph.",
                 tryIt: "Click Graph."),
        TourStep(id: "graph-explore", target: .graphView, title: "Exploring the graph",
                 body: "Drag the background to move around, pinch or scroll with ⌘ to zoom, and drag a bubble to pull its neighbours along. Click a page to light up its links; double-click (or ↩) opens it. “Neighbourhood” shows only the pages a few links away, and the legend hides or shows each kind.",
                 tryIt: "Hover over a bubble, then double-click one."),
        TourStep(id: "ask", target: .askPanel, title: "Ask a question",
                 body: "Ask in your own words. The answer is written from the wiki's pages and every claim links to the page it comes from; the pages used are listed under the answer. Ask this wiki, several, or all of them, and optionally save the answer as a new page.",
                 tryIt: "⌘K shows or hides this panel; ⌘↩ sends the question."),
        TourStep(id: "add", target: .addSourcesButton, title: "Add sources",
                 body: "Add documents (PDF, Word, PowerPoint, Excel, pictures, text) or web addresses. The language model reads them and writes or updates the wiki's pages. ⌘I opens it."),
        TourStep(id: "check", target: .checkSourcesButton, title: "Keep it current",
                 body: "Web pages and files added from outside the wiki are remembered by a fingerprint (SHA-256). Check them to see which changed since, and update the wiki from the new versions. ⌘U opens it."),
        TourStep(id: "done", target: nil, title: "That's the tour",
                 body: "The ⋯ button at the top right (or the Help menu) opens Keyboard Shortcuts (⌘/), the list of every key, and runs this tour again (⇧⌘T)."),
    ]
}
