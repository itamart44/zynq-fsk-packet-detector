# Multi-Channel FSK Signal Detection and Address Decoder (PYNQ-Z2)

## Overview
This project implements a real-time multi-channel receiver on a PYNQ-Z2 (Zynq) platform.

The system receives unknown input sample streams, detects whether a real transmission exists (not just noise), verifies that the signal is FSK, demodulates it into bits, detects frame boundaries using Sync correlation, and extracts the destination Address field.

Processing is split between FPGA (PL) for real-time signal processing and CPU (PS) for configuration, monitoring, logging, and visualization.

---

## Project Goals
- Detect signal activity (signal vs noise)
- Verify that the signal is FSK
- Demodulate FSK into a bitstream
- Detect frame start using Sync correlation
- Extract Address field
- Measure performance metrics (latency, detection accuracy)
- Support multiple channels in parallel (4 channels)

---

## System Pipeline (per channel)

Input Samples  
↓  
Energy Detection  
↓  
FSK Verification  
↓  
FSK Demodulation  
↓  
Sync Detection  
↓  
Address Extraction  
↓  
Metrics & Reporting  

---

## System Architecture

CPU (PS):
- Configure parameters
- Collect results
- Logging and metrics
- Visualization and debugging

FPGA (PL):
- Channel 0 pipeline: Input → Energy → FSK → Demod → Sync → Address
- Channel 1 pipeline: Input → Energy → FSK → Demod → Sync → Address
- Channel 2 pipeline: Input → Energy → FSK → Demod → Sync → Address
- Channel 3 pipeline: Input → Energy → FSK → Demod → Sync → Address

Outputs:
- Events (channel, timestamp, address, score)
- Counters and statistics

---

## Frame Assumptions
The system assumes a generic FSK frame structure:

Preamble → Sync → Address → Payload

The Address value is unknown in advance, but its position is defined.

---

## Performance Metrics
- Probability of Detection (Pd)
- Miss Rate
- False Alarm Rate
- Latency
- Channel activity statistics

Ground truth is provided by a controlled lab transmitter.

---

## Repository Structure
- docs — theory, formulas, design notes
- hw — FPGA design
- sw — CPU software
- tests — experiments
- demo — demonstration material

---

## Scope

Included:
- Real-time detection and decoding of FSK transmissions
- Address extraction
- Performance evaluation

Not Included:
- Wi-Fi or Bluetooth decoding
- Arbitrary unknown protocol decoding
- Wideband spectrum analysis

---

## Platform
- Board: PYNQ-Z2 (Zynq-7000)
- Tools: Vivado, PYNQ, Python
- Processing: FPGA streaming pipeline with ARM control

---

## Status
- Architecture definition
- Single channel pipeline
- Multi-channel integration
- Sync detection
- Address extraction
- Metrics
- Final demo
