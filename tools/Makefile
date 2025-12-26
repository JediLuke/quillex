# window_pinner - Pure X11 window-to-desktop mover
#
# Build: make
# Install: make install (copies to ~/bin)
# Clean: make clean

CC = gcc
CFLAGS = -Wall -Wextra -O2
LDFLAGS = -lX11

TARGET = window_pinner
PREFIX = $(HOME)/bin

all: $(TARGET)

$(TARGET): window_pinner.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

install: $(TARGET)
	mkdir -p $(PREFIX)
	cp $(TARGET) $(PREFIX)/

clean:
	rm -f $(TARGET)

.PHONY: all install clean
