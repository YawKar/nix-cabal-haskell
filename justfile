hs_dirs := "bins libs"

[default]
[private]
default:
    @just --list --unsorted

[private]
pre-commit-hook: format-check lint

# format everything
[group("Code Style")]
format check="":
    # nix
    find . -type f -name "*.nix" -exec nixfmt -sv {{ if check != "" { "-c" } else { "" } }} {} +
    # yaml
    yamlfmt {{ if check != "" { "-lint" } else { "" } }} .
    # just
    just --fmt {{ if check != "" { "--check" } else { "" } }}
    # cabal
    find {{ hs_dirs }} -type f -name "*.cabal" -exec cabal-fmt {{ if check != "" { "--check" } else { "--inplace" } }} {} +
    # haskell
    fourmolu --mode {{ if check != "" { "check" } else { "inplace" } }} {{ hs_dirs }}

[group("Code Style")]
format-check: (format "check")

# lint everything
[group("Code Style")]
lint fix="":
    # nix
    statix {{ if fix != "" { "fix" } else { "check" } }}
    # haskell (no auto-fix: apply-refact is broken in nixpkgs)
    hlint {{ hs_dirs }}

[group("Code Style")]
lint-fix: (lint "fix")

# build all packages
[group("Build")]
build:
    cabal build all

# NOTE: the build image comes from static/Containerfile (add C libraries there).
# Uses docker, or podman if docker is missing; override with CONTAINER_ENGINE=podman.
# build fully static (musl) executables in an Alpine container into dist-static/ (default: all)
[group("Build")]
[positional-arguments]
build-static *exes:
    #!/usr/bin/env bash
    set -euo pipefail
    engine=${CONTAINER_ENGINE:-$(command -v docker >/dev/null && echo docker || echo podman)}
    # Run as the current user so the build output on the host isn't owned by root.
    case $engine in
        podman) user_args=(--userns=keep-id) ;;
        *) user_args=(--user "$(id -u):$(id -g)" --env HOME=/tmp) ;;
    esac

    if [[ $# -eq 0 ]]; then
        mapfile -t exes < <(sed -n 's/^executable[[:space:]]\{1,\}//p' bins/*/*.cabal libs/*/*.cabal)
    else
        exes=("$@")
    fi
    echo "==> static build of: ${exes[*]}" >&2

    # Rebuilt on every run; the layer cache makes it instant when the Containerfile is unchanged.
    # Named after the project directory, so projects made from this template don't share an image.
    image="localhost/$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9.\n-' '-')-static"
    "$engine" build --quiet --tag "$image" --file static/Containerfile static/ >/dev/null

    # Inside the container: build, copy, strip, then check there is no dynamic loader and no shared libraries.
    # The separate builddir and CABAL_DIR keep musl artifacts apart from the host's, and cache them between runs.
    "$engine" run --rm "${user_args[@]}" \
        --volume "$PWD:/src" --workdir /src \
        --env CABAL_DIR=/src/dist-newstyle/static/cabal \
        "$image" sh -euc '
            build="--builddir=dist-newstyle/static --enable-executable-static"
            cabal update -v0
            targets=""; for exe in "$@"; do targets="$targets exe:$exe"; done
            cabal build $build $targets
            mkdir -p dist-static
            for exe in "$@"; do
                out="dist-static/$exe"
                cp "$(cabal list-bin -v0 $build "exe:$exe")" "$out"
                strip "$out"
                if readelf -lW "$out" | grep -q INTERP || readelf -dW "$out" | grep -q NEEDED; then
                    echo "error: $out is not static:" >&2
                    readelf -dW "$out" | grep NEEDED >&2 || true
                    exit 1
                fi
                echo "==> $out: $(file -b "$out")" >&2
            done
        ' sh "${exes[@]}"

# run all tests
[group("Test")]
test:
    cabal test all --test-show-details=direct

# measure test coverage of all libraries, open the HTML report
[group("Test")]
coverage:
    #!/usr/bin/env bash
    set -euo pipefail
    # separate builddir: coverage instrumentation would invalidate the normal build cache
    dir=dist-newstyle/coverage
    cabal test all --builddir="$dir" --enable-coverage --test-show-details=direct

    # cabal writes one report per test suite; merge them into one for the whole project.
    # --exclude=Main drops the test suites' own entry points.
    rm -rf coverage && mkdir -p coverage
    mapfile -t tix < <(find "$dir" -name '*.tix' -path '*/t/*')
    hpc sum --union --exclude=Main --output=coverage/all.tix "${tix[@]}"

    # Absolute paths: hpc resolves --hpcdir relative to each --srcdir.
    mapfile -t mix < <(find "$PWD/$dir" -type d -path '*/extra-compilation-artifacts/hpc/vanilla/mix' ! -path '*/t/*')
    hpc_dirs=() src_dirs=()
    for m in "${mix[@]}"; do hpc_dirs+=("--hpcdir=$m"); done
    for p in libs/*/ bins/*/; do src_dirs+=("--srcdir=$p"); done

    hpc report coverage/all.tix "${hpc_dirs[@]}"
    hpc markup coverage/all.tix "${hpc_dirs[@]}" "${src_dirs[@]}" --destdir=coverage/html >/dev/null
    just _open coverage/html/hpc_index.html

# pin cabal.project to the latest Hackage snapshot (re-freezes if frozen)
[group("Dependencies")]
bump-index:
    #!/usr/bin/env bash
    set -euo pipefail
    state=$(cabal update --ignore-project 2>&1 | tee /dev/stderr | sed -n 's/^The index-state is set to \(.*\)\.$/\1/p')
    if [ -z "$state" ]; then
        echo "error: could not read the index-state from 'cabal update'" >&2
        exit 1
    fi
    # -i.bak keeps this portable between GNU and BSD sed
    sed -i.bak "s/^index-state:.*/index-state: $state/" cabal.project && rm cabal.project.bak
    echo "cabal.project: index-state: $state"
    if [ -f cabal.project.freeze ]; then just freeze; fi

# run the `>>>` examples from documentation comments
[group("Test")]
doctest:
    # separate builddir: doctest as the compiler would invalidate the normal build cache
    for pkg in bins/*/ libs/*/; do cabal repl -v0 --builddir=dist-newstyle/doctest --with-compiler=doctest "$pkg" || exit 1; done

# generate documentation for all libraries into haddocks/
[group("Docs")]
docs:
    # separate builddir: haddock reconfigures packages and would invalidate the normal build cache
    cabal haddock-project --builddir=dist-newstyle/docs --hackage --output=haddocks
    @echo "open haddocks/index.html"

# NOTE: re-run after bumping ghcVersion in flake.nix: the freeze file also pins
# GHC's built-in libraries (base, ...), so a stale one fails to resolve.
# pin exact versions of all dependencies into cabal.project.freeze
[group("Dependencies")]
freeze:
    rm -f cabal.project.freeze
    cabal freeze

# show the optimized Core (GHC's intermediate language) of a package
[group("Inspect")]
core pkg: (_dump "simpl" "haskell" pkg)

# show the generated assembly of a package
[group("Inspect")]
asm pkg: (_dump "asm" "asm" pkg)

# Both dumps come from one build, so switching between `core` and `asm` doesn't rebuild.
[private]
_dump stage lang pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    # separate builddir: the dump flags would invalidate the normal build cache
    dir=dist-newstyle/dump
    cabal build -v0 --builddir="$dir" \
        --ghc-options="-ddump-simpl -ddump-asm -ddump-to-file -dsuppress-all -dsuppress-uniques" \
        "{{ pkg }}"
    # Only this package's library and executables, not its test suites (t/) or benchmarks (b/).
    mapfile -t files < <(find "$dir" -path "*/{{ pkg }}-[0-9]*" -name "*.dump-{{ stage }}" \
        ! -path "*/t/*" ! -path "*/b/*" | sort)
    [[ ${#files[@]} -gt 0 ]] || { echo "no .dump-{{ stage }} files for '{{ pkg }}' under $dir" >&2; exit 1; }
    bat --language={{ lang }} --style=header,grid --paging=always "${files[@]}"

# how to profile an executable (start here)
[group("Profiling")]
prof:
    #!/usr/bin/env bash
    cat <<'EOF'
    Profile an executable, then open the result in a viewer:

        just prof-<kind> <exe> [args...]

      prof-time    <exe> [args]   Where do time and allocations go?
                                  Cost centres added after optimization (-fprof-late),
                                  so the profile reflects the optimized program.
                                  build: profiling    view: profiteur (browser)

      prof-heap    <exe> [args]   What fills the heap over time, and from which source line?
                                  Info-table profiling (+RTS -hi), no profiling build needed.
                                  build: normal + info tables    view: eventlog2html (browser)

      prof-threads <exe> [args]   Threads, GC pauses and parallelism over time.
                                  build: normal       view: threadscope (GUI)

      prof-all     <exe> [args]   All three from one run, heap broken down by cost centre.
                                  It's a profiling build, so timings in threadscope are
                                  less representative than with prof-threads.
                                  view: profiteur + eventlog2html + threadscope

    Output goes to profiles/<exe>-<kind>.* and is overwritten on every run.

    Extra RTS flags go after the program's arguments, for example:

        just prof-heap cli1 input.txt +RTS -i0.05 -RTS   # sample the heap every 50ms
        just prof-threads cli1 +RTS -N4 -RTS             # run on 4 cores

    Quick numbers without any viewer:  cabal run cli1 -- +RTS -s -RTS
    EOF

# profile time and allocations (cost centres), view in profiteur
[group("Profiling")]
[positional-arguments]
prof-time exe *args:
    @just _prof time "$@"

# profile the heap by source location, view in eventlog2html
[group("Profiling")]
[positional-arguments]
prof-heap exe *args:
    @just _prof heap "$@"

# record threads and GC over time, view in threadscope
[group("Profiling")]
[positional-arguments]
prof-threads exe *args:
    @just _prof threads "$@"

# time + heap (by cost centre) + threads from one profiling run, open all viewers
[group("Profiling")]
[positional-arguments]
prof-all exe *args:
    @just _prof all "$@"

[positional-arguments]
[private]
_prof kind exe *args:
    #!/usr/bin/env bash
    set -euo pipefail
    kind=$1 exe=$2
    shift 2

    mkdir -p profiles
    stem="profiles/$exe-$kind"
    rm -f "$stem".*

    # separate builddirs: profiling and info tables would invalidate the normal build cache
    prof_build=(--builddir=dist-newstyle/prof --enable-profiling --profiling-detail=late)
    case $kind in
        time) build=("${prof_build[@]}") rts=(-p "-po$stem") ;;
        heap) build=(--builddir=dist-newstyle/heap "--ghc-options=-finfo-table-map -fdistinct-constructor-tables")
            rts=(-hi -l "-po$stem" "-ol$stem.eventlog") ;;
        threads) build=() rts=(-l "-ol$stem.eventlog") ;;
        all) build=("${prof_build[@]}") rts=(-p -hc -l "-po$stem" "-ol$stem.eventlog") ;;
    esac

    cabal build -v0 "${build[@]}" "exe:$exe"
    bin=$(cabal list-bin -v0 "${build[@]}" "exe:$exe")

    # Keep going if the program fails: the profile of a failing run is still useful.
    status=0
    "$bin" +RTS "${rts[@]}" -RTS "$@" || status=$?

    if [[ $kind == time || $kind == all ]]; then
        profiteur "$stem.prof" && just _open "$stem.prof.html"
    fi
    if [[ $kind == heap || $kind == all ]]; then
        eventlog2html "$stem.eventlog" && just _open "$stem.eventlog.html"
    fi
    if [[ $kind == threads || $kind == all ]]; then
        echo "==> threadscope $stem.eventlog" >&2
        threadscope "$stem.eventlog" >/dev/null 2>&1 &
    fi
    exit "$status"

# Open a file in its default application (a browser for HTML); only print the path in CI.
[positional-arguments]
[private]
_open file:
    #!/usr/bin/env bash
    echo "==> $1" >&2
    [[ -z "${CI:-}" ]] || exit 0
    if command -v xdg-open >/dev/null; then
        xdg-open "$1" >/dev/null 2>&1 &
    elif command -v open >/dev/null; then
        open "$1"
    fi

# NOTE: tasty-bench options go after the name (see `just bench lib1-bench --help`):
#   just bench lib1-bench -p long                       # only benchmarks matching "long"
#   just bench lib1-bench --csv baseline.csv            # save a baseline...
#   just bench lib1-bench --baseline baseline.csv --fail-if-slower 10   # ...and compare to it
# run all benchmarks, or one by name with its own options
[group("Bench")]
[positional-arguments]
bench name="" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "${1:-}" ]]; then
        # Build in parallel, then run one at a time: concurrent benchmarks skew each other's timings.
        cabal build -v0 all
        exec cabal bench all -j1
    fi
    name=$1
    shift
    cabal build -v0 "bench:$name"
    exec "$(cabal list-bin -v0 "bench:$name")" "$@"

# run the whole CI pipeline locally
[group("CI")]
ci: format-check lint build test coverage doctest docs
