# The Simulatrix

A physics and VFX workbench in Godot 4.7 (GL Compatibility). It looks like editor software (after Aseprite): a menu
bar, a tab for the open sim, a Simulations browser, a Properties panel and a status bar. Every sim has its properties
on the panel and notes under Help.

Its job is iterating on the assets and effects the games share. The VFX labs run on the very GameCommon components
the games use (installed copies, kept identical to GameCommon), so what you see here is what a game gets; and every
lab can export what you made into GameCommon's asset library, from where you send it into a project when you
choose. Nothing here changes a game by itself.

## The sims

One list, with like sims side by side.

| Sim | What it is |
| --- | --- |
| Playground | Godot `RigidBody2D` shapes: tap to drop, drag to pour, grab to throw. Gravity, bounce, pegs. |
| Chaos Pendulum | Double pendulum from the Lagrangian equations, RK4 with 8 substeps. Three "ghost" copies start 0.001 rad apart to show chaos. |
| Cloth | Verlet points + distance constraints; links snap past a stretch limit. Grab or cut, wind, pins. |
| Gravity Well | Inverse-square gravity around a draggable star, optional planet-planet gravity, merging collisions, slingshot launch with a predicted path. |
| Orbits 3D | Atlas's Earth (Blue Marble, clouds, city lights, air) and Moon on sphere meshes; real GM in Earth radii, leapfrog satellites launched by slingshot with a live predicted orbit and Pe/Ap/period readouts (`sims/orbits3d/`). |
| Charge Field | Coulomb field of up to 12 charges: potential and contours in `field.gdshader`, field lines traced (RK2). |
| Light Bench | 2D ray tracing: Snell's law with total internal reflection, Schlick partial reflections, Cauchy dispersion. |
| Ripple Tank | Fragment shader summing circular waves as complex phasors: live waves or time-averaged brightness, plus a double-slit setup. |
| Fluid | ~600 particles with Clavet-style double density relaxation (grid-binned neighbours), drawn as metaballs in a half-size SubViewport. |
| Pond | GameCommon `water` in a basin: pebbles, splashes, a wake float, presets, night; or (Body: Stream) the painted-woodland kit's running water. |
| Ocean | GameCommon `ocean`: wind-built Gerstner sea plus swell, folding whitecaps, gust patches, Toon style, things floating on the CPU copy of the waves. |
| Weather Lab | GameCommon `weather`: clouds (cumulus, stratus, storm, cirrus), GPU rain with puddles, settling snow, hail, lightning, time of day, fog; the painted-woodland kit's sun shafts and painted sky. |
| Wind | GameCommon `wind`: one wind field moving grass, swaying trees, leaves and seeds, ribbons, a flag; vector view and blasts. |
| Grass | GameCommon `grass`: finger pusher with trails, a rolling ball, `Grass.blast()`, palettes, quality. |
| Tree Lab | GameCommon `pine-tree` and `leafy-tree` (drawn by their own materials) with every setting as a slider, seed, debug views, forest mode; the painted-woodland kit's painted trees and bushes; a leaf-litter ground. |
| Falling Sand | A cellular automaton (one byte per cell) sent to the GPU as an R8 texture and coloured by `sand.gdshader`. |
| Sand | GameCommon `sand`: furrows, prints, ten kinds to paint, pour, wind, dunes. |
| Fire | GameCommon `fire` from candle to bonfire, five colours, tap to light more. |
| Particle Editor | Unity/Godot-style editor over `GPUParticles3D`: layered emitters, modules, curve and gradient editors, 20 presets, the kit's real leaf shapes as sprites, a Tumble mode. |
| Texture Lab | GPU noise and material generators (Perlin, Simplex, Worley, FBM, warp, wood, marble, bricks...), ramps, seamless tiling, 3D previews. |
| Shader Lab | Live Godot shader editor: syntax highlighting, errors by line (via `OS.add_logger`), uniforms become properties, 2D and 3D modes, 16 presets. |

## Components and exporting

- `scripts/`, `woodland/`, `creatures/`, `ocean/`, `weather/`, `wind/` are installed GameCommon components (water,
  fire, grass, pine-tree, leafy-tree, painted-woodland, sand, fireflies, ocean, weather, wind). Keep them identical
  to GameCommon: before working on one, compare every game's copy (some games improve theirs), pull newer general
  work back into GameCommon with its README, then `kit.sh install --force` it here.
- Each lab's last properties section is **Export** (`sims/exporter.gd`): a name, Export, Send to project... and
  Open folder. Export writes the asset (a generator `.tres`, a baked mesh and `.glb`, an effect or component
  `.tscn`, a `.gdshader`, PNGs, settings `.json`) and a `.asset.txt` note (components it needs, how to use it) into
  `C:/Projects/GameCommon/library/<kind>/`, and rewrites the library's README. Send to project... copies an asset
  and its components into a chosen Godot project (as `sh kit.sh asset <kind>/<name> <project>` does), leaving a
  project's own changed component files alone. In a browser, Export downloads the files instead.
- `sims/node_copy.gd` makes a fresh component node carrying only a live node's settings, for exporting scenes.

## Layout

- `main.gd` builds the whole UI in code. The Properties panel docks right in landscape and along the bottom in
  portrait; the Simulations browser shows in landscape only (use the Sims menu otherwise). It forwards touches that
  start inside the play area to the current sim, and leaves keys alone while a text field has focus.
- Phones (a short side under 600 CSS px) get a compact mode: the whole UI scaled up, bigger touch rows, a pared-down
  menu bar, Properties as a bottom sheet (tap its header to pull it taller). Panels scroll by dragging anywhere,
  with fling; a drag that becomes a scroll calls off the press under it. Number properties are `ui/value_bar.gd`:
  a sideways drag or a tap sets them, a double tap resets.
- `sims/sim.gd` is the base class. A sim describes its properties as data (`controls()`: section, slider with
  `unit`, toggle, choice, button, custom widget), emits `controls_changed` to rebuild them and `say` to show a
  line, and gives a `status()` line. Touches arrive in its own local coordinates; mouse input arrives as touch 0.
- `sims/sim3d.gd` is the base for 3D sims: a SubViewport world drawn into the play area, an orbit camera (drag,
  pinch, wheel; two fingers pan), and a Finger: Look / Poke choice for sims you can touch.
- Stretch is `canvas_items` / `expand` on a 720x720 base. The UI font is PixelifySans (OFL, `fonts/`).

## Tests and builds

```
godot --headless --path . -s tests/smoke.gd              # opens every sim in both orientations and presses every control
godot --path . -s tests/touch_ui.gd                       # phone-size touch: scrolling, value bars, the sheet
godot --path . -s tests/shots.gd -- --shots=C:/tmp/shots [--portrait] [--size=390x844]   # screenshots of every sim
godot --path . -s tests/vfx_shot.gd -- --sim=res://sims/vfx/ocean.gd --shots=C:/tmp/s [--portrait] [--poke]   # one sim
godot --headless --path . -s tests/export_check.gd -- --root=C:/tmp/lib            # export a pine, send it to a project
godot --headless --path . -s tests/export_labs.gd -- ...                           # every lab's export (see the file)
godot --headless --path . -s tests/component_export_check.gd -- ...                # ocean, weather, wind exports
godot --headless --path . --export-release Web build/index.html
```

Export tests write to a scratch library (`Exporter.root_override`), never the real one. Check new shaders in a real
browser too: Chrome on Windows compiles WebGL through ANGLE to Direct3D, and a very large shader with many loops can
take long enough to freeze the page.

The web build in `build/` is served by GitHub Pages at https://sclondon.github.io/Simulatrix/build/ and runs as a
cabinet in the Scareathon arcade; it doesn't need to stay current.
