# The Simulatrix

A pocket physics lab in Godot 4.7 (GL Compatibility), built for phones and the web.
Pick a simulation from the menu and poke at it; every sim has a control panel and a `?` help card.

| Sim | What's under the hood |
| --- | --- |
| Playground | Godot `RigidBody2D` shapes: tap to drop, drag to pour, grab to throw. Gravity, bounce, pegs. |
| Chaos Pendulum | Double pendulum from the Lagrangian equations, RK4 with 8 substeps. Three "ghost" copies start 0.001 rad apart to show chaos. |
| Cloth | Verlet points + distance constraints; links snap past a stretch limit. Grab or cut, wind, pins. |
| Gravity Well | Inverse-square gravity around a draggable star, optional planet-planet gravity, merging collisions, slingshot launch with a predicted path. |
| Ripple Tank | Fragment shader summing circular waves as complex phasors: live waves or time-averaged brightness, plus a double-slit setup. |
| Fluid | ~600 particles with Clavet-style double density relaxation (grid-binned neighbours), drawn as metaballs: blobs summed additively in a half-size SubViewport, thresholded by `fluid.gdshader`. Stir, pour, drain, tilt gravity; water, slime or lava. |
| Falling Sand | A cellular automaton (one byte per cell, rows with nothing moving are skipped) sent to the GPU as an R8 texture and coloured by `sand.gdshader`. Sand, water, stone, wood, fire, steam, lava, plants, oil. |
| Light Bench | 2D ray tracing: Snell's law with total internal reflection, Schlick partial reflections, and Cauchy dispersion so white light fans into a spectrum. Prisms, lenses, blocks, flat and curved mirrors. |
| Charge Field | Coulomb field of up to 12 charges: potential and contours in `field.gdshader`, field lines traced (RK2) from the positive charges, probe charges flung through the field. |

## Layout

- `main.gd` builds the whole UI in code: menu, top bar, and a control panel that docks right in landscape and
  along the bottom in portrait. It forwards touches that start inside the play area to the current sim.
- `sims/sim.gd` is the base class. A sim describes its controls as data (`controls()`), and gets `touch_down/move/up`
  in its own local coordinates. Mouse input arrives as touch index 0 (`emulate_touch_from_mouse`).
- Stretch is `canvas_items` / `expand` on a 720x720 base, so the short side is always 720 virtual pixels.

## Tests and builds

```
godot --headless --path . -s tests/smoke.gd              # opens every sim in both orientations and presses every control
godot --path . -s tests/shots.gd -- --shots=C:/tmp/shots [--portrait]   # screenshots of the menu and each sim
godot --headless --path . --export-release Web build/index.html
```

The web build in `build/` is served by GitHub Pages at https://sclondon.github.io/Simulatrix/build/ and runs as a
cabinet in the Scareathon arcade.
