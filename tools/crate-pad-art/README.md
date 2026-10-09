# Crate pad art

`goldpad_tex.png`: the gold (Robux) crate pad's 64x64 palette texture, recoloured to match
the user's reference render. Each colour is an 8x8 swatch on the import's own UV layout:

| Swatch (col,row) | Part of the pad | Colour |
|---|---|---|
| (0,5), (1,6) | side light bars | `FFF03A` |
| (0,6) | inner floor | `FFB42A` |
| (2,6) | dark trim | `9C6410` |
| (0,7) | body | `7E1620` |
| (1,7) | corner blocks | `FF2D55` |
| (2,7) | frame + corner caps | `D99A12` |

Uploaded with the Studio MCP `upload_image` from `python -m http.server 8765` in this
folder. Run the server outside the Bash sandbox or the uploader can't reach it. The id
is `PREMIUM_PAD_TEXTURE` in `src/server/build/CrateShopPads.luau`.
