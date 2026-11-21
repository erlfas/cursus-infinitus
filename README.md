# Forma Urbis: Cursus Infinitus

Run through an endless Roman city that builds itself around you.

A Godot 4 game in which you steer a running Roman citizen, seen from behind, through streets that never end. The city isn't stored anywhere. A **Wave Function Collapse (WFC)** solver lays it out in 8 × 8-tile chunks as you approach, and the tiles rise out of the ground in the exact order the algorithm decides them.

It grew out of `Isometric_Roman_City_WFC_Generator.html`, a single-page Three.js tool that solved one fixed grid. The game reuses its 24 Roman modules, socket rules, weights and random-number generator (bit-for-bit), and makes the grid infinite.

*Forma Urbis* ("the plan of the city") is named after the Forma Urbis Romae, the giant marble map of ancient Rome. *Cursus infinitus* means "endless run".

## Running it

Requires **Godot 4.7** (Forward+ renderer).

```sh
godot --path .            # play
```

Or open `project.godot` in the editor and press F5.

| Key | Action |
| --- | --- |
| W A S D / arrows | Run (relative to the camera) |
| Shift | Sprint |
| Space | Jump |
| Mouse | Look around (click the window to capture the mouse) |
| Wheel | Camera distance |
| Esc | Menu: daylight preset, city seed, quit |
| F3 | Debug readout (FPS, chunks, solve time, retries) |

The HUD counts distance in *passus* (1 passus ≈ 1.48 m) and shows Roman miles (*mille passuum*) in Roman numerals.

## How the city is generated

The tile set has 24 modules: roads, aqueducts, insulae, domus, forums and gardens. Each edge of a module carries one of four sockets: **R** (road), **A** (aqueduct), **F** (forum plaza) or **U** (urban margin). With rotations that gives 74 variants. Neighbouring tiles must have matching sockets on their shared edge.

For each chunk the solver runs these steps:

1. Every cell starts with all 74 variants, stored as a 2 × 40-bit mask.
2. It picks the cell with the lowest weighted Shannon entropy (minimum remaining values, tie-broken with a tiny jitter).
3. It collapses that cell with a weighted random draw. Forums, gardens, domus and aqueducts get a boost next to neighbours of the same family, so they cluster.
4. It propagates: neighbours are narrowed by the union of what the remaining options allow, rippling outward through a queue.
5. On a contradiction, it re-solves the chunk with a new random stream (up to 12 attempts).

To make the city endless:

- **Seams.** A new chunk's edge cells are first constrained by whatever neighbouring chunks are already solved, so the edges line up.
- **Street grid.** Every 16th column is pinned to a north–south road (*cardo*) and every 16th row to an east–west road (*decumanus*), with crossroads where they meet. Side streets can still branch off, and the runner can never be walled in.
- **Impossible corners.** Rarely, a corner touches two older chunks that no tile can satisfy. Only that cell is relaxed to the least-mismatching variants, and the rest of the chunk is solved normally.

Chunks are solved one at a time on a worker thread (about 6 ms each), revealed tile by tile in collapse order, merged into one mesh per material, and given collision only near the runner. Solved cells stay in memory, so streets you've visited are unchanged when you come back.

An interactive, step-by-step explanation with live boards running the same solver is in [`docs/wfc-walkthrough.html`](docs/wfc-walkthrough.html). Open it in a browser.

## Project layout

```
main.tscn                 entry scene (script: scripts/main.gd)
scripts/
  wfc_data.gd             module catalogue, variants, socket compatibility bitmasks, street-grid pins
  infinite_wfc.gd         infinite world + thread-safe chunk solver (MRV, propagation, retries, seam relaxation)
  rng.gd                  FNV-1a seed hash + mulberry32 PRNG (matches the original JS exactly)
  roman_meshes.gd         procedural Roman architecture baked to meshes + collision shapes
  chunk_streamer.gd       threaded solving, pop-in reveal, chunk mesh merging, collision, unloading
  citizen.gd              the runner: procedural model, run cycle, movement
  follow_camera.gd        third-person spring-arm chase camera
  lighting.gd             Meridies / Vespera / Nox daylight presets
  hud.gd, pause_menu.gd, ui_theme.gd
tests/test_infinite_wfc.gd  headless solver tests
docs/wfc-walkthrough.html   interactive algorithm walkthrough
Isometric_Roman_City_WFC_Generator.html   the original browser generator
```

## Tests

```sh
godot --headless --path . --import          # first time only, registers script classes
godot --headless --path . --script tests/test_infinite_wfc.gd
```

The test solves a 5 × 5-chunk area in random order for several seeds. It checks that sockets match across every seam, that avenues are roads, and that the avenue crossings are reachable by road. It also checks the PRNG against the JavaScript reference values and bakes every module mesh.

For a visual smoke test, `godot --path . -- --autoshot` runs the citizen on autopilot, saves four screenshots to the Godot user data folder and quits.
