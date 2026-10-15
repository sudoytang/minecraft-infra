# client-pack
Builder scripts for the HMCL / Modrinth client modpack (`Ytang-Cozy-Client-1.0.0.mrpack`, index only).
`build-hmcl-pack.mjs` resolves mod versions via the Modrinth API; `build-hmcl-preloaded.mjs` produces the
preloaded variant (~17 MB, not tracked – rebuild it). Paths assume host `~/client-pack-work`.
