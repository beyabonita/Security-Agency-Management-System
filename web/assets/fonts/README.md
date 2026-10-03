# Google Material Symbols Rounded

The icon font is a self-hosted Google Material Symbols subset, licensed under
Apache 2.0 (see `LICENSE.txt`). The agency logo remains the original image;
Material Symbols are used for interface controls only.

`material-symbols-rounded.json` records the official source, fixed 24px/500
weight/0 grade axes, and the icons included. Both outlined and filled states
are available. Loading only these icons keeps the asset small and avoids a
third-party font request during sign-in or emergency workflows.

When adding a new icon, add its name to the sorted `icons` array and regenerate
the subset using the recorded Google Fonts API URL plus
`&icon_names=<comma-separated icons>&display=block`. Download the WOFF2 URL
from that CSS response. Keep the license alongside the font. Run
`node web/tests/google_icons_test.js` and the `google_icons.spec.js` browser tests.
