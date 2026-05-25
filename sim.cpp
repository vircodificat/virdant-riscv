#include "VTop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <string>
#include <vector>
#include <iostream>
#include <iomanip>
#include <fstream>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <sys/select.h>

// Include the internal headers for direct memory access
#include "VTop_Top.h"
#include "VTop_cpu__03a__03aCpu.h"
#include "VTop_mem__03a__03aWbMem.h"
#include "VTop_mem__03a__03aMem.h"
#include "VTop_rf__03a__03aRf.h"

// ELF parsing
#include <libelf.h>
#include <gelf.h>

using namespace std;

vluint64_t main_time = 0;
vluint64_t clock_period_ns = 24;
vluint64_t half_clock_period_ps = clock_period_ns * 1000 / 2;

double sc_time_stamp() {
    return main_time;
}

void tick(VTop *top, VerilatedVcdC* tfp, uint64_t cycle = ~0ull, bool check_uart = false) {
    // Trace the Fetching-stage state before the posedge
    bool do_trace = (cycle < 4);
    if (do_trace) {
        uint32_t s = top->Top->cpu->__PVT__stage;
        uint32_t c = top->Top->mem->__PVT__wb__02ecyc;
        uint32_t b = top->Top->mem->__PVT__wb__02estb;
        uint32_t k = top->Top->mem->__PVT__wb__02eack;
        uint32_t r = top->Top->mem->mem->__PVT__read;
        uint32_t d = top->Top->mem->mem->__PVT__data_out;
        uint32_t a = top->Top->mem->__PVT__wb__02eadr;
        uint32_t i = top->Top->cpu->__PVT__instr;
        uint32_t cpu_adr = top->Top->cpu->__PVT__mem__02eadr;
        uint32_t pc_val = top->Top->cpu->__PVT__pc;
        cerr << "[pre] cyc=" << cycle
             << " stg=" << s << " adr=0x" << hex << a << dec
             << " cpu_adr=0x" << hex << cpu_adr << dec
             << " pc=0x" << hex << pc_val << dec
             << " cyc=" << c << " stb=" << b << " ack=" << k
             << " rd=" << r << " do=0x" << hex << d << dec
             << " instr=0x" << hex << i << dec
             << endl;
    }

    // Sample UART sender data_valid BEFORE the posedge.
    // After the posedge a rising edge (0→1) means a byte was
    // just written to the THR; read the data from rs2_out
    // which is what drives the Wishbone write data bus.
    bool dv_before = false;
    if (check_uart) {
        dv_before = top->Top->__PVT__uart_dev__DOT__sender__02edata_valid;
    }

    top->clock = 1;
    top->eval();
    main_time += half_clock_period_ps;
    if (tfp) tfp->dump(main_time);

    // Check AFTER posedge: on the rising edge of data_valid
    // a byte was just written to the UART THR.
    if (check_uart) {
        bool dv_after = top->Top->__PVT__uart_dev__DOT__sender__02edata_valid;
        if (dv_after && !dv_before) {
            uint8_t byte = top->Top->cpu->rf->__PVT__rs2_out & 0xFF;
            ssize_t written = write(STDOUT_FILENO, &byte, 1);
            (void)written;
        }
    }

    // Trace after the posedge
    if (do_trace) {
        uint32_t s = top->Top->cpu->__PVT__stage;
        uint32_t c = top->Top->mem->__PVT__wb__02ecyc;
        uint32_t b = top->Top->mem->__PVT__wb__02estb;
        uint32_t k = top->Top->mem->__PVT__wb__02eack;
        uint32_t r = top->Top->mem->mem->__PVT__read;
        uint32_t d = top->Top->mem->mem->__PVT__data_out;
        uint32_t a = top->Top->mem->__PVT__wb__02eadr;
        uint32_t i = top->Top->cpu->__PVT__instr;
        uint32_t cpu_adr = top->Top->cpu->__PVT__mem__02eadr;
        uint32_t pc_val = top->Top->cpu->__PVT__pc;
        cerr << "[pos] cyc=" << cycle
             << " stg=" << s << " adr=0x" << hex << a << dec
             << " cpu_adr=0x" << hex << cpu_adr << dec
             << " pc=0x" << hex << pc_val << dec
             << " cyc=" << c << " stb=" << b << " ack=" << k
             << " rd=" << r << " do=0x" << hex << d << dec
             << " instr=0x" << hex << i << dec
             << endl;
    }

    top->clock = 0;
    top->eval();
    main_time += half_clock_period_ps;
    if (tfp) tfp->dump(main_time);
}

void reset(VTop *top, VerilatedVcdC* tfp) {
    top->reset = 1;
    top->eval();
    tick(top, tfp);

    top->reset = 0;
    top->eval();
    tick(top, tfp);
}

void load_elf(const char* elf_path, VTop_mem__03a__03aMem* mem_module) {
    cout << "Loading ELF file: " << elf_path << endl;

    // Open the ELF file
    int fd = open(elf_path, O_RDONLY);
    if (fd < 0) {
        cerr << "Error: Cannot open ELF file: " << elf_path << endl;
        return;
    }

    // Initialize libelf
    if (elf_version(EV_CURRENT) == EV_NONE) {
        cerr << "Error: ELF library initialization failed" << endl;
        close(fd);
        return;
    }

    // Open ELF
    Elf* elf = elf_begin(fd, ELF_C_READ, NULL);
    if (!elf) {
        cerr << "Error: elf_begin failed: " << elf_errmsg(-1) << endl;
        close(fd);
        return;
    }

    // Get the ELF kind and verify it's an ELF file
    if (elf_kind(elf) != ELF_K_ELF) {
        cerr << "Error: File is not a valid ELF file" << endl;
        elf_end(elf);
        close(fd);
        return;
    }

    // Iterate through program headers and load segments
    size_t n;
    if (elf_getphdrnum(elf, &n) != 0) {
        cerr << "Error: elf_getphdrnum failed: " << elf_errmsg(-1) << endl;
        elf_end(elf);
        close(fd);
        return;
    }

    cout << "Found " << n << " program headers" << endl;

    for (size_t i = 0; i < n; i++) {
        GElf_Phdr phdr;
        if (gelf_getphdr(elf, i, &phdr) != &phdr) {
            cerr << "Error: gelf_getphdr failed for segment " << i << endl;
            continue;
        }

        // Only load LOAD segments
        if (phdr.p_type != PT_LOAD) {
            continue;
        }

        cout << "Loading segment " << i << ": "
             << "vaddr=0x" << hex << phdr.p_vaddr << " "
             << "filesz=0x" << phdr.p_filesz << " "
             << "memsz=0x" << phdr.p_memsz << dec << endl;

        // Get the section data
        Elf_Data* data = elf_getdata_rawchunk(elf, phdr.p_offset, phdr.p_filesz, ELF_T_BYTE);
        if (!data) {
            cerr << "Error: elf_getdata_rawchunk failed for segment " << i << endl;
            continue;
        }

        // Load the segment into memory.
        // Memory is indexed by word address: index 0 = 0x80000000, index 1 = 0x80000004, etc.
        // The linker may page-align the LOAD segment vaddr before the actual .text address
        // (e.g., a segment at 0x7ffff000 that covers .text at 0x80000000).  Offset past any
        // data below MEMORY_BASE.
        const uint32_t MEMORY_BASE = 0x80000000;
        const uint32_t MEMORY_WORDS = 16384;

        uint32_t vaddr = phdr.p_vaddr;
        uint8_t* src = (uint8_t*)data->d_buf;
        size_t filesz = phdr.p_filesz;

        // Skip data that maps below our RAM base.
        size_t seg_skip = 0;
        if (vaddr < MEMORY_BASE) {
            seg_skip = MEMORY_BASE - vaddr;
            if (seg_skip >= filesz) continue;  // nothing overlaps RAM
        }

        uint32_t mem_addr_start = vaddr + seg_skip;
        uint32_t mem_first_index = (mem_addr_start - MEMORY_BASE) / 4;
        uint8_t* src_start = src + seg_skip;
        size_t copy_len = filesz - seg_skip;

        cout << "  RAM offset: 0x" << hex << (mem_addr_start - MEMORY_BASE)
             << "  words: " << dec << (copy_len / 4) << endl;

        // Copy file contents into the memory array.
        for (size_t j = 0; j < copy_len; j += 4) {
            uint32_t word = 0;
            size_t cs = (copy_len - j < 4) ? (copy_len - j) : 4;
            for (size_t k = 0; k < cs; k++)
                word |= ((uint32_t)src_start[j + k]) << (k * 8);

            uint32_t idx = mem_first_index + j / 4;
            if (idx < MEMORY_WORDS)
                mem_module->mem[idx] = word;
        }

        // Zero out the rest (memsz - filesz) for BSS.
        if (phdr.p_memsz > phdr.p_filesz) {
            size_t bss_skip = (seg_skip > phdr.p_filesz) ? seg_skip - phdr.p_filesz : 0;
            size_t bss_start = phdr.p_filesz;
            size_t bss_len = phdr.p_memsz - bss_start;

            // If the segment began before MEMORY_BASE, part of the BSS may
            // also fall below our RAM — skip that too.
            if (vaddr + bss_start < MEMORY_BASE) {
                size_t bss_below = MEMORY_BASE - (vaddr + bss_start);
                bss_len = (bss_len > bss_below) ? bss_len - bss_below : 0;
                bss_start += bss_below;
            }

            for (size_t j = bss_start; j < phdr.p_memsz; j += 4) {
                uint32_t mem_addr = vaddr + j;
                if (mem_addr < MEMORY_BASE) continue;
                uint32_t idx = (mem_addr - MEMORY_BASE) / 4;
                if (idx < MEMORY_WORDS)
                    mem_module->mem[idx] = 0;
            }
        }
    }

    cout << "ELF loading complete" << endl;

    // Verification: read back the first few words
    cout << "Verification - Reading back loaded data:" << endl;
    for (int i = 0; i < 7; i++) {
        cout << "  mem[" << i << "] = 0x" << hex << mem_module->mem[i] << dec << endl;
    }
    cout << endl;

    elf_end(elf);
    close(fd);
}

int main(int argc, char** argv) {
    // Parse --uart flag and find the ELF file path
    bool enable_uart = false;
    std::string elf_file;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--uart") == 0) {
            enable_uart = true;
        } else if (argv[i][0] != '-') {
            // Non-flag argument: treat as ELF file path
            ifstream file(argv[i], ios::binary);
            if (file.is_open()) {
                unsigned char magic[4] = {0};
                file.read((char*)magic, 4);
                file.close();

                if (magic[0] == 0x7F && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F') {
                    elf_file = argv[i];
                    cout << "ELF file path: " << elf_file << endl;
                } else {
                    cerr << "Error: File is not a valid ELF file: " << argv[i] << endl;
                    return 1;
                }
            } else {
                cerr << "Error: Cannot open file: " << argv[i] << endl;
                return 1;
            }
        }
    }

    if (enable_uart) {
        // Set stdin to non-blocking mode so the simulation can poll for input
        // without blocking on every tick.
        int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
        if (flags != -1) {
            fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
        }
        cout << "UART emulation enabled: stdin connected to UART RX, stdout to UART TX" << endl;
    }

    // Pass remaining arguments to Verilator
    Verilated::commandArgs(argc, argv);

    VTop* top = new VTop;

    // Hold uart.rx high (idle) from the start so the UART receiver
    // does not falsely detect a start bit from the floating input.
    top->uart__02erx = 1;

    // Load ELF file if provided
    if (!elf_file.empty()) {
        load_elf(elf_file.c_str(), top->Top->mem->mem);
    } else {
        cout << "No ELF file provided" << endl;
        exit(1);
    }

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("dump.vcd");

    top->reset = 1;
    top->clock = 0;
    top->eval();
    if (tfp) tfp->dump(main_time);
    tfp->flush();

    // Verify memory pointers by checking after first eval
    cerr << "[INIT] mem0=" << hex << top->Top->mem->mem->mem[0]
         << " wb_adr=" << top->Top->mem->__PVT__wb__02eadr
         << " m_addr=" << top->Top->mem->mem->__PVT__addr
         << " m_do=" << top->Top->mem->mem->__PVT__data_out << dec << endl;

    reset(top, tfp);

    // Hexdump first 32 bytes of memory
    {
        cerr << "[HEXDUMP] First 32 bytes of memory:" << endl;
        auto& mem_ref = top->Top->mem->mem->mem;
        const int bytes_per_line = 16;
        for (int off = 0; off < 32; off += bytes_per_line) {
            cerr << "  0x" << hex << (0x80000000 + off) << ":  ";
            // Hex bytes
            for (int i = 0; i < bytes_per_line; i++) {
                uint32_t word = mem_ref[(off + i) / 4];
                uint8_t byte = (word >> ((off + i) % 4 * 8)) & 0xFF;
                cerr << hex << setw(2) << setfill('0') << (int)byte << setw(0);
                if (i == bytes_per_line / 2 - 1) cerr << "  ";
                else cerr << " ";
            }
            cerr << "|";
            // ASCII representation
            for (int i = 0; i < bytes_per_line; i++) {
                uint32_t word = mem_ref[(off + i) / 4];
                uint8_t byte = (word >> ((off + i) % 4 * 8)) & 0xFF;
                cerr << (byte >= 32 && byte < 127 ? (char)byte : '.');
            }
            cerr << "|" << dec << endl;
        }
        cerr << dec;
    }

    // UART emulation state (used only when enable_uart is true)
    // Tick interval for checking stdin (every ~10000 ticks ~= 240us at 24ns/cycle)
    uint64_t uart_rx_check_interval = 10000;
    uint64_t uart_rx_next_check = 0;

//    int max_cycles = 10000;
//    for (int i = 0; i < max_cycles; i++) {
    for (uint64_t cycle = 0; ; cycle++) {
        tick(top, tfp, cycle, enable_uart);
        if (cycle % 100 == 0) {
            tfp->flush();
        }

        if (enable_uart) {
            // ────────────────────────────────────────────────────────────
            // UART RX: periodically check stdin and inject bytes
            // ────────────────────────────────────────────────────────────
            // Only inject when rx_pending is 0 (previous byte consumed).
            // We don't gate with uart_stb here because rx_pending is a
            // registered flag that the CPU clears via RBR reads — it is
            // inherently qualified by actual UART access.
            if (cycle >= uart_rx_next_check) {
                uart_rx_next_check = cycle + uart_rx_check_interval;

                // Only inject if the receiver holding register is empty
                // (rx_pending == 0 means the CPU has consumed the previous byte).
                if (!top->Top->__PVT__uart_dev__DOT__rx_pending) {
                    uint8_t byte;
                    ssize_t n = read(STDIN_FILENO, &byte, 1);
                    if (n > 0) {
                        // Inject byte directly into the receiver's data path.
                        // The receiver shift register holds its value while in
                        // the Idle state (no serial activity), and rx_pending
                        // persists until the CPU reads RBR.
                        top->Top->__PVT__uart_dev__DOT__receiver__DOT__shift = byte;
                        top->Top->__PVT__uart_dev__DOT__rx_pending = 1;
                    }
                }
            }
        }

        if (top->fin) {
            break;
        }
    }

    cout << "Return code: " << top->return_code << endl;

    tfp->close();
    delete top;

    return top->return_code;
}
