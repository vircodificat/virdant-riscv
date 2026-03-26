#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

void tick(Vtop *top) {
    top->clock = 1;
    top->eval();
    top->clock = 0;
    top->eval();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vtop* top = new Vtop;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("out.vcd");

    top->reset = 0;
    top->reset = 1;
    top->eval();

    tick(top);
    tick(top);
    tick(top);
    tick(top);
    tick(top);
    tick(top);
    tick(top);
    tick(top);

    for (int i = 0; i < 200; i++) {
        tfp->dump(main_time);
        main_time++;
    }

    tfp->close();
    delete top;
}
