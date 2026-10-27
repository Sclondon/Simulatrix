# The Simulatrix

A physics and VFX laboratory in Godot 4.7 (GL Compatibility), built for phones and the web. It looks like editor
software (after Aseprite): a menu bar, a tab for the open sim, a Simulations browser, a Properties panel and a status
bar. Every sim has its properties on the panel and notes under Help.

## Physics

| Sim | What's under the hood |
| --- | --- |
| Playground | Godot `RigidBody2D` shapes: tap to drop, drag to pour, grab to throw. Gravity, bounce, pegs. |
| Chaos Pendulum | Double pendulum from the Lagrangian equations, RK4 with 8 substeps. Three "ghost" copies start 0.001 rad apart to show chaos. |
| Cloth | Verlet points + distance constraints; links snap past a stretch limit. Grab or cut, wind, pins. |
| Gravity Well | Inverse-square gravity around a draggable star, optional planet-planet gravity, merging collisions, slingshot launch with a predicted path. |
| Ripple Tank | Fragment shader summing circular waves as complex phasors: live waves or time-averaged brightness, plus a double-slit setup. |
| Fluid | ~600 particles with Clavet-style double density relaxation (grid-binned neighbours), drawn as metaballs in a half-size SubViewport, thresholded by `fluid.gdshader`. |
| Falling Sand | A cellular automaton (one byte per cell) sent to the GPU as an R8 texture and coloured by `sand.gdshader`. |
| Light Bench | 2D ray tracing: Snell's law with total internal reflection, Schlick partial reflections, Cauchy dispersion. |
| Charge Field | Coulomb field of up to 12 charges: potential and contours in `field.gdshader`, field lines traced (RK2). |
| Orbits 3D | Atlas's Earth (Blue Marble, clouds, city lights, air) and Moon on sphere meshes; real GM in Earth radii, leapfrog satellites launched by slingshot with a live predicted orbit and Pe/Ap/period readouts (`sims/orbits3d/`). |

## VFX

Built on GameCommon components wherever one exists (`scripts/`, `woodland/`, `creatures/` are installed copies:
water, fire, grass, pine-tree, leafy-tree, painted-woodland, sand, fireflies).

| Sim | What it is |
| --- | --- |
| Ocean | Mariner's ocean made Gerstner: wind-built sea plus swell, folding whitecaps, Toon style, a buoy and dropped crates floating on a CPU copy of the waves. |
| Weather Lab | Clouds (cumulus, stratus, storm with anvil, cirrus), GPU rain with splashes and puddles, settling snow, hail, branching lightning with flash and thunder countdown, time of day, fog; the painted-woodland kit's sun shafts (crepuscular rays through cloud gaps) and its painted sky as a style. |
| Pond | GameCommon `Water` in a basin: pebbles, splashes, a wake float, presets, night; or (Body: Stream) the painted-woodland kit's running water down a channel that falls downhill, carrying dropped leaves. |
| Fire | GameCommon `Fire` from candle to bonfire, five colours, tap to light more. |
| Grass | GameCommon `Grass`: finger pusher with trails, a rolling ball, `Grass.blast()`, palettes, quality. |
| Wind | One wind field (`wind_field.gd`, timed to the grass shader's gusts) moving grass, swaying trees, leaves and seeds, streaks, a flag; vector view and blasts. |
| Tree Lab | `PineTree` and `LeafyTree` with every setting as a slider, seed, sway shader, debug views, forest mode; the painted-woodland kit's painted trees (oak, tall, leaner, aspen, snag: girth, lean, roots, swirl, real-leaf clumps, season) and its 3D bushes; a leaf-litter ground. |
| Sand | The GameCommon sand kit: furrows, prints, ten kinds to paint, pour, wind, dunes. |
| Texture Lab | GPU noise and material generators (Perlin, Simplex, Worley, FBM, warp, wood, marble, bricks...), ramps, seamless tiling, 3D previews, PNG export. |
| Particle Editor | Unity/Godot-style editor over `GPUParticles3D`: layered emitters, modules, curve and gradient editors, 20 presets (falling, gusting and swirling leaves among them), the kit's real leaf shapes as sprites, a Tumble mode, JSON library, `.tscn` export. |
| Shader Lab | Live Godot shader editor: syntax highlighting, errors by line (via `OS.add_logger`), uniforms become properties, 2D and 3D modes, 16 presets, save and export. |

## Layout

- `main.gd` builds the whole UI in code. The Properties panel docks right in landscape and along the bottom in
  portrait; the Simulations browser shows in landscape only (use the Sims menu otherwise). It forwards touches that
  start inside the play area to the current sim, and leaves keys alone while a text field has focus.
- `sims/sim.gd` is the base class. A sim describes its properties as data (`controls()`: section, slider with
  `unit`, toggle, choice, button, custom widget), emits `controls_changed` to rebuild them, and gives a `status()`
  line. Touches arrive in its own local coordinates. Mouse input arrives as touch index 0.
- `sims/sim3d.gd` is the base for 3D sims: a SubViewport world drawn into the play area, an orbit camera (drag,
  pinch, wheel; two fingers pan), and a Finger: Look / Poke choice for sims you can touch.
- Stretch is `canvas_items` / `expand` on a 720x720 base, so the short side is always 720 virtual pixels.
- The UI font is PixelifySans (OFL, `fonts/`).

## Tests and builds

```
godot --headless --path . -s tests/smoke.gd              # opens every sim in both orientations and presses every control
godot --path . -s tests/shots.gd -- --shots=C:/tmp/shots [--portrait]   # screenshots of the menu and each sim
godot --path . -s tests/vfx_shot.gd -- --sim=res://sims/vfx/ocean.gd --shots=C:/tmp/s [--portrait] [--poke]   # one sim
godot --headless --path . --export-release Web build/index.html
```

Check new shaders in a real browser too: Chrome on Windows compiles WebGL through ANGLE to Direct3D, and a very
large shader with many loops can take long enough to freeze the page.

The web build in `build/` is served by GitHub Pages at https://sclondon.github.io/Simulatrix/build/ and runs as a
cabinet in the Scareathon arcade.
