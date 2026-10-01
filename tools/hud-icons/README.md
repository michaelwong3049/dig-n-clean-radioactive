# HUD symbols

Source drawings for the right-edge HUD tiles (`HudTile`) and the speed and cash rows,
uploaded as 256px PNGs. The ids live in `src/client/HudArtwork.luau` (`Artwork.IMAGE`).

| File | Used by | `Artwork.IMAGE` key |
| --- | --- | --- |
| `index_cards.svg` | Index tile | `cards` |
| `shop_chest.svg` | Shop tile | `chest` |
| `nukes_bomb.svg` | Nukes tile | `nuke` |
| `warp_portal.svg` | Warp tile | `portal` |
| `gear_detector.svg` | Gear tile | `detector` |
| `glow.svg` | the soft glow behind every tile symbol (white, tinted per tile) | `glow` |
| `speed_shoe.svg` | the SPEED row's sneaker (`SpeedController`) | `speedShoe` |
| `edit_pencil.svg` | the pencil beside WALK SPEED that opens the walk-speed picker (`SpeedController`) | `editPencil` |
| `cash_bundle.svg` | the cash row's bundle of notes (`CashController`) | `cashBundle` |
| `health_heart.svg` | the health bar's heart (`HudController`) | `healthHeart` |
| `rads_trefoil.svg` | the rads bar's trefoil badge (`HudController`) | `radsTrefoil` |

To change one: edit the SVG (100x100 viewBox, `#12161d` outline), render it to a
transparent 256px PNG, upload it (Studio MCP `upload_image`, or Asset Manager), and paste
the new `rbxassetid://` into `Artwork.IMAGE`.

Rendering with headless Chrome. The files must come from an http server
(`python -m http.server 8765` in this folder). Pass a separate `--user-data-dir` if Chrome
is already open, or it writes nothing:

```
chrome --headless=new --disable-gpu --hide-scrollbars --user-data-dir=<temp dir>
  --default-background-color=00000000 --window-size=256,256
  --screenshot=<out.png> http://127.0.0.1:8765/shop_chest.svg
```
