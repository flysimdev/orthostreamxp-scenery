# OrthoStreamXP scenery

Scenery tiles that [AutoOrtho's scenery releases](https://github.com/kubilus1/autoortho-scenery) lack, for
[OrthoStreamXP](https://github.com/flysimdev/OrthoStreamXP). OrthoStreamXP adds them to the region they belong to
(North America's tiles to `OrthoStream_NA`, and their overlays to `OrthoStream_Overlays`). There is no extra scenery
package to install.

- **New installs** of a region download its tiles from here together with AutoOrtho's mesh.
- **Regions already installed** get them the next time OrthoStreamXP starts (for example, the first start after an
  update), or from **Update** on the Packages page.
- **AutoOrtho's files always win.** A file the region already has is never replaced. When AutoOrtho's own release adds
  one of these tiles, AutoOrtho's version is the one installed, and the tile can be removed from here.

## What is here

```
regions/
  <region>/                       eur, na, sa, afr, asi or aus_pac (AutoOrtho's regions)
    region.json                   { "version": 1 }  (raise it whenever this region's files change)
    mesh/
      Earth nav data/+40-130/+44-122.dsf
      textures/*.png              the tiles' sea masks (<row>_<col>_ZL<zoom>.png)
    overlays/
      Earth nav data/+40-130/+44-122.dsf
check.ps1                         checks regions/ (below)
pack.ps1                          regions/ -> the release's zips and supplements.json
.github/workflows/check.yml       check.ps1 + pack.ps1 on every push and pull request
.github/workflows/release.yml     a v* tag publishes the release
```

There are no `terrain/*.ter` files: OrthoStreamXP builds them from the tile names as X-Plane reads them.

The tiles are plain files in git, without Git LFS. Every file is under GitHub's 50 MB warning size (the largest DSF is
about 33 MB), and OrthoStreamXP never clones the repository: it downloads release assets only. Consider moving to
release-only storage if the repository grows past about 1 GB.

## Adding or changing tiles

1. Put each tile's files in the region it belongs to:
   - the mesh DSF in `mesh/Earth nav data/<10° folder>/`
   - its overlay DSF in `overlays/Earth nav data/<10° folder>/`
   - its sea-mask PNGs in `mesh/textures/`
   The 10° folder is the tile's latitude and longitude rounded down to tens: `+44-122` goes in `+40-130`, and `-19-174`
   in `-20-180`.
2. Raise `version` in that region's `region.json`. Regions you did not touch keep their version, so their users
   download nothing.
3. Run `./check.ps1`, then `./pack.ps1 -Tag vN` to see the result in `out/`. Both run on Windows PowerShell 5.1 or
   PowerShell 7.
4. Commit and push. **Check** runs on the push.

`check.ps1` refuses:
- a folder that is not one of AutoOrtho's regions
- a tile without both a mesh DSF and an overlay DSF
- a DSF in the wrong 10° folder, or one that is neither `XPLNEDSF` nor 7-Zip compressed
- a tile that is in two regions
- any other file
- a file of 100 MB or more (GitHub refuses those)

## Releasing

```
git tag v2
git push origin v2
```

The **Release** workflow:
1. downloads `supplements.json` of the newest release
2. runs `pack.ps1` (which stops if a region's files changed but its version did not)
3. publishes a release with `out/*`, marked as the latest one

You can add release notes in `release-notes/<tag>.md`; they go above GitHub's generated notes.

Each release has these assets, per region:

| Asset | What it is |
|---|---|
| `z_<region>_supplement.zip` (+ `.sha256`) | the mesh: `Earth nav data/` and `textures/` under a top folder `z_<region>_supplement/` |
| `y_<region>_supplement_overlays.zip` (+ `.sha256`) | the overlays: `Earth nav data/` under `y_<region>_supplement_overlays/` |
| `supplements.json` | the list OrthoStreamXP reads, one for the whole release |

OrthoStreamXP reads
`https://github.com/flysimdev/orthostreamxp-scenery/releases/latest/download/supplements.json`, so **the newest release
must not be a pre-release or a draft**.

## supplements.json

```json
{
  "schema": 1,
  "tag": "v1",
  "regions": {
    "na": {
      "version": 1,
      "tiles": ["+44-122", "+44-123"],
      "contentHash": "<sha256 of the region's file names and contents>",
      "mesh":     { "name": "z_na_supplement.zip", "url": "https://github.com/.../releases/download/v1/z_na_supplement.zip",
                    "size": 188225125, "sha256Url": "https://.../z_na_supplement.zip.sha256" },
      "overlays": { "name": "y_na_supplement_overlays.zip", "url": "...", "size": 13725266, "sha256Url": "..." }
    }
  }
}
```

How OrthoStreamXP treats this list:
- An installed region records the `version` it has. It downloads the files again only when that number goes up.
- `schema` changes only when the format does. OrthoStreamXP ignores a schema it does not know.
- It also ignores a region it does not know, and any entry whose file name is a path or whose address is not HTTPS.
- Every zip is checked against its `.sha256` after download.

## Licence and attribution

Released under the **GNU General Public License v3 (GPL-3.0)**, the same as OrthoStreamXP: see [LICENSE](LICENSE).
