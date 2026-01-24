# Local Tailwind Binary

This directory contains pre-downloaded Tailwind CSS binaries to avoid network issues during Docker builds.

## Required Binary

Download from GitHub releases and place in this directory:

**For ARM64 (Raspberry Pi):**
```
https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.7/tailwindcss-linux-arm64
```

After downloading, make it executable:
```bash
chmod +x tailwindcss-linux-arm64
```

## Why?

The Tailwind Elixir package normally downloads the binary during `mix assets.deploy`. On unstable networks (e.g., 5G), this can fail and break builds. By pre-downloading the binary, builds work offline.

## Version

This should match the version in `config/config.exs`:
```elixir
config :tailwind, version: "4.1.7"
```

If you upgrade Tailwind, download the new binary to match.
