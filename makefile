# Makefile for 32 KiB 4-Way Cache System

all: cache

cache:
	mkdir -p build
	# Compile all source modules and the testbench together
	iverilog -g2012 -o build/sim_cache.vvp src/cache_way.v src/cache_controller.v src/memory.v tb/tb_cache.v
	# Execute the simulation
	vvp build/sim_cache.vvp
	# Optionally open waveform viewer (commented out for automation)
	# gtkwave build/cache_waves.vcd cache_setup.gtkw &

comprehensive:
	mkdir -p build
	# Compile comprehensive testbench
	iverilog -g2012 -o build/sim_cache_comp.vvp src/cache_way.v src/cache_controller.v src/memory.v tb/tb_cache_comprehensive.v
	# Execute the comprehensive simulation
	vvp build/sim_cache_comp.vvp
	# Optionally open waveform viewer (commented out for automation)
	# gtkwave build/cache_comprehensive_waves.vcd cache_setup.gtkw &

clean:
	rm -rf build/*