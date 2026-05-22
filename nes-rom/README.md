# NES Timing Practice

NES conversion of the keyboard timing trainer. This is an NROM mapper 0 ROM with
16KB PRG and 8KB CHR-ROM.

## Build

```sh
make
```

Output:

```text
build/timing_practice.nes
```

## Controls

- A, B, D-pad: start or stop a timing attempt
- Start: edit or confirm the goal
- Select: reset history/streaks
- While editing: Up/Down change goal by 1, Left/Right change by 10

Timing is counted in rendered NTSC frames. The first detected press starts at
frame 0, and each VBlank increments the active timer by one frame until the next
detected measured button press.
