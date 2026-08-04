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
