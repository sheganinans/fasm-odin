package clockfreq

import "core:fmt"
import "core:mem/virtual"

import win "core:sys/windows"

import fasm "../.."

main :: proc() {
  switch api in fasm.make() {
  case fasm.DllError:
    fmt.printfln("%v", api)
    return

  case fasm.API:
    defer fasm.destroy(api)

    mul3_asm: cstring = `
      use64
      rdtsc
      shl rdx, 32
      or rax, rdx
      ret
    `

    switch bytes in fasm.run(api, mul3_asm) {
    case fasm.ErrState:
      fmt.printfln("%v", bytes)
      return

    case fasm.OkState:
      raw := raw_data(bytes)

      virtual.protect(raw, len(bytes), virtual.Protect_Flags{.Execute})

      get_cycles := transmute(proc "c" () -> u64)raw

      freq, start, end := new(win.LARGE_INTEGER), new(win.LARGE_INTEGER), new(win.LARGE_INTEGER)
      win.QueryPerformanceFrequency(freq)
      win.QueryPerformanceCounter(start)
      cycles_start := get_cycles()

      win.Sleep(1000)

      win.QueryPerformanceCounter(end)
      cycles_end := get_cycles()

      elapsed := (end^ - start^) / freq^
      cpu_freq := (cycles_end - cycles_start) / u64(elapsed)

      fmt.printfln("CPU frequency: %d MHz", cpu_freq / 1000000)}
  }
}
