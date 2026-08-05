set shell := ["zsh", "-cu"]

site := "site-dist"

default:
    just --list

install:
    pnpm install --frozen-lockfile

website-build:
    BUNDLE_PRAGMATA_PRO=1 pnpm run build

website-dev:
    BUNDLE_PRAGMATA_PRO=1 pnpm run dev

website-preview:
    BUNDLE_PRAGMATA_PRO=1 pnpm run preview

website-linkcheck:
    node site/check-links.mjs {{site}}

website-verify: install website-build website-linkcheck

# Strict OKF profile + log validation for docs/adr. Requires `okf` and `dhall`
# on PATH (not yet part of the Nix dev shell — see docs/guide/adr-conventions.md).
adr-validate:
    dhall type --file docs/adr/profile.dhall > /dev/null
    okf validate docs/adr \
        --profile docs/adr/profile.dhall \
        --profile-enforce \
        --log-enforce

# Every fixture must fail for its named evidence-boundary reason. Keeping the
# expectation table exhaustive makes a newly-added fixture fail this gate until
# its intended rejection is reviewed explicitly.
compile-fail-check:
    #!/usr/bin/env zsh
    set -eu
    typeset -A expected=(
      OmittedInCtorSchema.hs "non-bidirectional pattern synonym"
      OmittedWireSchema.hs "non-bidirectional pattern synonym"
      TrustedConstructorCapability.hs "hidden module"
      TrustedInCtorSchemaUpdate.hs "icSchema"
      TrustedWireCtorSchemaUpdate.hs "wcSchema"
      TrustedWireCtorUpdate.hs "wcMatch"
    )
    fixtures=(test/compile-fail/*.hs(N))
    (( ${#fixtures} > 0 )) || { print -u2 "no compile-fail fixtures found"; exit 1; }
    for fixture in $fixtures; do
      name=${fixture:t}
      token=${expected[$name]-}
      [[ -n $token ]] || { print -u2 "missing expected token for $fixture"; exit 1; }
      if output=$(cabal exec -- ghc -fno-code -XGHC2024 -package keiki "$fixture" 2>&1); then
        print -u2 "unexpected success: $fixture"
        exit 1
      fi
      if [[ $output != *$token* ]]; then
        print -u2 "wrong failure for $fixture (expected token: $token)"
        print -u2 -- "$output"
        exit 1
      fi
      print "expected failure: $fixture ($token)"
    done
