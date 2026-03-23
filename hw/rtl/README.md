# RTL - FSK Signal Processing

This directory contains the VHDL implementation of the FSK receiver pipeline.

## Pipeline Overview

SampleInput → Energy_Detector → sample_buffer → FFT_controller →  
Bin_selector → power_Calculator → FSK_Decision →  
Sync_Detector → Adders_Extractor → Output_Interface

## Description

- **SampleInput** – Handles incoming ADC samples  
- **Energy_Detector** – Filters noise and detects signal presence  
- **sample_buffer** – Buffers samples for FFT processing  
- **FFT_controller** – Converts signal to frequency domain  
- **Bin_selector** – Selects relevant frequency bins  
- **power_Calculator** – Computes power of selected bins  
- **FSK_Decision** – Determines bit value based on power  
- **Sync_Detector** – Detects start of transmission pattern  
- **Adders_Extractor** – Extracts address bits  
- **Output_Interface** – Formats data to AXI Stream

## Output

AXI Stream interface:
- `tdata` – 36-bit data bus
- `tvalid` – data valid signal
- `tready` – handshake signal
