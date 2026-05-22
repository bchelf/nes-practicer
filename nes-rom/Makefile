NES_NAME := timing_practice
BUILD_DIR := build
SRC_DIR := src

ASM ?= ca65
LD65 ?= ld65
PYTHON ?= python3

ASFLAGS := -g
LDFLAGS := -C nes.cfg

OBJS := $(BUILD_DIR)/main.o
CHR := $(BUILD_DIR)/font.chr

.PHONY: all clean

all: $(BUILD_DIR)/$(NES_NAME).nes

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(CHR): tools/make_chr.py | $(BUILD_DIR)
	$(PYTHON) tools/make_chr.py $@

$(BUILD_DIR)/main.o: $(SRC_DIR)/main.s $(CHR) | $(BUILD_DIR)
	$(ASM) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/$(NES_NAME).nes: $(OBJS) nes.cfg
	$(LD65) $(LDFLAGS) -o $@ $(OBJS)

clean:
	rm -rf $(BUILD_DIR)
