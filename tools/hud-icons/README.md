# HUD symbols

Source drawings for the right-edge HUD tiles (`HudTile`) and the speed and cash rows,
uploaded as 256px PNGs. The ids live in `src/client/HudArtwork.luau` (`Artwork.IMAGE`).

| File | Used by | `Artwork.IMAGE` key |
| --- | --- | --- |
| `index_cards.svg` | Index tile | `cards` |
| `shop_chest.svg` | Shop tile | `chest` |
| `nukes_bomb.svg` | Nukes tile | `nuke` |
| `warp_portal.svg` | Warp tile | `portal` |
| `daily_gift.svg` | Daily rewards tile (`DailyRewardsController`) | `gift` |
| `gear_detector.svg` | Gear tile | `detector` |
| `mastery_medal.svg` | the Masteries bar above Shop (`MasteriesController`) | `medal` |
| `settings_gear.svg` | the Settings button in the top-right corner (`SettingsController`) | `settingsGear` |
| `glow.svg` | the soft glow behind every tile symbol (white, tinted per tile) | `glow` |
| `trefoil_tile.svg` | the faint trefoils drifting across the Shop and Index bars (white, tinted black in `HudTile`) | `trefoilTile` (128px) |
| `speed_shoe.svg` | the SPEED row's sneaker (`SpeedController`) | `speedShoe` |
| `edit_pencil.svg` | the pencil beside WALK SPEED that opens the walk-speed picker (`SpeedController`) | `editPencil` |
| `cash_bundle.svg` | the cash row's bundle of notes (`CashController`) | `cashBundle` |
| `health_heart.svg` | the health bar's heart (`HudController`) | `healthHeart` |
| `rads_trefoil.svg` | the rads bar's trefoil badge (`HudController`) | `radsTrefoil` |
| `luck_clover_purple.svg` | the x4 clover (`CloverArt.PURPLE`); `pass_luck.svg` is also the x2 clover (`CloverArt.GREEN`) | `CloverArt` palettes |
| `shop_cash_1..4.svg` | the Shop panel's CASH cards, cheapest to dearest (`ShopController`) | `shopCash` (512px) |
| `shop_sunburst.svg` | the rays behind each CASH card's art (white, faded by ImageTransparency) | `sunburst` (512px) |
| `potion_<id>.svg` (5), `potions_tile.svg` | the potions (luck, cash, speed, strength, clean) and the Potions tile (`PotionController`) | not in `Artwork.IMAGE`: each potion's `image` and `TILE_IMAGE` in `Config/Potions` |
| `pass_*.svg` (8) | the Shop panel's PASSES cards (`ShopController`) | not in `Artwork.IMAGE`: each pass's `image` in `Config/GamePasses` |

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
