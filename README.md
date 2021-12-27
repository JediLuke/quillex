# QuillEx

A simple text-editor (basically a [Gedit](https://wiki.gnome.org/Apps/Gedit) clone) written entirely in Elixir.

#TODO screenshot

## Installing

### Scenic

The graphics in QuillEx are powered by an Elixir library called [Scenic](https://github.com/boydm/scenic). For Scenic to compile. some OpenGL libraries must be present on the system. Please see the Scenic [installation docs](https://hexdocs.pm/scenic/install_dependencies.html) on how to install Scenic on your system.

### Running QuillEx in dev mode

Once you have Scenic, just clone the repo and run in dev mode.

```
git clone #TODO
iex -S mix run
```

## TODO list

* would be cool to be able to call quillex from terminal, e.g. `qlx .`
* currently workin on showing the menubar...

## Known Bugs

### MenuBar

* We use the y-axis boundary to de-activate the menu, but not the x-axis
  of each sub-menu, so you can move the mouse around sideways without
  de-activating the menu - in practice, it's not such a pain or dangerous