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
      ]
    }
