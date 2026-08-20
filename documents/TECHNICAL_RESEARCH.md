# TF2 Distribution Manager — Technical Research Checklist

## Purpose

This document lists the technical questions that must be verified against the Transport Fever 2 Lua/modding API before the project commits to implementation.

Anything not proven by research is explicitly flagged as RESEARCH REQUIRED.

## Research Status Table

| Capability | Status | Notes |
| --- | --- | --- |
| Game scripts can access the Transport Fever 2 API | VERIFIED BY OFFICIAL API DOCUMENTATION | The modding framework exposes Lua scripting access to the game environment. |
| Line state can be inspected | VERIFIED BY OFFICIAL API DOCUMENTATION | Official docs describe line-related state and management surfaces. |
| Vehicles belonging to lines can be inspected | VERIFIED BY OFFICIAL API DOCUMENTATION | Vehicle and line objects are exposed through scripting APIs. |
| Existing vehicles can be assigned or reassigned to lines through API commands | VERIFIED BY OFFICIAL API DOCUMENTATION | The API exposes line assignment and vehicle management commands in principle. |
| Line creation and update commands exist | VERIFIED BY OFFICIAL API DOCUMENTATION | Line creation/update operations are documented as part of the game scripting surface. |
| Vehicle state exposes useful line/depot/terminal information | VERIFIED BY OFFICIAL API DOCUMENTATION | The object model includes runtime vehicle state information relevant to route and depot context. |
| Cargo systems expose cargo-related simulation state | VERIFIED BY OFFICIAL API DOCUMENTATION | Cargo and freight simulation data are part of the documented modding surface. |
| Custom GUI components are supported | VERIFIED BY OFFICIAL API DOCUMENTATION | The UI/modding docs describe custom GUI capabilities. |
| Whether reassignment is safe at arbitrary points during a delivery | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Safe reassignment timing must be verified in runtime scenarios. |
| Safest moment/state for truck reassignment | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | The safest transition point must be tested, not assumed. |
| Exact cargo destination information available for cargo waiting at a Distribution Centre | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Need runtime confirmation of what cargo/destination data is actually exposed. |
| Exact vehicle cargo compatibility extraction | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Compatibility must be tested across multiple vehicle types and eras. |
| Exact vehicle carrying-capacity extraction across vehicle types | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Capacity values must be validated by test rather than inferred from general game logic. |
| Whether persistent managed lines behave correctly with cargo routing | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Stable lines may help or hinder routing, and this requires runtime proof. |
| Whether a zero-vehicle persistent line continues to influence cargo routing correctly | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | This is a critical edge case for persistent service design. |
| Whether a standby line can physically hold trucks without unwanted circulation | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Standby semantics must be confirmed in a controlled in-game test. |
| Whether station waiting reduces operating cost and by how much | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Official docs confirm waiting/full-load behaviour but not a specific discount percentage. |
| Whether multiple Distribution Centres can safely share trucks | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Home-centre ownership and cross-centre assistance must be tested. |
| Whether inter-DC cargo transfer can work using the base game's cargo routing | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | This is a major system-level design question and remains unproven. |
| Whether historical physical Distribution Centre buildings can be modelled with era-based progression and production constraints | RESEARCH REQUIRED | This is a future content pipeline question, not a V1 implementation concern. |
| Whether loading positions and standby positions can be represented as distinct physical bottlenecks | RESEARCH REQUIRED | Exact support depends on vehicle pathing and yard simulation. |
| Whether reverse-in truck bays are feasible with custom paths and vehicle behaviour | RESEARCH REQUIRED | This is experimental and should not block the logical V1 model. |
| Whether Blender-created TF2 asset pipelines are compatible with actual export requirements | RESEARCH REQUIRED | Exact format and workflow must be verified with the tooling and game requirements. |

## Source Notes

Researchers should consult the official Transport Fever 2 documentation before assuming behavior beyond the documented API surface:

- Modding documentation
- API Reference
- Game Scripts documentation
- User Interface documentation
- line/vehicle/cargo API modules

Do not invent function names or API behavior unless they have been explicitly checked against the official API reference.

## Core Research Questions

### Town Association and Multiple Distribution Centres

- Can a logical Distribution Centre controller be associated with a Transport Fever 2 town?
- Can a town eventually support multiple Distribution Centres without redesigning the core architecture?
- Can the player define and manage several centres in the same town while keeping their fleets independent?
- Is there any base-game constraint that makes this concept unrealistic? RESEARCH REQUIRED.

### Vehicle State

- Can the mod identify which vehicles belong to the player's fleet?
- Can it identify whether a vehicle is idle, active, assigned, or otherwise in service?
- Can it identify the vehicle type and its cargo compatibility?
- Can it read carrying capacity or equivalent load data?
- Can it distinguish road freight vehicles from other vehicle classes?
- Can it inspect vehicles at a Distribution Centre and/or across the network?

### Cargo and Demand

- Can the mod inspect cargo demand for a stop or destination?
- Can it inspect cargo backlog or waiting counts?
- Can it determine whether a stop is currently under-served or overloaded?
- Can it detect cargo type requirements for a destination?
- Can it read cargo status without duplicating or interfering with Transport Fever 2's own routing logic?
- Can the mod inspect cargo waiting at a Distribution Centre itself, and if so, what exact information is available? RESEARCH REQUIRED.

### Line and Route State

- Can the mod inspect line assignments and line state for vehicles?
- Can it determine whether a vehicle is on a route, a depot line, or a custom managed service?
- Can it create, edit, or maintain a persistent system-managed line between a Distribution Centre and a managed destination?
- Can it safely keep a persistent line alive without causing cargo routing disruption?
- Is line churn required or harmful for cargo routing? RESEARCH REQUIRED.
- Does Transport Fever 2 require stable lines for certain cargo behaviors? RESEARCH REQUIRED.
- Does a zero-vehicle persistent line continue to influence cargo routing correctly? RESEARCH REQUIRED.

### Reassignment and Dispatch

- Can the mod dynamically reassign an existing vehicle from one service or line to another?
- Can it move a vehicle from standby to a managed service without destroying line state?
- Can it return a vehicle from managed service back to standby or a depot pool?
- Can it do this for multiple vehicles on the same destination?
- Are there constraints or limitations on vehicle reassignment or route change timing? RESEARCH REQUIRED.
- What is the safest moment or state for truck reassignment? RESEARCH REQUIRED.

### Standby / Parking Concept

The standby pool concept is a key design element, but it depends on how the game models idle vehicles and depot-like state.

Questions:

- Can idle trucks be grouped into a standby pool or mover line at the Distribution Centre?
- Is a vehicle's standby state represented by line assignment, depot assignment, or another state?
- Is it better to model standby as a dedicated line, a depot pool, or an internal dispatch state? RESEARCH REQUIRED.
- Can a standby line physically hold trucks without causing unwanted circulation? RESEARCH REQUIRED.

### Persistent Managed Lines

The design prefers persistent system-managed lines instead of repeatedly creating and deleting lines.

Questions:

- Does the API allow stable line management across long periods?
- Are persistent lines compatible with cargo routing for road freight?
- Is there a technical penalty for line persistence or dynamic reallocation? RESEARCH REQUIRED.

### Compatibility and Capacity

The design assumes compatibility and capacity can be read and respected.

Questions:

- Does the API expose cargo type compatibility and load capacity cleanly?
- Are there differences across vehicle ages, vehicle types, and cargo classes?
- Can the mod safely infer whether a given truck can carry a specific cargo type? RESEARCH REQUIRED.
- Can carrying capacity be extracted reliably for early horse carts, mid-century trucks, and modern high-capacity vehicles? RESEARCH REQUIRED.

### Inter-Distribution-Centre Fleet Assistance

- Can a vehicle be safely temporarily reassigned between Distribution Centre controllers?
- How should home-centre ownership be persisted?
- Does cross-centre reassignment affect cargo routing?
- How do borrowed trucks safely return home?
- Can a player-defined local reserve be enforced before trucks can be lent? RESEARCH REQUIRED.

### Inter-Distribution-Centre Cargo Transfer

- Can bulk cargo be transferred between Distribution Centres using the base game's cargo routing system?
- Can persistent lines between centres support this naturally?
- Does this create artificial cargo demand or conflict with base-game destination/routing logic? RESEARCH REQUIRED.

### Standby Economics Research

- Does the base game provide reduced operating cost for vehicles genuinely waiting in a station or terminal?
- What exact reduction, if any, occurs when waiting or idling in a controlled terminal state?
- Does this differ from vehicles queued or stopped outside a terminal?
- Should the mod prefer native TF2 waiting-cost mechanics over a custom maintenance rebate? RESEARCH REQUIRED until tested.

### Historical Physical Distribution Centres

- Can era-based Distribution Centre physical buildings be introduced in a way that fits Transport Fever 2's historical progression?
- Will separate loading positions and standby positions be required to represent bottlenecks and infrastructure differences?
- Can reverse-in loading bays be supported by pathing or vehicle behaviour, or do they require a forward-only fallback?
- Is Blender the appropriate future workflow for asset creation, and what exact export requirements apply? RESEARCH REQUIRED.

## Verification Strategy

The project must use a staged validation process:

1. inspect the official API references and examples,
2. run a minimal Lua test harness,
3. confirm the behavior against a controlled in-game scenario,
4. record the results in a design decision log,
5. and only then proceed to implementation planning.

## Explicit Rule

No feature may be considered implemented unless the underlying API behavior has been proven in a test environment. If nothing in the API can support the feature, the feature is rejected or postponed as RESEARCH REQUIRED.
