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

# Strict OKF profile + log validation for docs/capabilities. Requires `okf` and
# `dhall` on PATH (not yet part of the Nix dev shell — see the ADR note above).
capabilities-validate:
    dhall type --file docs/capabilities/profile.dhall > /dev/null
    okf validate docs/capabilities \
        --profile docs/capabilities/profile.dhall \
        --profile-enforce \
        --log-enforce

# Strict OKF profile + log validation for commit-pinned review records. Findings
# stay in the review body or become records in the owning request bundle.
reviews-validate:
    dhall type --file docs/reviews/profile.dhall > /dev/null
    okf validate docs/reviews \
        --strict \
        --profile docs/reviews/profile.dhall \
        --profile-enforce \
        --log-enforce

# Every fixture must fail for its named evidence-boundary reason. Keeping the
# expectation table exhaustive makes a newly-added fixture fail this gate until
# its intended rejection is reviewed explicitly.
compile-fail-check:
    #!/usr/bin/env zsh
    set -eu
    typeset -A expected=(
      OmittedInCtorSchema.hs "non-bidirectional pattern synonym ‘InCtor’"
      OmittedWireSchema.hs "non-bidirectional pattern synonym ‘WireCtor’"
      TrustedConstructorCapability.hs "hidden module in the package"
      TrustedInCtorSchemaUpdate.hs "record update at field ‘icSchema’"
      TrustedWireCtorSchemaUpdate.hs "record update at field ‘wcSchema’"
      TrustedWireCtorUpdate.hs "record update at field ‘wcMatch’"
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

# Controlled vocabulary: profile, provenance log, references, and source anchors.
terminology-validate:
    dhall type --file docs/terminology/profile.dhall > /dev/null
    okf validate docs/terminology --strict \
        --profile docs/terminology/profile.dhall \
        --profile-enforce --log-enforce
    mori terms validate --path . --bundle terminology
