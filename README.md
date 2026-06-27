# FPGA Voice Recorder with Real-Time DSP

A digital audio recorder and player implemented in SystemVerilog on the
**Terasic DE2-115 (Cyclone IV)** board. Beyond basic record/playback, it
implements variable-speed playback with linear interpolation, reverse
playback, a dual-memory architecture (on-chip SRAM + 128 MB SDRAM with a
prefetch cache), and a live LCD / seven-segment status display.

> Originally built as a team project for **NTUEE Digital Circuit Lab (DCLAB), Lab 3**.
> See [Attribution](#attribution--academic-integrity) for what is original work
> vs. course-provided skeleton.

---

## Highlights

- **Full audio path** — WM8731 codec brought up over **I²C**, with **I²S**
  receive/transmit (`AudRecorder` / `AudPlayer`), including correct handling of
  the I²S empty cycle and MSB-first bit shifting.
- **Real-time DSP** (`AudDSP`)
  - Variable-speed playback from **0.125× to 8×**
  - **Linear (1st-order) interpolation** and **zero-order (piecewise-constant)
    interpolation** for slow playback
  - **Reverse playback**
  - Signed arithmetic throughout to avoid overflow "pops"
- **Dual-memory architecture**
  - On-board **SRAM (2 MB)** for short recordings
  - **128 MB SDRAM** (2 × 64 MB) over an **Avalon-MM** bridge for long recordings
  - A **prefetch cache** (BRAM) that hides SDRAM latency so high-speed playback
    does not drop out
- **Resource-aware design** — playback time is shown as `MM:SS` using a
  precomputed ROM lookup table instead of a hardware divider, saving logic
  elements.
- **Live status UI** — current mode and playback speed on a character LCD,
  plus elapsed time on the seven-segment display.

---

## Demo

> _Add a short clip or photos of the board here — a 20–30 s video of recording,
> then playing back at 2× / 0.25× / reverse is the single most convincing thing
> you can put in this repo._

```
[ photo of DE2-115 running ]   [ LCD showing "PLAYING 2.0x" ]
```

---

## System Architecture

```
                         DE2-115 FPGA (Top.sv)
  ┌───────────────┐   I²C    ┌────────────────────┐
  │ I2cInitializer│ ───────► │  WM8731 Audio CODEC │
  └───────────────┘          │     (ADC / DAC)     │
                             └─────────┬───────────┘
            I²S (DACDAT) ◄──┐          │ I²S (ADCDAT)
  ┌───────────────┐         │          ▼
  │   AudPlayer   │         │   ┌──────────────┐
  │ (par → ser)   │         │   │ AudRecorder  │
  └──────┬────────┘         │   │ (ser → par)  │
         ▲ dac_data         │   └──────┬───────┘
  ┌──────┴────────┐         │          │ rec_data
  │    AudDSP     │ ◄───────┘   ┌──────▼────────────┐
  │ interpolation │ ◄────────── │  memory_adaptor    │
  │ speed / rev   │             │  (DRAM_Arbiter.sv) │
  └──────┬────────┘             └──┬──────────┬──────┘
         │ addr                    │          │
   ┌─────▼──────┐  ┌────────────┐  ▼          ▼
   │ SRAM ctrl  │  │ audio.mif  │ BRAM    SDRAM ctrl
   │ (2 MB)     │  │ (Audio ROM)│ cache   (Qsys / Avalon)
   └────────────┘  └────────────┘            │
                                              ▼
   ┌───────────────┐                   [ 128 MB off-chip SDRAM ]
   │ lcd_controller│  ──► LCD (mode / speed)
   └───────────────┘
                       seven-seg ──► elapsed time (MM:SS)
```

Three cooperating FSMs:

1. **Main control FSM** (`Top.sv`) — `I2C → IDLE → RECD/RECD_PAUSE` and
   `IDLE → PLAY/PLAY_PAUSE`, driven by debounced key edges.
2. **DSP scheduling FSM** (`AudDSP.sv`) — uses the ~375 BCLK gap between LRCK
   edges to sequentially fetch `Y0` and `Y1`, then compute the interpolated
   output:  `Y_interp = Y0 + (Y1 − Y0) · step / N`.
3. **I²C init FSM** (`I2cInitializer.sv`) — writes the 7 WM8731 configuration
   registers.

---

## Controls

| Input        | Function                                                        |
| ------------ | -------------------------------------------------------------- |
| `KEY[3]`     | Reset (active low)                                              |
| `KEY[0]`     | In IDLE: start **Record** · In Record: **Pause / Resume**      |
| `KEY[1]`     | In IDLE: start **Play** · In Play: **Pause / Resume**          |
| `KEY[2]`     | **Stop** (return to IDLE)                                       |
| `SW[3:0]`    | Playback speed select (Gray-coded → magnitude 1–8)             |
| `SW[4]`      | Slow mode: `0` = zero-order, `1` = linear interpolation         |
| `SW[5]`      | Reverse playback                                               |
| `SW[16]`     | Memory source: `0` = SRAM, `1` = SDRAM                          |
| `SW[17]`     | Play built-in audio ROM instead of recorded data               |

---

## Repository structure

```
src/
├── Top.sv                 # Top-level integration + main control FSM
├── AudDSP.sv              # Speed conversion + interpolation DSP core
├── AudPlayer.sv           # I²S transmit (parallel → serial)
├── AudRecorder.sv         # I²S receive  (serial → parallel)
├── DRAM_Arbiter.sv        # SDRAM memory adaptor + Avalon-MM bridge + prefetch cache
├── I2cInitializer.sv      # WM8731 register init over I²C
├── lcd_controller.sv      # Character-LCD status display
├── audio_rom_wrapper.sv   # Wrapper around the audio ROM IP
│
├── DE2_115/               # Board-level wrapper, pin assignments, timing constraints
│   ├── DE2_115.sv  DE2_115.qsf  DE2_115.sdc
│   ├── Debounce.sv        # Key debounce + edge detection
│   └── SevenHexDecoder.sv
│
├── scripts/               # Python tooling (audio → .mif, lookup-table generators)
│   ├── mif_gen.py  mif_gen2.py  mif_gen3.py  mif_gen_2048.py
│
└── IP_Cores/              # Quartus megafunction / Qsys IP (.qip / .v / .qsys)
```

> **Note:** the large generated `*.mif` audio data files are **not** committed
> (see `.gitignore`). Regenerate them from your own audio with the scripts in
> `scripts/` — e.g. export a raw 16-bit PCM file from Audacity and run
> `python scripts/mif_gen.py`.

---

## Hardware & toolchain

- **Board:** Terasic DE2-115 (Intel/Altera Cyclone IV EP4CE115)
- **Audio:** on-board Wolfson **WM8731** codec
- **Toolchain:** Intel Quartus Prime (with Qsys/Platform Designer for the SDRAM
  controller)
- **Language:** SystemVerilog

### Build

1. Open the project in Quartus and set `DE2_115.sv` as the top-level entity.
2. Generate the Qsys system in `IP_Cores/lab3_qsys.qsys` if needed.
3. Generate the required `*.mif` files (see note above).
4. Compile, then program the `.sof` to the board via the USB-Blaster.

---

## Engineering notes / things I debugged

The most interesting part of this project was getting it to work on *real*
hardware. A few representative bugs:

- **SRAM read setup time** — playback had high-frequency noise because the DSP
  switched the SRAM address on the same edge the player latched the MSB.
  Fixed by issuing the address **one BCLK early** so valid data is on the bus
  before LRCK transitions.
- **Tri-state bus contention** — switching SRAM from write (record) to read
  (play) produced `X` states on `io_SRAM_DQ`. Fixed by making `o_SRAM_WE_N`
  going high and the bus going high-impedance strictly co-occur on one clock edge.
- **Avalon-MM handshake deadlock** — the bridge's `wait_request` used
  combinational logic on its rising edge but sequential logic on its falling
  edge, so the master missed the slave's ready window. Fixed by making the
  falling edge level-sensitive for single-cycle handshakes.
- **Address truncation** — a 26-bit SRAM address was accidentally truncated to
  16 bits, shrinking usable capacity; corrected to 20 bits to cover the full 2 MB.

---

## Possible future work

- Auto-stop when playback reaches the end of the recording.
- Move the inline Gray-code / speed mapping into a documented table.
- Clean up remaining commented-out experimental blocks.
- Optional: real-time FFT / spectrum display on VGA.

---

## Attribution & Academic Integrity

This was a course lab. To be transparent:

- **Original work (this team):** the audio DSP (`AudDSP`), recorder/player I²S
  logic, the SDRAM `memory_adaptor` + prefetch cache (`DRAM_Arbiter.sv`), the
  LCD controller, the main control FSM, and all Python tooling.
- **Course-provided / adapted skeleton:** the board wrapper port list
  (`DE2_115.sv`, `Top.sv` interface), `I2cInitializer.sv` structure,
  `SevenHexDecoder.sv`, and the Qsys SDRAM IP.

> If you are a current student of this course, do not copy this as your own
> This is shared as a personal portfolio reference.

## Authors

Team 10 — _add names / GitHub handles here._

## License

MIT — see [`LICENSE`](LICENSE). (Course-provided skeleton files remain the
property of their original authors.)
