# Vendored dependencies

All dependencies are checked in as ordinary source files. There are no Git submodules, package-manager install steps, compiler binaries, or build-time downloads.

| Dependency | Version / commit | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.4.0) | `v5.4.0` / `c64a1edb67b6e3f4a15cca8909c9482ad33a02b0` | ERC20, IERC20, IERC20Metadata, Context, IERC6093 errors, LICENSE | MIT |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` / `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Entire `src/` tree and both license files; test tooling only | Apache-2.0 OR MIT |

The OpenZeppelin subset is the complete transitive import closure needed by the production token. No vendored Solidity source has been modified. The tagged archives' commit identifiers and SHA-256 checksums, plus checksums for every included file, are recorded in [dependencies.lock.json](dependencies.lock.json).

Licenses are retained at `lib/openzeppelin-contracts/LICENSE`, `lib/forge-std/LICENSE-APACHE`, and `lib/forge-std/LICENSE-MIT`. Repository-root remappings resolve imports to these local files.
