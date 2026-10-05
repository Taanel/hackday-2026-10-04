# Friday interface

Use native SwiftUI controls, system typography and adaptive semantic colors. A persistent sidebar separates Assistent, Sprache, Computer, Home Assistant and Darstellung. Each page has a short heading, clear sections and progressive disclosure for diagnostics and credentials. Avoid a single long settings column and nested decorative cards.

The assistant page prioritizes one input and one response. Search results show titles, applications or parent paths, with an explicit open action when ambiguous. Status is compact; the overlay orb communicates activity without continuous idle animation.

Reserve Liquid Glass for the floating weather overview. On macOS 26 use native glassEffect; older systems use system material. Respect reduced transparency and motion. Weather values come directly from the forecast API, not generated prose, and include dates, place and source. The overview is dismissible and disappears when a new command begins.
