--| Shared controlled-vocabulary profile from okf-profiles v0.18.0.
-- Loading this descriptor requires okf 0.9.0.0 or later.
let Profiles =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.18.0/package.dhall
        sha256:7d3a4a22be12fd0e697d6012ed1eb2efe4cb5dc4700d08fd49aa5e4c0e523df8

in  Profiles.documentation.terminology
