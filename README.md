# EenAllesCobblemon SMP Packwiz Modpack

This repository hosts the self-updating packwiz version of the EenAllesCobblemon SMP modpack for Prism Launcher.

## Pack details

- Minecraft: `1.21.1`
- Loader: `Fabric`
- Fabric Loader: `0.18.4`

## Hosted URLs

- Pack URL:  
  `https://raw.githubusercontent.com/yarnobachmann/EenAllesCobblemon-SMP/main/pack.toml`
- Prism zip URL:  
  `https://raw.githubusercontent.com/yarnobachmann/EenAllesCobblemon-SMP/main/EenAllesCobblemon-SMP-1.0.0-prism.zip`

## GitHub Pages publishing

1. Push the repository to GitHub.
2. In GitHub, open `Settings -> Pages`.
3. Set the source to `Deploy from a branch`.
4. Publish branch `main` from `/root`.
5. Keep `.nojekyll` in the repository root.

## Prism Launcher

The generated Prism zip contains:

- `instance.cfg`
- `mmc-pack.json`
- `packwiz-installer-bootstrap.jar`
- the custom pack icon

The instance pre-launch command uses the hosted `pack.toml` URL and updates automatically through `packwiz-installer-bootstrap.jar`.

## Build

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\build-prism-zip.ps1 -Variant full
```

To refresh the packwiz index without rebuilding the Prism zip:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\refresh-pack.ps1 -PackRoot .
```
