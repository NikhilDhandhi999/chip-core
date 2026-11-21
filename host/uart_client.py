"""
host/uart_client.py
Host-Side Python UART Client for chip-core (v7.0)
Talks over a real serial port (COM3, /dev/ttyUSB1, etc.) using the chip-core
binary packet protocol (`0x01` WRITE_INST, `0x02` WRITE_SRAM, `0x03` RUN_EXEC, `0x04` READ_PREDS).

Usage:
  python host/uart_client.py --port COM4 --baud 115200
"""

import argparse

CLASS_NAMES = ["Digit '0'", "Digit '1'", "Symbol 'X'", "Symbol '+'"]

def send_program_and_run(ser, inst_words, sram_bytes):
    for addr, word in enumerate(inst_words):
        pkt = bytes([0x01, addr & 0xFF]) + int(word).to_bytes(4, "big")
        ser.write(pkt)
        ack = ser.read(1)
        if ack != b"\x06":
            raise RuntimeError(f"Expected ACK 0x06 for inst {addr}, got {ack!r}")

    for addr, val in enumerate(sram_bytes):
        pkt = bytes([0x02, addr & 0xFF, val & 0xFF])
        ser.write(pkt)
        ack = ser.read(1)
        if ack != b"\x06":
            raise RuntimeError(f"Expected ACK 0x06 for sram {addr}, got {ack!r}")

    ser.write(b"\x03")
    done_byte = ser.read(1)
    if done_byte != b"\xaa":
        raise RuntimeError(f"Expected EXEC_DONE 0xAA, got {done_byte!r}")

    ser.write(b"\x04")
    preds = list(ser.read(4))
    if len(preds) != 4:
        raise RuntimeError(f"Expected 4 prediction bytes, got {preds!r}")
    return preds

def main():
    parser = argparse.ArgumentParser(description="chip-core v7.0 UART Host Client")
    parser.add_argument("--port", required=True, help="Serial port (e.g., COM4 or /dev/ttyUSB1)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    args = parser.parse_args()

    try:
        import serial  # type: ignore
    except ImportError:
        print("Install pyserial first: pip install pyserial")
        return

    with open("build/prog_vision.hex", "r", encoding="utf-8") as f:
        inst_words = [int(line.strip(), 16) for line in f if line.strip()]
    with open("build/sram_vision.hex", "r", encoding="utf-8") as f:
        sram_bytes = [int(line.strip(), 16) for line in f if line.strip()][:160]

    with serial.Serial(args.port, args.baud, timeout=2.0) as ser:
        preds = send_program_and_run(ser, inst_words, sram_bytes)
        print("Hardware UART Predictions:", [CLASS_NAMES[p & 3] for p in preds])

if __name__ == "__main__":
    main()
