# pkgup

Update Arch Linux PKGBUILD files for binary packages with the latest stable release from GitHub.

## Important Notice

The PKGBUILD must respect a specific format that I use for my own packages.

This tool is mostly intended for my personal use. It is intended to stay small. I use coding agents to help maintain it.

## Usage

To install `pkgup` with [LuaRocks](https://luarocks.org), use:

```bash
luarocks install https://raw.githubusercontent.com/catwell/pkgup/refs/heads/main/rockspec/pkgup-dev-1.rockspec
```

Run `pkgup` from the PKGBUILD directory.

The script will:
- Fetch the latest stable release from GitHub
- Download the checksums file from the release assets
- Update `pkgver` and architecture-specific `sha256sums_*` in the PKGBUILD

## Development

This project is written in [Teal](https://teal-language.org), a typed dialect of Lua.

To bootstrap the local development environment, run:

```bash
curl https://loadk.com/localua.sh -O
sh localua.sh .lua
./.lua/bin/luarocks install tl
./.lua/bin/luarocks install --only-deps rockspec/pkgup-dev-1.rockspec
```

To rebuild and install the Lua version, use:

```bash
tl gen pkgup.tl
./.lua/bin/luarocks make
```

## Copyright

Copyright (c) from 2026 Pierre Chapuis

Some definition files in `tealtypes` are copied from [Teal Types](https://github.com/teal-language/teal-types).
