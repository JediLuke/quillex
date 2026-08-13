# Elixir 1.20 and Quillex

Quillex targets Elixir 1.20 on Erlang/OTP 28. The exact development toolchain
is recorded in `.tool-versions`; `mix.exs` accepts compatible 1.20 patch
releases.

## Why 1.20

Elixir 1.20 is the first release in which the compiler gradually type-checks
all language constructs. Existing Elixir code participates automatically: the
compiler infers types from literals, patterns, guards, control flow, standard
library calls, and dependency information, then reports code it can prove is
incompatible or unreachable.

This is a **gradual set-theoretic type system**. A type describes a set of
possible runtime values; unions (`or`), intersections (`and`), and differences
(`and not`) let the compiler refine that set as execution moves through
patterns and guards. `dynamic()` marks a gradual type: the compiler reports a
problem only when none of the possible values can make the operation valid.

Official reading:

- [Elixir 1.20 release announcement](https://elixir-lang.org/blog/2026/06/03/elixir-v1-20-0-released/)
- [Gradual set-theoretic types](https://elixir.hexdocs.pm/gradual-set-theoretic-types.html)
- [Set-theoretic types cheatsheet](https://elixir.hexdocs.pm/types-cheat.html)
- [Compatibility and deprecations](https://elixir.hexdocs.pm/compatibility-and-deprecations.html)

## What we can use today

The type checker is already useful without adding annotations. During this
upgrade it found that RootScene built a state value with generic `Map.put/3`
calls and then passed it to a function requiring `%RootScene.State{}`. Making
the temporary render hints real struct fields and using struct-update syntax
preserved the type and removed the warning. It also proved three branches or
conditions were unreachable, so they were removed.

Compiler messages headed `type warning found at` are produced by this new
checker. Treat them as design feedback: prefer precise structs, discriminated
result tuples, pattern matching, and guards that make invariants visible.

## What is not available yet

Elixir 1.20 does not yet expose the new set-theoretic syntax for declaring
typed structs or function signatures. Those remain roadmap work. Existing
`@type` and `@spec` declarations still use Erlang typespec syntax and remain
valuable for documentation, tooling, and Dialyzer, but they are not the new
compiler type-signature system.

Do not add a third-party type checker merely to claim that Quillex is “typed.”
For now our policy is to keep Elixir's inferred type warnings clean in code we
own, add ordinary `@spec` declarations where they clarify public boundaries,
and adopt native signatures when Elixir stabilizes them.

## Audit workflow

Run a clean-enough forced compilation when reviewing a domain:

```bash
mix compile --force
```

Classify every diagnostic by owner:

1. Fix Quillex type warnings in the audited code.
2. Fix conventional Quillex warnings instead of hiding them.
3. Record warnings in pinned Scenic/widget forks against their owning repo.
4. Prefer upgrading third-party packages over patching files under `deps/`.

The eventual CI goal is warnings-as-errors for Quillex-owned code. The current
dependency constellation emits Elixir 1.20 warnings, so that gate needs either
dependency upgrades or an owner-aware diagnostics check first.
