# Multi-Channel FSK Signal Detection and Address Decoder (PYNQ-Z2)

## 📡 Overview
This project implements a real-time FPGA-based FSK receiver on a PYNQ-Z2 (Zynq-7000) platform.

The system processes incoming sample streams, detects signal activity (distinguishing signal from noise), performs frequency-domain analysis using FFT, demodulates FSK signals, detects frame boundaries via Sync correlation, and extracts the destination Address field.

The design follows a **hardware/software co-design approach**:
- FPGA (PL) performs real-time signal processing
- CPU (PS) handles data acquisition, monitoring, and visualization

This repository represents an **incremental development process**, starting from a single-channel pipeline and evolving toward a scalable multi-channel system.

---

## 🎯 Project Goals
- Detect signal activity (signal vs. noise)
- Perform frequency-domain analysis (FFT)
- Demodulate FSK signals
- Detect frame start using Sync correlation
- Extract Address field
- Stream processed data to CPU via AXI
- Support multi-channel processing (future extension)

---

## ⚙️ Current Implementation

The current implementation focuses on a **single-channel FPGA pipeline**:

- Sample input buffering  
- Energy detection  
- FFT-based frequency analysis  
- Frequency bin selection  
- Power calculation  
- FSK decision (bit-level detection)  
- Sync detection  
- Address extraction  
- AXI Stream output interface  

✔ The full pipeline has been verified in simulation  
✔ Python-side parsing and visualization are implemented  

---

## 🚀 Planned Extensions
- Multi-channel support (parallel pipelines in FPGA)
- Channel comparison and selection logic
- Full CPU (PS) integration via AXI DMA
- Real-time visualization (Python / PYNQ)
- Performance evaluation (latency, detection accuracy)

---

## 🔁 System Pipeline (Current)

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
FSK Decision  
↓  
Sync Detection  
↓  
Address Extraction  
↓  
AXI Stream Output  

---

## 🧠 System Architecture

### FPGA (PL)
- Fully pipelined real-time DSP chain
- Signal detection and validation
- FSK demodulation
- Frame synchronization
- Address extraction
- AXI Stream output

### CPU (PS)
- Data acquisition via AXI DMA
- Parsing of FPGA output stream
- Event detection (Signal / Address)
- Real-time visualization (Python)

---

## 📤 Output Interface

The FPGA outputs processed data via AXI Stream:

- `tdata` – encoded data (type + payload)  
- `tvalid` – data valid signal  
- `tready` – handshake signal  

The stream may include:
- Power measurements
- Sync detection events
- Extracted address values

---

## 🧪 Software (Python)

The `sw/` directory contains:

- `simulation.py`  
  Simulates FPGA output for development and debugging without hardware input  

- `run_fpga.py`  
  Reads real-time data from FPGA via DMA and displays:
  - Signal detection events  
  - Extracted addresses  
  - Power comparison graphs  

---

## 📦 Frame Assumptions

The system assumes a generic FSK frame structure:

Preamble → Sync → Address → Payload

The Address field position is known, while its value is not predefined.

---

## 📊 Performance Metrics (Planned)
- Probability of Detection (Pd)
- False Alarm Rate
- Miss Rate
- Latency
- Channel activity statistics

---

## 📂 Repository Structure

- `docs/` — theory, formulas, design notes  
- `hw/` — FPGA design (RTL + bitstream)  
- `sw/` — Python software (DMA + simulation)  
- `tests/` — testbenches and simulation results  
- `demo/` — demonstration materials  

---

## 🎯 Scope

### Included
- Real-time FPGA-based FSK detection
- Bit-level demodulation
- Frame synchronization (Sync detection)
- Address extraction
- AXI Stream output

### Not Included
- Full protocol decoding (e.g., Wi-Fi / Bluetooth)
- Unknown protocol reverse engineering
- Wideband spectrum analysis

---

## 🧰 Platform

- Board: PYNQ-Z2 (Zynq-7000)
- Tools: Vivado, PYNQ, Python
- Architecture: FPGA streaming pipeline with ARM (PS) control

---

## 📌 Status

- Architecture definition ✔  
- Single-channel FPGA pipeline ✔  
- AXI Stream output ✔  
- Sync detection ✔  
- Address extraction ✔  
- Python simulation ✔  
- Python DMA pipeline ✔  
- Multi-channel support (planned)  
- Final hardware validation (pending)  
