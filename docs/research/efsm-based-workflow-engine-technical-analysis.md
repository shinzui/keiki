<!-- Note: note_01kps2ajmne3qs9bbsz3j6pzv7 -->

# EFSM-Based Workflow Engine — Technical Analysis

> **Status: historical.** This analysis assumed an EFSM (control + opaque
> context + δ/ω/ρ) as the underlying formalism. keiki rejected EFSM in
> favour of the symbolic-register transducer; see
> `data-direction-c-symbolic-and-register-automata.md` and
> `synthesis-c-foundation-b-presentation-with-worked-examples.md` for
> the chosen direction. The capability mapping, strengths/limitations,
> and positioning analysis below remain useful as a workflow-engine
> survey, but every code sketch (`δ : S × Σ × C → S × C`, etc.) is in
> the rejected formalism.

## 1. Overview

This project proposes a workflow engine built on top of an **Extended Finite State Machine (EFSM)**, combined with:

* Event Sourcing (durability, replay)
* Message Queue (execution + scheduling)
* Subscriptions (effect interpretation)

The system replaces traditional workflow engines (e.g., Temporal/Cadence) with a **fully explicit, analyzable, and composable architecture**.

The EFSM acts as the *deterministic decision core*, while infrastructure handles execution concerns.

---

## 2. Core Architecture

### 2.1 Execution Model

The system decomposes workflow execution into four layers:

1. **EFSM (Pure Logic)**

   * Control state (finite, enumerable)
   * Context (dynamic data)
   * Transition functions (delta, omega, rho)

2. **Event Store (Durability Layer)**

   * Append-only log
   * Full replay for recovery
   * Audit trail by construction

3. **Queue (Execution Layer)**

   * Command delivery
   * Scheduling (delayed messages)
   * Work distribution

4. **Subscriptions (Effect Layer)**

   * Interpret events into side effects
   * Dispatch activities
   * Schedule timers

---

### 2.2 EFSM Formalism

An Extended Transducer is defined as:

* S: finite control states
* Ctx: unbounded context
* C: input commands
* E: output events

Functions:

* delta: transition function
* omega: output generation
* rho: context update

Key property:

> Control flow remains analyzable while data remains expressive.

---

## 3. Capability Mapping

The system reproduces workflow engine features as follows:

### 3.1 Durable Execution

* Achieved via event sourcing
* Replay reconstructs full state

### 3.2 Timers

* Modeled as events
* Implemented via delayed queue messages

### 3.3 Activities

* Request/response via queue
* External workers execute side effects

### 3.4 Retries

* Modeled explicitly in EFSM (state + context)
* Or handled by infrastructure policies

### 3.5 Signals

* Represented as commands
* Naturally handled by EFSM input alphabet

### 3.6 Child Workflows

* Event-driven orchestration
* Parent emits event → subscription spawns child

### 3.7 Cancellation

* Modeled via commands + compensation transitions

### 3.8 Versioning

* Event upcasting during replay

### 3.9 Snapshotting

* Reduces replay cost
* Transparent to EFSM

---

## 4. Strengths

### 4.1 Formal Verification

* Deadlock detection
* Reachability analysis
* Workflow equivalence
* Contract verification

### 4.2 Explicit Execution Model

* No hidden runtime behavior
* All effects are event-driven

### 4.3 Composability

* Uniform abstraction for:

  * Aggregates
  * Sagas
  * Workflows
  * Process managers

### 4.4 Auditability

* Full history preserved
* Deterministic replay

### 4.5 Infrastructure Independence

* No vendor lock-in
* Built on standard primitives

---

## 5. Limitations

### 5.1 Data-Level Verification Gap

* Context is not enumerable
* Cannot fully verify dynamic invariants

### 5.2 Operational Complexity

* Requires building:

  * Dashboard
  * Debugging tools
  * Monitoring

### 5.3 Developer Ergonomics

* EFSM is low-level
* Not suitable as authoring interface

### 5.4 Dynamic Fan-Out Analysis

* Runtime-dependent behavior not fully analyzable

---

## 6. Required Enhancements for Production

### 6.1 High-Level DSL

Introduce a linear, composable DSL:

* Sequential steps
* Parallel execution
* Retry policies
* Timeouts

Compiled into EFSM.

---

### 6.2 Built-in Primitives

Provide first-class constructs:

* retry
* timeout
* parallel
* race
* fan-out

---

### 6.3 Deterministic Runtime

Ensure:

* No side effects inside workflows
* All non-determinism externalized

---

### 6.4 Observability Layer

Implement:

* Workflow dashboard
* Event history viewer
* State inspection

---

### 6.5 Versioning Strategy

Support:

* Backward compatibility
* Long-running workflows across deployments

---

### 6.6 Execution Guarantees

Provide:

* Single-threaded workflow execution
* Idempotent command handling
* Ordering guarantees

---

## 7. Conceptual Model

The system can be understood as:

* EFSM = decision logic
* Event Store = memory
* Queue = execution
* Subscriptions = effects

---

## 8. Strategic Positioning

This approach is best suited for:

* Event-sourced architectures
* Systems requiring auditability
* Complex business workflows
* Strong correctness guarantees

Less suited for:

* Simple task orchestration
* Teams needing minimal setup

---

## 9. Conclusion

This project defines a workflow engine architecture that:

* Matches the capabilities of existing systems
* Provides stronger formal guarantees
* Aligns naturally with event sourcing

The remaining work is not theoretical, but practical:

> Building the developer and operational layers that make the system usable at scale.

---

## 10. Key Insight

The EFSM is not the workflow engine itself.

It is the **core execution model**, around which a complete system is constructed.


