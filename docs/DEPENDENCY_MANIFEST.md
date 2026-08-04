# Quillex 0.7.3 Dependency Constellation

Release dependencies in `mix.exs` resolve immutable Git revisions. Setting
`QUILLEX_LOCAL_DEPS=1` is the explicit sibling-path development override.

| Repository | Base revision | 0.7.3 result revision |
|---|---|---|
| Quillex | `f68e87588d2a93537a6ab7dfb4cc2b764a5df875` | `6da554a37d5a0cbb05cbc9903827489976e8d8a7` |
| Scenic | `e79ede34c7b2b2cb59e68d6aac0bf001e379270f` | `bc2854bceb943e70247dcbe50167aff08cc7147e` |
| scenic_driver_local | `825261acc3edcfc840ff511b405ca7c57a366efd` | `35de351b5bd2075e7651e9f8bef37e9f3659a85d` |
| scenic-widget-contrib | `44e382fa493ede12e645db944fadfaf4181fa739` | `e0bc98d6b67025d3b9c052598a4c6584b1624a15` |
| Spex | `fc1c21f74913c9d6899821b8265b1607c505b48b` | unchanged |
| scenic_mcp_experimental | `150558203147ffcd5aa0ccfb6ed50d20297998b3` | locked dependency `b3e0cb9b1a17dae2b645cb67a75531c503bc960d` |

The dependency commits contain only this release's scoped work. In particular,
the pre-existing `scenic_driver_local` Makefile and compile-task changes remain
uncommitted and intact; see `docs/AUDIT.md`.
