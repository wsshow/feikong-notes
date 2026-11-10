# Local outline icons

The app vendors a subset of Lucide at revision
`23f9abc4ed0146cffededd3d7f94c1018bfdf693`. See [LICENSE](LICENSE) for the Lucide
ISC and inherited Feather MIT notices; these are also registered in Flutter's
license registry.

`tool/generate_app_icons.py` defines the semantic-token mapping, converts the
upstream SVG primitives into path data, and prints an `apply_patch` patch for
`lib/widgets/app_icon_catalog.dart` and the license. It does not write files.
The custom settings, tag, selected-state, and chat-composer paths are defined
separately in the generator. Review and apply its output, then run `dart format`
on the catalog.

`AppIcon` draws the paths locally at a consistent 1.8-unit stroke with rounded
caps and joins. Paths are parsed once on first use and cached. No network
requests, SVG document loading, animation, or image decoding is needed at
runtime. Material `Icons` values are semantic identifiers only.

`AppIcon.chatComposer` selects the camera, circled voice, and circled plus
artwork drawn from the supplied composer reference, using a 2-unit stroke and
the same theme, disabled-color, and semantics handling. These variants only
apply to the local assistant input bar; standard icons and the upstream
licenses are unchanged.

`test/app_icon_test.dart` checks that all application tokens are mapped, every
path paints successfully, and navigation, sizing, colors, and semantics work.
