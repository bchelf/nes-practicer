        .setcpu "6502"

.segment "HEADER"
        .byte "NES", $1A
        .byte 1              ; 16KB PRG, NROM-128
        .byte 1              ; 8KB CHR-ROM
        .byte %00000000      ; mapper 0, horizontal mirroring
        .byte %00000000
        .byte 0,0,0,0,0,0,0,0

.segment "ZEROPAGE"
pad:            .res 1
pad_prev:       .res 1
pad_new:        .res 1
meas_new:       .res 1
active:         .res 1
editing:        .res 1
timer:          .res 1
goal:           .res 1
last_valid:     .res 1
last_start:     .res 1
last_end:       .res 1
last_frames:    .res 1
last_result:    .res 1       ; 0 early, 1 on target, 2 late
last_delta:     .res 1
success_flash:  .res 1
success_delay:  .res 1
firework_visible: .res 1
sfx_step:       .res 1
current_streak: .res 1
best_streak:    .res 1
hist_count:     .res 1
hist_successes: .res 1
row_idx:        .res 1
render_phase:   .res 1
tmp:            .res 1
tmp2:           .res 1
num:            .res 1
ptr:            .res 2

.segment "BSS"
hist_start:     .res 10
hist_end:       .res 10
hist_frames:    .res 10
hist_result:    .res 10

PPUCTRL    = $2000
PPUMASK    = $2001
PPUSTATUS  = $2002
OAMADDR    = $2003
OAMDATA    = $2004
PPUSCROLL  = $2005
PPUADDR    = $2006
PPUDATA    = $2007
JOY1       = $4016
APU_STATUS = $4015
PULSE1_CTRL= $4000
PULSE1_SWEEP=$4001
PULSE1_TIMER_LO=$4002
PULSE1_TIMER_HI=$4003

BTN_A      = %00000001
BTN_B      = %00000010
BTN_SELECT = %00000100
BTN_START  = %00001000
BTN_UP     = %00010000
BTN_DOWN   = %00100000
BTN_LEFT   = %01000000
BTN_RIGHT  = %10000000
BTN_MEASURE= %11110011

.macro SETADDR hi, lo
        lda #hi
        sta PPUADDR
        lda #lo
        sta PPUADDR
.endmacro

.macro PUTS label
        lda #<label
        sta ptr
        lda #>label
        sta ptr+1
        jsr ppu_puts
.endmacro

.segment "CODE"

reset:
        sei
        cld
        ldx #$40
        stx $4017
        ldx #$FF
        txs
        inx
        stx PPUCTRL
        stx PPUMASK
        stx $4010

        jsr wait_vblank

        lda #$00
        tax
clear_ram:
        sta $0000,x
        sta $0100,x
        sta $0200,x
        sta $0300,x
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne clear_ram

        lda #3
        sta goal
        jsr init_audio
        jsr wait_vblank
        jsr load_palettes
        jsr clear_nametable
        jsr draw_static

        lda #%10000000
        sta PPUCTRL
        lda #%00011110
        sta PPUMASK

main:
        jsr poll_controller
        jsr update_logic
        jsr wait_vblank
        jsr draw_timer
        lda success_delay
        bne @success_text_first
        lda success_flash
        bne @firework
        lda firework_visible
        bne @firework
        jsr render_scheduled
        jmp @scroll
@firework:
        jsr update_success_sound
        jsr draw_success_firework
        jmp @scroll
@success_text_first:
        cmp #2
        bne @success_message
        jsr draw_last
        dec success_delay
        jmp @scroll
@success_message:
        jsr draw_message
        dec success_delay
@scroll:
        lda #0
        sta PPUSCROLL
        sta PPUSCROLL
        jmp main

nmi:
irq:
        rti

wait_vblank:
        bit PPUSTATUS
@wait:
        bit PPUSTATUS
        bpl @wait
        rts

load_palettes:
        SETADDR $3F, $00
        ldy #0
@loop:
        lda palette_data,y
        sta PPUDATA
        iny
        cpy #32
        bne @loop
        rts

clear_nametable:
        SETADDR $20, $00
        lda #' '
        ldx #4
        ldy #0
@loop:
        sta PPUDATA
        iny
        bne @loop
        dex
        bne @loop
        rts

draw_static:
        SETADDR $20, $25
        PUTS str_title
        SETADDR $20, $63
        PUTS str_map
        SETADDR $20, $83
        PUTS str_help
        SETADDR $20, $C2
        PUTS str_current
        SETADDR $21, $62
        PUTS str_last_report
        SETADDR $21, $E2
        PUTS str_last_10
        rts

poll_controller:
        lda pad
        sta pad_prev
        lda #1
        sta JOY1
        lda #0
        sta JOY1
        sta pad
        lda #1
        sta tmp
        ldx #8
@read:
        lda JOY1
        and #1
        beq @next
        lda pad
        ora tmp
        sta pad
@next:
        asl tmp
        dex
        bne @read
        lda pad
        eor pad_prev
        and pad
        sta pad_new
        and #BTN_MEASURE
        sta meas_new
        rts

update_logic:
        lda pad_new
        and #BTN_SELECT
        beq @not_reset
        jmp reset_state

@not_reset:
        lda editing
        beq @normal
        jmp update_editing

@normal:
        lda pad_new
        and #BTN_START
        beq @check_buttons
        lda #1
        sta editing
        rts

@check_buttons:
        lda meas_new
        beq @tick
        jsr first_button
        sta tmp
        lda active
        beq @start
        lda tmp
        sta last_end
        lda timer
        sta last_frames
        jsr record_attempt
        lda #0
        sta active
        rts

@start:
        lda tmp
        sta last_start
        lda #0
        sta timer
        lda #1
        sta active

@tick:
        lda active
        beq @done
        lda timer
        cmp #255
        beq @done
        inc timer
@done:
        rts

update_editing:
        lda pad_new
        and #BTN_START
        beq @not_done
        lda #0
        sta editing
        jsr clear_history
        rts
@not_done:
        lda pad_new
        and #BTN_UP
        beq @down
        lda goal
        cmp #99
        beq @down
        inc goal
@down:
        lda pad_new
        and #BTN_DOWN
        beq @right
        lda goal
        beq @right
        dec goal
@right:
        lda pad_new
        and #BTN_RIGHT
        beq @left
        lda goal
        clc
        adc #10
        cmp #100
        bcc @store_plus
        lda #99
@store_plus:
        sta goal
@left:
        lda pad_new
        and #BTN_LEFT
        beq @done
        lda goal
        cmp #10
        bcs @sub10
        lda #0
        sta goal
        rts
@sub10:
        sec
        sbc #10
        sta goal
@done:
        rts

reset_state:
        lda #0
        sta active
        sta editing
        sta timer
        jsr clear_history
        rts

clear_history:
        lda #0
        sta last_valid
        sta success_flash
        sta success_delay
        sta firework_visible
        sta sfx_step
        sta current_streak
        sta best_streak
        sta hist_count
        rts

first_button:
        lda meas_new
        and #BTN_A
        beq @b
        lda #0
        rts
@b:
        lda meas_new
        and #BTN_B
        beq @up
        lda #1
        rts
@up:
        lda meas_new
        and #BTN_UP
        beq @down
        lda #2
        rts
@down:
        lda meas_new
        and #BTN_DOWN
        beq @left
        lda #3
        rts
@left:
        lda meas_new
        and #BTN_LEFT
        beq @right
        lda #4
        rts
@right:
        lda #5
        rts

record_attempt:
        lda #1
        sta last_valid

        lda last_frames
        cmp goal
        beq @on_target
        bcc @early
        lda #2
        sta last_result
        lda last_frames
        sec
        sbc goal
        sta last_delta
        jmp @shift
@early:
        lda #0
        sta last_result
        lda goal
        sec
        sbc last_frames
        sta last_delta
        jmp @shift
@on_target:
        lda #1
        sta last_result
        lda #0
        sta last_delta

@shift:
        ldx #8
@shift_loop:
        lda hist_start,x
        sta hist_start+1,x
        lda hist_end,x
        sta hist_end+1,x
        lda hist_frames,x
        sta hist_frames+1,x
        lda hist_result,x
        sta hist_result+1,x
        dex
        bpl @shift_loop

        lda last_start
        sta hist_start
        lda last_end
        sta hist_end
        lda last_frames
        sta hist_frames
        lda last_result
        sta hist_result
        lda hist_count
        cmp #10
        beq @streak
        inc hist_count

@streak:
        lda last_result
        cmp #1
        beq @hit
        lda #0
        sta current_streak
        rts
@hit:
        lda #18
        sta success_flash
        lda #2
        sta success_delay
        lda #1
        sta firework_visible
        lda #$FF
        sta sfx_step
        lda current_streak
        cmp #255
        beq @check_best
        inc current_streak
@check_best:
        lda current_streak
        cmp best_streak
        bcc @done
        beq @done
        sta best_streak
@done:
        rts

init_audio:
        lda #%00000001
        sta APU_STATUS
        lda #%10111111
        sta PULSE1_CTRL
        lda #%00001000
        sta PULSE1_SWEEP
        rts

silence_success_sound:
        lda #%00110000
        sta PULSE1_CTRL
        rts

update_success_sound:
        lda success_delay
        bne @silent
        lda success_flash
        beq @silent
        cmp #16
        bcs @step0
        cmp #13
        bcs @step1
        cmp #10
        bcs @step2
        cmp #7
        bcs @step3
        cmp #4
        bcs @step4
        lda #5
        jmp @play_step
@step0:
        lda #0
        jmp @play_step
@step1:
        lda #1
        jmp @play_step
@step2:
        lda #2
        jmp @play_step
@step3:
        lda #3
        jmp @play_step
@step4:
        lda #4
@play_step:
        cmp sfx_step
        beq @done
        sta sfx_step
        tax
        lda #%10111111
        sta PULSE1_CTRL
        lda success_note_lo,x
        sta PULSE1_TIMER_LO
        lda success_note_hi,x
        sta PULSE1_TIMER_HI
@done:
        rts
@silent:
        lda sfx_step
        cmp #$FE
        beq @done
        jsr silence_success_sound
        lda #$FE
        sta sfx_step
        rts

render_scheduled:
        lda render_phase
        cmp #0
        bne @not_goal
        jsr draw_goal
        jmp @advance
@not_goal:
        cmp #1
        bne @not_last
        jsr draw_last
        jmp @advance
@not_last:
        cmp #2
        bne @not_header
        jsr draw_history_header
        jmp @advance
@not_header:
        cmp #12
        bne @not_streak
        jsr draw_streak
        jmp @advance
@not_streak:
        cmp #13
        bne @history
        jsr draw_message
        jmp @advance
@history:
        sec
        sbc #3
        sta row_idx
        jsr draw_history_row
@advance:
        inc render_phase
        lda render_phase
        cmp #14
        bcc @done
        lda #0
        sta render_phase
@done:
        rts

draw_success_firework:
        lda #0
        sta OAMADDR
        lda success_flash
        bne @active
        lda firework_visible
        bne @hide_visible
        rts
@hide_visible:
        ldx #16
@hide:
        lda #$F0
        sta OAMDATA
        lda #'*'
        sta OAMDATA
        lda #0
        sta OAMDATA
        sta OAMDATA
        dex
        bne @hide
        lda #0
        sta firework_visible
        rts

@active:
        dec success_flash
        lda success_flash
        cmp #12
        bcc @mid_or_big
        lda #<firework_small
        sta ptr
        lda #>firework_small
        sta ptr+1
        jmp @draw
@mid_or_big:
        cmp #6
        bcc @big
        lda #<firework_mid
        sta ptr
        lda #>firework_mid
        sta ptr+1
        jmp @draw
@big:
        lda #<firework_big
        sta ptr
        lda #>firework_big
        sta ptr+1
@draw:
        ldy #0
@loop:
        lda (ptr),y
        sta OAMDATA
        iny
        cpy #64
        bne @loop
        rts

draw_timer:
        SETADDR $20, $E2
        lda active
        beq @zero
        lda timer
        jmp @num
@zero:
        lda #0
@num:
        jsr ppu_put_num3
        PUTS str_frames
        rts

draw_goal:
        SETADDR $21, $22
        PUTS str_goal
        lda goal
        jsr ppu_put_num3
        PUTS str_frames
        rts

draw_last:
        SETADDR $21, $82
        jsr clear_short
        SETADDR $21, $A2
        jsr clear_short
        lda last_valid
        bne @valid
        SETADDR $21, $82
        PUTS str_no_attempt
        rts
@valid:
        SETADDR $21, $82
        lda last_start
        jsr ppu_put_button
        PUTS str_arrow
        lda last_end
        jsr ppu_put_button
        lda #' '
        sta PPUDATA
        lda last_frames
        jsr ppu_put_num3
        lda #'F'
        sta PPUDATA

        SETADDR $21, $A2
        lda last_result
        cmp #1
        beq @on
        cmp #0
        beq @early
        PUTS str_late_by
        lda last_delta
        jsr ppu_put_num3
        rts
@early:
        PUTS str_early_by
        lda last_delta
        jsr ppu_put_num3
        rts
@on:
        PUTS str_on_target
        rts

draw_history_header:
        lda #0
        sta hist_successes
        tax
@count:
        cpx hist_count
        bcs @draw
        lda hist_result,x
        cmp #1
        bne @next
        inc hist_successes
@next:
        inx
        cpx #10
        bne @count
@draw:
        SETADDR $21, $E2
        PUTS str_last_10
        lda #' '
        sta PPUDATA
        lda hist_successes
        jsr ppu_put_num2
        PUTS str_over_10
        rts

draw_history_row:
        ldx row_idx
        lda hist_row_hi,x
        sta PPUADDR
        lda hist_row_lo,x
        sta PPUADDR
        jsr clear_short
        ldx row_idx
        cpx hist_count
        bcs @done
        lda hist_row_hi,x
        sta PPUADDR
        lda hist_row_lo,x
        sta PPUADDR
        txa
        clc
        adc #1
        jsr ppu_put_num2
        lda #' '
        sta PPUDATA
        ldx row_idx
        lda hist_start,x
        jsr ppu_put_button
        PUTS str_arrow
        ldx row_idx
        lda hist_end,x
        jsr ppu_put_button
        lda #' '
        sta PPUDATA
        ldx row_idx
        lda hist_frames,x
        jsr ppu_put_num3
        lda #'F'
        sta PPUDATA
        lda #' '
        sta PPUDATA
        ldx row_idx
        lda hist_result,x
        tax
        lda result_chars,x
        sta PPUDATA
@done:
        rts

draw_streak:
        SETADDR $23, $42
        PUTS str_streak
        lda current_streak
        jsr ppu_put_num3
        PUTS str_best
        lda best_streak
        jsr ppu_put_num3
        rts

draw_message:
        SETADDR $23, $62
        jsr clear_line
        SETADDR $23, $62
        lda editing
        beq @not_editing
        PUTS str_msg_edit
        rts
@not_editing:
        lda active
        beq @not_active
        PUTS str_msg_stop
        rts
@not_active:
        lda last_valid
        beq @start
        lda last_result
        cmp #1
        beq @msg_on
        cmp #0
        beq @msg_early
        PUTS str_msg_late
        rts
@msg_early:
        PUTS str_msg_early
        rts
@msg_on:
        PUTS str_msg_on
        rts
@start:
        PUTS str_msg_start
        rts

ppu_puts:
        ldy #0
@loop:
        lda (ptr),y
        beq @done
        sta PPUDATA
        iny
        bne @loop
@done:
        rts

clear_line:
        ldx #32
        bne clear_spaces
clear_short:
        ldx #28
clear_spaces:
        lda #' '
@loop:
        sta PPUDATA
        dex
        bne @loop
        rts

ppu_put_button:
        asl a
        tax
        lda button_ptrs,x
        sta ptr
        lda button_ptrs+1,x
        sta ptr+1
        jmp ppu_puts

ppu_put_num2:
        sta num
        lda #'0'
        sta tmp
        lda num
@tens:
        cmp #10
        bcc @ones
        sec
        sbc #10
        sta num
        inc tmp
        jmp @tens
@ones:
        lda tmp
        sta PPUDATA
        lda num
        clc
        adc #'0'
        sta PPUDATA
        rts

ppu_put_num3:
        sta num
        lda #'0'
        sta tmp
        lda num
@hundreds:
        cmp #100
        bcc @put_h
        sec
        sbc #100
        sta num
        inc tmp
        jmp @hundreds
@put_h:
        lda tmp
        sta PPUDATA
        lda #'0'
        sta tmp
        lda num
@tens:
        cmp #10
        bcc @put_t
        sec
        sbc #10
        sta num
        inc tmp
        jmp @tens
@put_t:
        lda tmp
        sta PPUDATA
        lda num
        clc
        adc #'0'
        sta PPUDATA
        rts

.segment "RODATA"
palette_data:
        .byte $0F,$30,$10,$00, $0F,$30,$10,$00, $0F,$30,$10,$00, $0F,$30,$10,$00
        .byte $0F,$30,$10,$00, $0F,$30,$10,$00, $0F,$30,$10,$00, $0F,$30,$10,$00

; Rising major arpeggio on pulse 1: C5 E5 G5 C6 E6 G6.
success_note_lo:
        .byte $53,$F3,$97,$29,$79,$4B
success_note_hi:
        .byte $01,$00,$00,$00,$00,$00

firework_small:
        .byte 112,'*',0,124, 104,'*',0,124, 120,'*',0,124, 112,'*',0,116
        .byte 112,'*',0,132, 106,'*',0,118, 106,'*',0,130, 118,'*',0,130
        .byte 100,'*',0,116, 124,'*',0,116, 100,'*',0,132, 124,'*',0,132
        .byte 108,'*',0,112, 116,'*',0,112, 108,'*',0,136, 116,'*',0,136
firework_mid:
        .byte 112,'*',0,124,  72,'*',0,124, 176,'*',0,124, 112,'*',0, 72
        .byte 112,'*',0,176,  84,'*',0, 84,  84,'*',0,164, 164,'*',0,164
        .byte 164,'*',0, 84,  96,'*',0, 76, 128,'*',0, 76,  96,'*',0,172
        .byte 128,'*',0,172,  76,'*',0,104, 172,'*',0,104,  76,'*',0,144
firework_big:
        .byte 112,'*',0,124,   8,'*',0,124, 240,'*',0,124, 112,'*',0,  8
        .byte 224,'*',0,224,   8,'*',0,  8,   8,'*',0,224, 224,'*',0,  8
        .byte 112,'*',0,224,  40,'*',0, 40, 184,'*',0, 40,  40,'*',0,208
        .byte 184,'*',0,208,   8,'*',0, 72, 240,'*',0, 72,   8,'*',0,176

button_ptrs:
        .word str_a, str_b, str_up, str_down, str_left, str_right

result_chars:
        .byte '-', '=', '+'

hist_row_hi:
        .byte $22,$22,$22,$22,$22,$22,$22,$22,$23,$23
hist_row_lo:
        .byte $02,$22,$42,$62,$82,$A2,$C2,$E2,$02,$22

str_title:       .byte "NES TIMING PRACTICE",0
str_map:         .byte "D-PAD AND A/B START OR STOP",0
str_help:        .byte "START EDIT GOAL  SELECT RESET",0
str_current:     .byte "CURRENT TIMER",0
str_goal:        .byte "GOAL ",0
str_frames:      .byte " FRAMES",0
str_last_report: .byte "LAST REPORT",0
str_no_attempt:  .byte "NO ATTEMPT",0
str_last_10:     .byte "LAST 10 ATTEMPTS",0
str_over_10:     .byte "/10",0
str_arrow:       .byte " > ",0
str_early_by:    .byte "EARLY BY ",0
str_late_by:     .byte "LATE BY ",0
str_on_target:   .byte "ON TARGET",0
str_streak:      .byte "STREAK ",0
str_best:        .byte " BEST ",0
str_msg_edit:    .byte "EDIT GOAL U/D 1 L/R 10 START OK",0
str_msg_stop:    .byte "PRESS ANY MEASURE BUTTON TO STOP",0
str_msg_start:   .byte "PRESS A/B/D-PAD TO START",0
str_msg_early:   .byte "EARLY",0
str_msg_late:    .byte "LATE",0
str_msg_on:      .byte "ON TARGET",0
str_a:           .byte "A",0
str_b:           .byte "B",0
str_up:          .byte "UP",0
str_down:        .byte "DOWN",0
str_left:        .byte "LEFT",0
str_right:       .byte "RIGHT",0

.segment "VECTORS"
        .word nmi, reset, irq

.segment "CHARS"
        .incbin "build/font.chr"
