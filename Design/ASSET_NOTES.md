# Asset notes

Magic Right's application icon was selected and supplied by the project owner for this repository. The menu bar icon was created specifically for Magic Right. Neither asset is sourced from a competing Finder-extension product.

## Application icon

- `AppIcon-generated-source.png` is the project-owner-selected 1254 px source with the connected black corner background and its dark edge fringe removed to genuine transparency.
- `AppIcon-master.png` is the reviewed 1024 px master used by the README and to export the Xcode AppIcon set.
- The direction is a friendly blue-and-white Finder helper holding a star wand, with the built-in “Right Click!” callout.
- The alpha conversion changes only the edge-connected outer background and halo; interior black text, facial details, and wand remain intact.
- The exported 16 px through 1024 px variants were checked together on a neutral background. Small variants preserve the character silhouette and color identity even though the callout is intentionally not readable at menu-scale sizes.

## Menu bar icon

- `SuperRightApp/Assets.xcassets/MenuBarIcon.imageset` is a monochrome macOS template asset.
- Its direction is a transparent mouse outline with the right button receiving the visual emphasis.
- It must remain legible in light, dark, and system-tinted menu bar appearances.

Keep future asset revisions in this repository with a source note, license note when applicable, and small-size visual check before release.
