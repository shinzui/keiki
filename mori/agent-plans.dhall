let Schema = https://raw.githubusercontent.com/shinzui/mori-schema/a3c59033a08c2eaef2cfba4a3c99fc9c192ca6d7/package.dhall
      sha256:18258ef583580a897f4af3e7c86db0342afb42fb40efc535b217ba1089230141

let AgentPlans = https://raw.githubusercontent.com/shinzui/mori-schema/a3c59033a08c2eaef2cfba4a3c99fc9c192ca6d7/extensions/agent-plans/package.dhall
      sha256:0b567808087da1924fb121df044c9432f676bb81305d5373809e3182d054943b

in  AgentPlans.AgentPlansCatalog::{
    , plans =
      [ AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/84-preserve-readable-business-semantics-in-keiki-transducers-and-diagrams.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , owner = None Text
        , summary = None Text
        , dependencies =
          [ AgentPlans.PlanDependency::{
            , kind = AgentPlans.DependencyKind.Integration
            , target = "mori://shinzui/keiro/plans/179-generate-one-human-readable-authoritative-keiro-transducer"
            }
          ]
        }
      ]
    }
