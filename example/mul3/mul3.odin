package mul3

import "core:fmt"
import "core:mem/virtual"

import fasm "../.."

main :: proc() {
  switch api in fasm.make() {
  case fasm.DllError:
    fmt.printfln("%v", api)
    return

  case fasm.API:
    defer fasm.destroy(api)

    fmt.printfln("\nUsing fasm version: %s\n", fasm.version(api))

    mul3_asm: cstring = `
      use64
      mov rax, rcx
      mov rcx, 3
      mul rcx
      ret
    `

    switch bytes in fasm.run(api, mul3_asm) {
    case fasm.ErrState:
      fmt.printfln("%v", bytes)
      return

    case fasm.OkState:
      raw := raw_data(bytes)

      virtual.protect(raw, len(bytes), virtual.Protect_Flags{.Execute})

      mul3 := transmute(proc "c" (_: int) -> int)raw

      for i in 0 ..= 10 {
        fmt.printfln("mul3(%v) = %v", i, mul3(i))
      }
    }
  }
}
