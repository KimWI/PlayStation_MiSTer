vcom -93 -quiet -work  sim/mem ^
../../rtl/SyncFifo.vhd ^
../../rtl/SyncFifoFallThrough.vhd ^
../../rtl/SyncRam.vhd

vcom -2008 -quiet -work sim/psx ^
../../rtl/dpram.vhd ^
../../rtl/divider.vhd ^
../../rtl/pGPU.vhd ^
../../rtl/mul32u.vhd ^
../../rtl/mul9s.vhd ^
../../rtl/gpu_fillVram.vhd ^
../../rtl/gpu_cpu2vram.vhd ^
../../rtl/gpu_vram2vram.vhd ^
../../rtl/gpu_vram2cpu.vhd ^
../../rtl/gpu_line.vhd ^
../../rtl/gpu_rect.vhd ^
../../rtl/gpu_poly.vhd ^
../../rtl/gpu_pixelpipeline.vhd ^
../../rtl/gpu_videoout.vhd ^
../../rtl/gpu.vhd

vcom -quiet -work sim/tb ^
../system/src/tb/globals.vhd ^
../system/src/tb/ddrram_model.vhd ^
src/tb/tb.vhd

