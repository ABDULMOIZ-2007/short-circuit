# Visual assets
Palette: near-black #111615, charcoal #191f1d, copper #eea171, sage #91bf97 and warm white #e8eae3.

- textures/pcb-copper.png: original generated decorative PCB texture.
- textures/pcb-copper.webp: optimized version used in both interfaces.
- textures/dot-grid.svg: reusable 24 px dotted schematic grid.
- textures/line-grid.svg and paper-grid.svg: dark and light technical grids.
- textures/panel-grain.svg: low-contrast reusable panel grain.
- symbols/: exact vector symbols for resistor, voltage source, current source, capacitor, ground and wire.
- brand/logo.svg and icon-192.png / icon-512.png: scalable identity and application icons.
- brand/android/: density-specific launcher icons and a dark Android launch background.

The functional schematic is drawn with vectors in Flutter Canvas and browser SVG. These symbols remain crisp when zoomed. The generated copper texture is decorative and is never used to represent electrical connectivity.

tools/generate_assets.js regenerates vectors and optimized raster files from the logo definitions and the original generated texture. It requires the optional sharp development dependency.

