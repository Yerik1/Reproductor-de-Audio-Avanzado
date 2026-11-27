CC      ?= gcc
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra -Werror -D_DEFAULT_SOURCE
BUILD   := build
LIB_SRC := src/wav.c src/catalog.c src/resampler.c src/mailbox.c src/player.c
HDRS    := $(wildcard src/*.h)

.PHONY: all test clean

all: test

$(BUILD):
	mkdir -p $@

$(BUILD)/test_main: tests/test_main.c $(LIB_SRC) $(HDRS) | $(BUILD)
	$(CC) $(CFLAGS) -Isrc -o $@ tests/test_main.c $(LIB_SRC)

test: $(BUILD)/test_main
	./$(BUILD)/test_main

clean:
	rm -rf $(BUILD)
