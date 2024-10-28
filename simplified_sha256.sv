module simplified_sha256 #(parameter integer NUM_OF_WORDS = 20)(
 input logic  clk, reset_n, start,
 input logic  [15:0] message_addr, output_addr,
 output logic done, mem_clk, mem_we,
 output logic [15:0] mem_addr,
 output logic [31:0] mem_write_data,
 input logic [31:0] mem_read_data);

// FSM state variables 
// Note : Students can add more states or remove states as per their implementation
enum logic [2:0] {IDLE, READ, WAIT, BLOCK, COMPUTE, WRITE} state;

//////////////////////////////////////////////////////////////////////////////////////
/* NOTE : Below mentioned code frame work is for reference purpose.
Local variables might not be complete and you might have to add more variables
or modify these variables. Code below is more as a reference and a helper code
which students can use as a starting point. Student can also develop using your
own method and implementation even without using the code framework provided below.
Code mentioned below is using 1 always block implementation which always_ff
and hence all statements within it should be non-blocking assignment state.
*/
//////////////////////////////////////////////////////////////////////////////////////

// Local variables
// Note : Add or remove variables as per your implementation
logic [31:0] w[16]; // This is for word expansion in compute sate. For optimized implementation this can be w[16]
logic [31:0] message[20]; // Stores 20 message words after read from the memory
logic [31:0] wt;
logic [31:0] h0, h1, h2, h3, h4, h5, h6, h7;
logic [31:0] a, b, c, d, e, f, g, h;
logic [ 7:0] i, j, write_idx;
logic [31:0] SNew0, SNew1;
logic [15:0] offset; // in word address
logic [ 7:0] num_blocks;
logic        cur_we;
logic [15:0] cur_addr;
logic [31:0] cur_write_data;
logic [512:0] memory_block0;
logic [512:0] memory_block1;

logic [1:0] block_num_idx;
logic [ 7:0] tstep;

// SHA256 K constants
parameter int k[0:63] = '{
   32'h428a2f98,32'h71374491,32'hb5c0fbcf,32'he9b5dba5,32'h3956c25b,32'h59f111f1,32'h923f82a4,32'hab1c5ed5,
   32'hd807aa98,32'h12835b01,32'h243185be,32'h550c7dc3,32'h72be5d74,32'h80deb1fe,32'h9bdc06a7,32'hc19bf174,
   32'he49b69c1,32'hefbe4786,32'h0fc19dc6,32'h240ca1cc,32'h2de92c6f,32'h4a7484aa,32'h5cb0a9dc,32'h76f988da,
   32'h983e5152,32'ha831c66d,32'hb00327c8,32'hbf597fc7,32'hc6e00bf3,32'hd5a79147,32'h06ca6351,32'h14292967,
   32'h27b70a85,32'h2e1b2138,32'h4d2c6dfc,32'h53380d13,32'h650a7354,32'h766a0abb,32'h81c2c92e,32'h92722c85,
   32'ha2bfe8a1,32'ha81a664b,32'hc24b8b70,32'hc76c51a3,32'hd192e819,32'hd6990624,32'hf40e3585,32'h106aa070,
   32'h19a4c116,32'h1e376c08,32'h2748774c,32'h34b0bcb5,32'h391c0cb3,32'h4ed8aa4a,32'h5b9cca4f,32'h682e6ff3,
   32'h748f82ee,32'h78a5636f,32'h84c87814,32'h8cc70208,32'h90befffa,32'ha4506ceb,32'hbef9a3f7,32'hc67178f2
};

// Get num of blocks
assign num_blocks = determine_num_blocks(NUM_OF_WORDS); 
assign tstep = (i - 1);

// Note : Function defined are for reference purpose. Feel free to add more functions or modify below.
// Function to determine number of blocks in memory to fetch

function logic [31:0] wtnew;
  logic [31:0] s0, s1;

  s0 = rightrotate(w[1], 7) ^ rightrotate(w[1], 18) ^ (w[1] >> 3);
  s1 = rightrotate(w[14], 17) ^ rightrotate(w[14], 19) ^ (w[14] >> 10);
  wtnew = w[0] + s0 + w[9] + s1;
endfunction

function logic [15:0] determine_num_blocks(input logic [31:0] size);

  // Student to add function implementation
  if (size % 16 != 0) begin
    determine_num_blocks = (size / 16) + 1;
  end
  else begin
    determine_num_blocks = (size / 16);
  end

endfunction


// SHA256 hash round
function logic [255:0] sha256_op(input logic [31:0] a, b, c, d, e, f, g, h, w,
                                 input logic [7:0] t);
    logic [31:0] S1, S0, ch, maj, t1, t2; // internal signals
begin
    S1 = rightrotate(e, 6) ^ rightrotate(e, 11) ^ rightrotate(e, 25);
    // Student to add remaning code below
    // Refer to SHA256 discussion slides to get logic for this function
    ch = (e & f) ^ (~e & g);
    t1 = h + S1 + ch + k[t] + w;
    S0 = rightrotate(a, 2) ^ rightrotate(a, 13) ^ rightrotate(a, 22);
    maj = (a & b) ^ (a & c) ^ (b & c);
    t2 = S0 + maj;
    sha256_op = {t1 + t2, a, b, c, d + t1, e, f, g};
end
endfunction


// Generate request to memory
// for reading from memory to get original message
// for writing final computed has value
assign mem_clk = clk;
assign mem_addr = cur_addr + offset;
assign mem_we = cur_we;
assign mem_write_data = cur_write_data;


// Right Rotation Example : right rotate input x by r
// Lets say input x = 1111 ffff 2222 3333 4444 6666 7777 8888
// lets say r = 4
// x >> r  will result in : 0000 1111 ffff 2222 3333 4444 6666 7777 
// x << (32-r) will result in : 8888 0000 0000 0000 0000 0000 0000 0000
// final right rotate expression is = (x >> r) | (x << (32-r));
// (0000 1111 ffff 2222 3333 4444 6666 7777) | (8888 0000 0000 0000 0000 0000 0000 0000)
// final value after right rotate = 8888 1111 ffff 2222 3333 4444 6666 7777
// Right rotation function
function logic [31:0] rightrotate(input logic [31:0] x,
                                  input logic [ 7:0] r);
   rightrotate = (x >> r) | (x << (32 - r));
endfunction


// SHA-256 FSM 
// Get a BLOCK from the memory, COMPUTE Hash output using SHA256 function
// and write back hash value back to memory
// Note : Inside always_ff all statements should use non-blocking assignments
always_ff @(posedge clk, negedge reset_n)
begin
  if (!reset_n) begin
    cur_we <= 1'b0;
    state <= IDLE;
  end 
  else case (state)
    // Initialize hash values h0 to h7 and a to h, other variables and memory we, address offset, etc
    IDLE: begin 
       if(start) begin
       // Student to add rest of the code 
          h0 <= 32'h6a09e667;
          h1 <= 32'hbb67ae85;
          h2 <= 32'h3c6ef372;
          h3 <= 32'ha54ff53a;
          h4 <= 32'h510e527f;
          h5 <= 32'h9b05688c;
          h6 <= 32'h1f83d9ab;
          h7 <= 32'h5be0cd19;

          a <= 0;
          b <= 0;
          c <= 0;
          d <= 0;
          e <= 0;
          f <= 0;
          g <= 0;
          h <= 0;

          block_num_idx <= 2'b00;
          offset <= 0;
          i <= 0;
          write_idx <= 0;
          cur_we <= 0;
          cur_write_data <= 0;
          cur_addr <= message_addr;
          state <= WAIT;
       end
    end

    WAIT: begin
      state <= READ;
    end

    READ: begin
      if (offset <= 20) begin
        if (offset != 0) begin
          message[offset-1] <= mem_read_data;
        end
        offset <= offset + 1;
        cur_we <= 1'b0;
        state <= READ;
      end
      else begin
        state <= BLOCK;
      end
    end

    BLOCK: begin
	// Fetch message in 512-bit block size
	// For each of 512-bit block initiate hash value computation
       block_num_idx <= block_num_idx + 1; 
       i <= 0;
       if (block_num_idx < num_blocks) begin
          a <= h0;
          b <= h1;
          c <= h2;
          d <= h3;
          e <= h4;
          f <= h5;
          g <= h6;
          h <= h7;
          state <= COMPUTE;

          if (block_num_idx == 0) begin
            for (int temp_idx = 0; temp_idx < 16; temp_idx++) begin
              w[temp_idx] <= message[temp_idx];
            end
          end

          else begin
            for (int temp_idx = 0; temp_idx < 4; temp_idx++) begin
              w[temp_idx] <= message[temp_idx + 16];
            end
            w[4] <= 32'h80000000;
            for (int temp_idx = 5; temp_idx < 15; temp_idx++) begin
              w[temp_idx] <= 0;
            end
            w[15] <= 32'h280;
          end
       end 

       else begin
        state <= WRITE;
       end
    end

    COMPUTE: begin
	    // 64 processing rounds steps for 512-bit block
        {a, b, c, d, e, f, g, h} <= {h0, h1, h2, h3, h4, h5, h6, h7};
        
       if (i < 64) begin
          i <= i + 1;
          for (int n = 0; n < 15; n++) begin
            w[n] <= w[n+1];
          end
          w[15] <= wtnew;
          {a, b, c, d, e, f, g, h} <= sha256_op(a, b, c, d, e, f, g, h, w[0], i);
          state <= COMPUTE;
        end

        else begin
            h0 <= h0 + a;
            h1 <= h1 + b;
            h2 <= h2 + c;
            h3 <= h3 + d;
            h4 <= h4 + e;
            h5 <= h5 + f;
            h6 <= h6 + g;
            h7 <= h7 + h;
            state <= BLOCK;
        end
      end

   WRITE: begin
      if (write_idx<= 7) begin
        state <= WRITE;
        write_idx <= write_idx + 1;
        offset <= write_idx;
        cur_we <= 1'b1;
        cur_addr <= output_addr;
        case (write_idx)
          0: cur_write_data <= h0;
          1: cur_write_data <= h1;
          2: cur_write_data <= h2;
          3: cur_write_data <= h3;
          4: cur_write_data <= h4;
          5: cur_write_data <= h5;
          6: cur_write_data <= h6;
          7: cur_write_data <= h7;
        endcase
      end
      else begin
        state <= IDLE;
      end
    end

  endcase
end
// Generate done when SHA256 hash computation has finished and moved to IDLE state
assign done = (state == IDLE);

endmodule