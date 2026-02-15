# Old README Notes

Preserved from the original README.md.

## TODO list

* would be cool to be able to call quillex from terminal, e.g. `qlx .`
* currently workin on showing the menubar...

## Known Bugs

### MenuBar

* We use the y-axis boundary to de-activate the menu, but not the x-axis
  of each sub-menu, so you can move the mouse around sideways without
  de-activating the menu - in practice, it's not such a pain or dangerous

## Features I want to support

- unlimited undo/redo capability
- unlimited line length
- global search/replace (on all buffers at once)
- block operations?
- automatic indentation
- word wrapping
- justified line wrap
- delimiter matching
- code folding
- scrolling text boxes
- cut & paste
- search & replace
- memory limit, how much we will pull into memory at any one point of time... Need to use paging if we go over this limit
- highlight current line & current word like VS code doeso

## RadixStore design notes

  # the Root scene pulls from the radix store on bootup, and then subscribes to changes
  # the reason why I'm doing it this way, and not passing in the radix state
  # from the top (which would be possible, because I initialize the
  # radixstate during app bootup & pass it in to radix store, just so that
  # this process can then go fetch it) is because it seems cleaner to me
  # because if this process restarts then it will go & fetch the correct state &
  # continue from there, vs if I pass it in then it will restart again with
  # whatever I gave it originally (right??!?)

  # now that I type this out... wouldn't that be a safer, better option?
  # this process isn't supposed to crash, if it does crash probably it is due
  # to bad state, and then probably I don't want to immediately go & fetch that
  # bad state...

  # for that reason I actually _am_ going to pass it in from the top

  # After all this debate I changed my mind again, I dont want to be passing
  # around big blobs of state, I want the RadixStore process to just keep
  # the State and everything interacts with RadixState via that process, so
  # this process does go & fetch RadixState on bootup

  # Lol further addendum, I've decided that the reasoning of not wanting
  # to pass the RadixState in because I didnt want to copy a huge state variable
  # around is absurd given how muich I copy it around all over the place in
  # the rest of the app, but I'm going to stick with just fetching it on
  # startup because if the whole GUI does crash up to this level, I want
  # it to start again from the current RadixStore
