let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/1f70781427426c09673d46f8e6733b7e7d0abedc/package.dhall
        sha256:3b79aae9216456678300441ca8616b64a4b4fa520a1286dfcc418f60899d5d4a

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
    }
