`ifdef OMSP_NO_INCLUDE
`else
`include "openMSP430_defines.v"
`endif

module omsp_spm(
  input  wire         mclk,
  input  wire         puc_rst,
  input  wire  [15:0] pc,
  input  wire  [15:0] prev_pc,
  input  wire  [15:0] eu_mab,
  input  wire         eu_mb_en,
  input  wire   [1:0] eu_mb_wr,
  input  wire         update_spm,
  input  wire         enable_spm,
  input  wire         check_new_spm,
  input  wire  [15:0] next_id,
  input  wire  [15:0] r12,
  input  wire  [15:0] r13,
  input  wire  [15:0] r14,
  input  wire  [15:0] r15,
  input  wire   [2:0] data_request,
  input  wire  [15:0] spm_data_select,
  input  wire  [15:0] spm_key_select,
  input  wire         write_key,
  input  wire  [15:0] key_in,
  input  wire         spm_busy,
  output reg          enabled,
  output wire         violation,
  output wire         data_selected,
  output wire         key_selected,
  output reg   [15:0] requested_data,
  output wire [0:127] key_out
);

reg [15:0] id;
reg [15:0] public_start;
reg [15:0] public_end;
reg [15:0] secret_start;
reg [15:0] secret_end;

reg   [3:0] key_idx;
reg [0:127] key;

function exec_spm;
  input [15:0] current_pc;

  begin
    exec_spm = current_pc >= public_start & current_pc < public_end;
  end
endfunction

function do_overlap;
  input [15:0] start_a;
  input [15:0] end_a;
  input [15:0] start_b;
  input [15:0] end_b;

  begin
    do_overlap = (start_a < end_b) & (end_a > start_b);
  end
endfunction

initial
begin
  public_start = 0;
  public_end = 0;
  secret_start = 0;
  secret_end = 0;
  enabled = 0;
end

always @(posedge mclk or posedge puc_rst)
begin
  if (puc_rst)
  begin
    id <= 0;
    public_start <= 0;
    public_end <= 0;
    secret_start <= 0;
    secret_end <= 0;
    enabled <= 0;
    key_idx <= 0;
  end
  else if (update_spm)
  begin
    if (enable_spm)
    begin
      if ((r12 < r13) & (r14 < r15))
      begin
        id <= next_id;
        public_start <= r12;
        public_end <= r13;
        secret_start <= r14;
        secret_end <= r15;
        enabled <= 1;
        key_idx <= 0;
        $display("New SM config: %h %h %h %h", r12, r13, r14, r15);
      end
      else
      begin
        $display("Invalid SM config: %h %h %h %h", r12, r13, r14, r15);
      end
    end
    else if (pc >= public_start && pc < public_end)
    begin
      id <= 0;
      public_start <= 0;
      public_end <= 0;
      secret_start <= 0;
      secret_end <= 0;
      enabled <= 0;
      $display("SM disabled");
    end
  end
  else if (key_selected & write_key)
  begin
    key[16*key_idx+:16] <= key_in;
    key_idx <= key_idx + 1;
  end
end

wire exec_public = exec_spm(pc);
wire access_secret = eu_mb_en & (eu_mab >= secret_start) & (eu_mab < secret_end);
wire access_public = eu_mb_en & (eu_mab >= public_start) & (eu_mab < public_end);
wire mem_violation = access_secret & ~exec_public & ~spm_busy;
wire pmem_violation = access_public & ~exec_public & ~spm_busy;
wire exec_violation = exec_public & ~exec_spm(prev_pc) & (pc != public_start);
wire create_violation = check_new_spm &
                        (do_overlap(r12, r13, public_start, public_end));// |
                         //do_overlap(r12, r13, secret_start, secret_end) |
                         //do_overlap(r14, r15, public_start, public_end) |
                         //do_overlap(r14, r15, secret_start, secret_end));
assign violation = enabled & (pmem_violation | mem_violation | exec_violation | create_violation);

always @(posedge mclk)
begin
  if (violation)
  begin
    if (pmem_violation)
      $display("pmem violation @%h, from %h", eu_mab, pc);
    else if (mem_violation)
      $display("mem violation @%h, from %h", eu_mab, pc);
    else if (exec_violation)
      $display("exec violation %h -> %h", prev_pc, pc);
    else if (create_violation)
    begin
      $display("create violation:");
      $display("\tme:  %h %h %h %h", public_start, public_end, secret_start, secret_end);
      $display("\tnew: %h %h %h %h", r12, r13, r14, r15);
    end
  end
end

// FIXME: WTF? This somehow doesn't work when executing HKDF
// assign selected = enabled & exec_spm(spm_select);
assign data_selected = enabled & (spm_data_select >= public_start) &
                                 (spm_data_select < public_end);

always @(*)
  if (data_selected)
  case (data_request)
    `SPM_REQ_PUBSTART: requested_data = public_start;
    `SPM_REQ_PUBEND:   requested_data = public_end;
    `SPM_REQ_SECSTART: requested_data = secret_start;
    `SPM_REQ_SECEND:   requested_data = secret_end;
    `SPM_REQ_ID:       requested_data = id;
    default:           requested_data = 16'bx;
  endcase
  else
  requested_data = 16'bz;

assign key_selected = enabled & (spm_key_select >= public_start) &
                                (spm_key_select < public_end);
assign key_out = key_selected ? key : 128'bz;

endmodule
