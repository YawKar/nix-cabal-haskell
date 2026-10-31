# nix-cabal-haskell

A template for multi-package Haskell projects: a cabal workspace of libraries and
executables, with Nix providing a reproducible toolchain and [`just`](https://github.com/casey/just)
as the task runner.

The split of responsibilities is deliberate:

- **Nix** provides the tools only: GHC, cabal, HLS, formatters, linters, profilers.
- **cabal** resolves and builds Haskell dependencies from Hackage, pinned by
  `index-state` and `cabal.project.freeze`.
- **just** is the one interface for everything: local development, git hooks and CI
  all run the same recipes.

## Quick start

Requirements: [Nix](https://nixos.org/download/) with flakes enabled. Docker or
Podman only for static builds.

```sh
nix develop          # enter the dev shell (also installs the git hooks)
cabal update         # download the Hackage index (once per machine)
just ci              # format-check, lint, build, test, coverage, doctest, docs
just                 # list all recipes
```

Run an executable with `cabal run cli1 -- <args>`.

### Starting a new project from the template

1. Create the repository from this template (or copy it) and enter `nix develop`.
2. Rename the project: `description` and the shell `name`s in `flake.nix`, and the
   example packages under `bins/` and `libs/`.
3. Replace the example packages with your own (see [Adding a package](#adding-a-package)).
4. Pin a fresh Hackage snapshot and dependency set: `just bump-index`.

## Layout

```
.
├── bins/                    executables
│   ├── cli1/                  uses lib1
│   └── cli2/                  uses lib1 and lib2
├── libs/                    libraries (with test/ and bench/)
│   ├── lib1/
│   └── lib2/                  depends on lib1
├── cabal.project            the workspace: every package under bins/*/ and libs/*/
├── cabal.project.freeze     exact versions of all dependencies
├── flake.nix                dev shells and git hooks
├── justfile                 all recipes
├── fourmolu.yaml            Haskell formatter settings
├── .yamlfmt                 YAML formatter settings
├── static/Containerfile     Alpine image for static builds
└── .github/workflows/       CI (ci.yml) and manual static builds (static.yml)
```

### Adding a package

Create a directory with a `.cabal` file under `bins/` or `libs/`; `cabal.project`
picks it up automatically. Depend on other packages in the workspace by name, without
version bounds:

```cabal
build-depends:
  , base  >=4.20 && <5
  , lib1
```

Executables can use any library, and libraries can depend on each other as long as
there are no cycles. The examples share settings through a `common` stanza
(`GHC2024`, a strict set of warnings); cabal can't share stanzas across files, so
each package has its own copy.

For a new Hackage dependency, add it to `build-depends` and run `just freeze`.

## Tooling

| Tool | Version | Purpose |
|---|---|---|
| GHC | 9.10.3 | compiler (`ghcVersion` in `flake.nix`) |
| cabal-install | 3.16.1 | build tool |
| haskell-language-server | 2.13 | editor support |
| fourmolu | 0.19 | Haskell formatter |
| cabal-fmt | 0.1.12 | `.cabal` formatter |
| hlint | 3.10 | Haskell linter |
| doctest | 0.24 | runs `>>>` examples in comments |
| nixfmt, statix | | Nix formatter and linter |
| yamlfmt | | YAML formatter |
| profiteur, eventlog2html, threadscope, bat | | profile viewers and dump pager |

Versions come from the nixpkgs revision in `flake.lock`. Two shells:

- `nix develop`: everything above, plus a Hoogle database for GHC's libraries.
- `nix develop .#ci`: only what CI needs (no HLS, Hoogle, viewers or git hooks).

## Recipes

| Recipe | What it does |
|---|---|
| **Code style** | |
| `just format` / `just format-check` | format (or check) Nix, YAML, justfile, `.cabal` and Haskell files |
| `just lint` / `just lint-fix` | statix and hlint (hlint has no auto-fix: `apply-refact` is broken in nixpkgs) |
| **Build and test** | |
| `just build` | `cabal build all` (libraries, executables, tests and benchmarks) |
| `just test` | run all test suites |
| `just coverage` | test coverage of all libraries, merged into one HTML report |
| `just doctest` | run the `>>>` examples in documentation comments |
| `just build-static [exe...]` | fully static Linux executables (see [Static binaries](#static-binaries)) |
| **Docs** | |
| `just docs` | Haddock documentation for all libraries in `haddocks/` |
| **Dependencies** | |
| `just bump-index` | move `index-state` to the latest Hackage snapshot (re-freezes if frozen) |
| `just freeze` | regenerate `cabal.project.freeze` |
| **Performance** | |
| `just bench [name] [args...]` | run all benchmarks, or one with tasty-bench options |
| `just prof` | help screen for the profiling recipes below |
| `just prof-time exe [args...]` | time and allocation profile, opens profiteur |
| `just prof-heap exe [args...]` | heap profile by source location, opens eventlog2html |
| `just prof-threads exe [args...]` | threads and GC timeline, opens ThreadScope |
| `just prof-all exe [args...]` | all three from one profiling run |
| `just core pkg` / `just asm pkg` | optimized Core or assembly of a package, in a pager |
| **CI** | |
| `just ci` | the whole CI pipeline locally |

Recipes that need different compiler flags (coverage, doctest, docs, profiling, dumps,
static builds) use their own build directory under `dist-newstyle/`, so they never
invalidate the normal build.

Generated output, all gitignored: `haddocks/`, `coverage/`, `profiles/`, `dist-static/`.
HTML reports open in your browser automatically, unless the `CI` environment variable
is set.

## Reproducibility

| What | Pinned by | Update with |
|---|---|---|
| Tools (GHC, cabal, ...) | `flake.lock` | `nix flake update` |
| Hackage snapshot | `index-state` in `cabal.project` | `just bump-index` |
| Exact dependency versions | `cabal.project.freeze` | `just freeze` |
| Static build image | digest in `static/Containerfile` | edit the `FROM` line |

### Changing the GHC version

1. Change `ghcVersion` in `flake.nix` (e.g. `ghc912`) and re-enter `nix develop`.
2. Change the image tag and digest in `static/Containerfile` to the same GHC version.
3. Run `just freeze`. The freeze file also pins GHC's built-in libraries such as
   `base`, so a stale one fails to resolve.
4. Adjust `base` bounds in the `.cabal` files if needed.

### `cabal-version`

The `.cabal` files use `cabal-version: 3.12`. This is the version of the file
format, not of cabal-install. 3.12 is also the newest format the pinned `cabal-fmt`
can read, so only raise it when you need a newer format feature and every tool that
reads `.cabal` files supports it.

## Git hooks

Entering `nix develop` installs a pre-commit hook (via
[git-hooks.nix](https://github.com/cachix/git-hooks.nix)) that runs
`just format-check` and `just lint`. The hook brings its own pinned tools, so it also
works when committing from an editor outside the dev shell. The generated
`.pre-commit-config.yaml` is a symlink into the Nix store and is gitignored.

## Continuous integration

**`ci.yml`** runs on pushes to `main`, pull requests and manual dispatch, on Linux and
macOS. Each check is a separate step: format check, lint, build, test, coverage,
doctest, docs. The cabal store is cached by dependency files; the coverage report and
documentation are uploaded as artifacts from the Linux job.

**`static.yml`** is manual only (Actions → "Static binaries" → "Run workflow"). It
builds static executables for x86_64 and aarch64 Linux and uploads them as artifacts.
An optional input takes executable names (empty means all).

Benchmarks are compiled in CI (so they can't silently break) but not run: timings on
shared runners are too noisy to compare.

## Documentation and doctests

Write [Haddock](https://haskell-haddock.readthedocs.io/) comments with `-- |`, and add
examples that `just doctest` checks:

```haskell
-- | A louder 'greet'.
--
-- >>> shout "world"
-- "HELLO, WORLD!"
shout :: String -> String
```

`just docs` builds one site for all libraries with a shared index, search and links
to highlighted source; dependencies link to Hackage. Executables aren't included.

## Coverage

`just coverage` runs every test suite with GHC's coverage instrumentation (HPC) and
merges the results, so tests in one package count toward coverage of the libraries
they use. It prints a summary and opens `coverage/html/hpc_index.html`.

## Benchmarks

Benchmarks use [tasty-bench](https://github.com/Bodigrim/tasty-bench), which has a
criterion-compatible API with far fewer dependencies (to switch to criterion, replace
the `Test.Tasty.Bench` import with `Criterion.Main` and the dependency).

```sh
just bench                                         # all benchmarks, one at a time
just bench lib1-bench -p long                      # only benchmarks matching "long"
just bench lib1-bench --csv base.csv               # save a baseline...
just bench lib1-bench --baseline base.csv --fail-if-slower 10   # ...and compare to it
```

## Profiling and inspecting generated code

`just prof` prints a guide to the profiling modes, with examples of passing RTS
options. For quick numbers without any viewer:
`cabal run cli1 -- +RTS -s -RTS`.

`just core lib2` shows the optimized Core: inlining, specialization and strictness
are visible there. `just asm cli2` shows the generated assembly.

## Static binaries

`just build-static` builds executables inside an Alpine (musl) container and checks
that the results have no dynamic loader and no shared libraries. They run on any
Linux distribution. The image is built from `static/Containerfile` and cached;
override the container engine with `CONTAINER_ENGINE=podman`.

Notes:

- The GHC image is built without GMP ("int-native"), so the binaries don't include
  that LGPL library.
- macOS doesn't support fully static binaries.
- Binaries from the dev shell are for local use only: they load libraries from
  `/nix/store` paths, which don't exist on other machines.

## Using C libraries (FFI)

Declare the library in the package's `.cabal` file. pkg-config then provides the
compiler and linker flags:

```cabal
pkgconfig-depends: zlib
```

```haskell
foreign import ccall unsafe "zlib.h zlibVersion" c_zlibVersion :: IO CString
```

If a Hackage binding exists (like the `zlib` package), depend on it instead; it
declares this for you. Then make the library available to each kind of build:

- **Dev shell and CI:** add `pkgs.pkg-config` to the tools and the library (e.g.
  `pkgs.zlib`) to `buildInputs` of both shells in `flake.nix`.
- **Static builds:** add the library's `-dev` and `-static` Alpine packages to
  `static/Containerfile`. zlib, libffi, OpenSSL, curl, bzip2, ncurses and gmp are
  already in the base image.
- **Loading at runtime** (`dlopen` via `System.Posix.DynamicLinker`): needs no build
  changes, but doesn't work in fully static binaries. In the dev shell, point
  `LD_LIBRARY_PATH` at the library (e.g. with `lib.makeLibraryPath` in the
  `shellHook`).

## License

Released into the public domain under [the Unlicense](LICENSE): use, copy, modify
and distribute it for any purpose, with no conditions and no warranty. The example
packages declare `license: Unlicense` in their `.cabal` files. Projects created from
the template can keep it or choose their own.
