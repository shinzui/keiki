let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/93104153ecf8817547229a867302a70a25c4b3d8/package.dhall
        sha256:5e00bba267f27069df1d3caadfec2ec6a8c4e797ce652d78c09528f981b71b42

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
      ]
    }
