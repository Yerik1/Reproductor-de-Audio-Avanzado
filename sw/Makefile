CC      ?= gcc
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra -Werror -D_DEFAULT_SOURCE
BUILD   := build
LIB_SRC := src/wav.c src/catalog.c src/resampler.c src/mailbox.c src/player.c
HDRS    := $(wildcard src/*.h)

CROSS   ?= arm-linux-gnueabihf-
ARM_DIR := build-arm

.PHONY: all test arm clean

all: test

$(BUILD):
	mkdir -p $@

$(BUILD)/test_main: tests/test_main.c $(LIB_SRC) $(HDRS) | $(BUILD)
	$(CC) $(CFLAGS) -Isrc -o $@ tests/test_main.c $(LIB_SRC)

test: $(BUILD)/test_main
	./$(BUILD)/test_main

arm: $(ARM_DIR)/reproductor

$(ARM_DIR):
	mkdir -p $@

$(ARM_DIR)/reproductor: src/main_hps.c $(LIB_SRC) $(HDRS) | $(ARM_DIR)
	$(CROSS)gcc $(CFLAGS) -static -Isrc -o $@ src/main_hps.c $(LIB_SRC)

clean:
	rm -rf $(BUILD) $(ARM_DIR)
