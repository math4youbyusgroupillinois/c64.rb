require_relative "spec_helper"
require "c64/cpu"

module C64
  describe Cpu do

    def cpu; @cpu ||= C64::Cpu.new; end
    def registers; cpu.send :registers; end
    def memory; cpu.send :memory; end

    # Usage: run_instructions "AA BB", "CC DD EE", at: 0x400
    def run_instructions *i
      options = if i.last.is_a? Hash then i.pop else {} end
      offset = options[:at] || 0
      registers.pc = offset
      i.each do |instruction|
        instruction.split(" ").each do |hex|
          memory[offset] = hex.to_i(16)
          offset += 1
        end
      end
      i.length.times { cpu.step }
    end

    describe :AND do
      it "bitwise AND into accumulator" do
        registers.ac = 0b01010101
        run_instructions "29 F0" # AND #F0
        registers.ac.must_equal 0b01010000
      end
    end

    describe :BEQ do
      it "branches forwards for zero? true" do
        registers.sr = 0b00000010
        run_instructions "F0 04", at: 0x0400
        registers.pc.must_equal 0x0406
      end
      it "branches backwards for zero? true" do
        registers.sr = 0b00000010
        run_instructions "F0 F8", at: 0x0406
        registers.pc.must_equal 0x0400
      end
      it "does not branch for zero? false" do
        registers.sr = 0b00000000
        run_instructions "F0 08", at: 0x0400
        registers.pc.must_equal 0x0402
      end
    end

    describe :BNE do
      it "branches forwards for zero? false" do
        registers.sr = 0b00000000
        run_instructions "D0 04", at: 0x0400
        registers.pc.must_equal 0x0406
      end
      it "branches backwards for zero? false" do
        registers.sr = 0b00000000
        run_instructions "D0 F8", at: 0x0406
        registers.pc.must_equal 0x0400
      end
      it "does not branch for zero? true" do
        registers.sr = 0b00000010
        run_instructions "D0 08", at: 0x0400
        registers.pc.must_equal 0x0402
      end
    end

    describe :CLD do
      it "clears decimal mode" do
        registers.status.decimal = true
        run_instructions "D8"
        registers.status.decimal?.must_equal false
      end
    end

    describe :CMP do
      it "compares memory with accumulator" do
        registers.sr = 0
        memory[0xDEAD] = 0x01
        run_instructions "A9 01", "DD AD DE" # LDA #01, CMP 0x0000,x
        registers.status.tap do |s|
          s.zero?.must_equal true
          s.carry?.must_equal true
          s.negative?.must_equal false
        end
      end
    end

    describe :DEC do
      it "decrements memory by one" do
        memory[0xDEAD] = 0xAA
        run_instructions "CE AD DE" # DEC #0xDEAD
        memory[0xDEAD].must_equal 0xA9
      end
    end

    describe :DEX do
      it "decrements x by one" do
        run_instructions "A2 AA", "CA" # LDX #AA, DEX
        registers.x.must_equal 0xA9
      end
    end

    describe :DEY do
      it "decrements y by one" do
        run_instructions "A0 AA", "88" # LDY #AA, DEY
        registers.y.must_equal 0xA9
      end
    end

    describe :INC do
      it "increments memory by one" do
        memory[0xDEAD] = 0xAA
        run_instructions "EE AD DE" # INC #0xDEAD
        memory[0xDEAD].must_equal 0xAB
      end
    end

    describe :INX do
      it "increments x by one" do
        run_instructions "E8"
        registers.x.must_equal 1
      end
    end

    describe :INY do
      it "increments y by one" do
        run_instructions "C8"
        registers.y.must_equal 1
      end
    end

    describe :JMP do
      it "updates program counter" do
        run_instructions "4C AD DE" # JMP #0xDEAD
        registers.pc.must_equal 0xDEAD
      end
    end

    describe :JSR do
      it "stores PC, jumps to address" do
        run_instructions "20 AD DE", at: 1000
        registers.pc.must_equal 0xDEAD

        # The return address pushed to the stack by JSR is that of the
        # last byte of the JSR operand (that is, the most significant
        # byte of the subroutine address), rather than the address of
        # the following instruction.
        # http://en.wikipedia.org/wiki/MOS_Technology_6502#Bugs_and_quirks

        # little-endian 0xEA03 == 1002
        memory[registers.sp + 1].must_equal 0xEA
        memory[registers.sp + 2].must_equal 0x03
      end
    end

    { ac: 0xA9, x: 0xA2, y: 0xA0 }.each do |reg, op|
      describe "LD#{reg.to_s[0].upcase} immediate" do
        it "loads immediate value into #{reg} register" do
          run_instructions "#{op.to_s(16)} AA"
          registers[reg].must_equal 0xAA
        end
      end
    end

    { ac: 0xA5, x: 0xA6, y: 0xA4 }.each do |reg, op|
      describe "LD#{reg.to_s[0].upcase} zeropage" do
        it "loads zeropage value into #{reg} register" do
          memory[0x10] = 0xAA
          run_instructions "#{op.to_s(16)} 10"
          registers[reg].must_equal 0xAA
        end
      end
    end

    { ac: 0xB5, y: 0xB4 }.each do |reg, op|
      describe "LD#{reg.to_s[0].upcase} zeropage_x" do
        it "loads zeropage X-indexed value into #{reg} register" do
          registers.x = 0x04
          memory[0x10 + 0x04] = 0xAA
          run_instructions "#{op.to_s(16)} 10"
          registers[reg].must_equal 0xAA
        end
      end
    end

    describe "LDX zeropage_y" do
      it "loads zeropage Y-indexed value into X register" do
        registers.y = 0x04
        memory[0x10 + 0x04] = 0xAA
        run_instructions "B6 10"
        registers.x.must_equal 0xAA
      end
    end

    describe "LDA setting SR flags" do
      it "sets zero flag off" do
        registers.status.zero = true
        run_instructions "A9 01"
        registers.status.zero?.must_equal false
      end
      it "sets zero flag on" do
        run_instructions "A9 00"
        registers.status.zero?.must_equal true
      end
    end

    describe :NOP do
      it "does nothing" do
        run_instructions "EA"
        registers.pc.must_equal 1
      end
    end

    describe :ORA do
      it "bitwise OR into accumulator" do
        registers.ac = 0b01010101
        run_instructions "09 F0" # AND #F0
        registers.ac.must_equal 0b11110101
      end
    end

    describe :RTS do
      it "returns from subroutine, restores stack pointer" do
        sp = registers.sp
        memory[0xDEAD] = 0x60       # RTS
        run_instructions "20 AD DE" # JSR to 0xDEAD
        cpu.step
        registers.pc.must_equal 0x03
        registers.sp.must_equal sp
      end
    end

    describe :SEI do
      it "sets interrupt disable" do
        registers.status.interrupt = false
        run_instructions "78"
        registers.status.interrupt?.must_equal true
      end
    end

    describe :STX do
      it "stores X into memory (absolute)" do
        run_instructions "A2 AA", "8E AD DE" # LDX, STX
        memory[0xDEAD].must_equal 0xAA
      end
    end

    describe :STY do
      it "stores Y into memory (absolute)" do
        run_instructions "A0 AA", "8C AD DE" # LDY, STY
        memory[0xDEAD].must_equal 0xAA
      end
    end

    describe :TAX do
      it "transfers accumulator to X" do
        run_instructions "A9 AA", "AA" # LDA, TAX
        registers.x.must_equal 0xAA
      end
    end

    describe :TAY do
      it "transfers accumulator to Y" do
        run_instructions "A9 AA", "A8" # LDA, TAY
        registers.y.must_equal 0xAA
      end
    end

    describe :TXS do
      it "transfers X to stack pointer" do
        run_instructions "A2 AA", "9A" # LDS, TXS
        registers.sp.must_equal 0xAA
      end
    end

  end
end
