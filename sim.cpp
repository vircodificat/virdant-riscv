#include "VTop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <string>
#include <vector>
#include <iostream>
#include <fstream>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>

// Include the internal headers for direct memory access
#include "VTop_Top.h"
#include "VTop_mem__03a__03aWbMem.h"
#include "VTop_mem__03a__03aMem.h"

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

void tick(VTop *top, VerilatedVcdC* tfp) {
    top->clock = 1;
    top->eval();
    main_time += half_clock_period_ps;
    tfp->dump(main_time);

    top->clock = 0;
    top->eval();
    main_time += half_clock_period_ps;
    tfp->dump(main_time);
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

        // Load the segment into memory
        // Memory is indexed by word address: index 0 = 0x80000000, index 1 = 0x80000004, etc.
        // The ELF virtual address is the actual memory address
        const uint32_t MEMORY_BASE = 0x80000000;
        uint32_t vaddr = phdr.p_vaddr;
        uint8_t* src = (uint8_t*)data->d_buf;
        size_t filesz = phdr.p_filesz;

        // Copy file contents (filesz bytes)
        for (size_t j = 0; j < filesz; j += 4) {
            uint32_t word = 0;
            size_t copy_size = (filesz - j < 4) ? (filesz - j) : 4;

            for (size_t k = 0; k < copy_size; k++) {
                word |= ((uint32_t)src[j + k]) << (k * 8);
            }

            // Virtual address directly gives us the memory address
            uint32_t mem_addr = vaddr + j;
            uint32_t mem_index = (mem_addr - MEMORY_BASE) / 4;

            if (mem_index < 16384) {
                mem_module->mem[mem_index] = word;
//                cout << "  mem[" << mem_index << "] (vaddr 0x" << hex << mem_addr << ") = 0x" << word << dec << endl;
            }
        }

        // Zero out the rest (memsz - filesz)
        if (phdr.p_memsz > phdr.p_filesz) {
            for (size_t j = phdr.p_filesz; j < phdr.p_memsz; j += 4) {
                uint32_t mem_addr = vaddr + j;
                uint32_t mem_index = (mem_addr - MEMORY_BASE) / 4;

                if (mem_index < 16384) {
                    mem_module->mem[mem_index] = 0;
                }
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
    // Check if argv[1] is provided as an ELF file path
    std::string elf_file;

    if (argc > 1) {
        // argv[1] should be a path to an ELF file
        ifstream file(argv[1], ios::binary);
        if (file.is_open()) {
            unsigned char magic[4] = {0};
            file.read((char*)magic, 4);
            file.close();

            // Check if it's an ELF file by magic bytes (0x7F 'E' 'L' 'F')
            if (magic[0] == 0x7F && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F') {
                elf_file = argv[1];
                cout << "ELF file path: " << elf_file << endl;
            } else {
                cerr << "Error: File is not a valid ELF file: " << argv[1] << endl;
                return 1;
            }
        } else {
            cerr << "Error: Cannot open file: " << argv[1] << endl;
            return 1;
        }
    }

    // Pass remaining arguments to Verilator
    Verilated::commandArgs(argc, argv);

    VTop* top = new VTop;

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
    tfp->dump(main_time);

    reset(top, tfp);

//    int max_cycles = 10000;
//    for (int i = 0; i < max_cycles; i++) {
    for (;;) {
        tick(top, tfp);
        if (top->fin) {
            break;
        }
    }

    cout << "Return code: " << top->return_code << endl;

    tfp->close();
    delete top;

    return top->return_code;
}
