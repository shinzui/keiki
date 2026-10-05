--| Shared reader-facing documentation profile from okf-profiles v0.19.0.
--
-- Source: mori://shinzui/okf-profiles/profiles/user-documentation
-- Requires okf 0.9.0.0 or later. Bump the tag and semantic hash together.
let Profiles =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.19.0/package.dhall
        sha256:85176d78369b6d73c9f13c30277903b629d6bf048a4c7d71fc26e68b99c3eaa6

in  Profiles.documentation.userDocumentation
