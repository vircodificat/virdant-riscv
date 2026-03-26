#include "VTop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

void tick(VTop *top, VerilatedVcdC* tfp) {
    top->clock = 1;
    top->eval();
    tfp->dump(main_time);
    main_time += 5;

    top->clock = 0;
    top->eval();
    tfp->dump(main_time);
    main_time += 5;
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
    top->clock = 1;
    top->eval();
    tfp->dump(main_time);

    reset(top, tfp);

    for (int i = 0; i < 200; i++) {
        tick(top, tfp);
    }

    tfp->close();
    delete top;
}
