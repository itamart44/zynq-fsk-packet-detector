# FPGA Architecture Design
## Multi-Channel FSK Signal Detection System

This document describes the FPGA architecture used to detect FSK transmissions,
extract packet addresses, and report events to the CPU.

The FPGA performs real-time signal processing while the CPU manages the system
and reads the detected events.

---

SYSTEM OVERVIEW

The FPGA processes incoming samples using a DSP pipeline.

Signal flow:

Samples → Energy Detection → Sample Buffer → FFT → Frequency Detection → Bitstream Generation → Sync Detection → Address Extraction → Event Generation → FIFO → CPU Interface

---

FPGA BLOCK DIAGRAM

Samples
   ↓
Energy Detector
   ↓
Sample Buffer (256 samples)
   ↓
FFT Controller
   ↓
FFT IP
   ↓
Bin Selector
   ↓
Power Calculation
   ↓
FSK Decision
   ↓
Sync Detector
   ↓
Address FSM
   ↓
Event Builder
   ↓
Event FIFO
   ↓
AXI-Lite CPU Interface

---

SIGNAL PARAMETERS

Sampling Rate
Fs = 1 MHz

Sample Width
16-bit signed samples

FSK Frequencies
bit 0 → 100 kHz
bit 1 → 120 kHz

FFT Size
NFFT = 256

Frequency resolution
Δf = Fs / NFFT ≈ 3906 Hz

FFT bins used for detection
k0 = 26
k1 = 31

---

BLOCK DESCRIPTIONS

1. Sample Input

Receives 16-bit digital samples from the signal source
(ADC, SDR front-end, or recorded signal).

---

2. Energy Detector

Purpose: detect whether a signal is present or the input contains only noise.

Energy calculation:

E = Σ x[n]²

Window size:

256 samples

Threshold:

T_E = 3 × E_noise

Only when:

E > T_E

does the system continue to FFT processing.

This prevents unnecessary FFT calculations.

---

3. Sample Buffer

Collects 256 samples required for the FFT window.

Buffer size:

256 samples × 16 bits

The buffer ensures that the FFT receives a complete and well-defined window.

---

4. FFT Controller

Controls communication with the FFT IP block.

Responsibilities:

Feed 256 samples to the FFT  
Manage start and valid signals  
Synchronize FFT processing  

---

5. FFT Engine

Implemented using the Xilinx FFT IP core.

Chosen because:

High performance  
Reliable implementation  
Saves development time  

FFT size:

256 points

---

6. Bin Selector

Only two frequency bins are used for FSK detection.

k0 = 26  → ~100 kHz  
k1 = 31  → ~120 kHz

Selecting only these bins reduces hardware complexity.

---

7. Power Calculator

Computes signal power for each selected bin:

P[k] = Re[k]² + Im[k]²

Only calculated for:

k0
k1

---

8. FSK Decision

Bit value is determined by comparing bin power.

if P[k1] > P[k0] → bit = 1  
else → bit = 0

Each FFT window produces one decoded bit.

---

9. Sync Detector

Detects the start of a packet.

A 16-bit shift register stores the most recent bits.

Correlation is calculated with the sync pattern.

C = number of matching bits

Detection condition:

C ≥ 14

This allows up to two bit errors.

---

10. Address FSM

Finite State Machine that controls packet decoding.

States:

IDLE  
SYNC_FOUND  
READ_ADDRESS  
BUILD_EVENT  

After sync detection, the FSM reads:

8 address bits

---

11. Event Builder

Creates a packet detection event.

Event structure:

Word0
channel_id
address

Word1
sync_score

Word2
timestamp

Word3
latency

---

12. Event FIFO

Stores detected events until the CPU reads them.

FIFO depth:

32 events

Prevents event loss when multiple packets arrive quickly.

---

13. CPU Interface

Communication with the CPU is implemented using AXI-Lite registers.

The CPU reads four event words:

EVENT_WORD0
EVENT_WORD1
EVENT_WORD2
EVENT_WORD3

An interrupt is generated whenever a new event is written to the FIFO.

---

TIMESTAMP GENERATOR

A global counter runs continuously in the FPGA.

timestamp_counter++

When a packet is detected:

timestamp = timestamp_counter

This allows timing analysis and latency measurements.

---

CHANNEL SCALABILITY

The architecture is parameterized.

NUM_CHANNELS = 1 (default)

Future versions may support:

NUM_CHANNELS = 4

by replicating the processing pipeline.

---

SUMMARY

The FPGA performs the following processing pipeline:

Samples  
→ Energy Detection  
→ FFT Processing  
→ Frequency Detection  
→ Bitstream Generation  
→ Sync Detection  
→ Address Extraction  
→ Event Generation  
→ FIFO  
→ CPU  

This architecture enables real-time FSK signal detection while keeping the system scalable and modular.
