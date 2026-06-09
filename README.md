

# ATmega328P Reaction Time Game
> Bare-metal AVR Assembly — no Arduino libraries, no abstractions, just direct register manipulation.

A reaction-time measurement game written entirely in AVR assembly language for the **ATmega328P** (Arduino Uno). An LED and buzzer fire after a random delay; the player presses a button as fast as possible. The elapsed time is measured in milliseconds and sent over UART to a Serial Monitor with a performance rating.

Built as a **COAL (Computer Organization and Assembly Language)** course project.

---

## Demo Output (Serial Monitor)

```
Reaction Game Ready...
Get ready...
Reaction Time: 187 ms
🔥 Excellent!
-------------------
Get ready...
Reaction Time: 342 ms
🟡 Good
-------------------
Get ready...
Reaction Time: 521 ms
🔴 Slow
-------------------
```

---

## Hardware

| Pin | AVR Name | Role |
|-----|----------|------|
| D8  | PB0 | LED (visual cue) |
| D9  | PB1 | Buzzer via OC1A (audio cue) |
| D2  | PD2 | Push-button input |
| D1  | TX  | UART → Serial Monitor |

**Button wiring:** connect a 10 kΩ pull-down resistor from PD2 to GND. Without it the floating pin produces random readings. When the button is open, the resistor holds the pin at logic 0 (0 V). When pressed, 5 V dominates — the pin instantly reads logic 1.

---

## How It Works

### Game Loop (one round)

```
1. Print "Get ready..."  →  play 1000 Hz alert beep
2. Random delay          →  1000 – 4825 ms (seeded from Timer0)
3. LED ON + 2000 Hz tone →  player reacts and presses button
4. Measure reaction time →  16-bit ms counter via polling loop
5. Rate + report         →  UART output + buzzer feedback
6. Wait 2 s              →  repeat forever
```

### Random Delay

No random number hardware exists on the ATmega328P. Instead, Timer0 runs freely at 250 kHz from boot. Its count at the moment the loop starts is unpredictable (depends on exact timing of UART printing, delays, etc.), so it works as an entropy source:

```asm
in   r16, TCNT0       ; snapshot of free-running timer (0–255)
ldi  r17, 15
mul  r16, r17         ; r1:r0 = seed × 15  (0–3825)
movw r24, r0          ; copy 16-bit result into r25:r24
; add 1000 ms base to guarantee minimum 1-second wait
ldi  r16, LOW(1000)
ldi  r17, HIGH(1000)
add  r24, r16
adc  r25, r17         ; r25:r24 = 1000–4825 ms

random_delay_loop:
    rcall delay_1ms
    sbiw  r24, 1
    brne  random_delay_loop
```

`MUL` writes its 16-bit product to `r1:r0`. `MOVW` copies the pair atomically. `ADC` (Add with Carry) handles the carry from the low-byte addition into the high byte — essential for correct 16-bit arithmetic on this 8-bit CPU.

### Reaction Time Measurement

```asm
ldi  r24, 0
ldi  r25, 0          ; 16-bit counter = 0
wait_press:
    sbic PIND, PD2   ; skip next if pin is LOW (not pressed)
    rjmp press_done  ; pin is HIGH → button pressed → exit
    rcall delay_1ms  ; wait 1 ms
    adiw r24, 1      ; counter++
    rjmp wait_press
```

`SBIC` (Skip If Bit in I/O is Clear) reads the hardware pin register directly — no library, no interrupt, no overhead. The counter value when the loop exits equals the reaction time in milliseconds.

### 16-bit Comparison (Scoring)

A register on the ATmega328P is 8 bits (max 255). Reaction times can exceed 255 ms, so the value lives in the `r25:r24` pair. Comparing it against a threshold needs two instructions:

```asm
; Check: reactionTime < 200?
ldi  temp,  HIGH(200)
ldi  temp2, LOW(200)
cp   r24, temp2      ; compare low bytes
cpc  r25, temp       ; compare high bytes, accounting for borrow
brlo excellent       ; branch if result < 200
```

`CP` sets the Carry flag from the low-byte comparison. `CPC` (Compare with Carry) uses that Carry when comparing the high bytes, making it a proper 16-bit unsigned comparison.

### Score Thresholds

| Result | Condition | Buzzer Tone | Duration |
|--------|-----------|-------------|----------|
| 🔥 Excellent | < 200 ms | 2000 Hz | 100 ms |
| 🟡 Good | 200 – 399 ms | 1200 Hz | 200 ms |
| 🔴 Slow | ≥ 400 ms | 400 Hz | 400 ms |

Tone frequency formula (Timer1, CTC mode, prescaler ÷64):
```
f = 16,000,000 / (2 × 64 × (OCR1A + 1))
```

---

## Key Assembly Concepts

| Instruction | What it does here |
|-------------|-------------------|
| `SBI / CBI` | Set/clear a single I/O bit — drives LED and buzzer directly |
| `SBIC PIND, PD2` | Polls the button pin without any blocking or interrupt overhead |
| `OUT` vs `STS` | `OUT` reaches I/O addresses 0x00–0x3F; `STS` is needed for UART/Timer registers in extended I/O space (above 0x3F) |
| `CP + CPC` | Two-step 16-bit comparison on an 8-bit CPU |
| `MUL` | 8×8 unsigned multiply; result always lands in `r1:r0` |
| `PUSH / POP` | Saves `r25:r24` across print subroutines that clobber those registers |
| `LPM + Z` | Reads null-terminated strings from Flash program memory byte-by-byte |
| `RCALL / RET` | All delay and print functions are proper subroutines with stack-managed return addresses |

---

## UART & String Output

UBRR0 is set to **103**, giving exactly 9600 baud at 16 MHz:
```
UBRR0 = (16,000,000 / (16 × 9600)) − 1 = 103
```

Strings are stored in Flash using `.db` and read with the Z-pointer + `LPM`. A custom `print_uint16` routine converts the binary millisecond count to ASCII decimal digits using repeated subtraction (no hardware division on AVR) with leading-zero suppression.

---

## Software Delays

All timing is pure software — no timer interrupts. The 1 ms primitive:

```asm
delay_1ms:
    ldi  r24, LOW(3994)
    ldi  r25, HIGH(3994)
d1_loop:
    sbiw r24, 1          ; 2 cycles
    brne d1_loop         ; 2 cycles (taken)
    ret
; 3994 × 4 cycles + ~24 overhead ≈ 16,000 cycles = 1 ms @ 16 MHz
```

Longer delays (`delay_100ms`, `delay_200ms`, `delay_500ms`, `delay_2000ms`) are built by calling this in counted loops — no duplication.

---

## Building & Flashing

Assemble with **AVR Studio** or **AVRDUDE**. To flash to an Arduino Uno:

```bash
avrdude -c arduino -p m328p -P COM3 -b 115200 \
        -U flash:w:"reaction time game.hex":I
```

Change `COM3` to your port (`/dev/ttyUSB0` on Linux). Open any Serial Monitor at **9600 baud** to see results.

---

## Project Structure

```
.
├── reaction_time_game.asm   # Full AVR assembly source
├── reaction_time_game.hex   # Compiled Intel HEX (flash this)
└── README.md
```

---

## Team

| Name | Roll No |
|------|---------|
| AbdurRehman | F24608034 |
| Shoaib | F24608044 |
| Hamza Tariq | F24608024 |
| Abdullah Adil | F24608026 |

NUTECH — SE-2024 · Computer Organization and Assembly Language
