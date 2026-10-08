# HUD symbols

Source drawings for the right-edge HUD tiles (`HudTile`) and the speed and cash rows,
uploaded as 256px PNGs. The ids live in `src/client/HudArtwork.luau` (`Artwork.IMAGE`).

| File | Used by | `Artwork.IMAGE` key |
| --- | --- | --- |
| `ai/*.png` (6) | the left-edge button grid: Shop basket, Index cards, Nukes bomb, Gear detector, Warp portal, Gifts box. AI-made PNGs, no SVG source; cut out of a white background | `chest`, `cards`, `nuke`, `detector`, `portal`, `giftBox` |
| `index_cards.svg`, `shop_chest.svg`, `nukes_bomb.svg`, `warp_portal.svg`, `gear_detector.svg` | the grid's old flat pictures, replaced by `ai/` | no longer used |
| `ai/daily_calendar.png`, `ai/settings_gear.png` | the top-right corner row: Daily rewards calendar, Settings cog. AI-made PNGs cut out of a white background | `calendar`, `settingsGear` |
| `daily_gift.svg` | the Daily rewards panel and the Free Gifts fallback picture | `gift` |
| `mastery_medal.svg` | the Masteries bar above Shop (`MasteriesController`) | `medal` |
| `settings_gear.svg` | the Settings button's old flat cog, replaced by `ai/settings_gear.png` | no longer used |
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
| `pass_*.svg` (8) | the Shop panel's PASSES cards (`ShopController`) | not in `Artwork.IMAGE`: each pass's `image` in `Config/GamePasses` |
| `playtime/*.png` (7) | the Free Gifts tile's clock and the gift cards' pictures (nuke/bumped/liquid crates, cash, cash + Speed, Speed); potion cards use the potion's own picture (`tools/potion-art`); PNGs only, no SVG source. Most are AI-made, cut out of a white background | not in `Artwork.IMAGE`: `PlaytimeGifts.ICONS` in `Config/PlaytimeGifts` |

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
