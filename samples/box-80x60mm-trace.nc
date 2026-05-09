( GRBL outline trace — matches samples/box-80x60mm.svg : 80 x 60 mm rectangle )
( Set G54 XY zero at the lower-left CORNER you want aligned with SVG (0,0). )
( Set Z0 on spoilboard/tool touch-off; shallow pass for first run. Flip Y here if CAD is mirrored. )

G90 G21 G17 G94

( Safe traverse height — raise if clamps are tall )
G0 Z5 F800

G0 X0 Y0 F2000

( First cut depth — deepen only after a dry/air run feels right — mm )
G1 Z-0.5 F240

F900
G1 X80 Y0
G1 X80 Y60
G1 X0 Y60
G1 X0 Y0

( Retract )
G0 Z5 F800

M5
G0 X0 Y0
M30
