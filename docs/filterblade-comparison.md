# FilterBlade feature review

Reviewed the live [PoE 1 FilterBlade site](https://www.filterblade.xyz/?game=Poe1) on November 12, 2026: Start, Overview, Customize (including currency tier lists), Simulate, Themes, Advanced, campaign auto-adjust and the anonymous export flow. Login, saved cloud content and paid background services were not exercised. That review preceded the fork's update to NeverSink 8.21.0a for 3.30.

This is a comparison, not a claim of FilterBlade parity. Its website, customizer definitions, economy service and cloud systems are separate from the MIT-licensed NeverSink filter files.

| FilterBlade capability | Our fork after this redesign | Remaining work |
| --- | --- | --- |
| Guided start page | Campaign, early mapping and endgame cards | More character-specific starter presets |
| Strictness presets | Seven pinned NeverSink levels | Updated through fork releases |
| Game modes | Normal and Ruthless | No PoE 2 support; Softcore/Hardcore economy tiers are separate work |
| Build auto-adjust | Reads saved crafts, planned gear, gems, resources and Atlas plans | More stage-specific vendor recipes |
| Campaign weapon selection | Eighteen native families, equipped-family selection and progressive base-level windows | More character-specific class presets |
| Campaign armour selection | Armour/evasion/ES combinations and Ward, with native base art | More starter presets |
| Campaign vendor rares | Base preset rules plus level-bounded linked-colour, six-socket/link and quality-gem policies | More vendor recipes; no proceeds model |
| Endgame build adjustment | Exact saved targets and Atlas pickups | Trade/SSF-specific policies |
| Item overview and colour examples | Live scene using the compiled filter | Explanatory galleries for every item family |
| Hierarchical customizer | Category sidebar, search, personal/base/policy scope and collapsible compiled sections | Human-edited subcategories |
| Base-filter rule browsing | Full parsed preset catalogue with styled examples | Human-edited descriptions for every source rule |
| Category coverage | Sixteen families including cards, flasks, tinctures, jewels, recipes and special currency | Deeper nested sections |
| Rule editing | Stable override identities across catalogue, matched rules and structure; provable shadowing diagnostics | Broader predicate-overlap analysis |
| Show/hide toggles | Personal enable/disable; action editor | Per-category inclusion policies |
| Rule order | Select with one click, edit with a double-click, and drag personal rules or use arrows or Alt+Up/Down relative to visible rules | Base-filter rule order remains pinned |
| Currency tier lists | Custom/preset tier browsing, exact item movement, drag/drop, tier creation/removal/order | Economy-driven automatic reassignment |
| Stacked currency tiering | Existing stack conditions are preserved and editable | Uniform/adjusted stacked-tier controls |
| Economy-based tiers | Pinned NeverSink snapshot | Live pricing, outlier handling and recalculation |
| Global search | Searches names and raw condition/action text | Cross-page command palette |
| Loot generator | Deterministic example scenes, including cards and essences, and build-target samples | Representative drop distributions and encounter presets |
| Hidden-drop display | Simulator toggle and searchable scene review with shown, minimal, hidden and uncertain counts | Counts describe examples, not drop rates |
| Click a simulated item | Explains results and opens matched blocks for editing | More unknown-property guidance |
| Item configuration | Editable properties and native game-clipboard import | Hidden identities are never inferred |
| Item history | Session history plus persistent named sets of exact sample properties | More encounter sample presets |
| Generator level settings | Shared area/item-level controls and a tiered-gear comparison scene | More encounter-specific samples |
| Expensive-drop generation | Currency scene and exact custom samples | A separate expensive-item mode based on verified tiers |
| Preview background | Stone, dark and light scenes | Additional environments |
| Individual colours | Colour wheel, brightness and opacity controls, swatches, exact RGBA input and live preview | More built-in palette presets |
| Font size | Live size slider | Additional typography presets |
| Alert sound selection | All 16 numbered IDs plus silence; custom references preserved | Exact game audio preview and custom sound pack management |
| Minimap icons | All twelve shapes, colour/size selection and native geometry previews | Exact game-texture rendering |
| Themes | Generated-target palettes, personal restyling, whole-filter decorators and named appearance snapshots | More built-in themes |
| Global one-click edits | Reversible whole-filter and category font/colour, alert identity/volume, icon and beam controls | More saved appearance presets |
| Shared modules | Portable named snapshots, cross-profile copy and explicit updates | Public discovery and module dependency graphs |
| Review changes | Rule/item review, file-level compiled/base comparisons, provable conflicts and undo/redo | Richer predicate overlap analysis |
| Filter structure | Compiled section/family tree, priority conflicts, exact block text, editing and file comparison | More source-rule descriptions |
| Test local filter | Original imported text retained; simulator evaluates it | Resolve external Import files explicitly |
| Save/resume | Native Save/bundles, page drafts and two-slot local draft recovery | Further crash/restart field testing |
| Cloud saved filters | Account list/import UI | FilterBlade cloud saves are not connected |
| Share filters/modules | Build sharing and portable bundles | Dedicated public filter/module catalogue |
| One-time PoE upload | Explicit reviewed API publication | Live verification with a filter-authorised account |
| Automatic uploads | Not implemented | Requires a separately operated update service |
| Frequent economy refresh | Not connected | FilterBlade's hosted economy feed is not bundled |
| Single-filter download | Copy/export `.filter`, preserving existing files | Optional replacement workflow |
| Export all strictnesses | Seven files or one ZIP, including personal edits and appearance, with collision checks | Imported filters have no preset variants |
| Validation | Native parser checks and account-server validation when authorised | Broader syntax coverage and live game validation |
| Mobile layout | Desktop layouts tested at 960, 1024 and 1280 widths | Native PoB is not a mobile web app |

The remaining offline polish includes additional starter presets and encounter sample collections. Hosted economy updates remain separate service work. The release checklist tracks implementation and repeated workflow verification.

Reference screenshots were captured outside the repository during the review. Third-party advertising scripts logged browser errors; the main anonymous customizer and simulator remained usable. No login, publication, purchase or subscription was performed.
