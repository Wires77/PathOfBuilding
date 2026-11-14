# Atlas planner

Open **Atlas** beside **AI builds**, or switch to **Atlas** in the full-width planning workspace. **< Build** returns to your previous build tab.

1. Choose the exact tree version. We bundle official **3.27.0, 3.29.1 and 3.29.3** Standard and Ruthless Standard graphs, plus **3.30.0-preview** and **3.30.0-preview-ruthless**. New plans default to the character's mode and the matching bundled version where available; 3.28 uses the 3.29.3 snapshot. Both 3.30 previews have **150 base points**. Standard and Covens graphs match within each mode at the pinned preview revision, but Ruthless has different modifiers. Historical league-specific Atlas variants are not included.
2. Enter a name and the number of Atlas points you have earned. The initial budget is the tree's maximum; it does not read account progression. On older trees, you must have enough earned points to reach Unwavering Vision before its granted points can be used. Plans that cannot reach it are flagged; some need a temporary path and refunds, which the planner marks for review rather than proving a transition. Previously saved plans remain readable.
3. Filter a mechanic directly in the inspector, or search names and stat text. Matching nodes highlight and preview a result without moving the camera. Choose a result or press **Go** to center it. Result labels show added point costs. Use **Connect +N** to add the previewed shortest connection.
4. Use the mouse wheel to zoom and drag empty space to pan. **Fit tree** resets the view. The canvas uses the official background, node icons, frames and mechanic emblems. Allocated paths are gold; avoided nodes have red frames. Hover for modifier descriptions. Double click a node to connect it, or remove it if allocated.
5. **Avoid selected** excludes a node from future paths. Desired and avoided preferences are saved with the plan and portable JSON. **Remove branch** also removes disconnected allocations. **Undo** and **Redo** restore allocations and preferences. Press Enter after editing a budget to include it in history.
6. Open **Notes & sharing** for farming notes and import/export. Choose **Keep plan** to keep the draft in this build. This changes unsaved metadata. Use the normal build **Save** to persist it. Saved plans have a total metadata size guard, with no eight-plan count limit; **Saved plans** opens or deletes them.

**Find nodes** opens a searchable list with mechanic filters and added point costs. Choosing a result highlights its mechanic on the tree. The minimap moves the camera without changing allocations. Drag the divider beside the inspector to resize it.

Mechanic filters include Mirage, Wildwood, Sentinels, Torment, Rogue Exiles and Threads. A node that mentions multiple mechanics appears in each applicable filter; the investment summary assigns one primary category per node so its totals do not double-count points. Categories are based on node text and are not a simulation of encounter interactions.
Automatic starting routes avoid allocating nodes that explicitly prevent encounters, unless already allocated. This routing precaution does not change saved avoidance preferences; blocking nodes remain available for manual plans. Review each suggested route and its keystones before applying it.
In 3.30, Harvest includes Sacred Flora and Fauna; the Wildwood filter focuses on the Viridian Wildwood encounter rather than every effect that mentions Wildwood Wisps.

**Targets** collects desired nodes; Shift-click marks them directly on the tree. Toggle a mechanic's notables together, then preview a route retaining existing allocations or rebuilding from the start. Recalculation runs in short background slices, with pause/cancel controls. Review added/refunded points, connected targets and keystone effects, then **Use preview**. Changed plans require recalculation. For up to four targets, the optimizer finds the fewest added nodes while retaining existing allocations and respecting exclusions, when that route passes the budget checks. Larger sets compare a bounded selection of target orders and do not guarantee an optimum. The minimum-node result does not prove a refund sequence for granted points.

**Routes** compares the shortest connection with available alternatives. In **Plan tools**, mark a selected node as a preferred waypoint, open editable mechanic starting routes, compare the draft with a saved plan, or restore an earlier history state. Starting routes compare target orders and connect up to three nearby notables from the bundled graph; they do not predict farming income. Route comparisons honor the current budget and exclusions.

**Allocated stats** opens an investment overview, mechanic counts, keystone tradeoffs and searchable raw bonuses. Saved-plan comparison can overlay added paths in green and removed paths in red. Counts are not effective map odds: increased effect, conditions and keystone interactions are not simulated. Atlas allocations do not change character DPS or EHP.

## Sharing

**Copy plan** exports JSON with the exact patch version, point budget, allocations and notes. **Paste plan** imports that JSON into the current draft. Review it before keeping it.

**Official link** copies a version-six `pathofexile.com/fullscreen-atlas-skill-tree/` URL. These URLs do not contain a patch version. For an official URL import, first select its original patch and budget, then use **Paste plan**. The importer rejects unknown, disconnected and over-budget nodes. Node IDs can survive between patches while changing meaning, so a successful import is not proof that the selected patch is correct. Use our JSON format for reliable versioned sharing.

Other planners' proprietary links, old URL formats and shortened links are not imported. Export an official Atlas URL from that planner first. The official website may display a different patch from an older saved plan.

## AI tools

Reconnect the MCP client after updating. Enable build proposals in **AI builds**.

- `get_atlas_plans`: read saved plans, bundled versions and the build revision.
- `search_atlas_nodes`: search a selected official graph for native node IDs and text.
- `plan_atlas_tree`: connect up to thirty desired IDs to a plan, optionally avoiding nodes. Returns a separate draft, added nodes, point accounting, stat text and an official link.
- `propose_atlas_plan`: submit that plan for normal desktop review. Only the desktop **Apply** button commits the candidate; build **Save** persists it.

Search and routing are queued. Poll `get_proposal_status` and match the returned request ID. Neither tool applies changes. Routing uses deterministic shortest connections in target order. Set `optimize: true` to compare target orders and, for up to four targets, find the minimum added-node route when it passes the budget checks. Larger sets use a bounded heuristic. Starting-route suggestions use the faster order comparison. Existing allocations and exclusions stay intact; the final tree must fit the supplied budget. The response reports whether the result is heuristic, the number of orders checked and savings against the original order when that order was valid. Ruthless results include the versioned plan and a sharing warning rather than an unverified official URL. Gateways use the official graph links. Granted Atlas points are counted in the final budget; a minimum-node route does not itself prove a refund sequence to reach a grant.

Example request: “Use my Atlas version and a 90-point budget. Find Essence and map-sustain nodes, avoid mechanics I dislike, and propose a connected farming plan. Explain the keystones and tradeoffs before I apply it.”

The planner does not fetch character Atlas completion, scrape community trees, provide popularity heatmaps, price supplies or predict farming income. **Stages & strategy** records progression, respec routes, maps, supplies, requirements and dated setup estimates; see [connected planning tools](planning-workflows.md).

## Sources and maintenance

Node names, stats, links, positions, point limits, granted points and artwork come from [GGG's official Atlas export](https://github.com/grindinggear/atlastree-export). Each bundled graph records its immutable source URL, commit and SHA-256. Decorative mastery icons are excluded from allocation. Artwork is bundled from the same pinned official export; planning works offline. No third-party planner code or artwork is bundled.

`python tools/update_atlas_data.py` regenerates the graphs from pinned official exports. Updating versions also requires changing the native and MCP version allowlists, testing changed rules and budgets, and publishing the new files in the updater manifest. There is no silent network update of saved plans.

Use `--version 3.30.0-preview` or `--version 3.30.0-preview-ruthless` to regenerate one pinned preview. Each verifies its matching league export; all Ruthless generators also check that their Standard counterpart shares artwork. Historical Ruthless snapshots use the official Standard-mode export, not the differing league export. Existing plans retain their original version; changing versions starts an empty draft rather than reinterpreting old node IDs. Ruthless official-link encoding is not yet verified, so use versioned plan JSON for sharing Ruthless plans.

Feature research: [Path of Pathing](https://pathofpathing.com/) offers desired/avoided-node routing and exports; [poe.ninja](https://poe.ninja/posts/atlas-trees) offers community-tree filters, heatmaps and stat breakdowns. Our planner provides local versioned planning and AI review; those broader discovery tools remain useful alongside it.
