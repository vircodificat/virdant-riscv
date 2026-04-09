#include "VTop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

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

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    VTop* top = new VTop;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("out.vcd");

    top->reset = 1;
    top->clock = 0;
    top->eval();
    tfp->dump(main_time);

    reset(top, tfp);

    int max_cycles = 10000;
    for (int i = 0; i < max_cycles; i++) {
        tick(top, tfp);
        if (top->fin) {
            break;
        }
    }

    tfp->close();
    delete top;
}
