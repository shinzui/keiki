let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/027403783777cbce0e87eb660a0b3d8119ebe8d2/package.dhall
        sha256:d29ca03286afa92b7589d09b7a6d98ad8e39d11b255a4b8751f3327b0722fba3

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "keiki"
      , namespace = "shinzui"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , description = Some "Pure core for symbolic-register transducer event sourcing."
      , domains = [ "StateMachines", "EventSourcing", "Workflow", "DurableExecution" ]
      , owners = [ "shinzui" ]
      }
    , repos = [ Schema.Repo::{ name = "keiki", github = Some "shinzui/keiki" } ]
    , packages =
      [ Schema.Package::{
        , name = "keiki"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "."
        , description = Some "Pure core for symbolic-register transducer event sourcing"
        , dependencies =
          [ Schema.Dependency.WithAugmentation
              { name = "haskell-hvr/cryptohash-sha256:cryptohash-sha256"
              , extraDocs = [] : List Schema.DocRef.Type
              , localPathOverride = None Text
              , kind = Some Schema.DependencyKind.ThirdParty
              , source = Some Schema.DependencySource.Hackage
              , scope = Some Schema.DependencyScope.Regular
              , versionConstraint = Some "^>=0.11"
              }
          , Schema.Dependency.WithAugmentation
              { name = "LeventErkok/sbv:sbv"
              , extraDocs = [] : List Schema.DocRef.Type
              , localPathOverride = None Text
              , kind = Some Schema.DependencyKind.ThirdParty
              , source = Some Schema.DependencySource.Hackage
              , scope = Some Schema.DependencyScope.Regular
              , versionConstraint = Some ">=11.7 && <15"
              }
          ]
        }
      , Schema.Package::{
        , name = "keiki-codec-json"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "keiki-codec-json"
        , description = Some "Optional JSON codec for keiki's RegFile"
        , dependencies =
          [ Schema.Dependency.WithAugmentation
              { name = "haskell/aeson:aeson"
              , extraDocs = [] : List Schema.DocRef.Type
              , localPathOverride = None Text
              , kind = Some Schema.DependencyKind.ThirdParty
              , source = Some Schema.DependencySource.Hackage
              , scope = Some Schema.DependencyScope.Regular
              , versionConstraint = Some "^>=2.2"
              }
          , Schema.Dependency.WithAugmentation
              { name = "Bodigrim/tasty-bench:tasty-bench"
              , extraDocs = [] : List Schema.DocRef.Type
              , localPathOverride = None Text
              , kind = Some Schema.DependencyKind.ThirdParty
              , source = Some Schema.DependencySource.Hackage
              , scope = Some Schema.DependencyScope.Test
              , versionConstraint = Some "^>=0.4 || ^>=0.5"
              }
          ]
        }
      , Schema.Package::{
        , name = "keiki-codec-json-test"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "keiki-codec-json-test"
        , description = Some "Property-test toolkit for keiki-codec-json downstream consumers"
        , dependencies =
          [ Schema.Dependency.WithAugmentation
              { name = "haskell/aeson:aeson"
              , extraDocs = [] : List Schema.DocRef.Type
              , localPathOverride = None Text
              , kind = Some Schema.DependencyKind.ThirdParty
              , source = Some Schema.DependencySource.Hackage
              , scope = Some Schema.DependencyScope.Regular
              , versionConstraint = Some "^>=2.2"
              }
          ]
        }
      , Schema.Package::{
        , name = "jitsurei"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "jitsurei"
        , description = Some "Worked examples for the keiki library"
        , dependencies =
          [ Schema.Dependency.WithAugmentation
              { name = "LeventErkok/sbv:sbv"
              , extraDocs = [] : List Schema.DocRef.Type
              , localPathOverride = None Text
              , kind = Some Schema.DependencyKind.ThirdParty
              , source = Some Schema.DependencySource.Hackage
              , scope = Some Schema.DependencyScope.Regular
              , versionConstraint = Some ">=11.7 && <15"
              }
          , Schema.Dependency.WithAugmentation
              { name = "Bodigrim/tasty-bench:tasty-bench"
              , extraDocs = [] : List Schema.DocRef.Type
              , localPathOverride = None Text
              , kind = Some Schema.DependencyKind.ThirdParty
              , source = Some Schema.DependencySource.Hackage
              , scope = Some Schema.DependencyScope.Test
              , versionConstraint = Some ">=0.4 && <0.6"
              }
          ]
        }
      ]
    , dependencies =
      [ "Bodigrim/tasty-bench:tasty-bench"
      , "LeventErkok/sbv:sbv"
      , "haskell-hvr/cryptohash-sha256:cryptohash-sha256"
      , "haskell/aeson:aeson"
      ]
    , dependencyRefs =
      [ Schema.MoriRef::{
        , namespace = "Bodigrim"
        , name = "tasty-bench"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "tasty-bench"
        }
      , Schema.MoriRef::{
        , namespace = "LeventErkok"
        , name = "sbv"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "sbv"
        }
      , Schema.MoriRef::{
        , namespace = "haskell-hvr"
        , name = "cryptohash-sha256"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "cryptohash-sha256"
        }
      , Schema.MoriRef::{
        , namespace = "haskell"
        , name = "aeson"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "aeson"
        }
      ]
    , okfBundles =
      [ Schema.OkfBundle::{
        , name = "improvement-requests"
        , path = "docs/improvement-requests"
        , profile = Some "mori/improvement-requests-profile.dhall"
        , okfVersion = "0.1"
        , description = Some
            "Cross-repository improvement requests owned by Keiki"
        }
      , Schema.OkfBundle::{
        , name = "adrs"
        , path = "docs/adr"
        , profile = Some "docs/adr/profile.dhall"
        , okfVersion = "0.2"
        , description = Some "Durable architecture decisions"
        }
      , Schema.OkfBundle::{
        , name = "capabilities"
        , path = "docs/capabilities"
        , profile = Some "docs/capabilities/profile.dhall"
        , okfVersion = "0.2"
        , description = Some
            "What keiki provides today, one concept per capability, with evidence"
        }
      , Schema.OkfBundle::{
        , name = "reviews"
        , path = "docs/reviews"
        , profile = Some "docs/reviews/profile.dhall"
        , okfVersion = "0.2"
        , description = Some
            "Commit-pinned records of Keiki artifacts having been reviewed"
        }
      ]
    }
