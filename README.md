# Multi-Channel FSK Signal Detection and Address Decoder (PYNQ-Z2)

## Overview
This project implements a real-time FPGA-based FSK receiver on a PYNQ-Z2 (Zynq) platform.

The system processes incoming sample streams, detects signal activity (distinguishing signal from noise), performs frequency-domain analysis using FFT, demodulates FSK signals into bits, detects frame boundaries using Sync correlation, and extracts the destination Address field.

Processing is split between FPGA (PL) for real-time signal processing and CPU (PS) for configuration, monitoring, logging, and visualization.

This repository represents an incremental implementation of the system, developed in stages toward a full multi-channel design.

---

## Project Goals
- Detect signal activity (signal vs noise)
- Perform frequency-domain analysis (FFT)
- Demodulate FSK into a bitstream
- Detect frame start using Sync correlation
- Extract Address field
- Support real-time streaming output to CPU
- Support multiple channels in parallel (future extension)

---

## Current Implementation

The current implementation focuses on a single-channel FPGA pipeline:

- Sample input handling
- Energy detection
- FFT-based frequency analysis
- Frequency bin selection
- Power calculation
- FSK decision (bit extraction)
- Sync detection
- Address extraction
- AXI Stream output interface

### Planned Extensions
- Multi-channel support (parallel pipelines)
- CPU (PS) integration via AXI FIFO
- Real-time visualization using Python (PYNQ)
- Performance metrics (latency, detection accuracy)

---

## System Pipeline (Current)

Input Samples  
↓  
Energy Detection  
↓  
FFT Processing  
↓  
Frequency Bin Selection  
↓  
Power Calculation  
↓  
FSK Decision (bit extraction)  
↓  
Sync Detection  
↓  
Address Extraction  
↓  
AXI Stream Output  

---

## System Architecture

CPU (PS):
- Configuration and control
- Data collection via AXI
- Logging and visualization

FPGA (PL):
- Real-time streaming signal processing pipeline
- Fully pipelined DSP chain
- AXI Stream output interface

---

## Output Interface

The system outputs processed data via AXI Stream:

- `tdata` – 36-bit data bus  
- `tvalid` – data valid signal  
- `tready` – handshake signal  

The output is packetized and may include:
- Power measurements
- Sync detection events
- Extracted address values

---

## Frame Assumptions
The system assumes a generic FSK frame structure:

Preamble → Sync → Address → Payload

The Address value is unknown in advance, but its position is defined.

---

## Performance Metrics (Planned)
- Probability of Detection (Pd)
- Miss Rate
- False Alarm Rate
- Latency
- Channel activity statistics

---

## Repository Structure
- `docs` — theory, formulas, design notes  
- `hw` — FPGA design (RTL)  
- `sw` — CPU software (Python / PYNQ)  
- `tests` — testbenches and simulation results  
- `demo` — demonstration material  

---

## Scope

Included:
- Real-time FPGA-based FSK detection
- Bit extraction and frame synchronization
- Address decoding
- AXI Stream output

Not Included:
- Wi-Fi / Bluetooth decoding
- Unknown protocol reverse engineering
- Wideband spectrum analysis

---

## Platform
- Board: PYNQ-Z2 (Zynq-7000)
- Tools: Vivado, PYNQ, Python
- Architecture: FPGA streaming pipeline with ARM (PS) control

---

## Status
- Architecture definition ✔  
- Single-channel pipeline ✔  
- AXI Stream output ✔  
- Sync detection ✔  
- Address extraction ✔  
- Multi-channel support (planned)  
- CPU integration (in progress)  
- Final demo (pending)
